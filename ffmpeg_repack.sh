#!/bin/bash
# ffmpeg_repack.sh - 无损转封装(remux, 不重编码); 薄壳, 公共流程在 lib/encode_core.sh
#   不带参数: 交互输入文件路径
#   带参数  : 文件路径
# 默认出口 mp4; EXT=mkv 可切; --repair / REPAIR=1 强制 mkv 并注入修复选项
# 行为与统一入口 enc_run copy 完全一致 —— 本文件不再自备 ffmpeg 命令, 仅做委托
# (与 ffmpeg_hevc_qsv.sh 同构: source 两份 lib + parse_switches + help guard + enc_run <enc>)

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
    "ffmpeg_repack.sh  -  无损转封装（不重编码，默认 mp4；EXT=mkv 可切）" \
    "用法: ./ffmpeg_repack.sh 源文件" \
    "本入口没有码率表；无论源格式都产出 <名>-repacked.<ext>（绝不覆写源）" || :

enc_run copy "$@"
