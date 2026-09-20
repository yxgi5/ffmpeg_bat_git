#!/bin/bash
# ============================================================
# nvenc_pair_calib.sh - AV1 vs HEVC equal-quality calibration
#                        for THIS machine's hardware encoders
#
#   Measures the bitrate ratio r = bitrate(AV1) / bitrate(HEVC)
#   at equal VMAF for the NVIDIA hardware encoders:
#   hevc_nvenc vs av1_nvenc, both preset p4 CBR - exactly the
#   parameterisation the repo's entry scripts use in production.
#
#   PARITY NOTE: 1:1 twin of test/bat/nvenc_pair_calib.bat.
#   Same segment (silent 10s from the middle), same near-
#   transparent x264 references (crf 10, 720p / 1080p, 4K only
#   if the source is 4K), same 3-point ladders, same results.csv
#   columns. The curve fitting is done off-box: run
#   test/py/nvenc_pair_solve.py on the work dir afterwards.
#
#   Usage:  bash test/sh/nvenc_pair_calib.sh [source]
#     source  : video file; prompted if omitted. If an unquoted command
#               substitution split the path on spaces, the pieces are glued
#               back automatically (it says so when it happens).
#
#   Work dir: ${TMPDIR:-/tmp}/ffmpeg_bat_nvenc_pair  (safe to delete)
#   Exit code: 0 = results.csv written; 2 = setup error
#   Requires: ffmpeg/ffprobe with libvmaf, NVIDIA GPU with
#   HEVC NVENC + AV1 NVENC (Ada or newer). ASCII only, LF.
#   Env knobs: WORK=<dir>, FFMPEG_BIN=<bin dir> / FFMPEG=<file> to pin
#   the ffmpeg (otherwise find_ffmpeg in lib/common.sh picks a build
#   that actually has libvmaf, instead of trusting PATH).
# ============================================================

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve ffmpeg through lib/common.sh's find_ffmpeg (same four-level fallback as
# lib/common.bat: FFMPEG_BIN/FFMPEG > repo ffmpeg/bin > PATH > well-known prefixes),
# skipping candidates that lack libvmaf. Plain PATH lookup is not enough on Windows:
# an MSYS2 shell resolves `ffmpeg` to /mingw64/bin 8.1 (no libvmaf) while the gyan
# full build sits one level further down the list. The library is optional on
# purpose - this script is also meant to be copyable to a bare remote box, where it
# simply falls back to whatever `ffmpeg` PATH hands it.
if [ -r "$SELF_DIR/../../lib/common.sh" ]; then
    # shellcheck source=../../lib/common.sh
    . "$SELF_DIR/../../lib/common.sh"
fi
if declare -F find_ffmpeg >/dev/null 2>&1; then
    FF="$(find_ffmpeg --need-filter libvmaf)" || {
        echo "ERROR: no ffmpeg with the libvmaf filter was found."
        echo "       install a full build or set FFMPEG_BIN=/path/to/bin (or FFMPEG=/path/to/ffmpeg)."
        exit 2; }
    FP="$(find_ffprobe "$FF")" || { echo "ERROR: no ffprobe next to $FF and none on PATH"; exit 2; }
else
    FF=ffmpeg; FP=ffprobe
fi
# Every call that touches a file goes through ff_run/fp_run (lib/common.sh): they
# hand a native Windows build the X:/... spelling it can actually open, because
# Cygwin does not rewrite POSIX argv paths for native child processes (see
# native_path). Without the library there is nothing to translate.
if ! declare -F ff_run >/dev/null 2>&1; then
    ff_run() { "$FF" "$@"; }
    fp_run() { "$FP" "$@"; }
fi
"$FF" -hide_banner -encoders 2>/dev/null | grep -q " av1_nvenc " \
    || { echo "ERROR: no av1_nvenc in $FF - AV1 NVENC needs an Ada (RTX 40) or newer GPU"; exit 2; }
"$FF" -hide_banner -encoders 2>/dev/null | grep -q " hevc_nvenc " \
    || { echo "ERROR: no hevc_nvenc in $FF"; exit 2; }

# 反引号或 $( ) 形式的命令替换写在引号外面时, shell 会把整条路径按空格切开, 于是一条
# source 变成好几个参数(典型: cygpath "F:\a b\c.mp4" 外面忘了加引号)。有 lib/common.sh
# 时把最长前缀粘回去(rejoin_split_path); 该库是可选的(本脚本要能拷到裸机上跑), 没有它
# 就只能按单参数处理。
SRC="${1:-}"
GLUED=""
if [ "$#" -gt 1 ]; then
    if [ "$(type -t rejoin_split_path)" = "function" ]; then
        rejoin_split_path "$@"
        SRC="$REJOIN_PATH"
        [ "$REJOIN_N" -gt 1 ] && GLUED="yes"
        if [ "$#" -gt "$REJOIN_N" ]; then
            echo "ERROR: too many arguments ($#)."
            echo "       usage: test/sh/nvenc_pair_calib.sh [source]"
            exit 1
        fi
    else
        echo "ERROR: too many arguments ($#)."
        echo "       usage: test/sh/nvenc_pair_calib.sh [source]"
        exit 1
    fi
fi
if [ -n "$GLUED" ]; then
    echo "note: the shell had split the source path on spaces ($# arguments); glued back to"
    echo "      [$SRC]"
fi

if [ -z "$SRC" ]; then
    printf 'enter the full path of a video file: '
    read -r SRC
