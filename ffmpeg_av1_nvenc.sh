#!/bin/bash
# ffmpeg_av1_nvenc.sh - AV1 NVENC 硬件加速压缩脚本 (P1 重构版)
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
# (2026-09-30) 早先这里有一段"Linux 下把 /opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin
# 前置到 PATH"的补丁, 为了绕开"发行版 ffmpeg 没有 av1_nvenc"。现在前置检查里的
# find_ffmpeg_for_encoder av1_nvenc 按能力筛选就能摸到那份(实测命中 N-117740),
# 而这个硬编码目录名还有反作用: 一旦 /opt 下摆的是更旧、能力更少的构建(如 7.0.2
# static, 连 nvenc/vaapi 都没有), 它会被无条件顶到 PATH 最前面。故删掉。

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
# find_ffmpeg_for_encoder 先按"必须带 av1_nvenc 编码器"筛 —— 发行版 ffmpeg 常缺它,
#   能用的那份往往在 /opt 下且不在 PATH 上; 谁都没有时退回不筛选(保持原有报错路径)
if ! FF="$(find_ffmpeg_for_encoder av1_nvenc)"; then
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

# ---------- 码率查表 (bitrate_table_av1.csv, AV1 专用模型) ----------
BIT=$(lookup_bitrate "$SRC_PIX" "bitrate_table_av1.csv")
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
# 说明: 本命令只使用 cuda 解码 + av1_nvenc 编码, 不经过任何 QSV 滤镜/编码器,
# 因此不带 -init_hw_device qsv=hw:0 (旧版残留参数在 cygwin ffmpeg 下会因
# MFX 会话创建失败而直接报错, 且对 nvenc 流程毫无作用)
CMD=("$FF" -hide_banner -threads 0 -v verbose)
CMD+=(-hwaccel cuda -hwaccel_output_format cuda)
CMD+=(-i "$ABS_NAME")

if [ "$SRC_FRAMERATE" -gt 31 ]; then
    CMD+=(-r 30)
    echo "DOWN TARGET FRAME RATE TO 30"
fi

CMD+=(-c:v:0 av1_nvenc -preset p4 -tune:v hq -rc cbr -b:v "$TARGET_BITRATE")
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
