#!/bin/bash
# ffmpeg_avc_qsv.sh - AVC QSV 硬件加速压缩脚本 (P1 重构版)
#   不带参数: 交互输入文件路径和输出码率
#   带参数  : 文件路径, 码率/输出文件名自动决定
# 行为与重构前保持一致: 码率查表(CSV), 目标码率=查表值/2, 源码率过低则沿用源码率

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.sh)
#   优先级 参数 > 环境变量 > defaults.cfg; 没给的参数回退 env / cfg(老 set 写法仍兼容)
#   其余位置参数(文件名)交还给 $@, 下方 check_param_number 照常处理
parse_switches "$@"
set -- ${PS_REST[@]+"${PS_REST[@]}"}

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================

# ---------- 输出容器开关 EXT: mp4(默认) / mkv ----------
# 默认值写在 lib/defaults.cfg(两族共用一份), 校验 / 去空白 / -c:s 的选法统统在
# lib/common.sh 的 init_ext 里 —— 加容器、改默认都只动那一处, 入口不再各写一遍。
# 命令行 EXT=mkv 优先于配置文件(load_defaults 只补没设过的键)。
init_ext || exit 1
# ---------- 前置检查 ----------
# ffmpeg 定位走 lib/common.sh 的 find_ffmpeg, 与 .bat 侧同序:
#   FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH 逐项 > 常见前缀
# 不能只信 command -v: 它只回第一个命中, 而"第一个"经常正是缺能力的那个
#   (Linux 上就是发行版那份 4.4.2), 后面那个能用的构建于是永远轮不到
# find_ffmpeg_for_encoder 先按"必须带 h264_qsv 编码器"筛 —— 发行版 ffmpeg 常缺它,
#   能用的那份往往在 /opt 下且不在 PATH 上; 谁都没有时退回不筛选(保持原有报错路径)
if ! FF="$(find_ffmpeg_for_encoder h264_qsv)"; then
    echo -e "\033[41;36mffmpeg command not found!\033[0m"
    exit 1
fi
if ! FP="$(find_ffprobe "$FF")"; then
    echo -e "\033[41;36mffprobe command not found!\033[0m"
    exit 1
fi
export FF FP
echo "ffmpeg : $FF ($(ffmpeg_build_id "$FF"))"

check_param_number "$#"
param_number=$?

# ---------- 输入文件 ----------
if [ "$param_number" -eq 0 ]; then
    echo "请输入待压缩视频地址: "
    read -r SRC_FILE
else
    SRC_FILE="$1"
fi

check_file_exists "$SRC_FILE"
check_file_isvideo "$SRC_FILE"

# ---------- 源视频信息 ----------
SRC_CODEC=$(check_file_codec "$SRC_FILE")

SRC_FRAMERATE=$(check_file_framerate "$SRC_FILE")
if [[ $SRC_FRAMERATE == *"/"* ]]; then
    ratenum=${SRC_FRAMERATE%%/*}
    rateden=${SRC_FRAMERATE##*/}
    SRC_FRAMERATE=$(( ratenum / rateden ))
fi

# check_file_resolution 已归一为空格分隔单行("1280 720")
SRC_RESOLUTION=$(check_file_resolution "$SRC_FILE")
read -r SRC_W SRC_H <<< "$SRC_RESOLUTION"
echo "SRC_W: $SRC_W"
echo "SRC_H: $SRC_H"

SRC_PIX=$(( SRC_W * SRC_H ))

SRC_SIZE=$(check_file_size "$SRC_FILE")
SRC_DURATION=$(check_file_duration "$SRC_FILE")
SRC_BITRATE=$(check_file_bitrate "$SRC_FILE")

# 码率兜底: check_file_bitrate 已优先 stream.bit_rate, 再 format.bit_rate;
#          均无效则按 文件大小*8/时长 估算(需有效时长)
if ! [[ "$SRC_BITRATE" =~ ^[0-9]+$ ]] || [ "$SRC_BITRATE" -le 0 ]; then
    DURATION_INT=$(printf "%.0f" "$SRC_DURATION" 2>/dev/null || echo 0)
    if [ "${DURATION_INT:-0}" -gt 0 ]; then
        SRC_BITRATE=$(( SRC_SIZE * 8 / DURATION_INT ))
    fi
fi

