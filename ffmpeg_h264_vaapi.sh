#!/bin/bash
# ffmpeg_h264_vaapi.sh - AVC VAAPI 硬件加速压缩脚本 (P1 重构版, 仅 Linux)
#   不带参数: 交互输入文件路径和输出码率
#   带参数  : 文件路径, 码率/输出文件名自动决定
# 行为与重构前保持一致: 码率查表(CSV), 目标码率=查表值/2, 源码率过低则沿用源码率

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# VAAPI 仅存在于 Linux (Intel 核显); iHD 驱动覆盖 Gen8+ 核显
export LIBVA_DRIVER_NAME=iHD

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================

# ---------- 前置检查 ----------
# ffmpeg 定位走 lib/common.sh 的 find_ffmpeg, 与 .bat 侧同序:
#   FFMPEG_BIN(目录) / FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH 逐项 > 常见前缀
# 不能只信 command -v: 它只回第一个命中, 而"第一个"经常正是缺能力的那个
#   (Linux 上就是发行版那份 4.4.2), 后面那个能用的构建于是永远轮不到
# find_ffmpeg_for_encoder 先按"必须带 h264_vaapi 编码器"筛 —— 发行版 ffmpeg 常缺它,
#   能用的那份往往在 /opt 下且不在 PATH 上; 谁都没有时退回不筛选(保持原有报错路径)
if ! FF="$(find_ffmpeg_for_encoder h264_vaapi)"; then
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

# 码率无效时按 文件大小*8/时长 估算
if ! [[ "$SRC_BITRATE" =~ ^[0-9]+$ ]] || [ "$SRC_BITRATE" -le 0 ]; then
    TMP=$(( SRC_SIZE * 8 ))
    DURATION_INT=$(printf "%.0f" "$SRC_DURATION")

    if [ "$DURATION_INT" -le 0 ]; then
        echo "duration异常"
        exit 1
    fi

    SRC_BITRATE=$(( TMP / DURATION_INT ))
fi

echo "SRC_BITRATE: $SRC_BITRATE"

# ---------- 码率查表 (bitrate_table_avc.csv, AVC 专用模型) ----------
BIT=$(lookup_bitrate "$SRC_PIX" "bitrate_table_avc.csv")
if [ $? -ne 0 ] || [ -z "$BIT" ]; then
    echo -e "\033[41;36mManual handle it!\033[0m"
    exit 2
fi

TARGET_BITRATE=$(( BIT / 2 ))
echo "ref TARGET_BITRATE: $TARGET_BITRATE"

percentage=$(( TARGET_BITRATE * 100 / SRC_BITRATE ))
echo "compress percentage: ${percentage}%"

if [ "$percentage" -ge 100 ]; then
    TARGET_BITRATE=$SRC_BITRATE
fi

# 码率异常: 退出码 5, 与 .bat 侧(exit /b 5)数值一致
if [ "$percentage" -le 0 ]; then
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
TARGET_FILE="${ABS_PATH}/${filename_without_suffix}-compressed.mp4"

echo "ABS_NAME: ${ABS_NAME}"
echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"

# ---------- 构建并执行 ffmpeg 命令 (数组, 无 eval) ----------
# VAAPI 解码+编码需要显式指定渲染设备 (仅 Linux 可用)
CMD=("$FF" -hide_banner -threads 0 -v verbose)
# ---------- 10bit 源: 两种症状, 两种修法 (2026-09-30 实测) ----------
# ① H.264 High 10: 卡在**解码**侧 —— VAAPI 的 H.264 解码器不吃 profile 110
#    ("Codec h264 profile 110 not supported for hardware decode."), 硬解挂掉后
#    10bit 帧退回系统内存, 编码器要硬件表面 -> "Impossible to convert ...
#    auto_scale_0" -> rc=1 / 0 字节。这种源改走软解, 再 hwupload 上去。
# ② HEVC Main10: 硬解正常, 卡在**编码**侧 —— 本入口写死 -profile:v:0 main, 而
#    Main 不接受 10bit 输入。修法是 scale_vaapi=format=nv12: 在 VAAPI 硬件内部
#    降到 8bit。不能用软滤镜 format=nv12(帧还在 VAAPI 表面, auto_scale 接不上)。
# 8bit 源的命令行一字不改。
HW_DEC=1
if src_hw_decode_hostile "$ABS_NAME"; then
    HW_DEC=0
    echo "H.264 High 10 源 -> VAAPI 硬解不支持, 改软解 + hwupload"
    CMD+=(-init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va)
else
    CMD+=(-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128)
fi
CMD+=(-i "$ABS_NAME")
if [ "$HW_DEC" = 0 ]; then
    CMD+=(-vf "format=nv12,hwupload")
elif src_is_10bit "$ABS_NAME"; then
    echo "10bit 源 -> scale_vaapi=format=nv12 (VAAPI 硬件内降 8bit)"
    CMD+=(-vf "scale_vaapi=format=nv12")
fi

if [ "$SRC_FRAMERATE" -gt 31 ]; then
    CMD+=(-r 30)
    echo "DOWN TARGET FRAME RATE TO 30"
fi

CMD+=(-c:v:0 h264_vaapi -profile:v:0 main -b:v "$TARGET_BITRATE")
CMD+=(-g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2)
cover_map_gate "$FF"
CMD+=(-map 0:V -map 0:a? -map 0:s? ${COVER_MAP[@]+"${COVER_MAP[@]}"} -c:s mov_text -map_metadata 0 -map_chapters 0)
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
