#!/bin/bash
# =========================================================================
#  tools/scene_detect.sh  -  场景切换检测(找镜头切点)
#
#  用法:
#    ./tools/scene_detect.sh <视频> [阈值]
#      视频   任意 ffmpeg 读得了的文件
#      阈值   场景变化分数 0~1, 越大越严格(只报跳变很猛的), 默认 0.35。
#             经验值: 0.2 很敏感(连淡入淡出都算), 0.3~0.4 是常用档, 0.5+ 只报硬切
#
#  开关(环境变量, 写在命令之前):
#    MAX=N        只输出前 N 个切点(先跑一遍看数量再定, 省得被几千条刷屏)
#    MIN_GAP=秒   丢掉与上一个切点间隔小于该值的点。镜头边缘常有一串密集抖动,
#                 例如渐变转场会连报好几条, MIN_GAP=1 基本能压成一条
#    CHAPS=路径   顺手写出 FFmetadata 章节文件(可直接 mkvmerge / ffmpeg 灌进去):
#                   ffmpeg -i in.mkv -i chaps.txt -map_metadata 1 -c copy out.mkv
#                 章节名默认 "第N段", 用 CHAP_PREFIX= 改, 首章名用 CHAP_FIRST= 改
#
#  一条命令的样子:
#    ./tools/scene_detect.sh movie.mkv 0.35
#    MAX=40 MIN_GAP=1 CHAPS=chaps.txt ./tools/scene_detect.sh movie.mkv
#
#  输出: 每行一个切点 "序号  秒  时:分:秒.毫秒"; CHAPS 另写文件
#
#  为什么不能"看一眼就切":
#    ffmpeg 的 scene 分数是相邻帧的差异强度, 与分辨率、噪声、压缩强度都有关 ——
#    同一部片子, 动画/静态访谈要调低阈值, 动作片/闪烁画面要调高。所以本脚本
#    只做"把分数超过阈值的帧挑出来"这一件事, 阈值由你按素材定: 先跑默认档看条数,
#    太多就调高、太少就调低, 别指望一个默认值通吃。
#
#  注意:
#    1) select 表达式里的逗号必须用单引号包起来:
#         -vf "select='gt(scene,0.35)',showinfo"
#       写成 "select=gt(scene,0.35),showinfo" 的话, ffmpeg 会把逗号当成**滤镜分隔
#       符**, 于是报 "No such filter: '0.35)'" 然后 Filter not found 退出 ——
#       网上流传的命令行(含最早那版 .bat)多半就是漏了这对引号, 一条切点都出不来。
#    2) showinfo 打在 stderr 的 info 级别, 所以**不能加 -v error**: 加了就一条都不
#       输出(看着像"这个片子没有切点")。本脚本刻意不设 -v。
#    3) select 滤镜要解码全片, 小时级素材是分钟级耗时, 不是卡住。只想看个大概就
#       先 -t 一小段(用环境变量 CLIP=600 只解前 600 秒)。
#    4) 输出顺序天然递增, 不需要再排序。
# =========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

# ---------- 开关参数化 (2026-10-04) ----------
# --key value / --key=value -> 同名大写环境变量; 环境变量写法照旧有效(参数 > 环境变量)。
# 键表只认本脚本这几个(PS_KEYS), 不进公共 SWITCH_KEYS(见 lib/common.sh 的 PS_KEYS 注释)。
# -h / --help 不在键表里, parse_switches 会把它们原样交还给下面的 case(不会被吃掉)。
# 阈值: 既能当第 2 个位置参数给, 也能 --th 0.3 / TH=0.3 给; 两个都给时位置参数优先
# (本脚本原本就是这个顺序 —— 参数化不改 precedence, 只是多一条入口)。
PS_KEYS=(max min_gap chaps th clip chap_first chap_prefix)
parse_switches "$@"
set -- ${PS_REST[@]+"${PS_REST[@]}"}

TAG="[scene]"
info() { printf '%s %s\n' "$TAG" "$*"; }
die()  { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; exit 1; }

[ $# -ge 1 ] || { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit 1; }
case "${1:-}" in -h|--help) awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;; esac

declare -F find_ffmpeg >/dev/null 2>&1 || die "lib/common.sh 未加载 —— 请在完整仓库里运行本脚本"
FF="$(find_ffmpeg)" || die "找不到 ffmpeg"
FP="$(find_ffprobe "$FF")" || FP=""

