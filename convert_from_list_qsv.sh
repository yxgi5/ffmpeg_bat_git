#!/bin/bash
# convert_from_list_qsv.sh - 批量压缩: 按清单逐行调用 HEVC QSV 脚本 (P1 重构版)
# 用法: ./convert_from_list_qsv.sh [清单文件]   不带参数默认 list.txt
# 清单每行一个视频路径; 兼容含空格的文件名(while read), 空行自动跳过
# 注意: Cygwin 的 ffmpeg QSV 会话初始化失败, 此脚本不适用于 Cygwin 环境

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

run_list "${LIST_FILE}" "${SCRIPT_DIR}/ffmpeg_hevc_qsv.sh"
