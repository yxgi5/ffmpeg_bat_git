#!/bin/bash
# =========================================================================
#  tools/dvd_repair.sh  -  补齐"解压出来的 DVD 目录"里缺失的 IFO / BUP
#
#  用法:
#    ./tools/dvd_repair.sh <源目录> [输出ISO]
#      源目录   含 VIDEO_TS 的 DVD 根目录, 或 VIDEO_TS 目录本身(两种都认)
#      输出ISO  给了就在修完之后接着调 dvd_restore.sh 打包; 不给就只修不打
#
#  谁会调它: 没有。dvd_shrink.sh 只调 dvd_restore.sh, 不会替你补文件 —— 缺了就是
#            缺了, 得自己先跑一遍本脚本(顺序: 先 dvd_repair.sh 修, 再 dvd_shrink.sh 瘦)。
#            本脚本只在"给了输出ISO"时自动往下走一步: 修完自己调 dvd_restore.sh 打包。
#
#  开关(环境变量, 写在命令之前):
#    APPLY=1         真的改盘。默认只读预览: 只把"缺什么 / 打算怎么补"打印出来
#    KEEPMENU=1      重建时把原来的 VTS_xx_0.VOB(菜单)一起喂给 dvdauthor, 菜单能保住
#                    (默认 1; 失败会自动退回"不要菜单", 并把那个 VOB 挪到备份目录)
#    CHAPTERS=auto|none   重建时补不补章节。auto(默认)=用 ffmpeg 做场景检测自动打点。
#                    原 IFO 丢了, 章节时间点也就跟着没了, 只能重新检测
#    SCENE_TH=0.40   场景检测阈值(0~1, 越大越不敏感 -> 章节越少)
#    MIN_GAP=30      相邻章节至少隔多少秒(去抖, 免得一个镜头切一次)
#    MAX_CH=60       章节上限, 超了就按"总时长 / 上限"重新拉开间距
#    FORMAT=pal|ntsc 强制制式。默认从 VOB 分辨率判(576 / 288 = PAL, 其余 = NTSC)
#    FORCE=1         BUP 与 IFO 在本盘上就不一致的盘, 也照样用 BUP 顶 IFO
#    KEEP_WORK=1     保留工作目录(dvdauthor 的中间产物与日志)
#
#  四种缺失, 四种结局(2026-09-29 实测, 样本 DVD001(Canndy) 及故意弄坏的副本):
#    ① 缺 .BUP, .IFO 还在   -> 直接 cp。DVD 规范里 BUP 就是 IFO 的逐字节备份;
#       实测这张盘 3 对 IFO/BUP 的 md5 完全相同, 补出来和原盘没有差别。
#    ② 缺 .IFO, .BUP 还在   -> 反方向同样是 cp。看着"没坏"是错觉: ffprobe 能读出
#       title 是因为 libdvdread 会自动退回 BUP, 硬件 DVD 机和 mkisofs -dvd-video
#       没这待遇, 后者直接失败:
#         genisoimage: Failed to open VTS info. Unable to parse DVD-Video structures
#       也就是说这一档不补就打不出 ISO。补之前先拿本盘其余"两个都在"的对做比对,
#       确认它们逐字节相同才动手 —— 有的盘 BUP 与 IFO 并不一致, 那种要 FORCE=1。
#    ③ .IFO 和 .BUP 都没了 -> 只能 dvdauthor 重建: 拿该标题集自己的 VOB 重新生成
#       IFO/BUP(不重编码, 实测 1.6 GB 约 2 秒), 再 dvdauthor -T 重生成 VIDEO_TS.IFO/BUP。
#       两个只有真跑才会踩到的坑:
#         * 只换坏的那组、留着原来的 VIDEO_TS.IFO -> 正片少读一大截: 实测 1682s
#           只剩 1119s, 正好是第一个 VOB 的量。VMG 必须跟着重建。
#         * 重建后的 IFO 没有菜单时, 原来的 VTS_xx_0.VOB 成了孤儿文件,
#           mkisofs -dvd-video 会失败("Either VIDEO_TS.IFO or VIDEO_TS.VOB is not
#           of correct size")。要么把菜单一起喂进去(KEEPMENU=1), 要么把它挪走。
#       代价: 该组 VOB 会被 dvdauthor 重写一遍(内容等价, 尾部 padding 可能少一点);
#       原文件先 mv 到备份目录, 不会凭空消失。菜单能保(喂进去即可); 章节时间点随 IFO
#       一起没了, 只能用 CHAPTERS=auto 重新做一遍场景检测补回来(近似, 不是原盘的)。
#    ④ VOB 本身缺(编号断号, 例如 _1 _3 在而 _2 不在) -> 补不出来: 音视频数据真没了。
#       只报告, 告诉你是哪一段丢了。
#
#  依赖:
#    ①②  只要 cp
#    ③    dvdauthor + ffmpeg / ffprobe(探分辨率与音轨; CHAPTERS=auto 时还要做一遍
#         场景检测, 代价是一次全片解码, 30 分钟正片大约 1~3 分钟)
#
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[dvd_repair]"
info()  { printf '%s %s\n' "$TAG" "$*"; }
warn()  { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()   { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()   { err "$*"; exit 1; }
usage() { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit "${1:-0}"; }

APPLY="${APPLY:-0}"
KEEPMENU="${KEEPMENU:-1}"
CHAPTERS="${CHAPTERS:-auto}"
SCENE_TH="${SCENE_TH:-0.40}"
MIN_GAP="${MIN_GAP:-30}"
MAX_CH="${MAX_CH:-60}"
FORCE="${FORCE:-0}"
KEEP_WORK="${KEEP_WORK:-0}"

# =========================================================================
#  参数与路径
# =========================================================================
SRC="${1:-}"
OUT="${2:-}"
[ -n "$SRC" ] || usage 1
case "$SRC" in -h|--help) usage 0 ;; esac
[ -d "$SRC" ] || die "源目录不存在: $SRC"
SRC="${SRC%/}"
[ -n "$SRC" ] || SRC="/"

if [ -d "$SRC/VIDEO_TS" ]; then
    DVD_ROOT="$SRC"; VTS="$SRC/VIDEO_TS"
elif [ "$(basename "$SRC")" = "VIDEO_TS" ]; then
    DVD_ROOT="$(dirname "$SRC")"; VTS="$SRC"
else
    die "源目录里没有 VIDEO_TS, 也不叫 VIDEO_TS: $SRC"
fi
VTS="$(cd "$VTS" && pwd)"
DVD_ROOT="$(cd "$DVD_ROOT" && pwd)"

# 工作目录与备份目录都放在 DVD 根**旁边**: 放根目录里面会被 dvd_restore.sh 当成
# 夹带物警告, 也会被 mkisofs 一起扫进镜像
BASE_NAME="$(basename "$DVD_ROOT")"
[ -n "$BASE_NAME" ] && [ "$BASE_NAME" != "/" ] || BASE_NAME="DVDVIDEO"
WORK="$(dirname "$DVD_ROOT")/.dvd_repair_${BASE_NAME}"
BACKUP="$(dirname "$DVD_ROOT")/.dvd_repair_backup_${BASE_NAME}"
rm -rf "$WORK"
mkdir -p "$WORK" || die "建不了工作目录: $WORK"
cleanup() { [ "$KEEP_WORK" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT

echo ============================================================
info "源 DVD 根   : $DVD_ROOT"
info "VIDEO_TS    : $VTS"
info "模式        : $([ "$APPLY" = "1" ] && echo "APPLY=1 真的改盘" || echo "只读预览(APPLY=1 才会动文件)")"
echo ============================================================

# =========================================================================
#  小工具
# =========================================================================
# 原文件先挪到备份目录(同分区 mv 是免费的), 不让它凭空消失
mv_away() {
    local f="$1"
    mkdir -p "$BACKUP" || return 1
    mv -f "$f" "$BACKUP/$(basename "$f")" 2>/dev/null ||
        { cp -f "$f" "$BACKUP/$(basename "$f")" && rm -f "$f"; } || return 1
}

xml_attr() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g'; }

# 秒 -> H:MM:SS.s(dvdauthor 的 chapters 属性要这个格式, 首章必须落在 0)
fmt_time() {
    awk -v s="$1" 'BEGIN{
        h = int(s / 3600); m = int((s - h * 3600) / 60); sec = s - h * 3600 - m * 60;
        printf "%d:%02d:%05.2f\n", h, m, sec;
    }'
}

# 该组 idx >= 1 的 VOB(正片), 按序号升序。_0.VOB 是菜单, 不算
group_vobs() {
    local g="$1" f n s rest idx
    for f in "$VTS"/VTS_${g}_*.VOB; do
        [ -f "$f" ] || continue
        n="$(basename "$f")"; s="${n#VTS_}"; rest="${s#*_}"; idx="${rest%%.*}"
        [ "$idx" = "0" ] && continue
        case "$idx" in *[!0-9]*) continue ;; esac
        printf '%d\t%s\n' "$idx" "$f"
    done | sort -n -k1,1 | cut -f2-
}

# 该组正片 VOB 编号断号(1..max 里缺了谁) -> 打印缺失的编号
group_gaps() {
    local g="$1" f n s rest idx max=0 i out=""
    for f in "$VTS"/VTS_${g}_*.VOB; do
        [ -f "$f" ] || continue
        n="$(basename "$f")"; s="${n#VTS_}"; rest="${s#*_}"; idx="${rest%%.*}"
        [ "$idx" = "0" ] && continue
        case "$idx" in *[!0-9]*) continue ;; esac
        [ "$idx" -gt "$max" ] && max="$idx"
    done
    i=1
    while [ "$i" -le "$max" ]; do
        [ -f "$VTS/VTS_${g}_${i}.VOB" ] || out="$out $i"
        i=$((i + 1))
    done
    printf '%s' "${out# }"
}

