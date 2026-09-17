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
#     source  : video file; prompted if omitted
#
#   Work dir: ${TMPDIR:-/tmp}/ffmpeg_bat_nvenc_pair  (safe to delete)
#   Exit code: 0 = results.csv written; 2 = setup error
#   Requires: ffmpeg/ffprobe with libvmaf, NVIDIA GPU with
#   HEVC NVENC + AV1 NVENC (Ada or newer). ASCII only, LF.
# ============================================================

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v ffmpeg >/dev/null 2>&1 || { echo "ERROR: ffmpeg not on PATH"; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { echo "ERROR: ffprobe not on PATH"; exit 2; }
ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf \
    || { echo "ERROR: this ffmpeg build has no libvmaf filter - use a gyan.dev full or master build"; exit 2; }
ffmpeg -hide_banner -encoders 2>/dev/null | grep -q " av1_nvenc " \
    || { echo "ERROR: no av1_nvenc here - AV1 NVENC needs an Ada (RTX 40) or newer GPU"; exit 2; }
ffmpeg -hide_banner -encoders 2>/dev/null | grep -q " hevc_nvenc " \
    || { echo "ERROR: no hevc_nvenc in this ffmpeg build"; exit 2; }

SRC="${1:-}"
if [ -z "$SRC" ]; then
    printf 'enter the full path of a video file: '
    read -r SRC
fi
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "ERROR: source video not found or not given"; exit 2; }

SW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$SRC" < /dev/null | tr -d '\r')
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" < /dev/null | tr -d '\r' | cut -d. -f1)
case "$SW$DUR" in *[!0-9]*) echo "ERROR: ffprobe failed on $SRC (no video stream?)"; exit 2 ;; esac
SS=$((DUR / 2))

WORK="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_nvenc_pair}"
mkdir -p "$WORK"
CSV="$WORK/results.csv"
printf 'res,codec,br_req,br_delivered,vmaf\n' > "$CSV"

echo "source : $SRC"
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
        ffmpeg -y -hide_banner -loglevel error -i "$ref" \
            -c:v "$codec" -preset p4 -rc cbr -b:v "$br" -an "$out" < /dev/null \
            || { echo "  ENCODE FAIL $tag"; return 1; }
    fi
    del=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate \
          -of csv=p=0 "$out" < /dev/null | tr -d '\r')
    case "$del" in ''|*[!0-9]*) del=0 ;; esac
    # log_path must stay RELATIVE: an absolute path breaks the
    # filtergraph parser on Windows (drive colon = separator).
    if [ ! -f "$WORK/$js" ]; then
        ( cd "$WORK" && ffmpeg -hide_banner -loglevel error \
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
        ffmpeg -y -hide_banner -loglevel error -ss "$SS" -t 10 -i "$SRC" \
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
