#!/bin/bash
# =========================================================================
#  tools/dvd_shrink.sh  -  DVD-Video -> 重编码成低码率 MPEG-2 -> 新的 DVD-Video ISO
#
#  用法:
#    ./tools/dvd_shrink.sh <源> [输出ISO] [title号]
#      源      ISO 镜像 / 含 VIDEO_TS 的目录 / 光驱设备(如 /dev/sr0)
#      输出ISO 默认 <源旁边>/<名字>_shrunk.iso
#      title号 给了就切到 MODE=TITLE, 只处理这一条
#
#  开关(环境变量, 写在命令之前):
#    MODE=AUTO|ALL|TITLE  AUTO(默认)=挑时长最长的那条正片; ALL=每条 title 都做
#    TARGET_MB=4300       目标盘容量(MiB)。4300 ≈ DVD-5 留好余量; 双层填 8000
#    VBITRATE=3.5M        直接指定视频码率, 跳过"按容量反推"
#    ABITRATE=192k        源音轨不是 AC3/MP2 必须重编码时的码率
#    AUDIO=copy|ac3       copy(默认)=AC3/MP2 原样复制; ac3=强制重编码(dvdauthor
#                         报 "Discontinuity ... please remultiplex input" 时用,
#                         那条告警本身不影响播放, 重编一遍就消失了)
#    SUBS=copy|none       DVD 位图字幕默认复制; dvdauthor 抱怨 subpicture 就填 none
#    VFILT_EXTRA=...      追加到滤镜链末尾(如 setsar=32:27)
#    KEEP_WORK=1          保留中间产物(重编码的 .mpg 与 dvdauthor 树), 默认清理
#    CHECK=0              跳过开头的源盘体检(不建议; 见"源盘缺文件怎么办")
#    ALLOW_GAP=1          体检发现"补不出来的缺失"(VOB 断号)或"标题集数对不上"时,
#                         不拦, 带着缺口继续。默认拦下并退出(与 dvd_restore.sh 同义)
#
#  为什么不能用 HEVC / H.264:
#    DVD-Video 规范只认 MPEG-1 / MPEG-2 视频 + AC-3 / MP2 / LPCM / DTS 音频,
#    dvdauthor 也只吃 MPEG-2 program stream。把 HEVC 塞进 VOB 里"能出 ISO 也能刻盘",
#    但没有任何一台 DVD 机解得了, ffmpeg 的 dvdvideo 也读不出流 —— 那是自造格式,
#    不是 DVD。要的是"小体积 + 能存档"就走 tools/dvd_to_data_iso.sh。
#
#  代价(动手前请读完):
#    * 重编码必然掉画质。源盘本身码率就低于目标时是**纯亏** —— 脚本会先算一遍,
#      发现"反推出来的码率不比原盘低"就劝退(只警告, 不拦)。
#    * 原盘菜单会丢。菜单存在 VOB 里, 而 IFO 全部由 dvdauthor 重新生成, 按钮
#      位置和高亮图都没有了 —— 产物是"一条条正片 + 章节", 不是原盘复刻。
#    * 章节会尽量保留(从源盘读 chapter 点, 写进 dvdauthor 的 XML)。
#    * 不做 IVTC: DVD 规范只有 25(PAL) / 29.97(NTSC) 两种帧率, 逆变换成 23.976
#      反而出不来合规的盘(HEVC 归档那条路才做 IVTC)。
#
#  源盘缺文件怎么办(2026-09-29 起的"体检门"):
#    源是**目录**时, 开跑前先请 tools/dvd_repair.sh 只读体一次检(不改任何文件):
#      完好              -> 直接往下跑
#      有缺失但都能补    -> 停下来, 把"缺什么 + 该跑的那条修复命令"打出来
#      VOB 断号(补不出来) -> 停下来; 确实要带着缺口继续就 ALLOW_GAP=1
#    本脚本始终**不替你改源盘** —— 修是 dvd_repair.sh 的事, 而且它默认也是只读预览。
#    源是 ISO / 光驱时做不了体检(dvd_repair.sh 只认目录), 跳过不拦。
#    为什么要有这道门: 整组 .IFO + .BUP 全丢时那条 title 根本读不出来
#    (libdvdread: findDVDFile /VIDEO_TS/VTS_01_0.IFO failed), 以前只会静默跳过它 ——
#    MODE=ALL 做出来的盘就少一条正片, AUTO 则可能挑中别的一条, 而日志上什么都看不出来。
#
#  依赖: ffmpeg(带 dvdvideo 解复用器 + mpeg2video) + dvdauthor + mkisofs/genisoimage
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[dvd_shrink]"
info()  { printf '%s %s\n' "$TAG" "$*"; }
warn()  { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()   { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()   { err "$*"; exit 1; }
usage() { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit "${1:-0}"; }

# DVD-5 标称 4.7 GB = 4489 MiB; 扣掉 ISO 目录项、IFO/BUP 与 dvdauthor 的
# padding, 4300 MiB 是能安稳刻下去的量(实测 4.16 GiB 内容 -> 镜像 4.21 GiB)
TARGET_MB="${TARGET_MB:-4300}"
DVD9_REF_MB=8000
MAXVB=8500        # MPEG-2 视频码率上限(kbps): DVD 规范总码率上限 10.08 Mbps
MINVB=1200        # 低于它画质就明显不行了, 提示但不拦
ABITRATE="${ABITRATE:-192k}"
SUBS="${SUBS:-copy}"
VFILT_EXTRA="${VFILT_EXTRA:-}"
MODE="${MODE:-AUTO}"
MISS_MAX="${MISS_MAX:-5}"

# =========================================================================
#  参数
# =========================================================================
SRC="${1:-}"
OUT="${2:-}"
[ -n "$SRC" ] || usage 1
case "$SRC" in -h|--help) usage 0 ;; esac
[ -e "$SRC" ] || die "源不存在: $SRC"
[ "$#" -ge 3 ] && { DVD_TITLE="$3"; MODE="TITLE"; }

if [ -n "$OUT" ]; then
    :
elif [ -d "$SRC" ]; then
    OUT="$(dirname "$SRC")/$(basename "$SRC")_shrunk.iso"
elif [ -f "$SRC" ]; then
    OUT="$(dirname "$SRC")/$(basename "${SRC%.*}")_shrunk.iso"
else
    OUT="$PWD/dvd_shrunk.iso"
fi
OUT="$(realpath -m "$OUT")"
OUT_DIR="$(dirname "$OUT")"
[ -d "$OUT_DIR" ] || mkdir -p "$OUT_DIR" || die "建不了输出目录: $OUT_DIR"

# 工作目录与输出 ISO 同级: 中间产物是 GB 级的, 放 /tmp 容易把根分区塞满
WORK="$OUT_DIR/.dvd_shrink_$(basename "${OUT%.iso}")"
rm -rf "$WORK"
mkdir -p "$WORK" || die "建不了工作目录: $WORK"
AUTHOR="$WORK/author"

cleanup() { [ "${KEEP_WORK:-0}" = 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

echo ============================================================
info "源          : $SRC"
info "输出 ISO    : $OUT"
info "目标容量    : ${TARGET_MB} MiB"
info "工作目录    : $WORK"
echo ============================================================

# =========================================================================
#  依赖: ffmpeg 要同时有 dvdvideo 解复用器与 mpeg2video 编码器。
#  不能只问 command -v ffmpeg: PATH 上第一个常常是发行版老构建 —— 本机实测
#  Cygwin 的 /usr/bin/ffmpeg(7.1.1) 与 MINGW64 的 /mingw64/bin/ffmpeg(8.1)
#  **都没有** dvdvideo, 唯一带它的是 gyan full(C:\Program Files\ffmpeg\bin)。
#
#  这里早先自带一份 pick_ffmpeg, 候选只到 "PATH 各项 + /opt/ffmpeg/*/bin +
#  /usr/local/bin + /usr/bin": Linux 上够用(能用的那份常在 /opt 下), **Windows
#  上就挑不到** —— 缺的是"Windows 安装前缀"那一级, 而它只有 lib/common.sh 的
#  find_ffmpeg 才有(实测它在这两个 shell 里都能自动落到 gyan)。
#  所以统一改用 find_ffmpeg, 免得同一套定位逻辑在仓库里写两份、各漏一半。
# =========================================================================
FF="$(find_ffmpeg --need-demuxer dvdvideo --need-encoder mpeg2video)" \
    || die "找不到同时具备 dvdvideo 解复用器与 mpeg2video 编码器的 ffmpeg(可用 FFMPEG=/path/to/ffmpeg 指定)"
FP="${FFPROBE:-}"
[ -n "$FP" ] && [ -x "$FP" ] || FP="$(find_ffprobe "$FF" 2>/dev/null)"
[ -x "$FP" ] || FP="$(command -v ffprobe 2>/dev/null)"
[ -n "$FP" ] || die "找不到 ffprobe"
export FF FP

# dvdauthor: Linux 有现成的包; Cygwin / MSYS2 **官方源没有**, 但自己编译一份不难
# (实测 0.7.2, 装进 /usr/bin 或 /mingw64/bin 即可被 command -v 找到 —— 2026-09-30
#  本机两个环境都这么装上了, 本脚本在 Windows 侧因此也能完整跑)。
command -v dvdauthor >/dev/null 2>&1 || die "找不到 dvdauthor。Linux: sudo apt install dvdauthor;Cygwin/MSYS2 官方源没有这个包, 需自行编译后放进 /usr/bin 或 /mingw64/bin"
MKISOFS=""
for c in mkisofs genisoimage; do command -v "$c" >/dev/null 2>&1 && { MKISOFS="$(command -v "$c")"; break; }; done
[ -n "$MKISOFS" ] || die "找不到 mkisofs / genisoimage(最后一步打包 ISO 要用到)"
[ -x "$SCRIPT_DIR/dvd_restore.sh" ] || die "缺少同目录的 dvd_restore.sh(打包与校验由它完成)"

# =========================================================================
#  体检门: 源是**目录**时, 开跑前请 dvd_repair.sh 只读体一次检
#  退出码约定(见 dvd_repair.sh 的 CHECK_ONLY): 0 完好 / 1 有缺失但都能补 / 2 有补不出来的
#  源是 ISO / 光驱时做不了 —— dvd_repair.sh 只认目录, 硬喂 ISO 会被它当成"没有 VIDEO_TS"
#  报错, 那是假警报, 所以这里直接跳过。
# =========================================================================
CHK_DIR=""
if [ "${CHECK:-1}" != "0" ] && [ -d "$SRC" ]; then
    if [ -d "$SRC/VIDEO_TS" ] || [ "$(basename "$SRC")" = "VIDEO_TS" ]; then CHK_DIR="$SRC"; fi
fi
if [ -n "$CHK_DIR" ]; then
    info "体检源盘结构 ..."
    CHECK_ONLY=1 bash "$SCRIPT_DIR/dvd_repair.sh" "$CHK_DIR"
    case "$?" in
        0) info "体检通过    : IFO/BUP 成对齐全, VOB 编号连续" ;;
        1)
            err "源盘有缺失(清单见上) —— 本脚本不替你补, 先修再瘦身: 修完的盘才是完整原料"
            die "修复命令:
       APPLY=1 bash \"$SCRIPT_DIR/dvd_repair.sh\" \"$CHK_DIR\"
   (不想要这道门就 CHECK=0)"
            ;;
        2)
            if [ "${ALLOW_GAP:-0}" = "1" ]; then
                warn "有补不出来的缺失 —— ALLOW_GAP=1, 继续; 少的那一段不会出现在产物里"
            else
                err "源盘有补不出来的缺失(VOB 断号): 那一整段的音视频真没了"
                die "确认要带着缺口继续就加 ALLOW_GAP=1 重跑:
       ALLOW_GAP=1 $0 \"$SRC\" ${OUT:+\"$OUT\"} ${DVD_TITLE:+\"$DVD_TITLE\"}"
            fi
            ;;
        *) die "体检失败(dvd_repair.sh 退出码非 0/1/2), 先单独跑它看报错" ;;
    esac
