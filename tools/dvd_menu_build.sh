#!/bin/bash
# =========================================================================
#  tools/dvd_menu_build.sh  -  多段源 -> 统一音频 -> 带按钮菜单的 DVD-Video ISO
#
#  用法:
#    ./tools/dvd_menu_build.sh <工作目录> <菜单底图> <源1> [源2 ...]
#      工作目录   中间产物 + dvd/ + 最终 ISO 都放这里(不存在会建)。重跑会跳过
#                 已存在的中间产物, 想全量重来就换个空目录
#      菜单底图   一张图(jpg/png 均可)。菜单就是它 + 30s 静音 + 按钮框
#      源N        1 个或多个视频文件(VOB / mpg / mkv ...), 按给出顺序拼成正片
#
#  开关(环境变量, 写在命令之前):
#    SPLIT=秒[,秒...]  切分点。给 N 个点就出 N+1 个 title(菜单上 N+1 个按钮)。
#                      不给则整段做 1 个 title。切点请落在关键帧上, 用
#                      tools/dvd_find_split.sh 找, 否则切出来的片头会花/会卡
#    FORMAT=PAL|NTSC   默认 PAL(720x576, 25fps)。NTSC = 720x480
#    ABIT=448k         AC3 音频码率。DVD 常用 192k / 224k / 448k
#    MR=10080000       -muxrate, DVD 规范上限 10080000 bps
#    MENU_SEC=30       菜单时长(秒)。播完按 XML 里的 post 跳回菜单, 等于循环
#    BTNS="x0,y0,x1,y1;..."   按钮矩形, 分号分隔。个数要与 title 数一致。
#                      默认两个(PAL 720x576 下居中偏上):
#                      "150,230,339,404;385,230,574,404"
#    ASPECT=4:3|16:9   菜单与正片的显示比例, 默认 4:3
#    C_NORM/C_HI/C_SEL/C_T/C_HT  按钮三态的框色与线宽, 默认
#                      0x555555 / 0xFFFFFF / 0xFFD200 / 6 / 8
#    ISO=路径         输出镜像, 默认 <工作目录>.iso, 写在工作目录**旁边**
#                     (dvd_restore.sh 拒绝把 ISO 打进源目录里, 见它头部第 1 条)
#    CHECK=0          跳过收尾的音频洞体检(不建议)
#
#  一条命令的样子:
#    SPLIT=1823.1063 BTNS="150,230,339,404;385,230,574,404" \
#      ./tools/dvd_menu_build.sh /tmp/zp001_menu ~/fr_01.jpg \
#        /data/ZP001_1.vob /data/ZP001_2.vob
#
#  为什么不能"拼起来 + spumux 一下"就完事 —— 实测踩坑:
#    1) spumux 的 image / highlight / select 是**三张 PNG 的文件名**, 不是颜色
#       (dvdauthor 源码 subgen-parse-xml.c: spu_highlight -> localize_filename)。
#       写成颜色名时日志是 "ERR: Unable to open file white" 并且
#       "0 subtitles added, 1 subtitles skipped" —— 不红不报错, 只是子图没进去:
#       产物与输入字节数一模一样。没有子图就没有 PCI 里的 BTN_GRP, 表现是
#       VLC 里方向键选不动按钮(看着像"菜单不支持键盘", 其实是没写进去)。
#       只有 transparent 才是颜色。本脚本按三态 PNG 生成, 并核对
#       "subtitles added" 不是 0、产物字节数确实变大了。
#    2) -muxrate 只能加在"逐段统一音频"那一步(dvd muxer 默认码率不够交错
#       音频, 否则满屏 "buffer underflow" + dvdauthor 报
#       "Discontinuity ... please remultiplex")。concat 重封装与切分**不能**加:
#       静态/末尾 padding 会造出只有填充没有音视频的 VOBU, dvdauthor 直接
#       "ERR: Cannot infer pts for VOBU ..." 退出。
#    3) 音频有洞的根源常常是 LPCM: 每包样本数不规则, 解码出来时间戳抖, AC3
#       编码器原样带走 -> 成品里约 4% 的音频帧跳 2 帧(64ms)。修法是重编码时加
#       -af "aresample=48000:async=1:first_pts=0" 按时间轴补偿(实测 4802 -> 0)。
#       本脚本在拼好之后固定做一遍这一步, 收尾再体检一次。
#    4) 一个 PGC 只能声明一种音频格式。多段源的音频不一致(有的 pcm_dvd、
#       有的 ac3)时必须先统一, 本脚本统一成 AC3, 视频全程 copy。
#    5) ffmpeg / ffprobe 会从 stdin 读键盘命令, 非交互环境 stdin 是不关的管道
#       -> 卡死几小时。这里全部 -nostdin + </dev/null。
#    6) 别写 ffprobe ... | head -N: head 拿够就关管道, ffprobe 收 SIGPIPE 返回
#       141, 配合 set -o pipefail 会把脚本直接干掉。让 ffprobe 自己只解前 90 秒
#       (-read_intervals "%+90")。
#    7) 本机 ffmpeg 没有 pcm_dvd 编码器, LPCM 流复制一律 "sample rate not set"
#       (dvd / vob / mpeg 三个 muxer 都试过) -> 只能往 AC3 统一。
#
#  依赖:
#    必需  ffmpeg / ffprobe, dvdauthor, spumux, mkisofs 或 genisoimage
#    本机  tools/dvd_restore.sh(最后一步打包, 会给镜像补 AUDIO_TS 并做结构校验)
#
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[dvd_menu]"
info() { printf '%s %s\n' "$TAG" "$*"; }
warn() { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()  { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"
    exit "${1:-0}"
}

# =========================================================================
#  参数
# =========================================================================
[ $# -ge 3 ] || usage 1
case "${1:-}" in -h|--help) usage 0 ;; esac

WORK="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
BG="$(normalize_source_path "$2" 2>/dev/null || printf '%s' "$2")"
shift 2
SRCS=("$@")

[ -f "$BG" ] || die "菜单底图不存在: $BG"
for s in "${SRCS[@]}"; do [ -f "$s" ] || die "源文件不存在: $s"; done

FORMAT="$(printf '%s' "${FORMAT:-PAL}" | tr 'a-z' 'A-Z')"
case "$FORMAT" in
    PAL)  VF=PAL;  TARGET=pal-dvd;  W=720; H=576; FPS=25 ;;
    NTSC) VF=NTSC; TARGET=ntsc-dvd; W=720; H=480; FPS=30000/1001 ;;
    *)    die "FORMAT 只认 PAL / NTSC, 收到: $FORMAT" ;;
