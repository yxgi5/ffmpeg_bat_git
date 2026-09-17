#!/bin/bash
# soft_pair_calib.sh - software-codec equal-quality pair calibration
# (SVT-AV1 p8 vs libx265 fast), the software twin of nvenc_pair_calib
# (hardware NVENC pair: test/sh/nvenc_pair_calib.sh + test/bat twin).
# Where bench_calib answers "what target bitrate keeps THIS source good",
# this tool answers the codec-family question "at equal VMAF, how many
# bits does software AV1 need relative to software HEVC".
#
# usage: soft_pair_calib.sh [full|1080|probe]
#   probe : toolchain check only (libsvtav1 + libx265 + libvmaf)
#   1080  : 1080p clips only (light cross-check)
#   full  : 720p + 1080p + 2160p (main run; the 4K reference is an
#           upscaled 1080p, so 4K numbers carry that caveat - they apply
#           equally to both codecs, only the ratio is meaningful)
#
# Output: <work>/results.csv (columns: clip,codec,br_req,br_delivered,vmaf)
# Solve the equal-quality bitrate ratio from that CSV with the maintained
# solver:   test/py/eq_quality_solve.py <work>/results.csv
# (the inline summary at the end is a self-contained fallback kept so the
# script stays runnable on a bare remote box without this repo).
#
# Environment overrides:
#   FFMPEG=...       ffmpeg to use, e.g. a master build under /opt
#                    (default: "ffmpeg" on PATH; ffprobe is taken from
#                    FFPROBE or the same directory as FFMPEG)
#   SOFT_PAIR_WORK=  work dir (default: ~/ffmpeg_soft_pair_calib).
#                    Avoid spaces: the path is embedded in a -lavfi filter
#                    string (libvmaf log_path), which cannot quote it.
#   SKIP_DOWNLOAD=1  never touch the network - you must have placed the
#                    src_*.mp4 clips into the work dir yourself (handy
#                    for offline machines and smoke-style dry runs).
#
# Clips: 10s h264 samples from test-videos.co.uk (Big Buck Bunny / Sintel,
# two content classes). References are near-transparent x264 crf10 slow
# transcodes normalized to fps=30/yuv420p; both codec ladders encode from
# that same reference so VMAF compares like with like.
# libvmaf notes (learned the hard way, see environment_matrix.md):
#   - the reference leg must span exactly the frames fed to it (here both
#     legs read the same full file, so no -ss/-t drift can occur);
#   - JSON mean must be read from the pooled_metrics "vmaf" object, not
#     the first "mean" in the file (frame rows and integer_adm2 pollute);
#   - on Windows/MSYS the log_path must be RELATIVE (a drive-letter colon
#     breaks filter-arg parsing), hence the cwd-relative logs/ paths.
set -u
MODE="${1:-full}"
if [ -n "${FFMPEG:-}" ]; then
    FF="$FFMPEG"
    FP="${FFPROBE:-$(dirname "$FF")/ffprobe}"
else
    FF=ffmpeg
    FP=ffprobe
fi
W="${SOFT_PAIR_WORK:-$HOME/ffmpeg_soft_pair_calib}"
LOG="$W/logs"; REF="$W/ref"; ENC="$W/enc"
mkdir -p "$LOG" "$REF" "$ENC"
cd "$W" || exit 1

echo "=== toolchain check ==="
$FF -hide_banner -encoders 2>/dev/null | grep -qE "libsvtav1" || { echo "FATAL: no libsvtav1"; exit 1; }
$FF -hide_banner -encoders 2>/dev/null | grep -qE "libx265"    || { echo "FATAL: no libx265"; exit 1; }
$FF -hide_banner -filters 2>/dev/null | grep -qE "libvmaf"     || { echo "FATAL: no libvmaf"; exit 1; }
[ "$MODE" = probe ] && { echo "toolchain OK"; exit 0; }