fi
# Accept a Windows path (F:\... / F:/...) directly; the helper comes from
# lib/common.sh, which is optional on purpose (this script is copyable to a bare
# remote box that has no repo around it).
if declare -F normalize_source_path >/dev/null 2>&1; then
    SRC="$(normalize_source_path "$SRC")"
fi
[ -n "$SRC" ] && [ -f "$SRC" ] || {
    echo "ERROR: source video not found or not given"
    echo "       tried: [$SRC]"
    exit 2; }

SW=$(fp_run -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$SRC" < /dev/null | tr -d '\r')
DUR=$(fp_run -v error -show_entries format=duration -of csv=p=0 "$SRC" < /dev/null | tr -d '\r' | cut -d. -f1)
case "$SW$DUR" in ""|*[!0-9]*) echo "ERROR: ffprobe failed on $SRC (no video stream?)"; exit 2 ;; esac
SS=$((DUR / 2))

# Per-parameter subdir for the same reason as test/sh/bench_calib.sh: the cached
# ref_<W>x<H>.mp4 and the per-point mp4/json are reused when present, so the
# directory has to change when the source or the segment start does.
if declare -F src_stamp >/dev/null 2>&1; then
    SZ="$(src_stamp "$SRC")"
else
    SZ="$(wc -c < "$SRC" 2>/dev/null | tr -d ' ')"
fi
WORK="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_nvenc_pair}"
WORK="$WORK/s${SS}t10_${SZ}"
mkdir -p "$WORK"
CSV="$WORK/results.csv"
printf 'res,codec,br_req,br_delivered,vmaf\n' > "$CSV"

echo "source : $SRC"
echo "ffmpeg : $FF"
echo "width  : $SW   segment start: ${SS}s"
echo "work   : $WORK"

score_point() {
    # score_point <W> <H> <codec> <br> <ref> <model>
    local w="$1" h="$2" codec="$3" br="$4" ref="$5" model="$6"
    local tag out del js vm
    tag="${w}x${h}_${br}_${codec}"
    out="$WORK/$tag.mp4"
    js="$tag.json"
    if [ ! -f "$out" ]; then
        ff_run -y -hide_banner -loglevel error -i "$ref" \
            -c:v "$codec" -preset p4 -rc cbr -b:v "$br" -an "$out" < /dev/null \
            || { echo "  ENCODE FAIL $tag"; return 1; }
    fi
    del=$(fp_run -v error -select_streams v:0 -show_entries stream=bit_rate \
          -of csv=p=0 "$out" < /dev/null | tr -d '\r')
    # containers without a per-stream rate fall back to the average, so the
    # column is never a silent 0 (same rule as test/sh/bench_calib.sh).
    case "$del" in ''|*[!0-9]*) del=$(fp_run -v error -show_entries \
          format=bit_rate -of csv=p=0 "$out" < /dev/null | tr -d '\r') ;; esac
    case "$del" in ''|*[!0-9]*) del=0 ;; esac
    # log_path must stay RELATIVE: an absolute path breaks the
    # filtergraph parser on Windows (drive colon = separator).
    if [ ! -f "$WORK/$js" ]; then
        ( cd "$WORK" && ff_run -hide_banner -loglevel error \
            -i "$tag.mp4" -i "$ref" \
            -lavfi "libvmaf=model=version=${model}:log_fmt=json:log_path=${js}" \
            -f null - < /dev/null ) \
            || { echo "  VMAF FAIL $tag"; return 1; }
    fi
    # only the pooled object is "vmaf": { (frames carry bare "vmaf": <num>)
    vm=$(awk '
        /"vmaf"[[:space:]]*:[[:space:]]*\{/ { inv = 1 }
        inv && /"mean"[[:space:]]*:/ {
            s = $0
            sub(/.*"mean"[[:space:]]*:[[:space:]]*/, "", s)
            sub(/[,"}].*$/, "", s)
            print s; exit
        }' "$WORK/$js")
    [ -n "$vm" ] || vm=0
    printf '%sx%s,%s,%s,%s,%s\n' "$w" "$h" "$codec" "$br" "$del" "$vm" >> "$CSV"
    echo "  $tag  delivered=$del  vmaf=$vm"
    return 0
}

run_res() {
    # run_res <W> <H> <ladder...> -- <model>
    local w="$1" h="$2" model="$6" ref br
    ref="$WORK/ref_${w}x${h}.mp4"
    echo
    echo "==== reference ${w}x${h} ===="
    if [ ! -f "$ref" ]; then
        ff_run -y -hide_banner -loglevel error -ss "$SS" -t 10 -i "$SRC" \
            -vf "scale=${w}:${h}:flags=lanczos,setsar=1,fps=30,format=yuv420p" \
            -c:v libx264 -crf 10 -preset slow -an "$ref" < /dev/null \
            || return 1
    fi
    for br in "$3" "$4" "$5"; do
        score_point "$w" "$h" hevc_nvenc "$br" "$ref" "$model"
        score_point "$w" "$h" av1_nvenc "$br" "$ref" "$model"
    done
    return 0
}

run_res 1280 720 800k 1600k 3200k vmaf_v0.6.1
[ "$SW" -ge 1920 ] && run_res 1920 1080 1500k 3300k 6600k vmaf_v0.6.1
[ "$SW" -ge 3840 ] && run_res 3840 2160 4000k 8000k 16000k vmaf_4k_v0.6.1

echo
echo "==== results ===="
cat "$CSV"
echo
echo "Run test/py/nvenc_pair_solve.py on $WORK"
echo "(or paste the table above back to the assistant) to solve the"
echo "equal-quality bitrate ratio r = AV1 / HEVC."
exit 0
