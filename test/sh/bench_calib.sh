#!/bin/bash
# ============================================================
# bench_calib.sh - derive a quality-preserving target bitrate
#                  for ONE source video (software encoders)
#
#   Purpose: for special cases where quality matters most, cut a
#   segment from the middle of the source, encode a bitrate ladder
#   with the codec's SOFTWARE encoder (the same baseline the bitrate
#   tables are calibrated against), score every point with libvmaf
#   against the source itself, and solve "bitrate needed for
#   VMAF 90/93/95/97". Compare against the table lookup value.
#
#   PARITY NOTE: 1:1 twin of test/bat/bench_calib.bat. Same args,
#   same ladder (T/4 T/3 T/2 3T/4 T), same CSV columns. The sh
#   side additionally solves the equal-quality crossings (awk);
#   the bat side prints the CSV and a VMAF>=95 recommendation.
#
#   Usage:  bash test/sh/bench_calib.sh [codec] [source] [max_h] [seconds]
#     codec   : avc | hevc (default) | av1   (software encoder)
#     source  : video file; prompted if omitted
#     max_h   : cap encoding height (e.g. 1080). 0 = keep source size
#     seconds : segment length, default 30
#     A source path whose command substitution lost its quotes (the shell then
#     splits it on spaces) is glued back automatically - it says so when it does.
#
#   Env knobs:
#     WORK=<path>  output dir; default $TMPDIR/ffmpeg_bench_calib_<codec>
#                  artifacts live in a per-parameter subdir of it, so a rerun
#                  can never pick up files made with different settings
#     FFMPEG=<file>   pin the ffmpeg to use
#                  as the .bat side); otherwise lib/common.sh find_ffmpeg
#                  picks one that actually has libvmaf
#
#   Requires: ffmpeg/ffprobe with libvmaf (gyan full / master build,
#   or a distro build with libvmaf), software encoders libx264 /
#   libx265 / libsvtav1. ASCII only, LF.
# ============================================================

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
# shellcheck source=../../lib/common.sh
. "$REPO/lib/common.sh"
# 统一 --help / -help / -h: 与 .bat 孪生同一套版式(见 lib/common.sh 的 ff_usage_block)
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" -- \
    "bench_calib.sh  -  硬件编码等质量档位标定" \
    "用法: bash test/sh/bench_calib.sh 源文件1 源文件2" \
    "与 .bat 孪生同口径: 同一素材在若干码率档上比 VMAF，输出该机该入口的推荐档位" || :

# --- 参数 ---------------------------------------------------------------
# 反引号或 $( ) 形式的命令替换写在引号外面时, shell 会把它打印的整条路径按空格切开,
# 于是一条 source 变成好几个参数 —— 典型就是 cygpath "F:\a b\c.mp4" 外面忘了加引号。
# 这里不报错, 而是把「拼起来确实存在的」最长前缀片段粘回一条路径
# (rejoin_split_path, lib/common.sh), 让这个习惯照样能用。
# source 之后剩下的参数依次是 max_h / seconds。
CODEC="hevc"
ARGV=("$@")
NEXT=0
case "${ARGV[0]:-}" in
    avc|hevc|av1) CODEC="${ARGV[0]}"; NEXT=1 ;;
esac

SRC=""
GLUED=""
if [ "${#ARGV[@]}" -gt "$NEXT" ]; then
    rejoin_split_path "${ARGV[@]:$NEXT}"
    SRC="$REJOIN_PATH"
    NEXT=$((NEXT + REJOIN_N))
    [ "$REJOIN_N" -gt 1 ] && GLUED="yes"
fi
CAP="0"
LEN="30"
if [ "${#ARGV[@]}" -gt "$NEXT" ]; then CAP="${ARGV[$NEXT]}"; NEXT=$((NEXT + 1)); fi
if [ "${#ARGV[@]}" -gt "$NEXT" ]; then LEN="${ARGV[$NEXT]}"; NEXT=$((NEXT + 1)); fi
if [ "${#ARGV[@]}" -gt "$NEXT" ]; then
    echo "ERROR: too many arguments ($#)."
    echo "       usage: test/sh/bench_calib.sh [avc|hevc|av1] [source] [max_h] [seconds]"
    exit 1
fi
if [ -n "$GLUED" ]; then
    echo "note: the shell had split the source path on spaces ($# arguments); glued back to"
    echo "      [$SRC]"
fi

case "$CODEC" in
    avc) CSV_NAME="bitrate_table_avc.csv";  ENC="libx264";   PSET="fast" ;;
    hevc) CSV_NAME="bitrate_table_hevc.csv"; ENC="libx265";  PSET="fast" ;;
    av1) CSV_NAME="bitrate_table_av1.csv";  ENC="libsvtav1"; PSET="8" ;;
esac

