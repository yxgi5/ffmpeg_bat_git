#!/bin/bash
# ffmpeg_libx265.sh - HEVC libx265 软件编码压缩脚本 (薄壳, 公共流程在 lib/encode_core.sh)
# 用法: ./ffmpeg_libx265.sh [视频文件]
#   不带参数: 交互输入文件路径和输出码率
#   带参数  : 文件路径, 码率/输出文件名自动决定
# 行为与重构前保持一致: 码率查表(CSV), 目标码率=查表值/2, 源码率过低则沿用源码率
#
# 公共段全在 lib/encode_core.sh 的 enc_run 里, 差异只剩 "libx265" 这个键
# (它与 libx264 的差别是码率表走默认的 hevc 表 + -pix_fmt nv12)。

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
    "ffmpeg_libx265.sh  -  HEVC libx265 软件编码压缩（无硬件要求）" \
    "用法: ./ffmpeg_libx265.sh 视频文件" || :

enc_run libx265 "$@"