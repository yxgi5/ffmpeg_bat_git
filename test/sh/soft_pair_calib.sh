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
#                    (default: lib/common.sh find_ffmpeg picks a build that
#                    has libvmaf + libsvtav1 + libx265; ffprobe is taken
#                    from FFPROBE or the same directory as FFMPEG).
#                    FFMPEG=<file> pins the ffmpeg to use (same name as the .bat side)
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
# NOTE (2026-09-20): 本脚本收的是 MODE, 不是 source 路径 —— 素材是下载/放进工作目录的。
# 上一条 "the source path looks split on spaces" 守卫是从 bench_calib.sh 抄过来的, 放在这里
# 是错的: 它会把一个拼错的 mode 说成"路径被空格切开", 把排查方向带偏。已删除, 改为真正
# 校验 MODE, 多余的参数也要报出来。
# Resolve ffmpeg through lib/common.sh's find_ffmpeg (same four-level fallback as
# lib/common.bat: FFMPEG_BIN/FFMPEG > repo ffmpeg/bin > PATH > well-known prefixes),
# skipping candidates that lack libvmaf. Plain PATH lookup is not enough on Windows:
# an MSYS2 shell resolves `ffmpeg` to /mingw64/bin 8.1 (no libvmaf) while the gyan
# full build sits one level further down the list. The library is optional on
# purpose - this script is also meant to be copyable to a bare remote box, where it
# simply falls back to whatever `ffmpeg` PATH hands it (FFMPEG/FFPROBE still win).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$SELF_DIR/../../lib/common.sh" ]; then
    # shellcheck source=../../lib/common.sh
    . "$SELF_DIR/../../lib/common.sh"
fi
# 统一 --help / -help / -h: 与 .bat 孪生同一套版式(见 lib/common.sh 的 ff_usage_block)
# 必须在 MODE 解析之前(2026-10-08 修): 否则 --help 会被下面的 case 当成 unknown mode
# 拦掉, 与其它 37 个脚本的 --help 行为不一致。common.sh 条件加载, 守卫排在其后。
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" -- \
    "soft_pair_calib.sh  -  软编等质量配对标定（SVT-AV1 p8 对 libx265 fast）" \
    "用法: bash test/sh/soft_pair_calib.sh [full 或 1080 或 probe]" \
    "full（默认，720p + 1080p + 2160p 一起标）/ 1080（只跑 1080p，轻量交叉核对）/ probe（只查工具链）" || :
MODE="${1:-full}"
case "$MODE" in
    full|1080|probe) ;;
    *) echo "ERROR: unknown mode [$MODE] - expected full | 1080 | probe"; exit 1 ;;
esac
if [ "$#" -gt 1 ]; then
    echo "ERROR: too many arguments ($#) - this script takes one mode only."
    echo "       usage: test/sh/soft_pair_calib.sh [full|1080|probe]"
    exit 1
fi
if declare -F find_ffmpeg >/dev/null 2>&1; then
    FF="$(find_ffmpeg --need-filter libvmaf --need-encoder libsvtav1 --need-encoder libx265)" || {
        echo "FATAL: no ffmpeg with libvmaf + libsvtav1 + libx265 was found"
        echo "       set FFMPEG=/path/to/ffmpeg"
        exit 1; }
    FP="$(find_ffprobe "$FF")" || { echo "FATAL: no ffprobe next to $FF"; exit 1; }
elif [ -n "${FFMPEG:-}" ]; then
    FF="$FFMPEG"
    FP="${FFPROBE:-$(dirname "$FF")/ffprobe}"
else
    FF=ffmpeg
    FP=ffprobe
fi
# Every call that touches a file goes through ff_run/fp_run (lib/common.sh): they
# hand a native Windows build the X:/... spelling it can actually open, because
# Cygwin does not rewrite POSIX argv paths for native child processes (see
# native_path). Without lib/common.sh there is nothing to translate.
if ! declare -F ff_run >/dev/null 2>&1; then
    ff_run() { "$FF" "$@"; }
    fp_run() { "$FP" "$@"; }
fi
W="${SOFT_PAIR_WORK:-$HOME/ffmpeg_soft_pair_calib}"
LOG="$W/logs"; REF="$W/ref"; ENC="$W/enc"
mkdir -p "$LOG" "$REF" "$ENC"
cd "$W" || exit 1

echo "=== toolchain check ==="
"$FF" -hide_banner -encoders 2>/dev/null | grep -qE "libsvtav1" || { echo "FATAL: no libsvtav1"; exit 1; }
"$FF" -hide_banner -encoders 2>/dev/null | grep -qE "libx265"    || { echo "FATAL: no libx265"; exit 1; }
"$FF" -hide_banner -filters 2>/dev/null | grep -qE "libvmaf"     || { echo "FATAL: no libvmaf"; exit 1; }
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
        ff_run -y -hide_banner -loglevel error -i "$REF/ref_bbb_1080.mp4" \
            -vf "scale=3840:2160:flags=lanczos,setsar=1,format=yuv420p" \
            -c:v libx264 -crf 10 -preset slow -an "$REF/ref_bbb_2160.mp4"
    fi
fi

# ---- prep near-transparent references (normalize fps/sar/pixfmt) ----
for key in "${!SRC[@]}"; do
    dim="${SRC[$key]}"; wh="${dim%%:*}x${dim##*:}"
    if [ ! -s "$REF/ref_$key.mp4" ]; then
        echo "prep  ref_$key ($wh)"
        ff_run -y -hide_banner -loglevel error -i "src_${key}.mp4" \
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
                                ff_run -hide_banner -loglevel error -i "$ref" -i "$ref" \
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
                ff_run -y -hide_banner -loglevel error -i "$ref" -c:v "$enc" $opts -b:v "$br" -an "$out" \
                    || { echo "encode FAIL $tag"; continue; }
            fi
            delivered=$(fp_run -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$out")
            case "$delivered" in ''|*[!0-9]*) delivered=$(fp_run -v error -show_entries format=bit_rate -of csv=p=0 "$out") ;; esac
            if [ ! -s "$js" ]; then
                echo "vmaf  $tag (delivered ${delivered}bps)"
                # log_path is deliberately cwd-relative: an absolute path
                # with a drive colon breaks libvmaf's filter-arg parser on
                # Windows (and POSIX /c/... paths are not rewritten there).
                ff_run -hide_banner -loglevel error -i "$out" -i "$ref" \
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