# 本盘"两个都在"的 IFO/BUP 对是否逐字节相同, 用来判断 BUP 能不能顶 IFO。
# 打印 "对数 不一致数"; 没有任何完整对时打印 "0 0"(无从判断)
pair_stats() {
    local pairs=0 bad=0 a b g
    if [ -f "$VTS/VIDEO_TS.IFO" ] && [ -f "$VTS/VIDEO_TS.BUP" ]; then
        pairs=$((pairs + 1)); cmp -s "$VTS/VIDEO_TS.IFO" "$VTS/VIDEO_TS.BUP" || bad=$((bad + 1))
    fi
    for g in $VTS_GROUPS; do
        a="$VTS/VTS_${g}_0.IFO"; b="$VTS/VTS_${g}_0.BUP"
        [ -f "$a" ] && [ -f "$b" ] || continue
        pairs=$((pairs + 1)); cmp -s "$a" "$b" || bad=$((bad + 1))
    done
    printf '%s %s\n' "$pairs" "$bad"
}

# =========================================================================
#  扫描: 列出所有标题集(VTS_xx), 包括只剩 VOB、连 IFO/BUP 都没了的那种
# =========================================================================
VTS_GROUPS=""
for f in "$VTS"/VTS_*_*.IFO "$VTS"/VTS_*_*.BUP "$VTS"/VTS_*_*.VOB; do
    [ -f "$f" ] || continue
    n="$(basename "$f")"; s="${n#VTS_}"; g="${s%%_*}"
    case " $VTS_GROUPS " in *" $g "*) ;; *) VTS_GROUPS="$VTS_GROUPS $g" ;; esac