esac

ABIT="${ABIT:-448k}"
MR="${MR:-10080000}"
MENU_SEC="${MENU_SEC:-30}"
ASPECT="${ASPECT:-4:3}"
BTNS="${BTNS:-150,230,339,404;385,230,574,404}"
C_NORM="${C_NORM:-0x555555}"; C_HI="${C_HI:-0xFFFFFF}"; C_SEL="${C_SEL:-0xFFD200}"
C_T="${C_T:-6}"; C_HT="${C_HT:-8}"

# 切点: "900,1800" -> 3 个 title
SPLIT="${SPLIT:-}"
if [ -n "$SPLIT" ]; then
    IFS=',' read -r -a SPLITS <<< "$SPLIT"
else
    SPLITS=()
fi

mkdir -p "$WORK" || die "建不了工作目录: $WORK"
ISO="${ISO:-$(dirname "$WORK")/$(basename "$WORK").iso}"

echo ============================================================
info "工作目录    : $WORK"
info "菜单底图    : $BG"
info "源          : ${#SRCS[@]} 段"
info "格式        : $FORMAT ($TARGET, ${W}x${H}@$FPS)"
info "切分点      : ${SPLIT:-<不切分>}"
info "输出 ISO    : $ISO"
echo ============================================================

# =========================================================================
#  依赖
# =========================================================================
declare -F find_ffmpeg >/dev/null 2>&1 || die "lib/common.sh 未加载 —— 请在完整仓库里运行本脚本"
FF="$(find_ffmpeg)" || die "找不到 ffmpeg"
FP="$(find_ffprobe "$FF")" || die "找不到 ffprobe"
for t in dvdauthor spumux; do
    command -v "$t" >/dev/null 2>&1 || die "缺少 $t(dvdauthor 工具包)。Debian/Ubuntu: apt install dvdauthor"
done
[ -x "$REPO_ROOT/tools/dvd_restore.sh" ] || die "缺少 tools/dvd_restore.sh"

# 包一层: -nostdin(见头部第 5 条) + stdin 关掉。路径改写交给 ff_run / fp_run。
ff() { ff_run -nostdin -hide_banner -v error "$@" </dev/null; }
fp() { fp_run -hide_banner -v error "$@" </dev/null; }

