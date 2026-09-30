#!/usr/bin/env bash
# 生成入口测试素材：10bit 源 与 4K 片段（60/25 fps），均含 ac3 音轨 + ass 字幕。
#
# 用法:
#   bash test/make_fixtures.sh              # 生成全部素材
#   bash test/make_fixtures.sh 10bit        # 只生成 10bit 素材
#   bash test/make_fixtures.sh 4k           # 只生成 4K 素材
#   bash test/make_fixtures.sh 4k60         # 只生成 4K60 素材
#   bash test/make_fixtures.sh input_hevc_4k60.mkv   # 只生成指定素材
#
# 环境变量:
#   FFMPEG  指定 ffmpeg 可执行文件（默认自动探测本机常见位置）
#   OUTDIR  产物输出目录（默认仓库根目录）
#
# 产物为 input_*.mkv，已被 .gitignore 忽略，不入库；入库的只有本脚本。
set -u

cd "$(dirname "$0")/.." || exit 1
OUTDIR=${OUTDIR:-.}

# ffmpeg 定位直接复用入口那套(lib/common.sh 的 find_ffmpeg):
#   不能只信 command -v —— Cygwin / MSYS2 的 PATH 首项常是 shell 自带那份原生构建
#   (Cygwin 7.1.1 就没有 libx264 / libx265), 造素材会直接 "Unknown encoder"。
#   按"必须带 libx264 与 libx265"筛, 才会落到机器上那份完整构建上。
# shellcheck source=lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if [ -n "${FFMPEG:-}" ]; then
    :
elif FFMPEG=$(find_ffmpeg --need-encoder libx264 --need-encoder libx265 2>/dev/null); then
    :
elif FFMPEG=$(find_ffmpeg --need-encoder libx265 2>/dev/null); then
    :
elif FFMPEG=$(find_ffmpeg 2>/dev/null); then
    :
else
    FFMPEG=""
fi
if [ -z "$FFMPEG" ] || [ ! -x "$FFMPEG" ]; then
  echo "make_fixtures: 找不到 ffmpeg，请用 FFMPEG=/path/to/ffmpeg 指定" >&2
  exit 2
fi
# 后续一律走 ff_run(不是直接 "$FFMPEG"): 选中的常是原生 Windows 构建, 它吃不了
# /tmp/... / /cygdrive/... 这类 POSIX 路径(实测 "No such file or directory"),
# ff_run 会把以 / 开头的参数改写成原生写法。纯 Linux 上恒等。
export FF="$FFMPEG"

TMPASS=$(mktemp "${TMPDIR:-/tmp}/fixture.XXXXXX.ass")
trap 'rm -f "$TMPASS"' EXIT
cat > "$TMPASS" <<'ASS'
[Script Info]
ScriptType: v4.00+
PlayResX: 640
PlayResY: 360

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Microsoft YaHei,24,&H00FFFFFF,&H000000FF,&H80000000,0,0,1,2,0,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,素材测试 第一行
Dialogue: 0,0:00:02.00,0:00:04.00,Default,,0,0,0,,第二行 中文 [A&B] (元字符)
Dialogue: 0,0:00:04.00,0:00:06.00,Default,,0,0,0,,third line ascii
Dialogue: 0,0:00:06.00,0:00:08.00,Default,,0,0,0,,第四行 字幕
Dialogue: 0,0:00:08.00,0:00:10.00,Default,,0,0,0,,end
ASS

# mk <输出名> <视频编码器> <pix_fmt> <尺寸> <帧率> [额外编码参数...]
mk() {
  out=$1; vcodec=$2; pix=$3; size=$4; fps=$5; shift 5
  extra=""
  if [ "$vcodec" = "libx265" ]; then extra="-x265-params log-level=error"; fi
  printf 'make_fixtures: %s (%s %s %sfps %s)\n' "$out" "$vcodec" "$size" "$fps" "$pix"
  # shellcheck disable=SC2086
  ff_run -hide_banner -v error -y \
    -f lavfi -i "testsrc2=s=${size}:r=${fps}:d=10" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
    -i "$TMPASS" \
    -map 0:v -map 1:a -map 2:s \
    -c:v "$vcodec" -pix_fmt "$pix" -preset ultrafast $extra "$@" \
    -c:a ac3 -b:a 192k -c:s ass -metadata:s:s:0 language=chi \
    "$OUTDIR/$out"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$OUTDIR/$out" ]; then
    printf 'make_fixtures:   -> %s ok\n' "$out"
  else
    printf 'make_fixtures:   -> %s 失败 rc=%s\n' "$out" "$rc" >&2
  fi
  return $rc
}

want=${1:-all}
match() { # 判断某个素材是否被本次筛选命中
  case "$want" in
    all) return 0 ;;
    "$1") return 0 ;;
    10bit) case "$1" in *10.mkv) return 0 ;; *) return 1 ;; esac ;;
    4k) case "$1" in *_4k*) return 0 ;; *) return 1 ;; esac ;;
    4k60) case "$1" in *_4k60*) return 0 ;; *) return 1 ;; esac ;;
    4k25) case "$1" in *_4k25*) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

rc_all=0
for spec in \
  "input_hevc10.mkv|libx265|yuv420p10le|640x360|25" \
  "input_avc10.mkv|libx264|yuv420p10le|640x360|25|-profile:v high10" \
  "input_hevc_4k60.mkv|libx265|yuv420p|3840x2160|60" \
  "input_avc_4k60.mkv|libx264|yuv420p|3840x2160|60|-profile:v high" \
  "input_hevc_4k25.mkv|libx265|yuv420p|3840x2160|25" \
  "input_avc_4k25.mkv|libx264|yuv420p|3840x2160|25|-profile:v high" ; do
  name=${spec%%|*}
  rest=${spec#*|}
  vcodec=${rest%%|*}; rest=${rest#*|}
  pix=${rest%%|*}; rest=${rest#*|}
  size=${rest%%|*}; rest=${rest#*|}
  fps=${rest%%|*}
  # 最后一段没有 | 时(该素材没有额外编码参数), ${rest#*|} 会原样返回整个值 ——
  # 于是帧率被当成"额外编码参数"再传一遍, ffmpeg 把它当输出文件(实测
  # "Unable to choose an output format for '60'")。没有就置空。
  case "$rest" in *"|"*) rest=${rest#*|} ;; *) rest="" ;; esac
  match "$name" || continue
  mk "$name" "$vcodec" "$pix" "$size" "$fps" $rest || rc_all=1
done

exit $rc_all