fi

info "ffmpeg      : $FF"

# =========================================================================
#  探测: 与 ffmpeg_dvd_hevc.sh 同款的两个坑
#    1) libdvdread 的抱怨("CHECK_VALUE failed in src/nav_read.c")在这个构建里
#       打到**标准输出**, 2>/dev/null 挡不住, 会混在真实数值前面 —— 只留数值行并
#       取最后一行(与 .bat 侧 for /f "后读到的覆盖前面的" 行为对齐)
#    2) csv=p=0 打出来是 "720,576," 这种带尾逗号的形态, 行级 ^...$ 匹配不上,
#       必须按**字段**判
# =========================================================================
probe_field() {
    # tr -d '\r' 必须在最前面: gyan 这类**原生**构建的行尾是 CRLF, CR 会粘在最后一个
    # 字段/整行末尾 -> 行级 ^...$ 永远匹配不上, 于是"时长恒空 -> 读不到 title"
    # (2026-09-30 实测: fp_run 直出是 6.000000, 过一遍下面的 tr+awk 就成空)。
    # 宽高那种按**字段**匹配的侥幸不受影响(CR 落在第 3 个字段上), 但一样要剥。
    fp_run -v error -f dvdvideo -title "$1" "${@:3}" -of csv=p=0 "$SRC" 2>/dev/null |
        tr -d '\r' | tr ',' '\n' | awk -v want="$2" 'BEGIN{ n = 0 } $0 ~ /^[0-9]+(\.[0-9]+)?$/ { n++; if (n == want) print $0 }' | tail -1
}