done
if [ -n "$VTS_GROUPS" ]; then
    VTS_GROUPS="$(printf '%s\n' $VTS_GROUPS | sort -n | tr '\n' ' ')"
    VTS_GROUPS="${VTS_GROUPS% }"
fi
[ -n "$VTS_GROUPS" ] || die "VIDEO_TS 里没有任何 VTS_xx_* 文件, 这不像 DVD-Video: $VTS"

# =========================================================================
#  分类
#   PLAN_KIND: CP(直接拷贝) / REBUILD(dvdauthor 重建) / VMG(重生成菜单 IFO) / GAP(补不出来)
# =========================================================================
PLAN_KIND=(); PLAN_DESC=(); PLAN_SRC=(); PLAN_DST=(); PLAN_GRP=()
add_plan() { PLAN_KIND+=("$1"); PLAN_DESC+=("$2"); PLAN_SRC+=("$3"); PLAN_DST+=("$4"); PLAN_GRP+=("$5"); }

NEED_VMG=0
NEED_TOOLS=0

# --- VIDEO_TS.IFO / VIDEO_TS.BUP(VMG, 全盘的目录) ---
if [ ! -f "$VTS/VIDEO_TS.IFO" ] && [ ! -f "$VTS/VIDEO_TS.BUP" ]; then
    add_plan VMG "VIDEO_TS.IFO 与 VIDEO_TS.BUP 都没有 —— dvdauthor -T 重新生成(不动 VOB)" "" "" ""
    NEED_VMG=1; NEED_TOOLS=1
elif [ ! -f "$VTS/VIDEO_TS.IFO" ]; then
    add_plan CP "缺 VIDEO_TS.IFO —— 用 VIDEO_TS.BUP 顶上" "$VTS/VIDEO_TS.BUP" "$VTS/VIDEO_TS.IFO" ""
elif [ ! -f "$VTS/VIDEO_TS.BUP" ]; then
    add_plan CP "缺 VIDEO_TS.BUP —— 用 VIDEO_TS.IFO 补一个" "$VTS/VIDEO_TS.IFO" "$VTS/VIDEO_TS.BUP" ""
