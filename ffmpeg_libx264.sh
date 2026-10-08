#!/bin/bash
# ffmpeg_libx264.sh - AVC libx264 软件编码压缩脚本 (薄壳, 公共流程在 lib/encode_core.sh)
# 用法: ./ffmpeg_libx264.sh [视频文件]
#   不带参数: 交互输入文件路径和输出码率
#   带参数  : 文件路径, 码率/输出文件名自动决定
# 码率查表使用 bitrate_table_avc.csv (AVC 专用模型, 源自 bitrate_calc.xlsx output 页 H 列)
#
# 本入口与另外 8 个编码入口的公共段(banner / 定位 ffmpeg / 探测源 / 码率查表 /
# 输出命名 / 命令拼装 / ff_run)全在 lib/encode_core.sh 的 enc_run 里, 差异压成
# "libx264" 这个键 —— 编码器名、码率表、解码方式、能力门都由那张表和三个钩子分派。
# 本文件只剩三件事: 头部说明、--help 文案、以及声明自己是哪个编码器。

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/encode_core.sh
source "${SCRIPT_DIR}/lib/encode_core.sh"

# 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.sh)
#   优先级 参数 > 环境变量 > defaults.cfg; 没给的参数回退 env / cfg(老 set 写法仍兼容)
#   其余位置参数(文件名)交还给 $@, enc_run 里的 check_param_number 照常处理
parse_switches "$@"
set -- ${PS_REST[@]+"${PS_REST[@]}"}
# 统一 --help / -help / -h: 与 .bat 孪生打印**同一套版式**(见 lib/common.sh 的
# ff_usage_block / ff/common.bat 的 :usage), 只有确实有差异的地方才不同(脚本名、
# 以及"拖到 bat 上"这种 bat 独有的用法)。位置必须早于任何"把 $1 当文件用"的代码。
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" -- \
    "ffmpeg_libx264.sh  -  AVC libx264 软件编码压缩（无硬件要求）" \
    "用法: ./ffmpeg_libx264.sh 视频文件" || :

enc_run libx264 "$@"