probe_title() {
    local t="$1" wh dur
    wh="$(fp_run -v error -f dvdvideo -title "$t" -select_streams v:0 \
          -show_entries stream=width,height -of csv=p=0 "$SRC" 2>/dev/null |
          tr -d '\r' | tr ',' ' ' | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print $1, $2 }' | tail -1)"
    [ -n "$wh" ] || return 1
    dur="$(probe_field "$t" 1 -show_entries format=duration)"
    # 时长读不出来就记 0, 而不是判这条 title 读不到: width/height 已经探到, title
    # 确实存在, 缺时长只影响"挑最长那条"和"按容量反推码率"。实测 dvdauthor 造的
    # 样例盘 format=duration 就是 N/A(2026-09-30) —— 按老写法整盘一条 title 都
    # 选不出来, shrink 在第一道门就退出了。
    [ -n "$dur" ] || { dur=0; DUR_UNKNOWN="${DUR_UNKNOWN:+$DUR_UNKNOWN,}$t"; }
    printf '%s %s\n' "$wh" "$dur"
}

probe_chapters() {
    fp_run -v error -f dvdvideo -title "$1" -show_entries chapter=start_time \
        -of csv=p=0 "$SRC" 2>/dev/null |
        tr -d '\r' | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ && $1 + 0 > 0 { printf "%s\n", $1 }'
}

