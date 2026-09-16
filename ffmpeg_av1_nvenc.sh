#!/bin/bash
# ffmpeg_av1_nvenc.sh - AV1 NVENC 硬件加速压缩脚本 (P1 重构版)
#   不带参数: 交互输入文件路径和输出码率
#   带参数  : 文件路径, 码率/输出文件名自动决定
# 行为与重构前保持一致: 码率查表(CSV), 目标码率=查表值/2, 源码率过低则沿用源码率

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# AV1 硬编编码器在老版本发行版 ffmpeg 中缺失, Linux 下优先使用新版 ffmpeg
OS=$(uname -s)

case "$OS" in
    Linux*)
        # 发行版 ffmpeg 常缺 av1 硬编编码器, 若存在新版构建则前置 PATH (软偏好, 不存在则回退发行版)
        if [ -d /opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin ]; then
            export PATH=/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin:$PATH
        fi
        ;;
    CYGWIN*)
        ;;
    MSYS*)
        ;;
    MINGW*)
        ;;
    *)
        ;;
esac

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================

# ---------- 前置检查 ----------
if ! check_command "ffmpeg"; then
    echo -e "\033[41;36mffmpeg command not found!\033[0m"
    exit 1
fi

if ! check_command "ffprobe"; then
    echo -e "\033[41;36mffprobe command not found!\033[0m"
    exit 1
fi

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

# ---------- 码率查表 (bitrate_table_av1.csv, AV1 专用模型) ----------
BIT=$(lookup_bitrate "$SRC_PIX" "bitrate_table_av1.csv")
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
# 说明: 本命令只使用 cuda 解码 + av1_nvenc 编码, 不经过任何 QSV 滤镜/编码器,
# 因此不带 -init_hw_device qsv=hw:0 (旧版残留参数在 cygwin ffmpeg 下会因
# MFX 会话创建失败而直接报错, 且对 nvenc 流程毫无作用)
CMD=(ffmpeg -hide_banner -threads 0 -v verbose)
CMD+=(-hwaccel cuda -hwaccel_output_format cuda)
CMD+=(-i "$ABS_NAME")

if [ "$SRC_FRAMERATE" -gt 31 ]; then
    CMD+=(-r 30)
    echo "DOWN TARGET FRAME RATE TO 30"
fi

CMD+=(-c:v av1_nvenc -preset p4 -tune:v hq -rc cbr -b:v "$TARGET_BITRATE")
CMD+=(-g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2)
CMD+=(-map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0)
CMD+=(-rtbufsize 120m -max_muxing_queue_size 1024 -n "$TARGET_FILE")

printf 'RUN_COM:'
printf ' %q' "${CMD[@]}"
printf '\n'

"${CMD[@]}"
if [ $? -ne 0 ]; then
    echo -e "\033[41;36mConvert failed！\033[0m"
    exit 1
fi