fi

# --- 各标题集 ---
for g in $VTS_GROUPS; do
    ifo="$VTS/VTS_${g}_0.IFO"; bup="$VTS/VTS_${g}_0.BUP"
    gaps="$(group_gaps "$g")"
    if [ -n "$gaps" ]; then
        miss=""
        for i in $gaps; do miss="$miss VTS_${g}_${i}.VOB"; done
        add_plan GAP "VTS_$g 的正片 VOB 缺:${miss} —— 编号断号, 音视频数据真没了, 补不出来" "" "" ""
    fi
    if [ -f "$ifo" ] && [ ! -f "$bup" ]; then
        add_plan CP "缺 VTS_${g}_0.BUP —— 用 VTS_${g}_0.IFO 补一个" "$ifo" "$bup" ""
    elif [ ! -f "$ifo" ] && [ -f "$bup" ]; then
        add_plan CP "缺 VTS_${g}_0.IFO —— 用 VTS_${g}_0.BUP 顶上" "$bup" "$ifo" ""
    elif [ ! -f "$ifo" ] && [ ! -f "$bup" ]; then
        vobs="$(group_vobs "$g" | wc -l | tr -d ' ')"
        if [ "${vobs:-0}" -eq 0 ]; then
            add_plan GAP "VTS_$g 的 IFO/BUP 都没有, 而且一个正片 VOB 也没有 —— 无从重建" "" "" ""
        else
            add_plan REBUILD "VTS_$g 的 IFO/BUP 都没有 —— 用 dvdauthor 从它的 $vobs 个 VOB 重建(不重编码), 随后重生成 VIDEO_TS.IFO/BUP" "" "" "$g"
            NEED_VMG=1; NEED_TOOLS=1
        fi
    fi
done

N_ALL=${#PLAN_KIND[@]}
if [ "$N_ALL" -eq 0 ]; then
    info "没发现缺失: IFO/BUP 成对齐全, VOB 编号连续"
    if [ -n "$OUT" ]; then
        echo ============================================================
        bash "$SCRIPT_DIR/dvd_restore.sh" "$DVD_ROOT" "$OUT" || exit 1
    fi
    exit 0
fi

echo "缺失与处置($N_ALL 项):"
i=0
while [ "$i" -lt "$N_ALL" ]; do
    printf '  %2d. %s\n' "$((i + 1))" "${PLAN_DESC[$i]}"
    i=$((i + 1))
done
N_GAP=0
for k in "${PLAN_KIND[@]}"; do [ "$k" = "GAP" ] && N_GAP=$((N_GAP + 1)); done
[ "$N_GAP" -eq 0 ] || warn "有 $N_GAP 项是补不出来的(内容真丢了), 需要重新抓那一整段"
echo ============================================================

if [ "$APPLY" != "1" ]; then
    info "只读预览结束, 没有改动任何文件。确认无误后加 APPLY=1 重跑"
    exit 0
fi

# =========================================================================
#  依赖: 只有真的要重建时才需要
# =========================================================================
if [ "$NEED_TOOLS" = "1" ]; then
    command -v dvdauthor >/dev/null 2>&1 || die "要重建 IFO/BUP, 但找不到 dvdauthor。安装: sudo apt install dvdauthor"
    FF="${FFMPEG:-}"
    [ -n "$FF" ] && [ -x "$FF" ] || FF="$(find_ffmpeg 2>/dev/null)"
    [ -n "$FF" ] && [ -x "$FF" ] || FF="$(command -v ffmpeg 2>/dev/null)"
    [ -n "$FF" ] || die "要重建 IFO/BUP, 但找不到 ffmpeg(可用 FFMPEG=/path/to/ffmpeg 指定)"
    FP="${FFPROBE:-}"
    [ -n "$FP" ] && [ -x "$FP" ] || FP="$(find_ffprobe "$FF" 2>/dev/null)"
    [ -n "$FP" ] && [ -x "$FP" ] || FP="$(command -v ffprobe 2>/dev/null)"
    [ -n "$FP" ] || die "要重建 IFO/BUP, 但找不到 ffprobe"
    info "ffmpeg      : $FF"
fi

# =========================================================================
#  场景检测: 原 IFO 没了, 章节时间点也就没了 —— 重新检测一遍
#  逐条 VOB 单独跑(concat 会让后面的文件时间戳归零), 用"前面文件的时长之和"
#  当偏移把时间点接起来; 最后再按 MIN_GAP 去抖, 首章固定落在 0
# =========================================================================
vobs_duration() {
    local v d total=0
    for v in "$@"; do
        d="$("$FP" -v error -show_entries format=duration -of csv=p=0 "$v" 2>/dev/null |
            awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }' | tail -1)"
        [ -n "$d" ] || d=0
        total="$(awk -v a="$total" -v b="$d" 'BEGIN{printf "%.3f", a + b}')"
    done
    printf '%.3f\n' "$total"
}