# 音轨: 打印 "编码 码率" 每行一条。AC3/MP2 可以直接 copy, 其余(LPCM 等)要重编
probe_audio() {
    fp_run -v error -f dvdvideo -title "$1" -select_streams a \
        -show_entries stream=codec_name,bit_rate -of csv=p=0 "$SRC" 2>/dev/null |
        awk -F, '$1 ~ /^[a-z0-9_]+$/ { br = ($2 ~ /^[0-9]+$/) ? $2 : 0; print $1, br }'
}

# =========================================================================
#  选 title
# =========================================================================
TITLES=""
case "$MODE" in
    TITLE)
        probe_title "$DVD_TITLE" >/dev/null || die "读不到 title $DVD_TITLE(检查源路径 / 是否受 CSS 保护)"
        TITLES="$DVD_TITLE"
        ;;
    ALL)
        miss=0; n=1
        while [ "$n" -le 99 ]; do
            if probe_title "$n" >/dev/null 2>&1; then miss=0; TITLES="$TITLES $n"
            else miss=$((miss + 1)); [ "$miss" -ge "$MISS_MAX" ] && break; fi
            n=$((n + 1))
        done
        ;;
    *)
        # AUTO: title 编号**不连续**(实测有的盘缺中间号), 读不到不能 break,
        # 容忍连续 MISS_MAX 次才收尾; 挑时长最长的那条
        # BEST 从 -1 起: 时长全读不出来(dur=0)时也要能选中第一条, 否则下面那句
        # "一个 title 都没读到" 会把整盘拦下
        BEST=-1; DVD_TITLE=""; miss=0; n=1
        while [ "$n" -le 99 ]; do
            if line="$(probe_title "$n")"; then
                miss=0
                d="$(awk '{printf "%d", $3}' <<<"$line")"
                [ "$d" -gt "$BEST" ] && { BEST="$d"; DVD_TITLE="$n"; }
            else
                miss=$((miss + 1)); [ "$miss" -ge "$MISS_MAX" ] && break
            fi
            n=$((n + 1))
        done
        [ -n "$DVD_TITLE" ] || die "一个 title 都没读到, 检查源路径 / 是否受 CSS 保护"
        TITLES="$DVD_TITLE"
        if [ "$BEST" -gt 0 ]; then
            info "自动选定    : title $DVD_TITLE(共 ${BEST}s, 最长)"
        else
            warn "每条 title 的时长都读不出来(title ${DUR_UNKNOWN:-?}; 合成盘 / 无导航信息时常见) —— 按读到的第一条 title $DVD_TITLE 处理, 容量反推做不了, 要精确码率请显式给 VBITRATE=xxxxk"
        fi
        ;;
esac
[ -n "$TITLES" ] || die "没选到任何 title"

