#!/bin/bash
# =========================================================================
#  tools/dvd_make_sample.sh  -  用本机 ffmpeg 合成一段 DVD 合规的 MPEG-2 PS,
#                               并顺手做成一张能拿来测的完整 DVD(VIDEO_TS + ISO)
#
#  用法:
#    ./tools/dvd_make_sample.sh [输出目录] [输出ISO]
#      输出目录  默认 ./dvd_sample。dvdauthor 在它下面生成 VIDEO_TS / AUDIO_TS
#      输出ISO   默认 <输出目录旁边>/<目录名>.iso(不能落在输出目录里面, 否则会被
#                自己打包进去 —— 和 dvd_restore.sh 同一个坑)
#
#  为什么要有它:
#    dvd_restore / dvd_shrink / dvd_repair 三个脚本都需要一张"我知道它应该长什么样"
#    的盘来验证: 几条 title、多长、章节在哪些时间点, 全是已知的。拿真盘测的话,
#    读出来 1682s 你也不确定对不对。本机合成一张, 期望值就是你自己定的参数。
#
#  开关(环境变量, 写在命令之前):
#    DURATION=300   每条 title 的时长(秒)
#    TITLES=1       做几条 title(每条一个标题集, 音调频率错开, 耳朵能分出来)
#    SCENE_LEN=30   每几秒切一次画面。切点同时就是章节点, 也是场景检测的期望值
#    FORMAT=pal|ntsc  pal(默认): 720x576@25;  ntsc: 720x480@30000/1001
#    ASPECT=4:3|16:9  默认 4:3(DVD 只认这两种)
#    VBITRATE=4000k / ABITRATE=192k
#    LABEL=1        画面上叠"scene N"和时间码(默认开; 没有 drawtext 或找不到字体
#                   就自动关掉并告警, 不因此失败)
#    NO_VIDEOTS=1   只出 mpg, 不建 VIDEO_TS
#    NO_ISO=1       建 VIDEO_TS, 但不打 ISO
#    KEEP_WORK=1    保留工作目录(生成的 mpg 与 dvdauthor 的 XML)
#
#  画面是什么:
#    6 种合成源轮着切 —— testsrc2(动态) / 纯白 / 彩条 / 纯黑 / rgbtestsrc / 深蓝。
#    纯色段是故意的: 白↔黑的跳变场景分数拉满, 保证切点一定检得出来。实测在阈值
#    0.40(dvd_repair 的默认值)能命中 4 个切点里的 3 个, 阈值放到 0.10 全中。
#
#  实测出来的坑(2026-09-29, 本机 /opt/ffmpeg 的 gpl 构建):
#    * -target pal-dvd 一条命令就出合规的 PS: mpeg2video 720x576@25 yuv420p +
#      ac3 48kHz, format=mpeg(PS)。**但它不管 SAR** —— 实测给的是 SAR=1:1、
#      DAR=5:4, 既不 4:3 也不 16:9, 不是合规盘。必须显式 -aspect, 加了之后
#      SAR 变 16:15 / DAR 4:3。NTSC 同理(720x480@30000/1001 + -aspect)。
#    * 编码很快: 60s 素材 0.65s 编完。但 -target 默认码率约 6.5M(60s 就 49 MB),
#      做测试素材太浪费, 所以默认压到 4000k; 要贴近"真 DVD 的码率"就自己调上去。
#    * sine 音源默认单声道, 要显式 -ac 2 才是立体声。
#    * 校验章节数不能问 ffprobe: 它的 dvdvideo 解复用器会漏 —— IFO 里 6 个章节它
#      只报 5 个, 只有 2 个时干脆报 0 个; mplayer -identify 读出来和 IFO 一致。
#      所以脚本直接读 VTS_xx_0.IFO 里 PGC 的 nr_of_programs 来核对。
#
#  依赖: ffmpeg(带 mpeg2video + ac3 编码器; LABEL 还要 drawtext) + dvdauthor +
#        tools/dvd_restore.sh(打 ISO 那一步)
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[dvd_make_sample]"
info()  { printf '%s %s\n' "$TAG" "$*"; }
warn()  { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()   { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()   { err "$*"; exit 1; }
usage() { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit "${1:-0}"; }

case "${1:-}" in -h|--help) usage 0 ;; esac

# =========================================================================
#  参数
# =========================================================================
OUT="${1:-$PWD/dvd_sample}"
ISO="${2:-}"
mkdir -p "$OUT" || die "建不了输出目录: $OUT"
OUT="$(cd "$OUT" && pwd)" || die "进不去输出目录: $OUT"
BASE="$(basename "$OUT")"
PARENT="$(dirname "$OUT")"
[ -n "$ISO" ] || ISO="$PARENT/$BASE.iso"
case "$ISO" in
    "$OUT"|"$OUT"/*) die "ISO 不能放在被打包的目录里面(会把自己卷进去): $ISO" ;;
esac

DURATION="${DURATION:-300}"
TITLES="${TITLES:-1}"
SCENE_LEN="${SCENE_LEN:-30}"
ASPECT="${ASPECT:-4:3}"
VBITRATE="${VBITRATE:-4000k}"
ABITRATE="${ABITRATE:-192k}"
LABEL="${LABEL:-1}"
NO_VIDEOTS="${NO_VIDEOTS:-0}"
NO_ISO="${NO_ISO:-0}"
KEEP_WORK="${KEEP_WORK:-0}"

# 数字参数先过一遍: awk 算出来的场景数后面要拿去做循环上界, 塞个字母进来会在
# 很后面的地方才炸, 而且炸出来的信息看不出是参数问题
for v in "$DURATION" "$TITLES" "$SCENE_LEN"; do
    case "$v" in
        ''|*[!0-9.]*) die "DURATION / TITLES / SCENE_LEN 只能是数字(现在: $DURATION / $TITLES / $SCENE_LEN)" ;;
    esac
done
[ "$TITLES" -ge 1 ] || die "TITLES 至少是 1"

case "${FORMAT:-pal}" in
    pal|PAL)     W=720; H=576; RATE=25;           TARGET=pal-dvd;  VFMT=pal;  VFORMAT=PAL  ;;
    ntsc|NTSC)   W=720; H=480; RATE=30000/1001;   TARGET=ntsc-dvd; VFMT=ntsc; VFORMAT=NTSC ;;
    *)           die "FORMAT 只能是 pal 或 ntsc(现在: ${FORMAT})" ;;
esac
case "$ASPECT" in 4:3|16:9) ;; *) die "ASPECT 只能是 4:3 或 16:9(现在: $ASPECT)" ;; esac

# 场景数 = ceil(DURATION / SCENE_LEN), 至少 1
NS="$(awk -v d="$DURATION" -v s="$SCENE_LEN" 'BEGIN{ n = int(d / s); if (d - n * s > 0.0001) n++; print (n < 1 ? 1 : n) }')"
FS="$(awk -v h="$H" 'BEGIN{ printf "%d", h / 12 }')"     # 字号跟着分辨率走: 576->48, 480->40

WORK="$PARENT/.dvd_make_sample_${BASE}"
rm -rf "$WORK"; mkdir -p "$WORK" || die "建不了工作目录: $WORK"
cleanup() { [ "$KEEP_WORK" = 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

echo ==========================================================
info "输出目录    : $OUT"
[ "$NO_ISO" = 1 ] || info "输出 ISO    : $ISO"
info "制式        : ${VFORMAT} ${W}x${H}@${RATE} ${ASPECT}"
info "每条 title  : ${DURATION}s, 共 ${TITLES} 条, 每 ${SCENE_LEN}s 一切(共 ${NS} 段)"
info "码率        : 视频 ${VBITRATE} / 音频 ${ABITRATE}(ac3)"
info "工作目录    : $WORK$( [ "$KEEP_WORK" = 1 ] && echo ' (KEEP_WORK=1, 保留)' )"
echo ==========================================================

# =========================================================================
#  依赖: ffmpeg 要同时有 mpeg2video 与 ac3 编码器
# =========================================================================
FF="${FFMPEG:-}"
[ -n "$FF" ] && [ -x "$FF" ] || FF="$(find_ffmpeg --need-encoder mpeg2video --need-encoder ac3 2>/dev/null)"
[ -n "$FF" ] && [ -x "$FF" ] || FF="$(command -v ffmpeg 2>/dev/null)"
[ -n "$FF" ] || die "找不到带 mpeg2video 与 ac3 编码器的 ffmpeg(可用 FFMPEG=/path/to/ffmpeg 指定)"

FP="${FFPROBE:-}"
[ -n "$FP" ] && [ -x "$FP" ] || FP="$(find_ffprobe "$FF" 2>/dev/null)"
[ -n "$FP" ] && [ -x "$FP" ] || FP="$(command -v ffprobe 2>/dev/null)"
[ -n "$FP" ] || die "找不到 ffprobe"

# 回读 ISO 要用 -f dvdvideo, 而能编码 mpeg2video 的构建未必带这个解复用器(实测
# 本机 /usr/bin/ffmpeg 就没有, 能用的那份在 /opt/ffmpeg 下)。合成那一步不需要它,
# 只有最后"读回来看看对不对"需要 —— 找不到就跳过校验, 不因此判失败。
pick_dvd_ff() {
    local d c
    if [ -n "${FFMPEG:-}" ] && [ -x "${FFMPEG}" ]; then echo "$FFMPEG"; return 0; fi
    for c in $(IFS=:; for d in ${PATH:-/usr/bin}; do [ -n "$d" ] && echo "$d/ffmpeg"; done) \
             /opt/ffmpeg/*/bin/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg; do
        [ -x "$c" ] || continue
        "$c" -hide_banner -demuxers 2>/dev/null |
            awk '{ if ($1 == "D" && $2 == "dvdvideo") f = 1 } END{ exit !f }' || continue
        echo "$c"; return 0
    done
    return 1
}
FPDVD=""
if dvd_ff="$(pick_dvd_ff 2>/dev/null)" && [ -n "$dvd_ff" ]; then
    cand="$(dirname "$dvd_ff")/ffprobe"
    [ -x "$cand" ] && FPDVD="$cand"