SRC="$(normalize_source_path "$1" 2>/dev/null || printf '%s' "$1")"
[ -f "$SRC" ] || die "文件不存在: $1"
TH="${2:-${TH:-0.35}}"
MAX="${MAX:-}"
MIN_GAP="${MIN_GAP:-0}"
CHAPS="${CHAPS:-}"
CHAP_PREFIX="${CHAP_PREFIX:-第%d段}"
CHAP_FIRST="${CHAP_FIRST:-第1段}"
CLIP="${CLIP:-}"

info "源      : $(basename "$SRC")"
info "阈值    : $TH${MAX:+  最多 $MAX 个}${MIN_GAP:+  最小间隔 ${MIN_GAP}s}${CLIP:+  只解前 ${CLIP}s}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 注意: 不加 -v error(见头部第 1 条), showinfo 的 info 级输出就是靠它;
# -nostdin + </dev/null: ffmpeg 会从 stdin 读键盘命令, 非交互环境能卡死几小时
CLIPARG=()
[ -n "$CLIP" ] && CLIPARG=(-t "$CLIP")
# 单引号包住 select 的表达式: 否则逗号被当滤镜分隔符(见头部第 1 条)。
# (注释只能写在命令**之前**: 反斜杠续行后紧跟的 # 会把后面整段吃掉, shell 照样
#  把它当注释, 于是 ffmpeg 只剩 -hide_banner 两个参数 -> 打印 usage 退出, 踩过)
ff_run -nostdin -hide_banner ${CLIPARG[@]+"${CLIPARG[@]}"} \
    -i "$SRC" -vf "select='gt(scene,$TH)',showinfo" -f null - 2> "$TMP" </dev/null || die "ffmpeg 失败"

# showinfo 形如: [Parsed_showinfo_1 @ ...] n: 123 pts: 4567 pts_time:12.345 ...
grep -ao 'pts_time:[0-9.]*' "$TMP" | cut -d: -f2 > "${TMP}.t" || true
N_RAW=$(wc -l < "${TMP}.t" | tr -d ' ')
[ "$N_RAW" -gt 0 ] || { info "阈值 $TH 下一个切点都没有 —— 试试调低阈值(例如 0.25)"; exit 0; }

# 间隔过滤 + 条数上限
awk -v gap="$MIN_GAP" -v max="${MAX:-0}" '
    $1 ~ /^[0-9.]+$/ {
        if (gap > 0 && p != "" && $1 - p < gap) { next }
        if (max > 0 && n >= max) { next }
        n++; printf "%.6f\n", $1; p = $1
    }' "${TMP}.t" > "${TMP}.f"
rm -f "${TMP}.t"

N=$(wc -l < "${TMP}.f" | tr -d ' ')
printf '%s\n' "-------------------------------------------"
awk '{ printf "%4d  %10.3f s  %02d:%02d:%06.3f\n", NR, $1,
               int($1/3600), int($1/60)%60, $1 - int($1/60)*60 }' "${TMP}.f"
printf '%s\n' "-------------------------------------------"
info "切点 $N 个(阈值 $TH 下原始命中 $N_RAW 个)"

# FFmetadata 章节: START/END 单位是 1/1000 秒, 末章 END 取全片时长
if [ -n "$CHAPS" ]; then
    DUR="0"
    if [ -n "$FP" ]; then
        DUR="$(fp_run -hide_banner -v error -show_entries format=duration -of default=nw=1 "$SRC" </dev/null \
               | tr -d '\r' | sed -n 's/^duration=//p')"
    fi
    [ -n "$DUR" ] || DUR=0
    {
        printf ';FFMETADATA1\n'
        printf 'title=%s\n\n' "$(basename "$SRC")"
        awk -v dur="$DUR" -v pre="$CHAP_PREFIX" -v first="$CHAP_FIRST" '
            BEGIN { ms = 0 }
            {
                end = int($1 * 1000 + 0.5)
                printf "[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=%s\n\n", ms, end,
                       (NR == 1 ? first : sprintf(pre, NR))
                ms = end
            }
            END { if (dur > 0) printf "[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=%s\n\n", ms, int(dur*1000+0.5), sprintf(pre, NR+1) }
        ' "${TMP}.f"
    } > "$CHAPS"
    info "章节文件: $CHAPS"
fi

exit 0