# ---- 对账: 盘上声明了几个标题集 vs 实际读出几条 title ----
# 整组 IFO/BUP 丢了的那条, libdvdread 读不出来就是"没有", 循环会安静地跳过它。
# 这里把"静默少一条"变成"说出来": MODE=ALL 时数量对不上就是产物要缺正片, 直接拦下
# (ALLOW_GAP=1 放行)。只在目录源上算 —— ISO / 光驱数不出 VTS_*_0.IFO。
if [ "${CHECK:-1}" != "0" ] && [ -d "$SRC" ]; then
    VTS_DIR="$SRC/VIDEO_TS"; [ -d "$VTS_DIR" ] || VTS_DIR="$SRC"
    n_ifo=0; for f in "$VTS_DIR"/VTS_*_0.IFO; do [ -f "$f" ] && n_ifo=$((n_ifo + 1)); done
    n_got=0; for t in $TITLES; do n_got=$((n_got + 1)); done
    if [ "$n_ifo" -gt 0 ] && [ "$n_got" -lt "$n_ifo" ]; then
        if [ "$MODE" = "ALL" ] && [ "${ALLOW_GAP:-0}" != "1" ]; then
            err "盘上有 $n_ifo 个标题集, 只读出 $n_got 条 title —— 少的那些多半是整组 IFO/BUP 丢了"
            die "确认少几条正片也要继续就加 ALLOW_GAP=1 重跑:
       MODE=ALL ALLOW_GAP=1 $0 \"$SRC\" ${OUT:+\"$OUT\"}
   (想先修: APPLY=1 bash \"$SCRIPT_DIR/dvd_repair.sh\" \"$SRC\")"
        fi
        warn "盘上有 $n_ifo 个标题集, 只读出 $n_got 条 title —— 少的那些读不出来(多半是整组 IFO/BUP 丢了)"
    fi
fi

# =========================================================================
#  反推码率
# =========================================================================
DUR_TOTAL="0"; AUD_WEIGHTED="0"; AENC_KIND=""; DUR_UNKNOWN=""
for t in $TITLES; do
    line="$(probe_title "$t")" || die "读不到 title $t"
    d="$(awk '{print $3}' <<<"$line")"
    ab="$(probe_audio "$t" | awk '{s += $2} END{printf "%d", s}')"
    [ -n "$ab" ] && [ "$ab" -gt 0 ] || ab=192000     # 探不到就按 AC3 192k 算
    DUR_TOTAL="$(awk -v a="$DUR_TOTAL" -v b="$d" 'BEGIN{printf "%.3f", a + b}')"
    AUD_WEIGHTED="$(awk -v a="$AUD_WEIGHTED" -v b="$ab" -v d="$d" 'BEGIN{printf "%.3f", a + b * d}')"
    # 音轨处理取决于**第一条**音轨的编码; 同一张盘各 title 一般一致
    [ -z "$AENC_KIND" ] && AENC_KIND="$(probe_audio "$t" | awk 'NR==1{print $1}')"
done

# DUR_TOTAL=0 = 一条时长都没读到: 凡是"按容量反推/估算"的都得绕开, 否则 awk 除零
DUR_OK="$(awk -v d="$DUR_TOTAL" 'BEGIN{print (d+0 > 0) ? 1 : 0}')"
AUD_AVG=""
[ "$DUR_OK" = 1 ] && AUD_AVG="$(awk -v a="$AUD_WEIGHTED" -v d="$DUR_TOTAL" 'BEGIN{printf "%d", a / d}')"
[ -n "$AUD_AVG" ] && [ "$AUD_AVG" -gt 0 ] || AUD_AVG=192000

if [ -n "${VBITRATE:-}" ]; then
    case "$VBITRATE" in
        *[kK]) VB_KB="${VBITRATE%[kK]}" ;;
        *[mM]) VB_KB="$(awk -v v="${VBITRATE%[mM]}" 'BEGIN{printf "%d", v * 1000}')" ;;
        *)     VB_KB="$(awk -v v="$VBITRATE" 'BEGIN{printf "%d", v / 1000}')" ;;
    esac
    info "视频码率    : ${VB_KB} kbps(VBITRATE 直接指定)"
elif [ "$DUR_OK" != 1 ]; then
    VB_KB="${VB_UNKNOWN:-5000}"
    info "视频码率    : ${VB_KB} kbps(时长读不出, 没法按容量反推; 可用 VBITRATE=xxxxk 或 VB_UNKNOWN=xxxx 覆盖)"
