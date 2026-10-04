#!/bin/bash
# =========================================================================
#  tools/dvd_aud_gap.sh  -  音频时间戳体检(找"音频洞")
#
#  用法:
#    ./tools/dvd_aud_gap.sh <文件> [更多文件 ...]
#
#  开关(环境变量):
#    SEC=90       每个文件只看前多少秒(默认 90)。看全片就 SEC=0
#    FRAME=0.032  一帧音频的时长(秒)。AC3 @48k = 1536/48000 = 0.032
#    TOL=1.02     容差倍数: 间隔 > FRAME*TOL 才算异常
#
#  输出: 每个文件一行
#    间隔= 相邻 PTS 间隔总数 / 正常 / 2帧洞 / 3帧洞 / >100ms
#
#  为什么需要它:
#    "音频洞"在播放器里是断续的爆音/静音, 在 dvdauthor 里是满屏
#    "Discontinuity ... please remultiplex", 但**文件能播、时长也对**,
#    光看 ffprobe 的 stream 信息一点都看不出来 —— 只有逐包量 PTS 间隔才现形。
#    典型根因是源音轨为 LPCM: 每包样本数不规则, 解码出来时间戳抖, AC3 编码器
#    原样带走, 成品里约 4% 的音频帧会跳 2 帧(64ms)。修法是重编码时加
#      -af "aresample=48000:async=1:first_pts=0"
#    实测同一份素材: 2 帧洞 4802 -> 0。tools/dvd_menu_build.sh 已内置这一步。
#
#  注意:
#    1) 别用 ffprobe ... | head -N 取前几个包: head 拿够就关管道, ffprobe 收
#       SIGPIPE 返回 141, 配合 set -o pipefail 会把脚本直接干掉。要让 ffprobe
#       自己少解一点, 用 -read_intervals "%+90"(本脚本就是这么做的)。
#    2) 只看 a:0。多语言 DVD 要查别的音轨, 改 -select_streams 即可。
# =========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

# ---------- 开关参数化 (2026-10-04) ----------
# --key value / --key=value -> 同名大写环境变量; 环境变量写法照旧有效(参数 > 环境变量)。
# 键表只认本脚本这几个(PS_KEYS), 不进公共 SWITCH_KEYS(见 lib/common.sh 的 PS_KEYS 注释)。
PS_KEYS=(sec frame tol)
parse_switches "$@"
set -- ${PS_REST[@]+"${PS_REST[@]}"}
# 统一 --help / -help / -h(见 lib/common.sh 的 ff_help_guard): 命中就打印本脚本头部
# 那段用法并退 0。common.sh 缺失时安静跳过, 由下面的 declare -F 守卫报真正的问题。
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" || :

[ $# -ge 1 ] || { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit 1; }

declare -F find_ffprobe >/dev/null 2>&1 || { echo "缺少 lib/common.sh" >&2; exit 1; }
FF="$(find_ffmpeg 2>/dev/null || command -v ffmpeg 2>/dev/null || printf '')"
FP="$(find_ffprobe "$FF" 2>/dev/null || command -v ffprobe 2>/dev/null || printf '')"
[ -n "$FP" ] || { echo "找不到 ffprobe" >&2; exit 1; }

SEC="${SEC:-90}"
FRAME="${FRAME:-0.032}"
TOL="${TOL:-1.02}"
LIM="$(awk -v f="$FRAME" -v t="$TOL" 'BEGIN{printf "%.6f", f*t}')"

# 只解前 SEC 秒: SEC=0 表示看全片
if [ "$SEC" = "0" ]; then RI=(); else RI=(-read_intervals "%+${SEC}"); fi

gap() {
    local f="$1"
    fp_run -hide_banner -v error ${RI[@]+"${RI[@]}"} -i "$f" -select_streams a:0 \
        -show_entries packet=pts_time -of csv=p=0 </dev/null \
    | awk -F',' -v t="$(basename "$f")" -v lim="$LIM" -v fr="$FRAME" '
        { sub(/\r$/, "") }        # 原生 Windows ffprobe 输出 CRLF, 不去就一个数都数不到
        $1 ~ /^[0-9.]+$/ {
            if (p != "" && $1 > p) {
                d = $1 - p; cnt++
                if      (d <= lim)      ok++
                else if (d <  fr * 1.6) g2++
                else if (d <  fr * 3)   g3++
                else                    big++
            }
            p = $1
        }
        END {
            if (cnt == 0) { printf "%-30s 没有可用的音频 PTS(选错流?)\n", t; exit }
            printf "%-30s 间隔=%d 正常=%d 2帧洞=%d 3帧洞=%d >100ms=%d\n", t, cnt, ok, g2, g3, big
        }'
}

for f in "$@"; do
    [ -f "$f" ] || { echo "不存在: $f" >&2; continue; }
    gap "$f"
done
