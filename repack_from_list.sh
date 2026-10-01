#!/bin/bash
# repack_from_list.sh - 批量无损转封装: 按清单逐行调用 copy_to_mp4 (P1 重构版)
# 用法: ./repack_from_list.sh [清单文件]   不带参数默认 list.txt
# 清单每行一个视频路径; 兼容含空格的文件名(while read), 空行自动跳过

# 开关透传: 本脚本不解析任何开关 —— 它们全部以环境变量的形式原样传给下游入口,
#   例如 EXT(输出容器) / BITRATE_NO_HALF(目标码率不除 2) / FF_HWACCEL(软硬解) /
#   FF_ON_EXIST(同名产物策略), 以及各入口自己的 switch(见 readme.md 的开关表)。
#   默认值统一写在 lib/defaults.cfg —— 无人值守前改那个文件即可, 命令行临时覆盖优先。
# load_defaults 把配置里的默认值装进本进程环境(子进程继承), 再回显一行: 跑一整晚的
#   日志里能一眼看出这份清单是按什么设置转的(2026-10-02: 即将无人值守)。
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
# ---------- 开关透传(无人值守留痕) ----------
# 开关透传: 本脚本不解析任何开关 —— 它们全部以环境变量的形式原样传给下游入口,
#   例如 EXT(输出容器) / BITRATE_NO_HALF(目标码率不除 2) / FF_HWACCEL(软硬解) /
#   FF_ON_EXIST(同名产物策略), 以及各入口自己的 switch(见 readme.md 的开关表)。
#   默认值统一写在 lib/defaults.cfg —— 无人值守前改那个文件即可, 命令行临时覆盖优先。
# load_defaults 把配置里的默认值装进本进程环境(子进程继承), 再回显一行: 跑一整晚的
#   日志里能一眼看出这份清单是按什么设置转的(2026-10-02: 即将无人值守)。
load_defaults
echo "SWITCHES : EXT=${EXT:-} BITRATE_NO_HALF=${BITRATE_NO_HALF:-} FF_ON_EXIST=${FF_ON_EXIST:-}"
check_file_is_text "${LIST_FILE}"

run_list "${LIST_FILE}" "${SCRIPT_DIR}/ffmpeg_copy_to_mp4.sh"