else
    # 容量 * 8 / 总时长 - 音频 = 每秒比特数, **再 /1000 才是 kbps**。
    # 漏掉这一步会得到 28 623 411 这种数(实测打印成 "28623411 kbps"), 而它一旦
    # 没撞上 MAXVB 上限就直接当 -b:v 28623411k 传给 mpeg2video —— 务必除 1000。
    # 98% 是留给 ISO 目录项 + IFO/BUP + padding 的余量
    VB_KB="$(awk -v mb="$TARGET_MB" -v d="$DUR_TOTAL" -v a="$AUD_AVG" \
             'BEGIN{printf "%d", ((mb * 1048576 * 8 * 0.98) / d - a) / 1000}')"
    info "视频码率    : ${VB_KB} kbps(按 ${TARGET_MB} MiB / ${DUR_TOTAL}s 反推, 音频 ${AUD_AVG} bps)"
fi

if [ "$VB_KB" -gt "$MAXVB" ]; then
    # 撞上限**通常不是装不下**, 而是"目标容量比内容宽裕得多"(20 分钟塞 DVD-5):
    # 反推出来 28 Mbps 这种数, 可 DVD 视频上限就 8.5 Mbps, 于是产物远小于目标盘。
    # 实测 20 分钟正片 -> 800 MiB / 目标 4300 MiB, 属于正常, 不要报错吓人。
    info "反推 ${VB_KB} kbps > DVD 视频上限 ${MAXVB} kbps —— 按上限编码(内容比目标盘短, 产物会明显小于 ${TARGET_MB} MiB)"
    VB_KB="$MAXVB"
elif [ "$VB_KB" -lt "$MINVB" ]; then
    warn "${VB_KB} kbps 太低了(${DUR_TOTAL}s 塞进 ${TARGET_MB} MiB), 画质会明显不行 —— 建议提高 TARGET_MB / 双层盘填 TARGET_MB=8000"
fi
MAX_KB="$(awk -v v="$VB_KB" 'BEGIN{m = int(v * 1.4); if (m > 9000) m = 9000; printf "%d", m}')"
ABIT_KB="$(awk -v a="$AUD_AVG" 'BEGIN{printf "%d", a / 1000}')"

# 按定下来的码率估一下产物, 早一步发现"目标盘根本装不下"。3% 是 ISO 目录项 +
# IFO/BUP 的余量。实测这个估算在**中低码率**很准(目标 300 MiB -> 估 302, 实出 306);
# 高目标会偏大: 给很高的 -b:v 时 mpeg2video 撞 qmin=2 根本编不到那么多
# (8500k 与 5839k 两条实测出一样大, 都停在 ~5.3 Mbps), 所以它是上界
if [ "$DUR_OK" = 1 ]; then
    EST_MB="$(awk -v v="$VB_KB" -v a="$ABIT_KB" -v d="$DUR_TOTAL" \
              'BEGIN{printf "%d", (v + a) * 1000 * d / 8 / 1048576 * 1.03}')"
    info "产物估算    : 约 ${EST_MB} MiB(上界, 实际通常更小)"
    [ "$EST_MB" -gt "$TARGET_MB" ] && warn "按 ${VB_KB} kbps 也要 ~${EST_MB} MiB, 超过目标 ${TARGET_MB} MiB —— 请提高 TARGET_MB(双层填 8000)或少选几条 title"
else
    EST_MB=0
fi

# 原盘码率粗估: 目录就累加 VIDEO_TS, ISO/设备就用文件体积
src_size=""
if [ -d "$SRC" ]; then
    if [ -d "$SRC/VIDEO_TS" ]; then
        src_size="$(find "$SRC/VIDEO_TS" -type f -printf '%s\n' 2>/dev/null | awk '{s += $1} END{printf "%d", s}')"
    elif [ "$(basename "$SRC")" = "VIDEO_TS" ]; then
        src_size="$(find "$SRC" -type f -printf '%s\n' 2>/dev/null | awk '{s += $1} END{printf "%d", s}')"
    fi
elif [ -f "$SRC" ]; then
    src_size="$(stat -c%s "$SRC")"
fi
if [ "$DUR_OK" = 1 ] && [ -n "$src_size" ] && [ "$src_size" -gt 0 ]; then
    orig_kb="$(awk -v s="$src_size" -v d="$DUR_TOTAL" 'BEGIN{printf "%d", s * 8 / d / 1000}')"
    info "原盘总码率  : ~${orig_kb} kbps(含音频)"
    [ "$VB_KB" -ge "$orig_kb" ] && warn "目标码率 ${VB_KB} kbps 不低于原盘 ${orig_kb} kbps —— 重编码纯属掉画质, 原样还原请改用 tools/dvd_restore.sh"