fi

if [ "$NO_VIDEOTS" != 1 ]; then
    command -v dvdauthor >/dev/null 2>&1 || die "找不到 dvdauthor(安装: sudo apt install dvdauthor)。只要 mpg 就加 NO_VIDEOTS=1"
    if [ "$NO_ISO" != 1 ]; then
        [ -x "$SCRIPT_DIR/dvd_restore.sh" ] || die "缺少同目录的 dvd_restore.sh(打 ISO 由它完成)。不打 ISO 就加 NO_ISO=1"
    fi
fi
info "ffmpeg      : $FF"

# =========================================================================
#  字体: 找不到就关掉 LABEL, 不算失败
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
FONT=""
if [ "$LABEL" = 1 ]; then
    if ! "$FF" -hide_banner -filters 2>/dev/null | grep -q " drawtext "; then
        warn "这个 ffmpeg 没有 drawtext 滤镜 —— LABEL 关掉, 画面只有测试图"
        LABEL=0
    elif FONT="$(pick_font)"; then
        info "字体        : $FONT"
    else
        warn "找不到可用的 ttf 字体 —— LABEL 关掉, 画面只有测试图"
        LABEL=0
    fi
fi

# 盘里到底有几个章节, 直接读 VTS_x_0.IFO 里 PGC 的 nr_of_programs —— 不问 ffprobe:
# 实测它的 dvdvideo 解复用器少报(IFO 里 6 个只给 5 个, 2 个干脆给 0 个), 而 mplayer
# -identify 读出来与 IFO 一致。校验口径不能建在一个自己会漏数的读数上。
#   0xCC        : VTS_PGCIT 的扇区号(相对 IFO 文件头)
#   PGCIT + 12  : 第 1 个 PGC 的字节偏移(相对 PGCIT)
#   PGC + 2     : nr_of_programs, 就是章节数
count_programs() {
    local f="$1" pgci off
    [ -f "$f" ] || return 1
    pgci="$(od --endian=big -An -tu4 -j 204 -N 4 "$f" 2>/dev/null | tr -d ' \n')" || return 1
    [ -n "$pgci" ] || return 1
    pgci=$((pgci * 2048))
    off="$(od --endian=big -An -tu4 -j $((pgci + 12)) -N 4 "$f" 2>/dev/null | tr -d ' \n')" || return 1
    [ -n "$off" ] || return 1
    od -An -tu1 -j $((pgci + off + 2)) -N 1 "$f" 2>/dev/null | tr -d ' \n'
}

