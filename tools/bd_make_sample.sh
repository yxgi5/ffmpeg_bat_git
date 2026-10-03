#!/bin/bash
# =========================================================================
#  tools/bd_make_sample.sh  -  用本机 ffmpeg 合成一张"迷你 BD": BDMV 目录骨架
#                               + STREAM 下几条真 m2ts, 并顺手打成 ISO
#
#  用法:
#    ./tools/bd_make_sample.sh [输出目录] [输出ISO]
#      输出目录  默认 ./bd_sample。BDMV/ 直接建在它下面(与真盘一致)
#      输出ISO   默认 <输出目录旁边>/<目录名>.iso(不能落在输出目录里面 ——
#                和 dvd_restore.sh / dvd_to_data_iso.sh 同一个坑)
#
#  为什么要有它:
#    ffmpeg_dvd_hevc 的蓝光链路需要一个"我知道它应该长什么样"的夹具: 几条 m2ts、
#    哪条最长(MODE=AUTO 该挑它当正片)、哪条没有视频流(该被跳过)、音轨是不是
#    LPCM(该走"Matroska 装不下 -> 自动转 AAC"那条分支) —— 全是自己定的参数。
#    拿真盘(BD-M28, 19.25 GB)回归太笨重, 而且每次都要挂载一次。
#
#  它造出来的是什么 —— 边界先说清, 免得拿去当"能播的 BD"用:
#    * STREAM/*.M2TS 是**真的** MPEG-TS(ffmpeg 现编): 有视频、有音轨, ffprobe 与
#      ffmpeg 的 mpegts 解复用器都读得动 —— 本仓库入口就是这么消费它们的
#    * index.bdmv / MovieObject.bdmv / PLAYLIST / CLIPINF 只造**骨架**: magic + 版本
#      + 各段长度字段齐全, 导航内容为空。造真导航数据要按 HDMV 规范写二进制
#      (mpls 的 PlayItem、clpi 的 CPI / EP_map ...), 而本机没有一份带 bluray 解复用器
#      的 ffmpeg 能回读验证(2026-10-03 实测: gyan full build / MSYS2 8.1 / WSL 4.4.2
#      三份都没有), 写个"看着像"的假的比不写更糟 —— 所以明说是骨架。家用蓝光机
#      读不了这张盘; 本仓库入口也用不到它们(它只认 BDMV/ 存在 + STREAM/*.m2ts)
#    * ISO 是 mkisofs -udf 的 UDF 1.02/1.5 桥, **不是 BD 规范的 UDF 2.5**(mkisofs
#      造不出 2.5)。Windows 的 Mount-DiskImage 能挂、能读目录, 这就够回归用了
#
#  开关(环境变量, 写在命令之前):
#    PRESET=1080i|1080p|720p|576i|480i
#                       默认 1080i(与实测那张 BD-M28 同档: 1920x1080 TFF 29.97):
#                         1080i 1920x1080@30000/1001 隔行(TFF)   1080p 1920x1080@24000/1001
#                         720p  1280x720@60000/1001              576i  720x576@25 隔行
#                         480i  720x480@30000/1001 隔行
#    SIZE=1920x1080 / RATE=30000/1001   显式给就盖住 PRESET(给了 SIZE 也默认逐行,
#                                       要隔行自己加 INTER=1)
#    INTER=0|1       隔行开关(默认跟 PRESET 走)
#    TITLES=3        带视频的 m2ts 条数。第 1 条最长(DURATION), 其余依次短 1 秒,
#                    于是 MODE=AUTO 一定会挑中第 1 条当正片
#    DURATION=3      第 1 条(正片)的时长(秒)
#    NOVIDEO=1       额外来一条**只有音轨、没有视频流**的碎片(默认开)—— 入口脚本
#                    遇到它应当跳过, 这条就是测跳过的(AUDIO=none 时无意义, 自动关)
#    VBITRATE=2000k / ABITRATE=192k
#    AUDIO=auto|pcm|ac3|none
#                   默认 auto: 有 pcm_bluray 编码器就用 LPCM(能测上面那条分支),
#                   没有就退到 ac3。实测 MSYS2 的 8.1 有 pcm_bluray, WSL 的 Ubuntu
#                   4.4.2 没有 —— 写死 pcm 会在只装发行版 ffmpeg 的机器上第一步就挂
#    LABEL=1         画面上叠 "clip N"(需要 drawtext + 一份 ttf; 缺一样就自动关掉
#                   并告警, 不因此失败)
#    NO_ISO=1        只建目录, 不打 ISO
#    KEEP_WORK=1     保留工作目录
#
#  实测出来的坑(2026-10-03):
#    * mpeg2video 的隔行要显式给 -flags +ildct+ilme -top 1: 不给的话 1080i 素材出来
#      是逐行(ffprobe 的 field_order=progressive), 与真盘(tt)对不上, 隔行这条回归
#      就白测了
#    * 骨架文件里的 u32 大端要**直接写进重定向**, 不能走命令替换 $( ): bash 的命令
#      替换会把 NUL 字节整段吞掉(实测 u32be 0 只剩空串), 文件会比预期短一截
#    * lavfi 的 sine 默认 44.1 kHz, 而 pcm_bluray 只认 48k / 96k / 192k —— 音源上
#      要显式 sample_rate=48000, 否则 ffmpeg 直接报 Unsupported sample rate
#    * du 的合计行在中文 locale 下是"总用量"不是 total(与 dvd_make_sample 同一条),
#      打印体积要 LC_ALL=C
#
#  依赖: ffmpeg(带 mpeg2video; AUDIO=pcm 还要 pcm_bluray) + mkisofs / genisoimage
#        校验: 7z(列镜像里的文件; 没有就只报大小)
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[bd_make_sample]"
info()  { printf '%s %s\n' "$TAG" "$*"; }
warn()  { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()   { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()   { err "$*"; exit 1; }
usage() { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit "${1:-0}"; }

case "${1:-}" in -h|--help) usage 0 ;; esac

# =========================================================================
#  参数
# =========================================================================
OUT="${1:-$PWD/bd_sample}"
ISO="${2:-}"
mkdir -p "$OUT" || die "建不了输出目录: $OUT"
OUT="$(cd "$OUT" && pwd)" || die "进不去输出目录: $OUT"
BASE="$(basename "$OUT")"
PARENT="$(dirname "$OUT")"
[ -n "$ISO" ] || ISO="$PARENT/$BASE.iso"
case "$ISO" in
    "$OUT"|"$OUT"/*) die "ISO 不能放在被打包的目录里面(会把自己卷进去): $ISO" ;;
esac

DURATION="${DURATION:-3}"
TITLES="${TITLES:-3}"
NOVIDEO="${NOVIDEO:-1}"
VBITRATE="${VBITRATE:-2000k}"
ABITRATE="${ABITRATE:-192k}"
AUDIO="${AUDIO:-auto}"
LABEL="${LABEL:-1}"
NO_ISO="${NO_ISO:-0}"
KEEP_WORK="${KEEP_WORK:-0}"
SIZE="${SIZE:-}"
RATE="${RATE:-}"
INTER="${INTER:-}"

for v in "$DURATION" "$TITLES"; do
    case "$v" in
        ''|*[!0-9]*) die "DURATION / TITLES 只能是正整数(现在: $DURATION / $TITLES)" ;;
    esac
done
[ "$TITLES" -ge 1 ] || die "TITLES 至少是 1"
[ "$DURATION" -ge 1 ] || die "DURATION 至少是 1 秒"

W=""; H=""
case "${PRESET:-1080i}" in
    1080i|1080i60) W=1920; H=1080; RATE="${RATE:-30000/1001}"; INTER="${INTER:-1}" ;;
    1080p)         W=1920; H=1080; RATE="${RATE:-24000/1001}"; INTER="${INTER:-0}" ;;
    720p)          W=1280; H=720;  RATE="${RATE:-60000/1001}"; INTER="${INTER:-0}" ;;
    576i)          W=720;  H=576;  RATE="${RATE:-25}";         INTER="${INTER:-1}" ;;
    480i)          W=720;  H=480;  RATE="${RATE:-30000/1001}"; INTER="${INTER:-1}" ;;
    *)             die "PRESET 只能是 1080i / 1080p / 720p / 576i / 480i(现在: ${PRESET})" ;;
esac
# SIZE / INTER 显式给了才算数(上面已经把 PRESET 的默认值写进去了)
if [ -n "$SIZE" ]; then
    case "$SIZE" in
        [0-9]*x[0-9]*) W="${SIZE%x*}"; H="${SIZE#*x}" ;;
        *) die "SIZE 要写成 宽x高(现在: $SIZE)" ;;
    esac
fi
case "$INTER" in 0|1) ;; *) die "INTER 只能是 0 或 1(现在: $INTER)" ;; esac
case "$AUDIO" in auto|pcm|ac3|none) ;; *) die "AUDIO 只能是 auto / pcm / ac3 / none(现在: $AUDIO)" ;; esac

FS="$(awk -v h="$H" 'BEGIN{ printf "%d", h / 12 }')"     # 字号跟着分辨率走: 1080->90

WORK="$PARENT/.bd_make_sample_${BASE}"
rm -rf "$WORK"; mkdir -p "$WORK" || die "建不了工作目录: $WORK"
cleanup() { [ "$KEEP_WORK" = 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

# =========================================================================
#  依赖
# =========================================================================
# ff_run / fp_run 来自 lib/common.sh: 它们把以 / 开头的参数改写成原生写法(X:/...)。
# 不包装的话 Cygwin / MSYS2 下把 POSIX 路径喂给原生 ffmpeg.exe 就是 No such file
# or directory —— 与 dvd_make_sample.sh / dvd_restore.sh 同一批处理。
declare -F ff_run >/dev/null 2>&1 || die "lib/common.sh 未加载(ff_run 缺失) —— 请在完整仓库里运行本脚本"

FF="${FFMPEG:-}"
[ -n "$FF" ] && [ -x "$FF" ] || FF="$(find_ffmpeg --need-encoder mpeg2video 2>/dev/null)"
[ -n "$FF" ] && [ -x "$FF" ] || FF="$(command -v ffmpeg 2>/dev/null)"
[ -n "$FF" ] || die "找不到带 mpeg2video 编码器的 ffmpeg(可用 FFMPEG=/path/to/ffmpeg 指定)"

FP="${FFPROBE:-}"
[ -n "$FP" ] && [ -x "$FP" ] || FP="$(find_ffprobe "$FF" 2>/dev/null)"
[ -n "$FP" ] && [ -x "$FP" ] || FP="$(command -v ffprobe 2>/dev/null)"
[ -n "$FP" ] || die "找不到 ffprobe"

has_enc() {   # has_enc <编码器名>: 这个构建有没有
    ff_run -hide_banner -encoders 2>/dev/null |
        awk -v n="$1" '$2 == n { f = 1 } END{ exit !f }'
}

# AUDIO=auto: 有 pcm_bluray 才用 LPCM(没有就 ac3)。降级要明说, 不然"这次没测到
# LPCM 那条分支"会被当成"那条分支没问题"
ACODEC="$AUDIO"
if [ "$AUDIO" = auto ]; then
    if has_enc pcm_bluray; then ACODEC=pcm; else ACODEC=ac3; fi
fi
if [ "$ACODEC" = pcm ] && ! has_enc pcm_bluray; then
    die "AUDIO=pcm, 但这个 ffmpeg 没有 pcm_bluray 编码器(实测 WSL 的 Ubuntu 4.4.2 就没有) —— 改用 AUDIO=ac3 或 auto"
fi
[ "$ACODEC" = none ] && NOVIDEO=0   # 一条流都没有的 m2ts 编不出来, 也没得测

HAVE_7Z=0; command -v 7z >/dev/null 2>&1 && HAVE_7Z=1

echo ==========================================================
info "输出目录    : $OUT"
[ "$NO_ISO" = 1 ] || info "输出 ISO    : $ISO"
info "ffmpeg      : $FF"
info "规格        : ${W}x${H}@${RATE} $( [ "$INTER" = 1 ] && echo '隔行(TFF)' || echo '逐行' ) 视频 ${VBITRATE}"
info "m2ts        : ${TITLES} 条带视频(第 1 条 ${DURATION}s, 依次短 1s)$( [ "$NOVIDEO" = 1 ] && echo ' + 1 条无视频流的碎片' )"
info "音轨        : ${ACODEC}$([ "$AUDIO" = auto ] && echo " (auto: $([ "$ACODEC" = pcm ] && echo '这台机器有 pcm_bluray' || echo '这台机器没有 pcm_bluray, 已降级'))")"
info "工作目录    : $WORK$( [ "$KEEP_WORK" = 1 ] && echo ' (KEEP_WORK=1, 保留)' )"
echo ==========================================================

# =========================================================================
#  字体: 找不到就关掉 LABEL, 不算失败(dvd_make_sample.sh 同款)
# =========================================================================
pick_font() {
    local f
    if command -v fc-match >/dev/null 2>&1; then
        f="$(fc-match -f '%{file}' 2>/dev/null)"
        [ -n "$f" ] && [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    fi
    for f in /usr/share/fonts/truetype/*/*.ttf /usr/share/fonts/TTF/*.ttf \
             /usr/local/share/fonts/*/*.ttf /Library/Fonts/*.ttf \
             /System/Library/Fonts/*.ttf /c/Windows/Fonts/arial.ttf \
             /cygdrive/c/Windows/Fonts/arial.ttf; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}
ff_esc() {  # drawtext 的值里冒号是选项分隔符、反斜杠是转义符, 两样都得躲
    local s="$1"
    s="${s//\\//}"
    s="${s//:/\\:}"
    printf '%s' "$s"
}
FONT=""; FONT_ESC=""
if [ "$LABEL" = 1 ]; then
    if ! ff_run -hide_banner -filters 2>/dev/null | grep -q " drawtext "; then
        warn "这个 ffmpeg 没有 drawtext 滤镜 —— LABEL 关掉, 画面只有测试图"
        LABEL=0
    elif FONT="$(pick_font)"; then
        FONT_ESC="$(ff_esc "$FONT")"
    else
        warn "找不到可用的 ttf 字体 —— LABEL 关掉, 画面只有测试图"
        LABEL=0
    fi
fi

# =========================================================================
#  1) 合成 m2ts
# =========================================================================
STREAM="$OUT/BDMV/STREAM"
rm -rf "$OUT/BDMV"
mkdir -p "$STREAM" || die "建不了 $STREAM"

CLIPS=()          # 生成出来的文件名(只含带视频的)
NOVIDEO_NAME=""
make_m2ts() {
    local idx="$1" out="$2" dur="$3" novid="$4" filt=""
    local -a CMD=()
    CMD+=(-f lavfi -i "testsrc2=size=${W}x${H}:rate=${RATE}:duration=${dur}")
    [ "$ACODEC" = none ] || CMD+=(-f lavfi -i "sine=frequency=$((440 + idx * 110)):sample_rate=48000:duration=${dur}")
    if [ "$novid" = 1 ]; then
        CMD+=(-vn)
    elif [ "$LABEL" = 1 ]; then
        filt="drawtext=fontfile='$FONT_ESC':text='clip ${idx}':fontsize=${FS}:fontcolor=white:box=1:boxcolor=black@0.5:x=(w-text_w)/2:y=h-$((FS * 2))"
        CMD+=(-filter_complex "[0:v]$filt[v]" -map "[v]")
    else
        CMD+=(-map 0:v)
    fi
    [ "$ACODEC" = none ] || CMD+=(-map 1:a)
    CMD+=(-c:v mpeg2video -b:v "$VBITRATE" -pix_fmt yuv420p)
    [ "$INTER" = 1 ] && CMD+=(-flags +ildct+ilme -top 1)
    case "$ACODEC" in
        pcm) CMD+=(-c:a pcm_bluray -ac 2) ;;
        ac3) CMD+=(-c:a ac3 -b:a "$ABITRATE" -ac 2) ;;
    esac
    CMD+=(-f mpegts "$out")
    # 走 ff_run(不是直接 "$FF"): 输出路径要改写成原生写法, 否则原生 ffmpeg.exe
    # 拿到 /tmp/... 会直接 No such file or directory
    ff_run -hide_banner -v error -y "${CMD[@]}" || return 1
    return 0
}

n=0
for t in $(seq 1 "$TITLES"); do
    d="$(( DURATION - (t - 1) ))"
    [ "$d" -ge 1 ] || d=1
    name="$(printf '%05d' "$n").M2TS"
    info "生成 $(basename "$name"): ${d}s"
    if make_m2ts "$t" "$STREAM/$name" "$d" 0; then
        CLIPS+=("$name")
    else
        die "素材生成失败(工作目录: $WORK)"
    fi
    n=$(( n + 1 ))
done
if [ "$NOVIDEO" = 1 ]; then
    name="$(printf '%05d' "$n").M2TS"
    info "生成 $(basename "$name"): 只有音轨, 没有视频流(测入口脚本会不会跳过)"
    if make_m2ts "$TITLES" "$STREAM/$name" 2 1; then
        NOVIDEO_NAME="$name"
    else
        die "无视频碎片的素材生成失败(工作目录: $WORK)"
    fi
fi
# LC_ALL=C: 中文 locale 下 du 的合计行是"总用量"不是 total, awk 匹配不到 -> 空
info "素材体积    : $(LC_ALL=C du -sh "$STREAM" 2>/dev/null | awk '{print $1}')"

# =========================================================================
#  2) BDMV 骨架: index / MovieObject / PLAYLIST / CLIPINF( + BACKUP)
#      只造"结构形状", 导航内容为空 —— 理由写在文件头。
#      真盘这四样分别管: 顶层菜单入口 / 导航命令 / 播放列表 / 每条流的剪辑信息。
# =========================================================================
u32be() {   # u32be <值>: 大端 4 字节。两个坑:
            #   ① 用八进制 \%03o 而不是 \x%02x —— printf 的 \x 后面必须紧跟十六进制
            #      数字, 而 %02x 是格式符不是数字, 实测报 "missing hex digit for \x"
            #   ② **必须直接写进重定向**, 不能走 $( ): bash 的命令替换会把 NUL 字节
            #      整段吞掉(实测 u32be 0 只剩空串)
    printf "\\%03o\\%03o\\%03o\\%03o" \
        $(( ($1 >> 24) & 255 )) $(( ($1 >> 16) & 255 )) $(( ($1 >> 8) & 255 )) $(( $1 & 255 ))
}

BDMV="$OUT/BDMV"
mkdir -p "$BDMV/PLAYLIST" "$BDMV/CLIPINF" || die "建不了 BDMV 子目录"

# index.bdmv: magic + 版本 + 两个段起始地址 + AppInfoBDMV(空) + Indexes(空)
{
    printf 'INDX0200'
    u32be 24      # IndexesStartAddress: 12 字节头 + AppInfoBDMV 的 4 字节长度
    u32be 0       # ExtensionDataStartAddress: 无扩展数据
    u32be 0       # AppInfoBDMV.length = 0
    u32be 0       # Indexes.length = 0
} > "$BDMV/index.bdmv"

# MovieObject.bdmv: magic + 版本 + 扩展地址 + MovieObjects(空)
{
    printf 'MOBJ0100'
    u32be 0       # ExtensionDataStartAddress
    u32be 0       # MovieObjects.length = 0
} > "$BDMV/MovieObject.bdmv"

for name in "${CLIPS[@]}"; do
    stem="${name%.*}"
    # mpls: magic + 版本 + 三个段起始地址 + AppInfoPlayList / PlayList / PlayListMark
    {
        printf 'MPLS0200'
        u32be 20  # PlayListStartAddress: 16 字节头 + AppInfoPlayList 的 4 字节长度
        u32be 24  # PlayListMarkStartAddress: 上面再 + PlayList 的 4 字节长度
        u32be 0   # ExtensionDataStartAddress
        u32be 0   # AppInfoPlayList.length = 0
        u32be 0   # PlayList.length = 0
        u32be 0   # PlayListMark.length = 0
    } > "$BDMV/PLAYLIST/${stem}.mpls"
    # clpi: magic + 版本 + 六个段长度(ClipInfo / SequenceInfo / ProgramInfo /
    #       CPI / ClipMark / ExtensionData), 全空
    {
        printf 'CLPI0200'
        u32be 0
        u32be 0
        u32be 0
        u32be 0
        u32be 0
        u32be 0
    } > "$BDMV/CLIPINF/${stem}.clpi"
done
# 无视频那条碎片也给它一个 clpi(真盘里每条流都有), 但不给 mpls —— 它本来就没
# 被任何播放列表引用
[ -n "$NOVIDEO_NAME" ] && {
    printf 'CLPI0200'
    u32be 0; u32be 0; u32be 0; u32be 0; u32be 0; u32be 0
} > "$BDMV/CLIPINF/${NOVIDEO_NAME%.*}.clpi"

# 真盘的 BACKUP 是 index / MovieObject / PLAYLIST / CLIPINF 的副本(STREAM 不备份,
# 因为它太大), 结构检查会看这一层, 夹具照做
mkdir -p "$BDMV/BACKUP/PLAYLIST" "$BDMV/BACKUP/CLIPINF"
cp -p "$BDMV/index.bdmv" "$BDMV/MovieObject.bdmv" "$BDMV/BACKUP/" 2>/dev/null
cp -p "$BDMV/PLAYLIST/"*.mpls "$BDMV/BACKUP/PLAYLIST/" 2>/dev/null
cp -p "$BDMV/CLIPINF/"*.clpi "$BDMV/BACKUP/CLIPINF/" 2>/dev/null

info "BDMV 骨架  : index.bdmv / MovieObject.bdmv + PLAYLIST ${#CLIPS[@]} + CLIPINF $(( ${#CLIPS[@]} + $( [ -n "$NOVIDEO_NAME" ] && echo 1 || echo 0 ) )) + BACKUP(导航数据为空, 见文件头)"

# =========================================================================
#  3) 回读: 每条 m2ts 到底长什么样
# =========================================================================
echo ----------------------------------------------------------
# 取**最后一次**匹配, 不是第一次: 实测本机这份 ffprobe(gyan 2025-05-01) 在
# -of default=nw=1 下会把同一段原样打印**两遍**(od 看过字节, 不是脚本重复调用)。
# 两遍的值一样, 取哪个都对; 写成取最后一次是为了哪天它改成"先打一遍空的"也不至于
# 取到空值。字段按名字取、不按位置(ffprobe 的 csv 顺序是它自己结构体的顺序,
# 不是 -show_entries 里写的顺序 —— dvd_make_sample.sh 里踩过同一条)。
field() { awk -F= -v k="$2" '$1 == k { v = $2 } END{ if (v != "") print v }' <<<"$1"; }
RC=0
check_m2ts() {
    local f="$1" v a w h dur c ac vstreams
    vstreams="$(fp_run -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null | tr -d '\r' | grep -c .)"
    v="$(fp_run -v error -select_streams v:0 -show_entries stream=codec_name,width,height,field_order -of default=nw=1 "$f" 2>/dev/null)"
    a="$(fp_run -v error -select_streams a:0 -show_entries stream=codec_name,channels,sample_rate -of default=nw=1 "$f" 2>/dev/null)"
    v="${v//$'\r'/}"; a="${a//$'\r'/}"
    dur="$(fp_run -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null | tr -d '\r' | awk '$1 ~ /^[0-9]/ {print $1}' | tail -1)"
    c="$(field "$v" codec_name)"; w="$(field "$v" width)"; h="$(field "$v" height)"
    ac="$(field "$a" codec_name)"
    [ -n "$ac" ] || ac="-"
    info "  $(basename "$f"): 视频 $( [ "$vstreams" -gt 0 ] && echo "${c} ${w}x${h} $(field "$v" field_order)" || echo "无" ) / 音频 ${ac} / ${dur:-?}s"
    # 期望: 尺寸与编码器对得上; 隔行那档 field_order 要是 tt(TFF)而不是 progressive
    if [ "$vstreams" -gt 0 ]; then
        [ "$c" = mpeg2video ] && [ "$w" = "$W" ] && [ "$h" = "$H" ] || { warn "  不合规: 期望 mpeg2video ${W}x${H}"; return 1; }
        if [ "$INTER" = 1 ]; then
            [ "$(field "$v" field_order)" = tt ] || { warn "  隔行没生效: field_order=$(field "$v" field_order)(期望 tt)"; return 1; }
        fi
    fi
    return 0
}
for name in "${CLIPS[@]}" ${NOVIDEO_NAME:+"$NOVIDEO_NAME"}; do
    check_m2ts "$STREAM/$name" || RC=1
done
[ "$RC" -eq 0 ] || die "素材自检没过(工作目录: $WORK)"

[ "$NO_ISO" = 1 ] && {
    info "NO_ISO=1, 到这里为止。下一步:"
    info "  MODE=ALL ./ffmpeg_dvd_hevc.sh \"$OUT\" <输出目录>   # 每条 m2ts 各出一个文件"
    info "  (Windows) .\\ffmpeg_dvd_hevc.bat \"$OUT\"          # 同上, 无视频那条应被跳过"
    exit 0
}

# =========================================================================
#  4) 打包: UDF 桥
# =========================================================================
# 挑打包器: 不能盲选 PATH 上第一个 —— Cygwin 下那常常是 WinCDEmu 的原生
# mkisofs.exe, 它吃不下 POSIX 路径(见 lib/common.sh 的 pick_mkisofs)
declare -F pick_mkisofs >/dev/null 2>&1 || die "lib/common.sh 未加载(pick_mkisofs 缺失) —— 请在完整仓库里运行本脚本"
MKISOFS="$(pick_mkisofs)" || die "找不到 mkisofs / genisoimage。安装: sudo apt install genisoimage"
VOLID="${VOLID:-BDSAMPLE}"
# BD 用的是 UDF 2.5, mkisofs 只能给 1.02/1.5 桥 —— 结构盘, 不是能进蓝光机的盘。
# -J -r 让 Windows / macOS / Linux 都读得到; 别加 -dvd-video(那是给 VIDEO_TS 排序的)
info "开始打包($MKISOFS -udf) ..."
"$MKISOFS" -udf -iso-level 3 -J -r -allow-limited-size -V "$VOLID" \
    -o "$(mkisofs_path "$ISO")" "$(mkisofs_path "$OUT")" || die "打包失败"
info "ISO 已生成  : $ISO"

# =========================================================================
#  5) 校验: UDF 序列 + 镜像里的 m2ts 条数
# =========================================================================
if command -v dd >/dev/null 2>&1; then
    vrs="$(dd if="$ISO" bs=2048 skip=16 count=8 2>/dev/null | tr -cd '[:print:]')"
    case "$vrs" in
        *BEA01*TEA01*) info "UDF 卷识别序列: 存在(BEA01 ... TEA01)" ;;
        *) warn "没找到 UDF 卷识别序列 —— $MKISOFS 可能没真加上 UDF" ;;
    esac
fi
if [ "$HAVE_7Z" = 1 ]; then
    m2ts_n="$(7z l -ba "$ISO" 2>/dev/null | awk '{print $NF}' | grep -ci '\.m2ts$')"
    exp_n="$((${#CLIPS[@]} + $( [ -n "$NOVIDEO_NAME" ] && echo 1 || echo 0 )))"
    if [ "$m2ts_n" = "$exp_n" ]; then
        info "镜像里的 m2ts: ${m2ts_n} 条(与期望一致)"
    else
        warn "镜像里的 m2ts 有 ${m2ts_n} 条, 期望 ${exp_n} 条"
    fi
else
    warn "没有 7z —— 只做了 UDF 序列检查, 跳过镜像内文件清单比对"
fi

echo ----------------------------------------------------------
info "完成。下一步(Windows):"
info "  .\\ffmpeg_dvd_hevc.bat \"$ISO\"                      # 自动挂载 -> 挑最长那条当正片"
info "  MODE=ALL .\\ffmpeg_dvd_hevc.bat \"$ISO\" <输出目录>    # 每条 m2ts 各出一个文件, 无视频那条应被跳过"
info "  Dismount-DiskImage -ImagePath \"$ISO\"               # 收尾(脚本正常结束时自己会卸)"
exit 0