# Resolve ffmpeg through lib/common.sh's find_ffmpeg (same four-level fallback as
# lib/common.bat: FFMPEG_BIN/FFMPEG > repo ffmpeg/bin > PATH > well-known prefixes).
# It skips candidates that lack the capability this tool needs, which is the point:
# on Windows an MSYS2 shell resolves `ffmpeg` to /mingw64/bin 8.1 (no libvmaf) while
# the gyan full build sits one level down the list, so plain PATH lookup used to
# fail here with "no libvmaf filter" on a machine that has one.
FF="$(find_ffmpeg --need-filter libvmaf)" || {
    echo "ERROR: no ffmpeg with the libvmaf filter was found."
    echo "       install a full build or set FFMPEG=/path/to/ffmpeg."
    exit 2; }
FP="$(find_ffprobe "$FF")" || {
    echo "ERROR: no ffprobe next to $FF and none on PATH"; exit 2; }
"$FF" -hide_banner -encoders 2>/dev/null | grep -q " $ENC " \
    || { echo "ERROR: encoder $ENC not in $FF"; exit 2; }

if [ -z "${SRC:-}" ]; then
    printf 'drag a video file here, or enter its full path: '
    read -r SRC
fi
SRC="$(normalize_source_path "$SRC")"
[ -n "$SRC" ] && [ -f "$SRC" ] || {
    echo "ERROR: source video not found"
    echo "       tried: [$SRC]"
    [ -d "$SRC" ] && echo "       that is a directory, not a video file"
    echo "       a Windows path (F:\\dir\\file.mkv) is accepted directly here, no cygpath needed;"
    echo "       the brackets show exactly what this shell received."
    exit 2; }