fmt_time() {
    awk -v s="$1" 'BEGIN{
        h = int(s / 3600); m = int((s - h * 3600) / 60); sec = s - h * 3600 - m * 60;
        printf "%d:%02d:%05.2f\n", h, m, sec;
    }'
}

# =========================================================================
#  素材: N 段合成源硬切 + 一条 sine 音轨
#  段长 = SCENE_LEN, 最后一段吃掉余数; 切点即章节点
# =========================================================================
PALETTE=(
    'testsrc2=s=%S%:r=%R%:d=%D%'
    'color=c=white:s=%S%:r=%R%:d=%D%'
    'smptebars=s=%S%:r=%R%:d=%D%'
    'color=c=black:s=%S%:r=%R%:d=%D%'
    'rgbtestsrc=s=%S%:r=%R%:d=%D%'
    'color=c=navy:s=%S%:r=%R%:d=%D%'
)

make_mpg() {
    local t="$1" mpg="$2" i dur tpl spec filt="" chain="" lbl tc
    local -a CMD=()

    for ((i = 0; i < NS; i++)); do
        dur="$(awk -v d="$DURATION" -v s="$SCENE_LEN" -v i="$i" 'BEGIN{ v = d - i * s; print (v > s ? s : v) }')"
        tpl="${PALETTE[$((i % ${#PALETTE[@]}))]}"
        spec="$(printf '%s' "$tpl" | sed -e "s|%S%|${W}x${H}|g" -e "s|%R%|${RATE}|g" -e "s|%D%|${dur}|g")"
        CMD+=(-f lavfi -i "$spec")
        if [ "$LABEL" = 1 ]; then
            # 每段贴一个静态标签: "scene N  0:01:00"(N 从 1 起, 时间是该段在整条
            # title 里的起点)。叠加时间码放在 concat 之后, 那里 pts 才是整条的时间
            lbl="drawtext=fontfile='$FONT':text='scene $((i + 1))  $(fmt_time $((i * SCENE_LEN)))'"
            lbl="$lbl:fontsize=$FS:fontcolor=white:box=1:boxcolor=black@0.5:x=(w-text_w)/2:y=h-$((FS * 2))"
            filt="${filt}[$i:v]$lbl[s$i];"
        fi
        chain="${chain}$([ "$LABEL" = 1 ] && echo "[s$i]" || echo "[$i:v]")"
    done

    filt="${filt}${chain}concat=n=${NS}:v=1:a=0[cat]"
    if [ "$LABEL" = 1 ]; then
        # %{pts:hms} 里的冒号要转义成 \: , 否则 ffmpeg 会把 hms 当成参数分隔符
        tc="drawtext=fontfile='$FONT':text='%{pts\:hms}':fontsize=$((FS / 2)):fontcolor=yellow:box=1:boxcolor=black@0.5:x=40:y=40"
        filt="${filt};[cat]$tc[v]"
    else
        filt="${filt};[cat]null[v]"
    fi

    # 音调频率按 title 错开, 播放时能听出这是第几条
    CMD+=(-f lavfi -i "sine=f=$((440 + (t - 1) * 110)):d=${DURATION}")
    CMD+=(-filter_complex "$filt")
    CMD+=(-map "[v]" -map "${NS}:a")
    CMD+=(-target "$TARGET" -aspect "$ASPECT" -b:v "$VBITRATE" -b:a "$ABITRATE" -ac 2)
    CMD+=("$mpg")

    info "生成 title $t -> $(basename "$mpg")"
    "$FF" -hide_banner -v error -y "${CMD[@]}" || return 1
    return 0
}