# 音频洞体检: AC3 一帧 = 1536/48000 = 32ms, 间隔明显大于它就是有洞。
# 只解前 90 秒(见头部第 6 条: 不能用 head 截断)。
# sub(/\r$/) 不是洁癖: 本机选中的是 Windows 原生 ffprobe, 它的输出是 CRLF,
# 不去掉的话 $1 是 "0.534667\r", 正则匹配不上, 统计会静默变成全 0 ——
# 看着像"没有洞", 其实是一个包都没数(实测踩过)。
gap() {
    local f="$1" tag="$2"
    fp -read_intervals "%+90" -i "$f" -select_streams a:0 \
       -show_entries packet=pts_time -of csv=p=0 \
    | awk -F',' -v t="$tag" '{ sub(/\r$/, "") }
       $1 ~ /^[0-9.]+$/ { if (p != "" && $1 > p) { d = $1 - p; cnt++;
          if (d < 0.0325) ok++; else if (d < 0.05) g2++; else if (d < 0.1) g3++; else big++ }
        p = $1 }
        END { if (cnt == 0) { printf "%-24s 没有可用的音频 PTS(选错流?)\n", t; exit }
              printf "%-24s 间隔=%d 正常=%d 2帧洞=%d 3帧洞=%d >100ms=%d\n", t, cnt, ok, g2, g3, big }'
}

# =========================================================================
#  1) 逐段把音频统一成 AC3(视频 copy), 唯一一处加 -muxrate
# =========================================================================
: > "$WORK/segs.txt"
i=0
for s in "${SRCS[@]}"; do
    i=$((i + 1))
    seg="$WORK/seg_$i.mpg"
    if [ -s "$seg" ]; then
        info "seg_$i.mpg 已存在, 跳过"
    else
        info "段 $i/${#SRCS[@]}: 视频 copy + 音频 -> AC3 $ABIT (muxrate $MR) ..."
        ff -y -i "$s" -map 0:v -map 0:a -c:v copy -c:a ac3 -b:a "$ABIT" \
           -muxrate "$MR" -f dvd "$seg" || die "段 $i 转换失败: $s"
        info "  seg_$i.mpg = $(stat -c%s "$seg") 字节"
    fi
    # concat 清单里的路径也要写成 ffmpeg 认的形式: Cygwin + 原生 exe 吃不下
    # /cygdrive/... (lib/common.sh 的 native_path)
    printf "file '%s'\n" "$(native_path "$seg")" >> "$WORK/segs.txt"
done

# =========================================================================
#  2) concat 重封装 -> 连续时间轴的 all.mpg(不加 -muxrate)
# =========================================================================
if [ -s "$WORK/all.mpg" ]; then
    info "all.mpg 已存在, 跳过"
else
    if [ "${#SRCS[@]}" -eq 1 ]; then
        ln -f "$WORK/seg_1.mpg" "$WORK/all.mpg" 2>/dev/null || cp -f "$WORK/seg_1.mpg" "$WORK/all.mpg"
        info "单段源, 直接复用 seg_1.mpg"
    else
        info "concat 重封装 -> all.mpg ..."
        ff -y -f concat -safe 0 -i "$WORK/segs.txt" -map 0:v -map 0:a -c copy -f dvd "$WORK/all.mpg" \
            || die "concat 失败"
    fi
fi

# =========================================================================
#  3) 音频时间轴抹平(头部第 3 条): LPCM 源头带来的 2 帧洞在这一步清掉
# =========================================================================
if [ -s "$WORK/all2.mpg" ]; then
    info "all2.mpg 已存在, 跳过"
else
    info "重编码音频(抹平时间轴) -> all2.mpg ..."
    gap "$WORK/all.mpg" "抹平前"
    ff -y -i "$WORK/all.mpg" -map 0:v -map 0:a -c:v copy -c:a ac3 -b:a "$ABIT" \
       -af "aresample=48000:async=1:first_pts=0" -f dvd "$WORK/all2.mpg" || die "音频抹平失败"
    gap "$WORK/all2.mpg" "抹平后"
fi

# =========================================================================
#  4) 切 title(全 copy, 不加 -muxrate)
# =========================================================================
if [ "${#SPLITS[@]}" -eq 0 ]; then
    N_TITLE=1
    ln -f "$WORK/all2.mpg" "$WORK/title1.mpg" 2>/dev/null || cp -f "$WORK/all2.mpg" "$WORK/title1.mpg"
    info "不切分: title1 = all2.mpg"