# ---- download clips (10s h264 sources, two content classes) ----
get() { # url outfile
    local url="$1" out="$2"
    if [ -s "$out" ]; then echo "have  $out"; return 0; fi
    if [ -n "${SKIP_DOWNLOAD:-}" ]; then echo "SKIP  $out (SKIP_DOWNLOAD set)"; return 1; fi
    curl -fsSL -m 300 -o "$out.part" "$url" && mv "$out.part" "$out" && echo "got   $out" || { echo "FAIL  $url"; return 1; }
}
declare -A SRC
if [ "$MODE" = full ]; then
    get "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_10MB.mp4"   src_bbb_720.mp4  && SRC[bbb_720]=1280:720
    get "https://test-videos.co.uk/vids/sintel/mp4/h264/720/Sintel_720_10s_10MB.mp4"                 src_sil_720.mp4  && SRC[sil_720]=1280:720
fi
get "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4" src_bbb_1080.mp4 && SRC[bbb_1080]=1920:1080
get "https://test-videos.co.uk/vids/sintel/mp4/h264/1080/Sintel_1080_10s_30MB.mp4"               src_sil_1080.mp4 && SRC[sil_1080]=1920:1080
if [ "${#SRC[@]}" -eq 0 ]; then
    echo "FATAL: no source clips available (offline? pre-place src_*.mp4 in $W)"
    exit 1
fi
echo "clips: ${!SRC[@]}"

# 4K: no downloadable 4K source -> upscale the BBB 1080 reference (caveat:
# softer content than a true 4K master; applies equally to both codecs)
if [ "$MODE" = full ]; then
    SRC[bbb_2160]=3840:2160
    if [ -s "$REF/ref_bbb_1080.mp4" ] && [ ! -s "$REF/ref_bbb_2160.mp4" ]; then
        echo "prep  ref_bbb_2160 (upscaled from ref_bbb_1080)"
        $FF -y -hide_banner -loglevel error -i "$REF/ref_bbb_1080.mp4" \
            -vf "scale=3840:2160:flags=lanczos,setsar=1,format=yuv420p" \
            -c:v libx264 -crf 10 -preset slow -an "$REF/ref_bbb_2160.mp4"
    fi
fi

# ---- prep near-transparent references (normalize fps/sar/pixfmt) ----
for key in "${!SRC[@]}"; do
    dim="${SRC[$key]}"; wh="${dim%%:*}x${dim##*:}"
    if [ ! -s "$REF/ref_$key.mp4" ]; then
        echo "prep  ref_$key ($wh)"
        $FF -y -hide_banner -loglevel error -i "src_${key}.mp4" \
            -vf "scale=$wh:flags=lanczos,setsar=1,fps=30,format=yuv420p" \
            -c:v libx264 -crf 10 -preset slow -an "$REF/ref_$key.mp4" || { echo "prep FAIL $key"; continue; }
    fi
done

# ---- encode ladders + VMAF ----
LADDER_720="800k 1600k 3200k"
LADDER_1080="1500k 3300k 6600k"
LADDER_2160="4000k 8000k 16000k"
RESULT="$W/results.csv"
echo "clip,codec,br_req,br_delivered,vmaf,model" > "$RESULT"