fi

echo =========================================================================

# =========================================================================
#  编码: 每条 title 出一个 DVD 合规的 MPEG-2 PS
# =========================================================================
AUDIO="${AUDIO:-copy}"
case "$AUDIO" in
    copy)
        case "$AENC_KIND" in
            ac3|mp2|mp3) AENC=(-c:a copy); info "音频        : $AENC_KIND -> 直接复制" ;;
            "")          AENC=(-c:a copy); info "音频        : 没探到音轨(无声 DVD), 按无声处理" ;;
            *)           AENC=(-c:a ac3 -b:a "$ABITRATE"); warn "音轨是 $AENC_KIND —— DVD 只认 AC3/MP2/LPCM/DTS, 重编码成 AC3 $ABITRATE" ;;
        esac
        ;;
    ac3)
        # 直接复制时 dvdauthor 有时会喊 "Discontinuity ... please remultiplex input"
        # (实测这条 20 分钟正片就有)。产物照样能播, 但在意的话让它重编一遍就没了
        AENC=(-c:a ac3 -b:a "$ABITRATE"); info "音频        : AUDIO=ac3 -> 重编码成 AC3 $ABITRATE" ;;
    *) die "AUDIO 只能是 copy 或 ac3" ;;
esac
case "$SUBS" in
    copy) SENC=(-c:s copy) ;;
    *)    SENC=() ;;
esac

enc() {
    local t="$1" mpg="$2" line w h fps vf=""
    line="$(probe_title "$t")" || return 1
    w="$(awk '{print $1}' <<<"$line")"; h="$(awk '{print $2}' <<<"$line")"
    fps="$(fp_run -v error -f dvdvideo -title "$t" -select_streams v:0 \
           -show_entries stream=r_frame_rate -of csv=p=0 "$SRC" 2>/dev/null |
           awk '$1 ~ /^[0-9]+\/[0-9]+$/ {print $1}' | tail -1)"

    # 制式: DVD 只有 PAL(576) / NTSC(480) 两套, 由高决定
    if [ "$h" -ge 500 ]; then FMT="PAL"; DH=576; OKFPS="25"; else FMT="NTSC"; DH=480; OKFPS="30000/1001"; fi
    # 合规分辨率: 720 / 704 / 352 宽, 576(288) 或 480(240) 高; 不在集合里就缩
    case "${w}x${h}" in
        720x576|704x576|352x576|352x288|720x480|704x480|352x480|352x240) ;;
        *) vf="scale=720:${DH}"; warn "title $t 是 ${w}x${h}, 不是 DVD 合规分辨率 —— 缩到 720x${DH}(scale 会保持显示宽高比)" ;;
    esac
    # 合规帧率: 只有 25 与 30000/1001
    if [ -n "$fps" ] && [ "$fps" != "$OKFPS" ]; then
        RATE=(-r "$OKFPS")
        warn "title $t 帧率 $fps 不是 ${FMT} 的 $OKFPS —— 强制转换, 可能有抖动"
    else
        RATE=()
    fi
    [ -n "$VFILT_EXTRA" ] && { [ -n "$vf" ] && vf="${vf},${VFILT_EXTRA}" || vf="$VFILT_EXTRA"; }

    info "编码 title $t -> $(basename "$mpg") ${w}x${h}${vf:+ 滤镜: $vf}"

    local CMD=(ff_run -y -hide_banner -v error -stats -f dvdvideo -title "$t" -i "$SRC")
    CMD+=(-map 0:V -map 0:a?)
    [ "$SUBS" = copy ] && CMD+=(-map 0:s?)
    [ -n "$vf" ] && CMD+=(-vf "$vf")
    CMD+=(-c:v mpeg2video -b:v "${VB_KB}k" -maxrate:v "${MAX_KB}k" -bufsize:v 1835008
          -g 12 -bf 2 -pix_fmt yuv420p ${RATE[@]+"${RATE[@]}"})
    CMD+=(${AENC[@]+"${AENC[@]}"} ${SENC[@]+"${SENC[@]}"})
    # -f dvd: 2048 字节一个 pack + 每个 GOP 带序列头, dvdauthor 只认这个形态
    CMD+=(-f dvd -packetsize 2048 -muxrate 10080000 "$mpg")
    "${CMD[@]}" || return 1
    [ -s "$mpg" ] || return 1
    return 0
}