else
    N_TITLE=$((${#SPLITS[@]} + 1))
    starts=(0 ${SPLITS[@]+"${SPLITS[@]}"})
    i=0
    while [ "$i" -lt "$N_TITLE" ]; do
        idx=$((i + 1))
        out="$WORK/title$idx.mpg"
        s="${starts[$i]}"
        if [ "$idx" -lt "$N_TITLE" ]; then
            e="${starts[$((i + 1))]}"
            dur="$(awk -v a="$e" -v b="$s" 'BEGIN{printf "%.6f", a-b}')"
            if awk -v b="$s" 'BEGIN{exit !(b<=0)}'; then
                ff -y -i "$WORK/all2.mpg" -t "$dur" -map 0:v -map 0:a -c copy -f dvd "$out" || die "切 title$idx 失败"
            else
                ff -y -ss "$s" -i "$WORK/all2.mpg" -t "$dur" -map 0:v -map 0:a -c copy -f dvd "$out" || die "切 title$idx 失败"
            fi
        else
            ff -y -ss "$s" -i "$WORK/all2.mpg" -map 0:v -map 0:a -c copy -f dvd "$out" || die "切 title$idx 失败"
        fi
        info "  title$idx.mpg = $(stat -c%s "$out") 字节"
        i=$((i + 1))
    done
fi
info "共 $N_TITLE 个 title"

# =========================================================================
#  5) 按钮: 个数必须等于 title 数
# =========================================================================
IFS=';' read -r -a BTN_LIST <<< "$BTNS"
[ "${#BTN_LIST[@]}" -ge "$N_TITLE" ] || die "BTNS 只给了 ${#BTN_LIST[@]} 个按钮, 但有 $N_TITLE 个 title(每个 title 要一个按钮)"

# =========================================================================
#  6) 菜单底图 + 静音
# =========================================================================
if [ -s "$WORK/menu.mpg" ]; then
    info "menu.mpg 已存在, 跳过"
else
    info "生成菜单底图(${MENU_SEC}s 静默 AC3) ..."
    ff -y -loop 1 -framerate "$FPS" -i "$BG" \
       -f lavfi -i anullsrc=r=48000:cl=stereo -t "$MENU_SEC" \
       -target "$TARGET" -aspect "$ASPECT" -pix_fmt yuv420p "$WORK/menu.mpg" || die "菜单底图生成失败"
fi

# =========================================================================
#  7) 按钮三态子图(三张 PNG, 尺寸必须一致; 只画边框不填充, 底图缩略图才看得见)
# =========================================================================
boxes() {   # $1=颜色 $2=线宽 -> drawbox 串
    local c="$1" t="$2" b="" one
    for one in "${BTN_LIST[@]}"; do
        IFS=',' read -r x0 y0 x1 y1 <<< "$one"
        [ -n "${y1:-}" ] || die "按钮矩形要写成 x0,y0,x1,y1, 收到: $one"
        b="$b${b:+,}drawbox=x=$x0:y=$y0:w=$((x1 - x0)):h=$((y1 - y0)):t=$t:color=$c@1"
    done
    printf '%s' "$b"
}
info "生成按钮三态子图 ..."
ff -y -f lavfi -i "color=black:s=${W}x${H}:r=1" -vf "$(boxes "$C_NORM" "$C_T"),format=rgb24"  -frames:v 1 "$WORK/btn_normal.png"
ff -y -f lavfi -i "color=black:s=${W}x${H}:r=1" -vf "$(boxes "$C_HI" "$C_HT"),format=rgb24"   -frames:v 1 "$WORK/btn_hilite.png"
ff -y -f lavfi -i "color=black:s=${W}x${H}:r=1" -vf "$(boxes "$C_SEL" "$C_HT"),format=rgb24"  -frames:v 1 "$WORK/btn_select.png"

# =========================================================================
#  8) spumux: 压入按钮子图(头部第 1 条)
# =========================================================================
{
    printf '<subpictures>\n  <stream>\n'
    printf '    <spu force="yes" start="00:00:00.000" end="%s"\n' \
        "$(awk -v s="$MENU_SEC" 'BEGIN{printf "%02d:%02d:%02d.000", int(s/3600), int(s/60)%60, int(s)%60}')"
    printf '         image="btn_normal.png" highlight="btn_hilite.png" select="btn_select.png"\n'
    printf '         transparent="black">\n'
    for ((k = 0; k < N_TITLE; k++)); do
        IFS=',' read -r x0 y0 x1 y1 <<< "${BTN_LIST[$k]}"
        printf '      <button x0="%s" y0="%s" x1="%s" y1="%s" />\n' "$x0" "$y0" "$x1" "$y1"
    done
    printf '    </spu>\n  </stream>\n</subpictures>\n'
} > "$WORK/spumux.xml"

if [ -s "$WORK/menu_spu.mpg" ]; then
    info "menu_spu.mpg 已存在, 跳过"
else
    info "spumux 压入按钮子图 ..."
    ( cd "$WORK" && VIDEO_FORMAT="$VF" spumux spumux.xml < menu.mpg > menu_spu.mpg 2> spumux.log ) \
        || { cat "$WORK/spumux.log" >&2; die "spumux 失败"; }
fi
# 校验: 日志里必须真的是 "N subtitles added" 且 N>0, 产物也必须变大。
# 写错成颜色名时这里是 "0 subtitles added, 1 subtitles skipped", 产物字节数不变。
ADDED="$(grep -ao '[0-9]* subtitles added' "$WORK/spumux.log" 2>/dev/null | head -1 || true)"
[ -n "$ADDED" ] || die "spumux 日志里没有 'subtitles added', 子图多半没进去。完整日志: $WORK/spumux.log"
case "$ADDED" in 0\ *) die "spumux 报告 $ADDED —— 子图没写进去(菜单按钮/方向键会失效)。检查 PNG 是否存在、transparent 是不是颜色、image/highlight/select 是不是文件名" ;; esac
M0=$(stat -c%s "$WORK/menu.mpg"); M1=$(stat -c%s "$WORK/menu_spu.mpg")
[ "$M1" -gt "$M0" ] || die "menu_spu.mpg($M1) 没有比 menu.mpg($M0) 大 —— 子图没写进去。日志: $WORK/spumux.log"
info "  spumux: $ADDED, menu_spu.mpg = $M1 字节 (menu.mpg = $M0)"

# =========================================================================
#  9) dvdauthor: VMGM 菜单 + N 个 title(同一 titleset, 音轨同为 AC3)
#     菜单 post 跳回自己 = 播完循环; title post call 菜单 = 播完回菜单
# =========================================================================
DVD_DIR="$WORK/dvd"
{
    printf '<dvdauthor dest="%s">\n' "$(da_path "$DVD_DIR")"
    printf '  <vmgm>\n    <menus>\n'
    printf '      <video format="%s" />\n' "$(printf '%s' "$FORMAT" | tr 'A-Z' 'a-z')"
    printf '      <audio format="ac3" lang="zh" />\n      <subpicture lang="zh" />\n'
    printf '      <pgc>\n        <vob file="%s" />\n' "$(da_path "$WORK/menu_spu.mpg")"
    for ((k = 1; k <= N_TITLE; k++)); do printf '        <button>jump title %d;</button>\n' "$k"; done
    printf '        <post>jump vmgm menu 1;</post>\n      </pgc>\n    </menus>\n  </vmgm>\n'
    printf '  <titleset>\n    <titles>\n'
    printf '      <video format="%s" />\n      <audio format="ac3" lang="zh" />\n' "$(printf '%s' "$FORMAT" | tr 'A-Z' 'a-z')"
    for ((k = 1; k <= N_TITLE; k++)); do
        printf '      <pgc>\n        <vob file="%s" />\n        <post>call vmgm menu 1;</post>\n      </pgc>\n' \
            "$(da_path "$WORK/title$k.mpg")"
    done
    printf '    </titles>\n  </titleset>\n</dvdauthor>\n'
} > "$WORK/dvd.xml"

rm -rf "$DVD_DIR"
info "dvdauthor 开始 ..."
( cd "$WORK" && VIDEO_FORMAT="$VF" dvdauthor -x dvd.xml </dev/null ) || die "dvdauthor 失败"
info "dvdauthor 完成"

# =========================================================================
#  10) 打包 ISO
# =========================================================================
info "打包 ISO ..."
"$REPO_ROOT/tools/dvd_restore.sh" "$DVD_DIR" "$ISO" </dev/null || die "打包失败"

# =========================================================================
#  11) 收尾体检
# =========================================================================
if [ "${CHECK:-1}" != "0" ]; then
    echo ============================================================
    info "音频洞体检(各看前 90 秒, AC3 一帧=32ms) ..."
    for v in "$DVD_DIR"/VIDEO_TS/VTS_*_1.VOB; do
        [ -f "$v" ] && gap "$v" "$(basename "$v")"
    done
fi

echo ============================================================
info "完成: $ISO"
info "菜单按钮 ${N_TITLE} 个, 播完循环; 每个 title 播完回菜单"
info "用播放器打开 ISO 验证: 方向键应该能在按钮之间移动(选不动就是子图没进去)"
exit 0