SW=$(fp_run -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$SRC" < /dev/null | tr -d '\r')
SH=$(fp_run -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$SRC" < /dev/null | tr -d '\r')
DUR=$(fp_run -v error -show_entries format=duration -of csv=p=0 "$SRC" < /dev/null | tr -d '\r' | cut -d. -f1)
case "$SW$SH$DUR" in ""|*[!0-9]*) echo "ERROR: ffprobe failed on $SRC"; exit 2 ;; esac
SS=$((DUR / 2))

# effective encode size: optional height cap, kept even
W2="$SW"; H2="$SH"
if [ "$CAP" -gt 0 ] 2>/dev/null && [ "$SH" -gt "$CAP" ]; then
    W2=$((SW * CAP / SH)); W2=$((W2 - W2 % 2)); H2=$((CAP - CAP % 2))
fi
PIX=$((W2 * H2))

T=$(lookup_bitrate "$PIX" "$CSV_NAME") || {
    echo "ERROR: pixel count $PIX outside $CSV_NAME range"; exit 2; }

PREP="fps=30,format=yuv420p,setsar=1"
if [ "$H2" -ne "$SH" ] || [ "$W2" -ne "$SW" ]; then
    PREP="scale=${W2}:${H2}:flags=lanczos,${PREP}"
fi
if [ "$H2" -ge 2160 ]; then MODEL="vmaf_4k_v0.6.1"; else MODEL="vmaf_v0.6.1"; fi

# The work dir is scoped to the parameter set: s<ss>t<len>_<W>x<H>_T<T>_<source bytes>.
# The "if the file exists" guards below keep a rerun cheap, so the directory MUST
# change whenever anything that changes the result changes - and it did not. A run
# printed "seg 30s" over artifacts left behind by an earlier test at a different
# segment length and reported their numbers as its own (user report, 2026-09-20:
# this side said 1783203 bps, the .bat side 2039817 bps on the same source).
# A parameter-scoped dir makes stale reuse impossible, with no signature
# bookkeeping, and its name doubles as a record of what produced the artifacts.
# Same rule on the .bat side (test/bat/bench_calib.bat).
WORK="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bench_calib_${CODEC}}"
WORK="$WORK/s${SS}t${LEN}_${W2}x${H2}_T${T}_$(src_stamp "$SRC")"
mkdir -p "$WORK"
CSV="$WORK/results.csv"
printf 'res,codec,br_req,br_delivered,vmaf\n' > "$CSV"

echo "source : $SRC"
echo "ffmpeg : $FF ($(ffmpeg_build_id "$FF"))"
echo "encode : ${W2}x${H2} fps30  seg ${LEN}s from ${SS}s  encoder $ENC ($PSET)"
echo "table  : $CSV_NAME -> T=$T   ladder: T/4 T/3 T/2 3T/4 T"
echo "vmaf   : model $MODEL (reference = the source itself)"
echo "work   : $WORK"
echo

encode_ladder() {
    local br tag out
    # The same five points as test/bat/bench_calib.bat, computed the same way.
    # This used to be T*25/100, T*33/100, ... which is not the ladder the header
    # (and the .bat side) documents: 33% is not 1/3, so point 2 was 897519 here
    # against 906585 there, and the artifact names disagreed for a same ladder.
    for br in $((T / 4)) $((T / 3)) $((T / 2)) $((T * 3 / 4)) "$T"; do
        [ "$br" -lt 100 ] && br=100
        tag="${W2}x${H2}_${br}"
        out="$WORK/$tag.mp4"
        if [ ! -f "$out" ]; then
            ff_run -y -hide_banner -loglevel error -ss "$SS" -t "$LEN" -i "$SRC" \
                -vf "$PREP" -c:v "$ENC" -preset "$PSET" -b:v "$br" -an "$out" < /dev/null \
                || { echo "  ENCODE FAIL $tag"; continue; }
        fi
        local del vm js
        del=$(fp_run -v error -select_streams v:0 -show_entries stream=bit_rate \
              -of csv=p=0 "$out" < /dev/null | tr -d '\r')
        # mp4 carries a per-stream rate, other containers (mkv) do not - fall
        # back to the container average rather than reporting a silent 0.
        case "$del" in ''|*[!0-9]*) del=$(fp_run -v error -show_entries \
              format=bit_rate -of csv=p=0 "$out" < /dev/null | tr -d '\r') ;; esac
        case "$del" in ''|*[!0-9]*) del=0 ;; esac
        js="$tag.json"
        if [ ! -f "$WORK/$js" ]; then
            # log_path must stay RELATIVE: an absolute path breaks the
            # filtergraph parser on Windows (drive colon = separator).
            # the reference leg needs the SAME -ss/-t as the encode leg,
            # otherwise libvmaf pairs frames from different offsets and
            # returns garbage (~0.7) scores.
            ( cd "$WORK" && ff_run -hide_banner -loglevel error \
                -i "$tag.mp4" -ss "$SS" -t "$LEN" -i "$SRC" \
                -filter_complex "[1:v]${PREP}[sref];[0:v][sref]libvmaf=model=version=${MODEL}:log_fmt=json:log_path=${js}[out]" \
                -map "[out]" -f null - < /dev/null ) \
                || { echo "  VMAF FAIL $tag"; continue; }
        fi
        # pooled_metrics holds several metric objects and every frame also
        # has a "vmaf": <number> line; only the pooled object is "vmaf": {
        vm=$(awk '
            /"vmaf"[[:space:]]*:[[:space:]]*\{/ { inv = 1 }
            inv && /"mean"[[:space:]]*:/ {
                s = $0
                sub(/.*"mean"[[:space:]]*:[[:space:]]*/, "", s)
                sub(/[,"}].*$/, "", s)
                print s; exit
            }' "$WORK/$js")
        [ -n "$vm" ] || vm=0
        printf '%sx%s,%s,%s,%s,%s\n' "$W2" "$H2" "$CODEC" "$br" "$del" "$vm" >> "$CSV"
        echo "  $tag  req=${br}  delivered=${del}  vmaf=$vm"
    done
}

solve_targets() {
    # log-linear fit vmaf ~ a*log2(delivered)+b over the CSV, then the
    # bitrate needed for each quality target. mawk-safe (no /re{n}/).
    awk -F',' -v tbl="$T" '
    NR > 1 && $4 + 0 > 0 && $5 + 0 > 0 {
        n++; x = log($4) / log(2); y = $5 + 0
        sx += x; sy += y; sxx += x * x; sxy += x * y
        printf "  point  req=%-9d delivered=%-9d vmaf=%.2f\n", $3, $4, y
    }
    END {
        if (n < 2) { print "  (not enough points to fit)"; exit }
        a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        b = (sy - a * sx) / n
        if (a <= 0) { print "  (degenerate fit, slope <= 0)"; exit }
        printf "  fit    vmaf = %.2f * log2(bitrate) %+.2f   (%d points)\n", a, b, n
        split("90 93 95 97", tg, " ")
        for (i = 1; i <= 4; i++) {
            t = tg[i]; x = (t - b) / a
            if (x > 40) printf "  VMAF%-3d beyond this ladder (x>=1e12 bps)\n", t
            else        printf "  VMAF%-3d needs ~%d bps delivered\n", t, exp(x * log(2))
        }
        x = (95 - b) / a
        rec = 0
        if (x > 40) print "\n  RECOMMENDATION: beyond this ladder (VMAF95 unreachable here)"
        else        rec = exp(x * log(2))
        if (rec > 0) printf "\n  RECOMMENDATION (VMAF95): ~%d bps\n", rec
        printf "  table T=%d, production T/2=%d -> recommendation / (T/2) = %.2f\n", tbl, tbl / 2, rec / (tbl / 2)
    }' "$CSV"
}

encode_ladder
echo
echo "==== summary ===="
solve_targets
echo
echo "csv: $CSV"
exit 0