RC=0
for t in $TITLES; do
    enc "$t" "$WORK/title_${t}.mpg" || RC=1
done
[ "$RC" -eq 0 ] || die "有 title 编码失败(工作目录保留在 $WORK, KEEP_WORK=1 可长期保留)"

# =========================================================================
#  dvdauthor: 每条 title 一个标题集, 章节从源盘带过来
# =========================================================================
xml_attr() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g'; }

# 秒 -> H:MM:SS.s(dvdauthor 的 chapters 属性要这个格式, 首章必须落在 0)
fmt_time() {
    awk -v s="$1" 'BEGIN{
        h = int(s / 3600); m = int((s - h * 3600) / 60); sec = s - h * 3600 - m * 60;
        printf "%d:%02d:%05.2f\n", h, m, sec;
    }'
}

XML="$WORK/dvd.xml"
AUTHOR_ESC="$(xml_attr "$(da_path "$AUTHOR")")"
{
    printf '<dvdauthor dest="%s">\n' "$AUTHOR_ESC"
    printf '  <vmgm />\n'
    for t in $TITLES; do
        ch="0"
        while IFS= read -r cs; do
            [ -n "$cs" ] && ch="$ch,$(fmt_time "$cs")"
        done < <(probe_chapters "$t")
        printf '  <titleset>\n    <titles>\n      <pgc>\n'
        printf '        <vob file="%s" chapters="%s"/>\n' "$(xml_attr "$(da_path "$WORK/title_${t}.mpg")")" "$ch"
        printf '      </pgc>\n    </titles>\n  </titleset>\n'
    done
    printf '</dvdauthor>\n'
} > "$XML"

# dvdauthor 靠 VIDEO_FORMAT 决定按哪套制式写 IFO, 不设就直接报错退出。
# 以第一条 title 的高为准(576/288 = PAL, 480/240 = NTSC)
FIRST_H="$(probe_title "$(awk '{print $1}' <<<"$TITLES")" | awk '{print $2}')"
case "$FIRST_H" in
    576|288) export VIDEO_FORMAT=PAL ;;
    *)       export VIDEO_FORMAT=NTSC ;;
esac
info "制式        : $VIDEO_FORMAT"

echo =========================================================================
info "dvdauthor 生成 VIDEO_TS ..."
dvdauthor -x "$XML" || die "dvdauthor 失败(常见原因: mpg 不是合规 MPEG-2 PS / 字幕不合规 —— 后者可试 SUBS=none)"
[ -f "$AUTHOR/VIDEO_TS/VIDEO_TS.IFO" ] || die "dvdauthor 没产出 VIDEO_TS.IFO"
info "VIDEO_TS    : $AUTHOR/VIDEO_TS"

# =========================================================================
#  打包 + 校验: 复用 dvd_restore.sh(它会补 AUDIO_TS、按 -dvd-video 排序打包、
#  验 UDF 与文件清单)
# =========================================================================
echo =========================================================================
# 卷标必须自己带过去: dvd_restore.sh 默认拿目录名当卷标, 而这里的目录叫 "author",
# 刻出来就是一张叫 author 的盘。取源名(ISO/文件则去扩展名), 之后统一走它的清洗规则
SRC_NAME="$(basename "$SRC")"
[ -d "$SRC" ] || [ -b "$SRC" ] || SRC_NAME="${SRC_NAME%.*}"
VOLID="${VOLID:-$SRC_NAME}"
export VOLID
bash "$SCRIPT_DIR/dvd_restore.sh" "$AUTHOR" "$OUT" || die "打包失败"
ISO_SZ="$(stat -c%s "$OUT" 2>/dev/null)"
[ -n "$ISO_SZ" ] || die "没找到产物 ISO: $OUT"

echo =========================================================================
TARGET_BYTES="$(awk -v mb="$TARGET_MB" 'BEGIN{printf "%d", mb * 1048576}')"
info "目标 / 实出: ${TARGET_MB} MiB / $(awk -v b="$ISO_SZ" 'BEGIN{printf "%.0f", b / 1048576}') MiB"
[ "$ISO_SZ" -gt "$TARGET_BYTES" ] && warn "产物超过目标容量 —— 刻盘前换更大的 TARGET_MB 重跑, 或刻 DVD-9"
info "完成        : $OUT"
info "下一步: 用播放器打开 ISO 确认能播(这是**重新制作**的 DVD, 原盘菜单不在里面)"
[ "${KEEP_WORK:-0}" = 1 ] && info "中间产物保留: $WORK"
exit 0