detect_scenes() {
    local off=0 v dur
    for v in "$@"; do
        "$FF" -hide_banner -v info -i "$v" \
            -filter:v "select='gt(scene,$SCENE_TH)',showinfo" -f null - 2>&1 |
            awk -v o="$off" '/pts_time:/{
                for (i = 1; i <= NF; i++)
                    if ($i ~ /^pts_time:/) { t = substr($i, 10) + 0; if (t > 1) printf "%.3f\n", t + o }
            }'
        dur="$("$FP" -v error -show_entries format=duration -of csv=p=0 "$v" 2>/dev/null |
            awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }' | tail -1)"
        [ -n "$dur" ] || dur=0
        off="$(awk -v a="$off" -v b="$dur" 'BEGIN{printf "%.3f", a + b}')"
    done | awk -v min="$MIN_GAP" 'BEGIN{ last = -1e9 }
        { t = $1 + 0; if (t - last >= min) { printf "%.3f\n", t; last = t } }'
}

thin_chapters() {
    local total="$1"; shift
    local n need
    n="$#"
    [ "$n" -le "$MAX_CH" ] && { printf '%s\n' "$@"; return 0; }
    need="$(awk -v d="$total" -v m="$MAX_CH" 'BEGIN{printf "%.3f", d / m}')"
    printf '%s\n' "$@" | awk -v min="$need" 'BEGIN{ last = -1e9 }
        { t = $1 + 0; if (t - last >= min) { printf "%.3f\n", t; last = t } }'
}

# =========================================================================
#  章节属性怎么给 dvdauthor —— 一个大坑, 实测(2026-09-29, 样本 VTS_01 = 两个 VOB,
#  1119.04s + 563.35s, 合计 1682.39s):
#    * 只在**第一个** <vob> 上写 chapters -> PGC 时长元数据被截断成"第一个 VOB 的长度"
#      (1681.76s 变成 1119.04s), 跨 VOB 的章节直接丢失;
#    * 每个 <vob> 都写一份, 时间是**相对该 VOB 自己的开头**(不是整条 title), 且首项
#      必须是 0 -> 时长正常, 章节也在;
#    * 但**第二个及以后的 VOB 会吞掉它章节列表的最后一项** —— 所以在末尾追加一个
#      "哨兵"(取该 VOB 时长 - 1 秒)把真实章节顶住, 代价是 VOB 边界前多一个章节;
#    * 任一章节时间超过它所在 VOB 的长度 -> 整条 PGC 被截断, 比不给章节还糟。
#  所以: 逐 VOB 切片 + 后续 VOB 加哨兵, 并且**建完立刻复核时长**, 不对就降级。
# =========================================================================
# 按"每个 VOB 一段"切分全局章节时间点, 结果放进全局数组 CH_ATTR(每个 VOB 一条
# chapters 属性值)。$1 = full(带哨兵的完整章节) / zero(每个 VOB 只写 0)
build_ch_attr() {
    local mode="$1" i=0 off=0 s start end last_rel=""
    local -a rel
    CH_ATTR=()
    while [ "$i" -lt "${#tvobs[@]}" ]; do
        start="$off"
        end="$(awk -v a="$off" -v b="${vdur[$i]}" 'BEGIN{printf "%.3f", a + b}')"
        if [ "$mode" = "zero" ] || [ "$CHAPTERS" != "auto" ]; then
            CH_ATTR+=("0")
        else
            rel=()
            for s in ${scenes[@]+"${scenes[@]}"}; do
                [ -n "$s" ] || continue
                awk -v s="$s" -v a="$start" -v b="$end" 'BEGIN{exit !(s > a + 1 && s < b - 1)}' || continue
                rel+=("$(awk -v s="$s" -v a="$start" 'BEGIN{printf "%.3f", s - a}')")
            done
            last_rel=""
            [ "${#rel[@]}" -gt 0 ] && last_rel="${rel[${#rel[@]} - 1]}"
            # 哨兵: 只有"后面还有 VOB"时才需要(第一个 VOB 不吞最后一项, 实测过)
            if [ "$i" -gt 0 ] && [ "${#rel[@]}" -gt 0 ]; then
                awk -v l="$last_rel" -v d="${vdur[$i]}" 'BEGIN{exit !(l < d - 2)}' &&
                    rel+=("$(awk -v d="${vdur[$i]}" 'BEGIN{printf "%.3f", d - 1}')")
            fi
            s="0"
            for last_rel in ${rel[@]+"${rel[@]}"}; do s="$s,$(fmt_time "$last_rel")"; done
            CH_ATTR+=("$s")
        fi
        off="$end"
        i=$((i + 1))
    done
    return 0
}

