#!/bin/bash
# convert_from_list_cuda.sh - 批量压缩: 按清单逐行调用 NVENC 脚本 (P1 重构版)
# 用法: ./convert_from_list_cuda.sh [清单文件]   不带参数默认 list.txt
# OS 分发: Linux / Cygwin / MINGW64 一律 -> ffmpeg_hevc_nvenc.sh
#   (2026-09-30: 原 Cygwin 专用变体 ffmpeg_hevc_nvenc_cygwin.sh 已合并回 nvenc.sh ——
#    实测 -hwaccel cuvid 在 ffmpeg 7.x 已被归一化成 cuda, 两版解码路径完全相同,
#    Cygwin 走同一入口即可; 旧驱动需要 hwdownload 回拷时设 FF_NVENC_HWDOWNLOAD=1)
# 清单每行一个视频路径; 兼容含空格的文件名(while read), 空行自动跳过

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

LIST_FILE=""
check_param_number "$#"
param_number=$?
if [ "$param_number" -eq 0 ]; then
    LIST_FILE="list.txt"
else
    LIST_FILE="$1"
fi

check_file_exists "${LIST_FILE}"
echo "LIST_FILE = ${LIST_FILE}"
check_file_is_text "${LIST_FILE}"

OS=$(uname -s)

case "$OS" in
    Linux*)
        echo "Linux"
        run_list "${LIST_FILE}" "${SCRIPT_DIR}/ffmpeg_hevc_nvenc.sh"
        ;;
    CYGWIN*)
        echo "Cygwin"
        run_list "${LIST_FILE}" "${SCRIPT_DIR}/ffmpeg_hevc_nvenc.sh"
        ;;
    MSYS*)
        echo "MSYS2 (usr/bin 无 ffmpeg, 跳过; 请使用 MINGW64 子环境)"
        ;;
    MINGW*)
        echo "MinGW"
        run_list "${LIST_FILE}" "${SCRIPT_DIR}/ffmpeg_hevc_nvenc.sh"
        ;;
    *)
        echo "Unknown: $OS"
        ;;
esac
