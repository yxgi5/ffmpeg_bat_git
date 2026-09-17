#!/bin/bash
# ffmpeg_copy_to_mp4.sh - 无损转封装为 mp4 (P1 重构版)
# 用法: ./ffmpeg_copy_to_mp4.sh [视频文件]
#   不带参数: 交互输入文件路径
# 行为: 视频流/音频流直接 copy, 仅重新封装容器; 已是 mp4 后缀则直接退出

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# 检查后缀是否已是 mp4 (不区分大小写)
function check_file_suffix() {
    local filename extension
    filename="$(basename "$1")"
    extension="${filename#*.}"
    if [ "${extension,,}" == "mp4" ]; then
        echo -e "suffix ${extension,,} 已经是mp4文件，不需要转换"
        exit 0
    else
        echo "suffix ${extension,,} not mp4 file, need to convert"
    fi
}

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
    echo "请输入待转换视频地址: "
    read -r SRC_FILE
else
    SRC_FILE="$1"
fi

check_file_exists "$SRC_FILE"
check_file_suffix "$SRC_FILE"

# ---------- 输出路径 ----------
echo "SRC_FILE: $SRC_FILE"
ABS_NAME=$(realpath "$SRC_FILE")
echo "ABS_NAME: ${ABS_NAME}"

ABS_PATH="$(dirname "$ABS_NAME")"
filename="$(basename "$ABS_NAME")"
filename_without_suffix="${filename%.*}"
TARGET_FILE="${ABS_PATH}/${filename_without_suffix}.mp4"

echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"
echo

# ---------- 构建并执行 ffmpeg 命令 (数组, 无 eval) ----------
CMD=(ffmpeg -hide_banner)
CMD+=(-i "$ABS_NAME")
CMD+=(-c:v copy -c:a copy)
# 流映射与 11 个编码入口完全一致 (2026-09-17 用户裁定): 默认选流只留 1 视频 + 1 音频,
# 多音轨/多字幕会被静默丢掉; 图形字幕(PGS/VobSub)转 mov_text 会失败, 属已知代价。
CMD+=(-map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0)
CMD+=(-n "$TARGET_FILE")

printf 'RUN_COM:'
printf ' %q' "${CMD[@]}"
printf '\n'

"${CMD[@]}"
if [ $? -ne 0 ]; then
    echo -e "\033[41;36mConvert failed！\033[0m"
    exit 1
fi