# =========================================================================
#  重建一个标题集: dvdauthor 吃了它的正片 VOB, 吐出新的 IFO/BUP 与该组 VOB
# =========================================================================
rebuild_group() {
    local g="$1" dest xml menu="" w h acodec fmt total got f n i attempt
    local -a tvobs vdur scenes CH_ATTR
    while IFS= read -r f; do [ -n "$f" ] && tvobs+=("$f"); done < <(group_vobs "$g")
    [ "${#tvobs[@]}" -gt 0 ] || { warn "VTS_$g 没有正片 VOB, 跳过"; return 1; }

    [ "$KEEPMENU" = "1" ] && [ -f "$VTS/VTS_${g}_0.VOB" ] && menu="$VTS/VTS_${g}_0.VOB"

    w="$("$FP" -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "${tvobs[0]}" 2>/dev/null | awk -F, '$1 ~ /^[0-9]+$/ { print $1 }' | tail -1)"
    h="$("$FP" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "${tvobs[0]}" 2>/dev/null | awk -F, '$1 ~ /^[0-9]+$/ { print $1 }' | tail -1)"
    acodec="$("$FP" -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "${tvobs[0]}" 2>/dev/null | awk -F, '$1 ~ /^[a-z0-9_]+$/ { print $1 }' | tail -1)"

    if [ -n "${FORMAT:-}" ]; then
        fmt="$(printf '%s' "$FORMAT" | tr 'A-Z' 'a-z')"
    elif [ "${h:-0}" -ge 500 ]; then
        fmt="pal"
    else
        fmt="ntsc"
    fi
    # dvdauthor 靠 VIDEO_FORMAT 决定按哪套制式写 IFO, 不设会直接报错退出
    VIDEO_FORMAT="$(printf '%s' "$fmt" | tr 'a-z' 'A-Z')"
    export VIDEO_FORMAT
    info "VTS_$g 重建   : ${w:-?}x${h:-?} $VIDEO_FORMAT 音频 ${acodec:-未知}"

    # 各 VOB 时长: 既是章节切片的依据, 也是"有没有被 dvdauthor 截断"的基准
    i=0
    while [ "$i" -lt "${#tvobs[@]}" ]; do
        vdur+=("$("$FP" -v error -show_entries format=duration -of csv=p=0 "${tvobs[$i]}" 2>/dev/null |
            awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }' | tail -1)")
        [ -n "${vdur[$i]}" ] || vdur[$i]=0
        i=$((i + 1))
    done
    total="$(printf '%s\n' ${vdur[@]+"${vdur[@]}"} | awk '{s += $1} END{printf "%.3f", s}')"

    if [ "$CHAPTERS" = "auto" ]; then
        info "VTS_$g 章节   : 场景检测中(一次全片解码, 阈值 $SCENE_TH)..."
        mapfile -t scenes < <(detect_scenes "${tvobs[@]}")
        [ "${#scenes[@]}" -gt "$MAX_CH" ] && mapfile -t scenes < <(thin_chapters "$total" "${scenes[@]}")
        info "VTS_$g 章节   : 检出 ${#scenes[@]} 个切点 -> 分到 ${#tvobs[@]} 个 VOB 上"
    fi

    dest="$WORK/author_$g"
    xml="$WORK/vts_$g.xml"

    # 依次试: 完整章节 -> 每个 VOB 只写 0(保时长, 丢章节) -> 完全不给章节属性。
    # 每试一次都复核时长: dvdauthor 截断章节时不报错, 只把时长悄悄写短。
    for attempt in full zero none; do
        build_ch_attr "$attempt"
        rm -rf "$dest"; mkdir -p "$dest" || return 1
        {
            printf '<dvdauthor dest="%s">\n' "$(xml_attr "$dest")"
            printf '  <vmgm />\n'
            printf '  <titleset>\n'
            if [ -n "$menu" ]; then
                printf '    <menus>\n      <video format="%s" />\n' "$fmt"
                printf '      <pgc><vob file="%s" /></pgc>\n' "$(xml_attr "$menu")"
                printf '    </menus>\n'
            fi
            printf '    <titles>\n      <video format="%s" />\n' "$fmt"
            case "$acodec" in
                ac3|mp2|pcm|dts) printf '      <audio format="%s" />\n' "$acodec" ;;
            esac
            printf '      <pgc>\n'
            i=0
            while [ "$i" -lt "${#tvobs[@]}" ]; do
                if [ "$attempt" = "none" ]; then
                    printf '        <vob file="%s" />\n' "$(xml_attr "${tvobs[$i]}")"
                else
                    printf '        <vob file="%s" chapters="%s" />\n' "$(xml_attr "${tvobs[$i]}")" "${CH_ATTR[$i]}"
                fi
                i=$((i + 1))
            done
            printf '      </pgc>\n    </titles>\n  </titleset>\n'
            printf '</dvdauthor>\n'
        } > "$xml"

        if ! dvdauthor -x "$xml" >"$WORK/vts_$g.log" 2>&1; then
            if [ -n "$menu" ]; then
                warn "VTS_$g 带菜单重建失败 —— 退回不带菜单再来一次(菜单会丢), 日志: $WORK/vts_$g.log"
                menu=""
                sed -i '/<menus>/,/<\/menus>/d' "$xml"
                dvdauthor -x "$xml" >"$WORK/vts_$g.log" 2>&1 || { warn "VTS_$g 重建失败, 日志: $WORK/vts_$g.log"; return 1; }
            else
                warn "VTS_$g 重建失败, 日志: $WORK/vts_$g.log"; return 1
            fi
        fi

        # 复核: dest 是只有这一组的独立 DVD 树, 里面的 title 1 就是这条 PGC
        got="$("$FP" -v error -f dvdvideo -title 1 -show_entries format=duration \
              -of csv=p=0 "$dest" 2>/dev/null | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }' | tail -1)"
        if [ -z "$got" ] || awk -v a="$got" -v b="$total" 'BEGIN{exit !(a >= b - 2)}'; then
            [ "$attempt" = "full" ] && info "VTS_$g 时长   : ${got:-?}s(基准 $(printf '%.0f' "$total")s) —— 章节保住了"
            [ "$attempt" = "zero" ] && warn "VTS_$g: 带章节会把时长写短 —— 已退回只保留首章, 章节没保住"
            [ "$attempt" = "none" ] && warn "VTS_$g: 连首章都保不住 —— 已退回完全不加章节"
            break
        fi
        warn "VTS_$g: $attempt 这一版时长只有 ${got}s, 少于应有的 $(printf '%.0f' "$total")s —— dvdauthor 把 PGC 截断了, 换一种写法重试"
    done

    # 只搬 VTS_*: dest 里那份 VIDEO_TS.IFO 是 dvdauthor 顺手生成的空壳 VMG,
    # 真 VMG 由后面统一的 dvdauthor -T 产出, 别拿它覆盖
    for f in "$dest"/VIDEO_TS/VTS_*; do
        [ -f "$f" ] || continue
        n="$(basename "$f")"
        [ -e "$VTS/$n" ] && mv_away "$VTS/$n"
        cp "$f" "$VTS/$n" || return 1
    done
    info "VTS_$g 重建   : 完成($(ls "$dest"/VIDEO_TS 2>/dev/null | wc -l | tr -d ' ') 个文件写回)"

    # 没要菜单的原 _0.VOB 已不在新 IFO 的引用里 —— 留着会让 mkisofs -dvd-video 失败
    # (实测: "Either VIDEO_TS.IFO or VIDEO_TS.VOB is not of correct size")
    if [ -z "$menu" ] && [ -f "$VTS/VTS_${g}_0.VOB" ] && ! [ -f "$dest/VIDEO_TS/VTS_${g}_0.VOB" ]; then
        mv_away "$VTS/VTS_${g}_0.VOB" &&
            info "VTS_${g}_0.VOB 已挪到备份目录(新 IFO 不含菜单, 留着会让 mkisofs -dvd-video 失败)"
    fi
    return 0
}