# 自检: 出來的 mpg 到底合不合规(主要盯 DAR, -target 不管 SAR 的坑就在这里露出来)。
# 字段按名字取, 不按位置: ffprobe 的 csv 输出顺序是它自己结构体的顺序, 不是你
# -show_entries 里写的顺序(实测调 width/height 之后 r_frame_rate 仍排在 DAR 后面,
# 按位置拼期望串必然对不上)
field() { awk -F= -v k="$2" '$1 == k { print $2 }' <<<"$1"; }
check_mpg() {
    local f="$1" v a c w h r dar ac sr ch
    v="$("$FP" -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,display_aspect_ratio -of default=nw=1 "$f" 2>/dev/null)"
    a="$("$FP" -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 "$f" 2>/dev/null)"
    c="$(field "$v" codec_name)"; w="$(field "$v" width)"; h="$(field "$v" height)"
    r="$(field "$v" r_frame_rate)"; dar="$(field "$v" display_aspect_ratio)"
    ac="$(field "$a" codec_name)"; sr="$(field "$a" sample_rate)"; ch="$(field "$a" channels)"
    [ -n "$sr" ] && a="$ac ${sr}Hz ${ch}ch" || a="-"
    info "  $(basename "$f"): ${c} ${w}x${h}@${r} DAR=${dar:-无} / $a"
    # 帧率: -target 写进去的是 25, ffprobe 读出来是 25/1(NTSC 则是 30000/1001)
    [ "$c" = mpeg2video ] && [ "$w" = "$W" ] && [ "$h" = "$H" ] &&
    { [ "$r" = "$RATE" ] || [ "$r" = "$RATE/1" ]; } &&
    [ "$dar" = "$ASPECT" ] && return 0
    warn "  不合规: 期望 mpeg2video ${W}x${H}@${RATE} DAR=${ASPECT}"
    return 1
}

# =========================================================================
#  1) 合成 MPEG-2 PS
# =========================================================================
MPGS=""
RC=0
for t in $(seq 1 "$TITLES"); do
    mpg="$WORK/title_${t}.mpg"
    if make_mpg "$t" "$mpg" && check_mpg "$mpg"; then
        MPGS="$MPGS $mpg"
    else
        RC=1
    fi
