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
#
#   Env knobs:
#     WORK=<path>  output dir; default $TMPDIR/ffmpeg_bench_calib_<codec>
#
#   Requires: ffmpeg/ffprobe with libvmaf (gyan full / master build,
#   or a distro build with libvmaf), software encoders libx264 /
#   libx265 / libsvtav1. ASCII only, LF.
# ============================================================

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
# shellcheck source=../../lib/common.sh
. "$REPO/lib/common.sh"

CODEC="${1:-hevc}"
case "$CODEC" in
    avc|hevc|av1) ;;
    *) CODEC="hevc"; SRC_ARG="$1"; CAP_ARG="$2"; LEN_ARG="$3" ;;
esac
if [ -n "$SRC_ARG" ]; then SRC="$SRC_ARG"; else SRC="${2:-}"; fi
if [ -n "$CAP_ARG" ]; then CAP="$CAP_ARG"; else CAP="${3:-0}"; fi
if [ -n "$LEN_ARG" ]; then LEN="$LEN_ARG"; else LEN="${4:-30}"; fi

case "$CODEC" in
    avc) CSV_NAME="bitrate_table_avc.csv";  ENC="libx264";   PSET="fast" ;;
    hevc) CSV_NAME="bitrate_table_hevc.csv"; ENC="libx265";  PSET="fast" ;;
    av1) CSV_NAME="bitrate_table_av1.csv";  ENC="libsvtav1"; PSET="8" ;;
esac

command -v ffmpeg >/dev/null 2>&1 || { echo "ERROR: ffmpeg not on PATH"; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { echo "ERROR: ffprobe not on PATH"; exit 2; }
ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf \
    || { echo "ERROR: this ffmpeg build has no libvmaf filter"; exit 2; }
ffmpeg -hide_banner -encoders 2>/dev/null | grep -q " $ENC " \
    || { echo "ERROR: encoder $ENC not in this ffmpeg build"; exit 2; }

if [ -z "${SRC:-}" ]; then
    printf 'drag a video file here, or enter its full path: '
    read -r SRC
fi
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "ERROR: source video not found"; exit 2; }

SW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$SRC" < /dev/null | tr -d '\r')
SH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$SRC" < /dev/null | tr -d '\r')
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" < /dev/null | tr -d '\r' | cut -d. -f1)
case "$SW$SH$DUR" in *[!0-9]*) echo "ERROR: ffprobe failed on $SRC"; exit 2 ;; esac
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

WORK="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bench_calib_${CODEC}}"
mkdir -p "$WORK"
CSV="$WORK/results.csv"
printf 'res,codec,br_req,br_delivered,vmaf\n' > "$CSV"

echo "source : $SRC"
echo "encode : ${W2}x${H2} fps30  seg ${LEN}s from ${SS}s  encoder $ENC ($PSET)"
echo "table  : $CSV_NAME -> T=$T   ladder: T/4 T/3 T/2 3T/4 T"
echo "vmaf   : model $MODEL (reference = the source itself)"
echo "work   : $WORK"
echo

encode_ladder() {
    local frac br tag out
    for frac in 25 33 50 75 100; do
        br=$((T * frac / 100))
        [ "$br" -lt 100 ] && br=100
        tag="${W2}x${H2}_${frac}"
        out="$WORK/$tag.mp4"
        if [ ! -f "$out" ]; then
            ffmpeg -y -hide_banner -loglevel error -ss "$SS" -t "$LEN" -i "$SRC" \
                -vf "$PREP" -c:v "$ENC" -preset "$PSET" -b:v "$br" -an "$out" < /dev/null \
                || { echo "  ENCODE FAIL $tag"; continue; }
        fi
        local del vm js
        del=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate \
              -of csv=p=0 "$out" < /dev/null | tr -d '\r')
        case "$del" in ''|*[!0-9]*) del=0 ;; esac
        js="$tag.json"
        if [ ! -f "$WORK/$js" ]; then
            # log_path must stay RELATIVE: an absolute path breaks the
            # filtergraph parser on Windows (drive colon = separator).
            # the reference leg needs the SAME -ss/-t as the encode leg,
            # otherwise libvmaf pairs frames from different offsets and
            # returns garbage (~0.7) scores.
            ( cd "$WORK" && ffmpeg -hide_banner -loglevel error \
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
