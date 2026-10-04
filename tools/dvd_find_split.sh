#!/bin/bash
# =========================================================================
#  tools/dvd_find_split.sh  -  给 DVD 切分找"能落刀"的时间点
#
#  用法:
#    ./tools/dvd_find_split.sh <目标秒> <源1> [源2 ...]
#      目标秒   想在哪切(例如 1823 表示 30:23)。脚本会去找离它最近的 I 帧
#      源N      1 个或多个文件, 按给出顺序拼起来算时间轴(与 dvd_menu_build.sh
#               的源顺序保持一致, 否则算出来的点会错位)
#
#  输出: 一行
#    split_at=<秒>
#  拿到后直接喂给 dvd_menu_build.sh:
#    SPLIT=$(./tools/dvd_find_split.sh 1823 a.vob b.vob | sed -n 's/^split_at=//p')
#
#  为什么要落在 I 帧(进一步说是 VOBU 起点):
#    MPEG-2 的 B/P 帧要参考前后帧, 从非 I 帧切开, 第二段的开头会花屏/卡住几帧;
#    而 DVD-Video 的每个 VOBU(视频对象单元)都以一个 NAV 包开头, 家用机靠它做
#    跳转与菜单返回。切在 VOBU 内部, dvdauthor 要么报
#      "ERR: Cannot infer pts for VOBU ..."
#    要么造出章节点错位的盘 —— 而文件本身能播, 很容易误判成"刻坏了"。
#    实测 ZP001: 目标 1823s 时最近的 I 帧是 1823.1063, 用后者切, dvdauthor 一次过。
#
#  多个切点就跑多次(每次给一个目标秒), 结果用逗号串起来:
#    SPLIT="1823.106300,3600.040000"
#
#  注意:
#    1) 多段源用 concat 解复用器拼起来算时间轴 —— 直接 cat 是不行的: 每段 PTS
#       都从 0 开始, 拼出来时间轴是断的, 算出来的"第 N 秒"根本不是那一段。
#    2) 全片扫一遍帧比较慢(小时级素材几分钟)。嫌慢就先拿一小段试。
# =========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

# 统一 --help / -help / -h(见 lib/common.sh 的 ff_help_guard), 位置在下面的参数个数
# 检查之前 —— 否则 -h 会被当成"目标秒", 报出一个和帮助无关的错。
# 本脚本一个开关都没有, 所以不接 parse_switches: 那会顺带认到公共 SWITCH_KEYS。
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" || :

[ $# -ge 2 ] || { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit 1; }

TARGET="$1"; shift
SRCS=("$@")
for s in "${SRCS[@]}"; do [ -f "$s" ] || { echo "源文件不存在: $s" >&2; exit 1; } done

declare -F find_ffmpeg >/dev/null 2>&1 || { echo "缺少 lib/common.sh" >&2; exit 1; }
FF="$(find_ffmpeg)" || { echo "找不到 ffmpeg" >&2; exit 1; }
FP="$(find_ffprobe "$FF")" || { echo "找不到 ffprobe" >&2; exit 1; }

LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
if [ "${#SRCS[@]}" -eq 1 ]; then
    SRC_ARG=("${SRCS[0]}")
else
    for s in "${SRCS[@]}"; do printf "file '%s'\n" "$(native_path "$s")" >> "$LIST"; done
    SRC_ARG=(-f concat -safe 0 -i "$LIST")
fi

BEST="$(fp_run -hide_banner -v error ${SRC_ARG[@]+"${SRC_ARG[@]}"} \
    -select_streams v:0 -show_entries frame=pts_time,pict_type -of csv=p=0 </dev/null \
  | awk -F',' '$2=="I" && $1 ~ /^[0-9.]+$/ {print $1}' \
  | awk -v t="$TARGET" 'BEGIN{min=1e9} {d=$1-t; if(d<0)d=-d; if(d<min){min=d; best=$1}} END{print best}')"

[ -n "$BEST" ] || { echo "没找到任何 I 帧 —— 源是不是没有视频流?" >&2; exit 1; }
printf 'split_at=%s\n' "$BEST"