# dvdauthor 靠 VIDEO_FORMAT 决定按哪套制式写 IFO, 不设就报错退出。
# 重建标题集时已按该组分辨率设过; 只重生成 VMG 的情形(没走过 rebuild_group)
# 在这里补上: 任取一个 VOB 探高度(576 / 288 = PAL, 其余 = NTSC)
ensure_format() {
    local v h=""
    [ -n "${VIDEO_FORMAT:-}" ] && { export VIDEO_FORMAT; return 0; }
    if [ -n "${FORMAT:-}" ]; then
        VIDEO_FORMAT="$(printf '%s' "$FORMAT" | tr 'a-z' 'A-Z')"
    else
        for v in "$VTS"/VTS_*_1.VOB "$VTS"/VIDEO_TS.VOB; do
            [ -f "$v" ] || continue
            h="$("$FP" -v error -select_streams v:0 -show_entries stream=height \
                -of csv=p=0 "$v" 2>/dev/null | awk -F, '$1 ~ /^[0-9]+$/ { print $1 }' | tail -1)"
            [ -n "$h" ] && break
        done
        if [ "${h:-0}" -ge 500 ]; then VIDEO_FORMAT="PAL"; else VIDEO_FORMAT="NTSC"; fi
    fi
    export VIDEO_FORMAT
    return 0
}