done
[ "$RC" -eq 0 ] || die "素材生成失败(工作目录: $WORK)"
info "素材体积    : $(du -ch $MPGS 2>/dev/null | awk '/total/{print $1}')"

[ "$NO_VIDEOTS" = 1 ] && {
    info "NO_VIDEOTS=1, 到这里为止。下一步:"
    info "  VIDEO_FORMAT=$VFORMAT dvdauthor -o <目录> -t $MPGS"
    exit 0
}

# =========================================================================
#  2) dvdauthor: 每条 title 一个标题集, 章节落在每个切点上
# =========================================================================
rm -rf "$OUT/VIDEO_TS" "$OUT/AUDIO_TS"
CH="0"
for ((i = 1; i < NS; i++)); do CH="$CH,$(fmt_time $((i * SCENE_LEN)))"; done

XML="$WORK/dvd.xml"
{
    printf '<dvdauthor dest="%s">\n' "$OUT"
    printf '  <vmgm />\n'
    for mpg in $MPGS; do
        printf '  <titleset>\n    <titles>\n'
        printf '      <video format="%s" />\n' "$VFMT"
        printf '      <audio format="ac3" lang="en" />\n'
        printf '      <pgc>\n        <vob file="%s" chapters="%s"/>\n' "$mpg" "$CH"
        printf '      </pgc>\n    </titles>\n  </titleset>\n'
    done
    printf '</dvdauthor>\n'
} > "$XML"

info "dvdauthor   : ${TITLES} 个标题集, 章节 ${CH}"
VIDEO_FORMAT="$VFORMAT" dvdauthor -x "$XML" >"$WORK/dvdauthor.log" 2>&1 \
    || { sed -n '1,20p' "$WORK/dvdauthor.log" >&2; die "dvdauthor 失败(日志: $WORK/dvdauthor.log, KEEP_WORK=1 可保留)"; }
grep -i "err" "$WORK/dvdauthor.log" | head -5 >&2

[ -f "$OUT/VIDEO_TS/VIDEO_TS.IFO" ] || die "dvdauthor 没产出 VIDEO_TS.IFO(日志: $WORK/dvdauthor.log)"

[ "$NO_ISO" = 1 ] && {
    info "NO_ISO=1, 到这里为止。下一步:"
    info "  ./tools/dvd_restore.sh \"$OUT\" \"$ISO\""
    info "  ./tools/dvd_repair.sh \"$OUT\"          # 体检(只读)"
    exit 0
}

# =========================================================================
#  3) 打包 + 校验: 复用 dvd_restore.sh
# =========================================================================
bash "$SCRIPT_DIR/dvd_restore.sh" "$OUT" "$ISO" || exit 1

# =========================================================================
#  4) 回读: ISO 里应该正好有 TITLES 条 title, 每条 DURATION 秒、NS 个章节
# =========================================================================
echo ----------------------------------------------------------
if [ -z "$FPDVD" ]; then
    warn "找不到带 dvdvideo 解复用器的 ffprobe —— 回读校验跳过(盘已经打好了)"
else
P="$FPDVD"
info "回读校验($P; 期望 ${TITLES} 条, 每条 ${DURATION}s / ${NS} 章节):"
for t in $(seq 1 "$TITLES"); do
    d="$("$P" -v error -f dvdvideo -title "$t" -show_entries format=duration -of csv=p=0 "$ISO" 2>/dev/null | grep -E '^[0-9]' | tail -1)"
    n="$(count_programs "$(printf '%s/VIDEO_TS/VTS_%02d_0.IFO' "$OUT" "$t")")"
    if [ -n "$d" ]; then
        info "  title $t: ${d%.*}s / ${n:-读不到} 章节"
        [ "${d%.*}" -eq "$DURATION" ] 2>/dev/null || warn "  title $t 时长对不上(期望 ${DURATION}s)"
        if [ -z "$n" ]; then
            warn "  读不到 VTS_${t} 的 IFO, 章节数没法核对"
        elif [ "$n" -ne "$NS" ]; then
            warn "  title $t 章节数对不上(期望 ${NS}, IFO 里是 ${n})"
        fi
    else
        warn "  title $t 读不出来"
    fi
done
fi
echo ----------------------------------------------------------
info "测试盘就绪  : $ISO"
info "下一步(验证另两个脚本):"
info "  ./tools/dvd_repair.sh \"$OUT\"                 # 体检, 应该一个缺失都没有"
info "  ./tools/dvd_shrink.sh \"$ISO\" <瘦身.iso>      # 瘦身, MODE=ALL 可全 title 跑"