vmaf_mean() { python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
pm=d.get('pooled_metrics',{})
v=pm.get('vmaf',pm.get('vmaf_neg'))
print('%.3f'%v['mean'] if v else 'NA')
" "$1" 2>/dev/null || echo NA; }

for key in "${!SRC[@]}"; do
    dim="${SRC[$key]}"; wh="${dim%%:*}x${dim##*:}"
    ref="$REF/ref_$key.mp4"
    [ -s "$ref" ] || continue
    case "$key" in *_720)  LADDER="$LADDER_720";  MODEL="model=version=vmaf_v0.6.1"      ;;
                    *_1080) LADDER="$LADDER_1080"; MODEL="model=version=vmaf_v0.6.1"    ;;
                    *_2160) LADDER="$LADDER_2160";
                            # verify 4k model once; fall back to default
                            if [ -z "${MODEL_4K_CHECK:-}" ]; then
                                MODEL_4K_CHECK=1
                                $FF -hide_banner -loglevel error -i "$ref" -i "$ref" \
                                    -lavfi "libvmaf=model=version=vmaf_4k_v0.6.1" -f null - 2>/dev/null \
                                    && MODEL_4K="model=version=vmaf_4k_v0.6.1" || MODEL_4K="model=version=vmaf_v0.6.1"
                                echo "4k model: $MODEL_4K"
                            fi
                            LADDER="$LADDER_2160"; MODEL="$MODEL_4K" ;;
    esac
    for br in $LADDER; do
        for pair in "x265:libx265:-preset fast" "av1:libsvtav1:-preset 8"; do
            tag="${pair%%:*}"; rest="${pair#*:}"
            enc="${rest%%:*}"; opts="${rest#*:}"
            tag="${key}_${br}_${tag}"; out="$ENC/$tag.mp4"; js="logs/$tag.json"
            if [ ! -s "$out" ]; then
                echo "enc   $tag"
                # shellcheck disable=SC2086
                $FF -y -hide_banner -loglevel error -i "$ref" -c:v "$enc" $opts -b:v "$br" -an "$out" \
                    || { echo "encode FAIL $tag"; continue; }
            fi
            delivered=$($FP -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$out")
            if [ ! -s "$js" ]; then
                echo "vmaf  $tag (delivered ${delivered}bps)"
                # log_path is deliberately cwd-relative: an absolute path
                # with a drive colon breaks libvmaf's filter-arg parser on
                # Windows (and POSIX /c/... paths are not rewritten there).
                $FF -hide_banner -loglevel error -i "$out" -i "$ref" \
                    -lavfi "libvmaf=$MODEL:log_fmt=json:log_path=$js" -f null - 2>"$LOG/$tag.err" \
                    || { echo "vmaf FAIL $tag"; tail -2 "$LOG/$tag.err"; continue; }
            fi
            echo "$key,${pair%%:*},$br,$delivered,$(vmaf_mean "$js"),$MODEL" >> "$RESULT"
        done
    done
done

# ---- solve equal-quality bitrate ratio per (clip, target vmaf) ----
# This inline solver is the self-contained fallback; the maintained,
# richer version lives in test/py/eq_quality_solve.py (same CSV format).
python3 - "$RESULT" > "$W/summary.txt" << 'PYEOF'
import csv, sys, math
rows = list(csv.DictReader(open(sys.argv[1])))
data = {}
for r in rows:
    if r['vmaf'] in ('NA',''): continue
    data.setdefault((r['clip'], r['codec']), []).append((float(r['br_delivered']), float(r['vmaf'])))
def fit(pts):
    xs=[math.log2(b) for b,_ in pts]; ys=[v for _,v in pts]
    n=len(xs); sx=sum(xs); sy=sum(ys); sxx=sum(x*x for x in xs); sxy=sum(x*y for x,y in zip(xs,ys))
    a=(n*sxy-sx*sy)/(n*sxx-sx*sx); b=(sy-a*sx)/n
    return a,b
print("equal-quality bitrate ratio  AV1/HEVC  (r<1 means AV1 needs fewer bits)")
print(f"{'clip':<14}{'target':>7}{'brHEVC':>10}{'brAV1':>10}{'r':>7}")
res={}
for (clip), _ in sorted({k[0]:1 for k in data}.items()):
    hx=data.get((clip,'x265')); ax=data.get((clip,'av1'))
    if not hx or not ax: continue
    (ah,bh)=fit(hx); (aa,ba)=fit(ax)
    lo=max(min(v for _,v in hx),min(v for _,v in ax))+1
    hi=min(max(v for _,v in hx),max(v for _,v in ax))-1
    if hi<=lo: print(f"{clip:<14}  overlap too small"); continue
    for T in (90,93,96):
        if not (lo<=T<=hi): continue
        bh=2**((T-bh)/ah); ba_=2**((T-ba)/aa)
        print(f"{clip:<14}{T:>7}{bh:>10.0f}{ba_:>10.0f}{ba_/bh:>7.3f}")
        res.setdefault(clip.rstrip('0123456789_').replace('_',''),[]).append(ba_/bh)
print()
if res:
    import statistics
    for k,v in res.items(): print(f"AGGREGATE {k:<10} r = {statistics.mean(v):.3f}  (n={len(v)})")
PYEOF

echo; echo "=== summary ==="; cat "$W/summary.txt"
echo "CALIB DONE"
