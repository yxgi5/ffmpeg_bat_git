#!/bin/bash
# convert_from_list_cuda.sh - 批量压缩: 按清单逐行调用 NVENC 脚本 (P1 重构版)
# 用法: ./convert_from_list_cuda.sh [清单文件]   不带参数默认 list.txt
# OS 分发: Linux / Cygwin / MINGW64 一律 -> ffmpeg_hevc_nvenc.sh
#   (2026-09-30: 原 Cygwin 专用变体 ffmpeg_hevc_nvenc_cygwin.sh 已合并回 nvenc.sh ——
#    实测 -hwaccel cuvid 在 ffmpeg 7.x 已被归一化成 cuda, 两版解码路径完全相同,
#    Cygwin 走同一入口即可; 旧驱动需要 hwdownload 回拷时设 FF_NVENC_HWDOWNLOAD=1)
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