# 时长兜底: format.duration 不可用时, 用 size*8/bitrate 反推(需有效码率)
if ! [[ "$SRC_DURATION" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(printf '%.0f' "$SRC_DURATION" 2>/dev/null || echo 0)" -le 0 ]; then
    if [[ "$SRC_BITRATE" =~ ^[0-9]+$ ]] && [ "$SRC_BITRATE" -gt 0 ]; then
        DURATION_INT=$(( SRC_SIZE * 8 / SRC_BITRATE ))
        [ "$DURATION_INT" -gt 0 ] && SRC_DURATION="$DURATION_INT"
    fi
fi

echo "SRC_BITRATE: $SRC_BITRATE"

# ---------- 码率查表 (bitrate_table_avc.csv, AVC 专用模型) ----------
BIT=$(lookup_bitrate "$SRC_PIX" "bitrate_table_avc.csv")
if [ $? -ne 0 ] || [ -z "$BIT" ]; then
    echo -e "\033[41;36mManual handle it!\033[0m"
    exit 2
fi

# 目标码率口径在同一处: BITRATE_NO_HALF=1 时跳过 /2(见 lib/common.sh)
TARGET_BITRATE=$(bitrate_from_table "$BIT")
echo "ref TARGET_BITRATE: $TARGET_BITRATE"

if [ "${SRC_BITRATE:-0}" -gt 0 ]; then
    percentage=$(( TARGET_BITRATE * 100 / SRC_BITRATE ))
    echo "compress percentage: ${percentage}%"
    if [ "$percentage" -ge 100 ]; then
        TARGET_BITRATE=$SRC_BITRATE
    fi
else
    percentage=0
    echo "compress percentage: N/A (源码率未知)"
fi

# 码率异常: 退出码 5, 与 .bat 侧(exit /b 5)数值一致
if [ "$TARGET_BITRATE" -le 0 ]; then
    echo "bitrate abnormal, please check"
    echo -e "\033[41;36mbitrate abnormal, please check\033[0m"
    exit 5
fi

# ---------- 交互模式可覆盖码率 ----------
if [ "$param_number" -eq 0 ]; then
    echo "请输入输出码率(如1150k,不输入则保持默认): "
    read -r TARGET_BITRATE_1
    if [ -n "$TARGET_BITRATE_1" ]; then
        TARGET_BITRATE="$TARGET_BITRATE_1"
    fi
fi
echo "real TARGET_BITRATE = $TARGET_BITRATE"

# ---------- 输出路径 ----------
echo "SRC_FILE: $SRC_FILE"
ABS_NAME=$(realpath "$SRC_FILE")
ABS_PATH=$(dirname "$ABS_NAME")
filename=$(basename "$ABS_NAME")
filename_without_suffix="${filename%.*}"
TARGET_FILE="${ABS_PATH}/${filename_without_suffix}-compressed.${EXT}"

echo "ABS_NAME: ${ABS_NAME}"
echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"

# ---------- 构建并执行 ffmpeg 命令 (数组, 无 eval) ----------
# QSV 解码+编码流程需要显式初始化 QSV 设备
CMD=("$FF" -hide_banner -threads 0 -v verbose)
CMD+=(-init_hw_device qsv=hw -filter_hw_device hw)

# ---------- 10bit 源: 两种症状, 两种修法 (2026-09-30 实测) ----------
# ① H.264 High 10 (profile 110): 卡在**解码**侧 —— QSV 的 H.264 解码器不吃
#    High 10, 硬解一挂, 10bit 帧退回系统内存, 而编码器要硬件表面, 于是
#    "Impossible to convert ... auto_scale_0" -> rc=1 / 产物 0 字节。
#    编码器没毛病, 所以下面那条 scale_qsv 修不了它(它假定帧已在 QSV 表面上)。
#    修法: 这种源**不用硬解**, 软解之后 hwupload 送上去(实测 rc=0, 产物 yuv420p)。
# ② 其余 10bit(HEVC Main10 等): 硬解正常, 卡在**编码**侧 —— h264_qsv 吃不下
#    10bit 输入("some encoding parameters are not supported by the QSV runtime"
#    -> "Error while opening encoder", rc=-40, 0 字节)。修法是 scale_qsv: 在 QSV
#    硬件内部转成 nv12。不能用软滤镜 format=nv12 —— 帧还在 QSV 表面, auto_scale
#    照样接不上。
# 只在真遇到时改命令行, 8bit + 非 High10 的源一字不改。
HW_DEC=1
if src_hw_decode_hostile "$ABS_NAME"; then
    HW_DEC=0
    echo "H.264 High 10 源 -> QSV 硬解不支持, 改软解 + hwupload"
else
    CMD+=(-hwaccel qsv -hwaccel_output_format qsv)
fi
CMD+=(-i "$ABS_NAME")
if [ "$HW_DEC" = 0 ]; then
    CMD+=(-vf "format=nv12,hwupload=extra_hw_frames=64")
elif src_is_10bit "$ABS_NAME"; then
    echo "10bit 源 -> scale_qsv=format=nv12 (QSV 硬件内降 8bit)"
    CMD+=(-vf "scale_qsv=format=nv12")
fi

if [ "$SRC_FRAMERATE" -gt 31 ]; then
    CMD+=(-r 30)
    echo "DOWN TARGET FRAME RATE TO 30"
fi

CMD+=(-c:v:0 h264_qsv -profile:v:0 main -preset veryfast -b:v "$TARGET_BITRATE")
CMD+=(-g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2)
cover_map_gate "$FF"
# EXT=mkv 时字幕默认原样复制(-c:s copy): mkv 装得下位图字幕, 比 mp4 少丢东西。
# 唯一例外是源里带 mov_text —— mp4 的软字幕格式, matroska 装不下, 实测
# -c:s copy 在这里直接 rc=-40 / 0 字节 —— 所以这种源把文本字幕转成 ass。
# CM_MOV 由上面的封面闸门顺路数出来, 没有额外起 ffprobe。
if [ "$EXT" = mkv ] && [ "${CM_MOV:-0}" = 1 ]; then SENC=(-c:s ass); fi
CMD+=(-map 0:V -map 0:a? -map 0:s? ${COVER_MAP[@]+"${COVER_MAP[@]}"} "${SENC[@]}" -map_metadata 0 -map_chapters 0)
CMD+=(-rtbufsize 120m -max_muxing_queue_size 1024 -n "$TARGET_FILE")

printf 'RUN_COM:'
printf ' %q' "${CMD[@]}"
printf '\n'

# 走 ff_run 而不是直接执行数组: 它会把以 / 开头的参数改写成原生路径
# (Cygwin/MINGW64 下选到原生 Windows 构建时, POSIX 路径会 No such file); Linux 上恒等
ff_run "${CMD[@]:1}"
if [ $? -ne 0 ]; then
    echo -e "\033[41;36mConvert failed！\033[0m"
    exit 1
fi