regen_vmg() {
    ensure_format
    [ -f "$VTS/VIDEO_TS.IFO" ] && mv_away "$VTS/VIDEO_TS.IFO"
    [ -f "$VTS/VIDEO_TS.BUP" ] && mv_away "$VTS/VIDEO_TS.BUP"
    dvdauthor -T -o "$DVD_ROOT" >"$WORK/vmg.log" 2>&1 || { warn "重生成 VIDEO_TS.IFO 失败, 日志: $WORK/vmg.log"; return 1; }
    [ -f "$VTS/VIDEO_TS.IFO" ] || return 1
    return 0
}

# =========================================================================
#  执行
# =========================================================================
stats="$(pair_stats)"
P_TOT="$(awk '{print $1}' <<<"$stats")"
P_BAD="$(awk '{print $2}' <<<"$stats")"
if [ "$P_TOT" -gt 0 ]; then
    if [ "$P_BAD" -eq 0 ]; then
        info "本盘 $P_TOT 对 IFO/BUP 逐字节相同 —— BUP 与 IFO 可以互相顶替"
    else
        warn "本盘 $P_TOT 对 IFO/BUP 里有 $P_BAD 对不一致(非规范盘) —— 用 BUP 顶 IFO 有风险"
    fi
else
    warn "本盘没有一对完整的 IFO/BUP 可供比对 —— 按规范照补, 但无从验证"
fi

RC=0
i=0
while [ "$i" -lt "$N_ALL" ]; do
    k="${PLAN_KIND[$i]}"
    case "$k" in
        CP)
            if [ "$P_BAD" -gt 0 ] && [ "${PLAN_DST[$i]}" != "${PLAN_DST[$i]%.IFO}" ] && [ "$FORCE" != "1" ]; then
                warn "跳过 ${PLAN_DESC[$i]} —— 本盘 IFO/BUP 本就不一致, 确认要这样就加 FORCE=1"
                RC=1
            else
                if cp -f "${PLAN_SRC[$i]}" "${PLAN_DST[$i]}"; then
                    info "已补: $(basename "${PLAN_DST[$i]}") <- $(basename "${PLAN_SRC[$i]}")"
                else
                    warn "补失败: ${PLAN_DST[$i]}"
                    RC=1
                fi
            fi
            ;;
        REBUILD)
            rebuild_group "${PLAN_GRP[$i]}" || RC=1
            ;;
        GAP)
            ;;
    esac
    i=$((i + 1))
done

if [ "$NEED_VMG" = "1" ]; then
    # 实测: 只换掉坏的那组、留着原来的 VIDEO_TS.IFO, 正片会少读一大截
    # (1682s -> 1119s), 所以只要动过重建就必须连带重生成 VMG
    if regen_vmg; then
        info "已重生成 VIDEO_TS.IFO / VIDEO_TS.BUP(dvdauthor -T)"
    else
        RC=1
    fi
fi

[ -d "$BACKUP" ] && info "被替换的原件: $BACKUP"
[ "$KEEP_WORK" = "1" ] && info "工作目录保留: $WORK"

if [ "$RC" -ne 0 ]; then
    die "有项目没修好(见上面的警告)"
fi

if [ -n "$OUT" ]; then
    echo ============================================================
    VOLID="${VOLID:-$BASE_NAME}"
    export VOLID
    bash "$SCRIPT_DIR/dvd_restore.sh" "$DVD_ROOT" "$OUT" || exit 1
else
    echo ============================================================
    info "修复完成: $VTS"
    info "下一步: tools/dvd_restore.sh \"$DVD_ROOT\" 打成可刻录的 ISO"
fi
exit 0
