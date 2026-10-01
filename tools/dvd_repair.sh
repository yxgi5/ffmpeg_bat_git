#!/bin/bash
# =========================================================================
#  tools/dvd_repair.sh  -  补齐"解压出来的 DVD 目录"里缺失的 IFO / BUP
#
#  用法:
#    ./tools/dvd_repair.sh <源目录> [输出ISO]
#      源目录   含 VIDEO_TS 的 DVD 根目录, 或 VIDEO_TS 目录本身(两种都认)
#      输出ISO  给了就在修完之后接着调 dvd_restore.sh 打包; 不给就只修不打
#
#  谁会调它:
#    * 体检模式(CHECK_ONLY=1)被 tools/dvd_shrink.sh 与 tools/dvd_to_data_iso.sh 当
#      "体检门"调用: 它们只看退出码, 仍然**不替用户改盘** —— 有缺失就停下来, 把本脚本
#      的修复命令打给用户(顺序不变: 先 dvd_repair.sh 修, 再瘦身 / 再压)。
#    * 本脚本自己只在"给了输出ISO"时往下走一步: 修完自动调 dvd_restore.sh 打包。
#    * dvd_restore.sh **不**调本脚本(它只指路): 否则"修完打包"会变成互相调用的死循环。
#
#  开关(环境变量, 写在命令之前):
#    CHECK_ONLY=1    只体检, 不改任何文件: 打印缺失清单, 结论走**退出码** ——
#                    0 = 完好 / 1 = 有缺失但都能补 / 2 = 有补不出来的(VOB 断号)
#                    给别的脚本当"体检门"用(见"谁会调它")
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
#    KEEPVMG=1       有重建也保留原 VIDEO_TS.IFO(菜单能保住), 不重生成 VMG
#    REGENVMG=1      反过来: 即使 VOB 布局没变也强制重生成 VMG(丢菜单, 换扇区表自洽)
#    MOVE_ORPHAN_VMG=1  重生成 VMG 后把不再被引用的 VIDEO_TS.VOB 挪到备份目录
#                    (默认只警告不挪: 菜单视频是原盘资产, 不替用户删)
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
#  TDVD003 这一轮(2026-09-30, 一张重新下载过、仍然坏着的盘: VTS_06_0.IFO/BUP 与
#  VTS_05_0.BUP 文件都在、内容整片 0x00)补出来的三条经验:
#    ⑤ IFO/BUP 偏移 0x0C 的 4 个字节(大端) = 该 VMG/VTS **整个区段**的最后一个扇区。
#       区段 = IFO + 该区段的全部 VOB + BUP, 不是"IFO 自身的大小"。按
#       "自身大小 / 2048 - 1"去"修"它, 会把本来正确的盘改坏 —— genisoimage
#       -dvd-video 就是按这个字段校验的, 于是永远报 "IFO is not of correct size"。
#       本脚本只**报告**不一致(体检时打出来), 不替你改。
#    ⑥ 文件在、内容是 0x00 的 IFO/BUP, 光看 [ -f ] 看不出来 —— 脚本会当它完好,
#       一路走到"没发现缺失"。判空必须判内容(本脚本的判法: 去掉所有 0x00 之后
#       还有没有别的字节), 上面 ①②③ 的处置对它同样适用。
#    ⑦ 重建标题集之后要不要跟着重生成 VMG(VIDEO_TS.IFO), 取决于 VOB 的扇区布局
#       变了没有:
#         - 变了(dvdauthor 重写过 VOB, 尾部 padding 变短等) -> 必须重生成, 否则
#           正片只读到一半(实测 1682s 剩 1119s);
#         - 没变 -> 重生成反而把原菜单弄丢: dvdauthor -T 造出来的 VMG 没有菜单,
#           而原来的 VIDEO_TS.VOB 成了没人引用的孤儿文件。这次就是这么踩的 ——
#           改成保留原 VMG 之后, 菜单和选段才正常。
#       本脚本按"该组 VOB 的总字节数变了没"自动判断, 两种实测结论都照顾到了;
#       要手工指定就用 KEEPVMG / REGENVMG。
#    ⑧ 别把原盘的 VIDEO_TS.VOB 换成自己生成的 —— 它必须和 VIDEO_TS.IFO **原配**。
#       2026-10-01 同一天两次端到端实测, 结论翻过一次案:
#         - 先拿工作副本试, 那里的 VIDEO_TS.VOB 是 ffmpeg 现做的蓝屏菜单(409600
#           字节), 与原盘 VIDEO_TS.IFO 里记的菜单大小对不上, 于是 -dvd-video 先报
#           "Either VIDEO_TS.IFO or VIDEO_TS.VOB is not of correct size"; 把 0x0C
#           按 ⑤ 改好后又报 "Video pad for file VIDEO_TS.BUP is -178"。当时据此
#           写成"严格 -dvd-video 与原盘菜单二选一", 是**误判**;
#         - 换成原配的源盘(VIDEO_TS.IFO 18432 + VIDEO_TS.VOB 329728), 先用本脚本
#           修掉整片 0x00 的 IFO/BUP(修完 0x0C 自检全部一致), 再 dvd_restore.sh
#           直接 -dvd-video: 一次就过(1917064 extents, UDF BEA01/TEA01 齐全,
#           22 个文件逐个对得上), 菜单照旧在 —— **两者可以兼得**。
#       顺带两条: dvdauthor -T 造出来的 VMG 确实不带菜单, 别拿它去顶原盘那个;
#       也不要走"把 VIDEO_TS.VOB 挪走"那条路, 那是主动丢菜单。
#    ⑨ dvdauthor 给"这条 XML 里唯一的 titleset"固定编号 **01** —— 拿它重建 VTS_06,
#       吐出来的文件照样叫 VTS_01_*。写回前必须把 01 换成目标组号, 否则按原名写回
#       覆盖的是完好的 VTS_01, 而待修的那一组一个字节都没动。2026-10-01 端到端实测
#       就踩了这个: VTS_01_1.VOB(857MB)被 158MB 的重建结果顶掉, VTS_06_0.IFO 仍是
#       整片 0x00 —— 一张盘越修越坏, 而日志还写着"重建完成"。
#
#  流程上的坑(同样来自这一轮):
#    * 本脚本是**原地改盘**的。若源所在目录正被别的进程清理(这次是 H:\Downloads
#      被后台任务反复删), 会修到一半素材就没了 —— 先在别处复制一份再修。
#    * 动过的原件都会进 .dvd_repair_backup_*, 源目录真被删了也还有得救;
#      这次正是靠备份目录里的 VIDEO_TS.IFO 把菜单捞回来的。
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

CHECK_ONLY="${CHECK_ONLY:-0}"
APPLY="${APPLY:-0}"
KEEPMENU="${KEEPMENU:-1}"
CHAPTERS="${CHAPTERS:-auto}"
SCENE_TH="${SCENE_TH:-0.40}"
MIN_GAP="${MIN_GAP:-30}"
MAX_CH="${MAX_CH:-60}"
FORCE="${FORCE:-0}"
KEEPVMG="${KEEPVMG:-0}"
REGENVMG="${REGENVMG:-0}"
MOVE_ORPHAN_VMG="${MOVE_ORPHAN_VMG:-0}"
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
if [ "$CHECK_ONLY" = "1" ]; then
    # 只体检: 不要在源盘旁边留下 .dvd_repair_* 目录(没动过文件却留个空壳最容易误判)
    WORK="$(mktemp -d 2>/dev/null || echo "/tmp/.dvd_repair_check_$$")"
else
    WORK="$(dirname "$DVD_ROOT")/.dvd_repair_${BASE_NAME}"
fi
BACKUP="$(dirname "$DVD_ROOT")/.dvd_repair_backup_${BASE_NAME}"
rm -rf "$WORK"
mkdir -p "$WORK" || die "建不了工作目录: $WORK"
cleanup() { [ "$KEEP_WORK" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT

echo ============================================================
info "源 DVD 根   : $DVD_ROOT"
info "VIDEO_TS    : $VTS"
if [ "$CHECK_ONLY" = "1" ]; then
    info "体检模式    : CHECK_ONLY=1 —— 不改任何文件, 结论走退出码(0 完好 / 1 可修 / 2 补不出来)"
fi
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

# ---------------------------------------------------------------------------
#  "这块 IFO/BUP 能不能用": 存在、非空、且去掉所有 0x00 之后还有别的字节。
#  返回 0 = 坏的(缺失 / 空 / 整片 0x00), 返回 1 = 能用。
#  为什么必须判内容: TDVD003 的 VTS_06_0.IFO/BUP 与 VTS_05_0.BUP 文件都在、大小也
#  正常(14336 / 30720 字节), 但整片是 0x00 —— 只看 [ -f ] 会被当成完好, 整张盘的
#  问题就全部漏掉了(2026-09-30 实测, 见头部注释 ⑥)
# ---------------------------------------------------------------------------
ifo_blank() {
    local f="$1"
    [ -f "$f" ] || return 0
    [ -s "$f" ] || return 0
    LC_ALL=C tr -d '\000' < "$f" 2>/dev/null | head -c 512 | grep -q . && return 1
    return 0
}

# 读 IFO/BUP 偏移 0x0C 的 4 个字节(大端) —— 该区段的最后一个扇区号。
# 别用 od -tu4: 它按**主机**字节序解释, x86 上会把这个大端字段读反。
read_last_sector() {
    local f="$1" b
    [ -f "$f" ] || return 1
    b="$(dd if="$f" bs=1 skip=12 count=4 2>/dev/null | od -An -tu1 | tr -s ' \n' ' ')"
    set -- $b
    [ "$#" -eq 4 ] || return 1
    printf '%d\n' $(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 ))
}

# 若干文件拼起来的总字节数 -> 末尾扇区号(向上取整到 2048)
last_sector_of() {
    local total=0 f sz
    for f in "$@"; do
        [ -f "$f" ] || continue
        sz="$(stat -c%s "$f" 2>/dev/null)"
        case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
        total=$(( total + sz ))
    done
    printf '%d\n' $(( (total + 2047) / 2048 - 1 ))
}

# 各组 IFO 里声明的末尾扇区(0x0C) 与实际算出来的末尾扇区 对不对得上。
# 对不上 -> genisoimage -dvd-video 会卡在这一组("IFO is not of correct size")。
# **只报告, 不修改**: 见头部注释 ⑤ —— 按错误公式去"修"会把好盘改坏。
sector_report() {
    local g dec act f rc=0
    local -a files
    if [ -f "$VTS/VIDEO_TS.IFO" ]; then
        dec="$(read_last_sector "$VTS/VIDEO_TS.IFO" 2>/dev/null || echo '')"
        if [ -n "$dec" ]; then
            act="$(last_sector_of "$VTS/VIDEO_TS.IFO" "$VTS/VIDEO_TS.VOB" "$VTS/VIDEO_TS.BUP")"
            [ "$dec" = "$act" ] || { warn "VIDEO_TS.IFO 声明末尾扇区 $dec, 实际是 $act"; rc=1; }
        fi
    fi
    for g in $VTS_GROUPS; do
        [ -f "$VTS/VTS_${g}_0.IFO" ] || continue
        dec="$(read_last_sector "$VTS/VTS_${g}_0.IFO" 2>/dev/null || echo '')"
        [ -n "$dec" ] || continue
        files=("$VTS/VTS_${g}_0.IFO")
        for f in "$VTS"/VTS_${g}_*.VOB; do [ -f "$f" ] && files+=("$f"); done
        [ -f "$VTS/VTS_${g}_0.BUP" ] && files+=("$VTS/VTS_${g}_0.BUP")
        act="$(last_sector_of "${files[@]}")"
        [ "$dec" = "$act" ] || { warn "VTS_${g}_0.IFO 声明末尾扇区 $dec, 实际是 $act"; rc=1; }
    done
    [ "$rc" -eq 0 ] && info "扇区自检    : 各组 IFO 的 0x0C 与实际区段一致"
    return $rc
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

# 本盘"两个都在且都有效"的 IFO/BUP 对是否逐字节相同, 用来判断 BUP 能不能顶 IFO。
# 打印 "对数 不一致数"; 没有任何完整对时打印 "0 0"(无从判断)。
# 整片 0x00 的那种不算数 —— 拿它跟好的另一半比, 只会得出"本盘不一致"的错误结论
pair_stats() {
    local pairs=0 bad=0 a b g
    if ! ifo_blank "$VTS/VIDEO_TS.IFO" && ! ifo_blank "$VTS/VIDEO_TS.BUP"; then
        pairs=$((pairs + 1)); cmp -s "$VTS/VIDEO_TS.IFO" "$VTS/VIDEO_TS.BUP" || bad=$((bad + 1))
    fi
    for g in $VTS_GROUPS; do
        a="$VTS/VTS_${g}_0.IFO"; b="$VTS/VTS_${g}_0.BUP"
        ifo_blank "$a" && continue
        ifo_blank "$b" && continue
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
# 重建过的组里, 有没有哪一组的 VOB 总字节数被 dvdauthor 改过(见头部注释 ⑦)
LAYOUT_CHANGED=0

# --- VIDEO_TS.IFO / VIDEO_TS.BUP(VMG, 全盘的目录) ---
# "坏了" = 缺失 **或** 内容整片 0x00(见头部注释 ⑥); 后者光看 [ -f ] 看不出来
VMG_BAD=0
vifo=0; vbup=0
ifo_blank "$VTS/VIDEO_TS.IFO" || vifo=1
ifo_blank "$VTS/VIDEO_TS.BUP" || vbup=1
if [ "$vifo" = "0" ] && [ "$vbup" = "0" ]; then
    VMG_BAD=1; NEED_VMG=1; NEED_TOOLS=1
    if [ -f "$VTS/VIDEO_TS.IFO" ] || [ -f "$VTS/VIDEO_TS.BUP" ]; then
        add_plan VMG "VIDEO_TS.IFO 与 VIDEO_TS.BUP 都在, 但内容无效(整片 0x00) —— dvdauthor -T 重新生成(不动 VOB)" "" "" ""
    else
        add_plan VMG "VIDEO_TS.IFO 与 VIDEO_TS.BUP 都没有 —— dvdauthor -T 重新生成(不动 VOB)" "" "" ""
    fi
elif [ "$vifo" = "0" ]; then
    VMG_BAD=1
    if [ -f "$VTS/VIDEO_TS.IFO" ]; then
        add_plan CP "VIDEO_TS.IFO 在但内容无效(整片 0x00) —— 用 VIDEO_TS.BUP 顶上" "$VTS/VIDEO_TS.BUP" "$VTS/VIDEO_TS.IFO" ""
    else
        add_plan CP "缺 VIDEO_TS.IFO —— 用 VIDEO_TS.BUP 顶上" "$VTS/VIDEO_TS.BUP" "$VTS/VIDEO_TS.IFO" ""
    fi
elif [ "$vbup" = "0" ]; then
    if [ -f "$VTS/VIDEO_TS.BUP" ]; then
        add_plan CP "VIDEO_TS.BUP 在但内容无效(整片 0x00) —— 用 VIDEO_TS.IFO 补一个" "$VTS/VIDEO_TS.IFO" "$VTS/VIDEO_TS.BUP" ""
    else
        add_plan CP "缺 VIDEO_TS.BUP —— 用 VIDEO_TS.IFO 补一个" "$VTS/VIDEO_TS.IFO" "$VTS/VIDEO_TS.BUP" ""
    fi
fi

# --- 各标题集 ---
for g in $VTS_GROUPS; do
    ifo="$VTS/VTS_${g}_0.IFO"; bup="$VTS/VTS_${g}_0.BUP"
    gifo=0; gbup=0
    ifo_blank "$ifo" || gifo=1
    ifo_blank "$bup" || gbup=1
    gaps="$(group_gaps "$g")"
    if [ -n "$gaps" ]; then
        miss=""
        for i in $gaps; do miss="$miss VTS_${g}_${i}.VOB"; done
        add_plan GAP "VTS_$g 的正片 VOB 缺:${miss} —— 编号断号, 音视频数据真没了, 补不出来" "" "" ""
    fi
    if [ "$gifo" = "1" ] && [ "$gbup" = "0" ]; then
        if [ -f "$bup" ]; then
            add_plan CP "VTS_${g}_0.BUP 在但内容无效(整片 0x00) —— 用 VTS_${g}_0.IFO 补一个" "$ifo" "$bup" ""
        else
            add_plan CP "缺 VTS_${g}_0.BUP —— 用 VTS_${g}_0.IFO 补一个" "$ifo" "$bup" ""
        fi
    elif [ "$gifo" = "0" ] && [ "$gbup" = "1" ]; then
        if [ -f "$ifo" ]; then
            add_plan CP "VTS_${g}_0.IFO 在但内容无效(整片 0x00) —— 用 VTS_${g}_0.BUP 顶上" "$bup" "$ifo" ""
        else
            add_plan CP "缺 VTS_${g}_0.IFO —— 用 VTS_${g}_0.BUP 顶上" "$bup" "$ifo" ""
        fi
    elif [ "$gifo" = "0" ] && [ "$gbup" = "0" ]; then
        vobs="$(group_vobs "$g" | wc -l | tr -d ' ')"
        if [ "${vobs:-0}" -eq 0 ]; then
            add_plan GAP "VTS_$g 的 IFO/BUP 都没有或都无效, 而且一个正片 VOB 也没有 —— 无从重建" "" "" ""
        else
            add_plan REBUILD "VTS_$g 的 IFO/BUP 缺失或无效 —— 用 dvdauthor 从它的 $vobs 个 VOB 重建(不重编码); VMG 稍后按 VOB 布局变没变再决定重不重生成" "" "" "$g"
            NEED_VMG=1; NEED_TOOLS=1
        fi
    fi
done

N_ALL=${#PLAN_KIND[@]}
if [ "$N_ALL" -eq 0 ]; then
    info "没发现缺失: IFO/BUP 成对齐全, VOB 编号连续"
    # 文件都在不等于盘是好的: TDVD003 就是 IFO/BUP 一个不缺, 但 0x0C 写的末尾扇区
    # 全错, 打包时 -dvd-video 一样过不去。所以这里也要自检(见头部注释 ⑤)
    sector_report || warn "上面这些 0x0C 与实际区段对不上 —— genisoimage -dvd-video 会卡住; 只报告不修改"
    # 体检模式下不往下打包: 调用方只要结论(退出码 0), 不该顺手产出一个镜像
    if [ -n "$OUT" ] && [ "$CHECK_ONLY" != "1" ]; then
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

# 体检模式: 结论只走退出码, 跳过后面所有会动文件的分支(含 dvdauthor 依赖检查)
#   0 = 完好        调用方继续
#   1 = 有缺失但都能补  调用方 die 并给出 APPLY=1 那条命令
#   2 = 有补不出来的    调用方 die: 内容真没了, 修也没用
if [ "$CHECK_ONLY" = "1" ]; then
    # 顺便把 0x0C 的自检做了: 对不上的话, 后面 genisoimage -dvd-video 会卡在这一组
    sector_report || warn "上面这些 0x0C 与实际区段对不上 —— genisoimage -dvd-video 会卡住; 只报告不修改(见头部注释 ⑤)"
    if [ "$N_GAP" -gt 0 ]; then
        info "体检结论: $N_ALL 项里 $N_GAP 项补不出来(内容真丢了) —— 退出码 2"
        exit 2
    fi
    info "体检结论: $N_ALL 项都能补(加 APPLY=1 重跑即可) —— 退出码 1"
    exit 1
fi

if [ "$APPLY" != "1" ]; then
    info "只读预览结束, 没有改动任何文件。确认无误后加 APPLY=1 重跑"
    exit 0
fi

# =========================================================================
#  依赖: 只有真的要重建时才需要
# =========================================================================
if [ "$NEED_TOOLS" = "1" ]; then
    # Cygwin / MSYS2 官方源没有 dvdauthor, 但可以自己编译(实测 0.7.2), 装进
    # /usr/bin 或 /mingw64/bin 后 command -v 就能找到 —— 2026-09-30 本机两个
    # 环境都已这么装上, 重建这条路在 Windows 侧同样跑得通。
    command -v dvdauthor >/dev/null 2>&1 || die "要重建 IFO/BUP, 但找不到 dvdauthor。Linux: sudo apt install dvdauthor;Cygwin/MSYS2 官方源没有这个包, 需自行编译后放进 /usr/bin 或 /mingw64/bin"
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
        d="$(fp_run -v error -show_entries format=duration -of csv=p=0 "$v" 2>/dev/null |
            tr -d '\r' |
            awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }' | tail -1)"
        [ -n "$d" ] || d=0
        total="$(awk -v a="$total" -v b="$d" 'BEGIN{printf "%.3f", a + b}')"
    done
    printf '%.3f\n' "$total"
}

detect_scenes() {
    local off=0 v dur
    for v in "$@"; do
        ff_run -hide_banner -v info -i "$v" \
            -filter:v "select='gt(scene,$SCENE_TH)',showinfo" -f null - 2>&1 |
            awk -v o="$off" '/pts_time:/{
                for (i = 1; i <= NF; i++)
                    if ($i ~ /^pts_time:/) { t = substr($i, 10) + 0; if (t > 1) printf "%.3f\n", t + o }
            }'
        dur="$(fp_run -v error -show_entries format=duration -of csv=p=0 "$v" 2>/dev/null |
            tr -d '\r' |
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
    local g="$1" dest xml menu="" w h acodec fmt total got f n i attempt sz
    local old_sz=0 new_sz=0
    local -a tvobs vdur scenes CH_ATTR
    while IFS= read -r f; do [ -n "$f" ] && tvobs+=("$f"); done < <(group_vobs "$g")
    [ "${#tvobs[@]}" -gt 0 ] || { warn "VTS_$g 没有正片 VOB, 跳过"; return 1; }

    [ "$KEEPMENU" = "1" ] && [ -f "$VTS/VTS_${g}_0.VOB" ] && menu="$VTS/VTS_${g}_0.VOB"

    w="$(fp_run -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "${tvobs[0]}" 2>/dev/null | tr -d '\r' | awk -F, '$1 ~ /^[0-9]+$/ { print $1 }' | tail -1)"
    h="$(fp_run -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "${tvobs[0]}" 2>/dev/null | tr -d '\r' | awk -F, '$1 ~ /^[0-9]+$/ { print $1 }' | tail -1)"
    acodec="$(fp_run -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "${tvobs[0]}" 2>/dev/null | tr -d '\r' | awk -F, '$1 ~ /^[a-z0-9_]+$/ { print $1 }' | tail -1)"

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
    _ac_txt="${acodec:-}"; [ -n "$_ac_txt" ] || _ac_txt="未知"
    info "VTS_$g 重建   : ${w:-?}x${h:-?} $VIDEO_FORMAT 音频 ${_ac_txt}"

    # 各 VOB 时长: 既是章节切片的依据, 也是"有没有被 dvdauthor 截断"的基准
    i=0
    while [ "$i" -lt "${#tvobs[@]}" ]; do
        vdur+=("$(fp_run -v error -show_entries format=duration -of csv=p=0 "${tvobs[$i]}" 2>/dev/null |
            tr -d '\r' |
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

    # 该组 VOB 现在总共有多少字节 —— 重建完再量一次, 用来判断扇区布局变没变
    # (变了就必须重生成 VMG, 没变就该保留原 VMG 以保住菜单; 见头部注释 ⑦)
    for f in "$VTS"/VTS_${g}_*.VOB; do
        [ -f "$f" ] || continue
        sz="$(stat -c%s "$f" 2>/dev/null)"
        case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
        old_sz=$(( old_sz + sz ))
    done

    # 依次试: 完整章节 -> 每个 VOB 只写 0(保时长, 丢章节) -> 完全不给章节属性。
    # 每试一次都复核时长: dvdauthor 截断章节时不报错, 只把时长悄悄写短。
    #
    # dvdauthor 的 XML 还有两个踩过的坑(2026-09-30 实测):
    #   * dest 要传 **DVD 根**, 不是 VIDEO_TS 目录 —— 写成 X/VIDEO_TS 会造出
    #     X/VIDEO_TS/VIDEO_TS, 白跑一趟;
    #   * 下面那个空 <vmgm /> 之所以能通过, 是因为本脚本 export 了 VIDEO_FORMAT
    #     (见 rebuild_group 里那次 export 与 ensure_format)。去掉它、又不在 XML 里
    #     写 <vmgm><menus><video format="pal"/></menus></vmgm>, 到 "creating table
    #     of contents" 那一步就会报 "no video format specified for VMGM"。
    for attempt in full zero none; do
        build_ch_attr "$attempt"
        rm -rf "$dest"; mkdir -p "$dest" || return 1
        {
            printf '<dvdauthor dest="%s">\n' "$(xml_attr "$(da_path "$dest")")"
            printf '  <vmgm />\n'
            printf '  <titleset>\n'
            if [ -n "$menu" ]; then
                printf '    <menus>\n      <video format="%s" />\n' "$fmt"
                printf '      <pgc><vob file="%s" /></pgc>\n' "$(xml_attr "$(da_path "$menu")")"
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
                    printf '        <vob file="%s" />\n' "$(xml_attr "$(da_path "${tvobs[$i]}")")"
                else
                    printf '        <vob file="%s" chapters="%s" />\n' "$(xml_attr "$(da_path "${tvobs[$i]}")")" "${CH_ATTR[$i]}"
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
        got="$(fp_run -v error -f dvdvideo -title 1 -show_entries format=duration \
              -of csv=p=0 "$dest" 2>/dev/null | tr -d '\r' | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1 }' | tail -1)"
        if [ -z "$got" ] || awk -v a="$got" -v b="$total" 'BEGIN{exit !(a >= b - 2)}'; then
            [ "$attempt" = "full" ] && info "VTS_$g 时长   : ${got:-?}s(基准 $(printf '%.0f' "$total")s) —— 章节保住了"
            [ "$attempt" = "zero" ] && warn "VTS_$g: 带章节会把时长写短 —— 已退回只保留首章, 章节没保住"
            [ "$attempt" = "none" ] && warn "VTS_$g: 连首章都保不住 —— 已退回完全不加章节"
            break
        fi
        warn "VTS_$g: $attempt 这一版时长只有 ${got}s, 少于应有的 $(printf '%.0f' "$total")s —— dvdauthor 把 PGC 截断了, 换一种写法重试"
    done

    # 只搬 VTS_*: dest 里那份 VIDEO_TS.IFO 是 dvdauthor 顺手生成的空壳 VMG,
    # 真 VMG 由后面统一的 dvdauthor -T 产出, 别拿它覆盖。
    #
    # **编号必须改写, 不能直接按原名写回**: 这条 XML 里只有一个 titleset,
    # dvdauthor 给它固定编号 01 —— 重建 VTS_06 时吐出来的照样叫 VTS_01_*。
    # 照原名写回, 覆盖掉的是**完好的 VTS_01**, 而待修的那一组一个字节都没修上
    # (2026-10-01 端到端实测: VTS_01_1.VOB 857MB 被 158MB 的重建结果顶掉,
    # VTS_06_0.IFO 仍是整片 0x00)。所以写回前先把 01 换成目标组号。
    for f in "$dest"/VIDEO_TS/VTS_01_*; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"              # VTS_01_1.VOB
        n="VTS_${g}_${base#VTS_01_}"         # -> VTS_06_1.VOB
        [ -e "$VTS/$n" ] && mv_away "$VTS/$n"
        cp "$f" "$VTS/$n" || return 1
    done
    info "VTS_$g 重建   : 完成($(ls "$dest"/VIDEO_TS 2>/dev/null | wc -l | tr -d ' ') 个文件写回)"

    # 布局变没变: dvdauthor 会把 VOB 重写一遍(内容等价, 尾部 padding 可能短一点)。
    # 总字节数变了 -> 原 VMG 里那张扇区表就过时了, 必须重生成(否则正片只读到一半);
    # 没变 -> 原 VMG 依然准确, 留着它才能保住菜单(见头部注释 ⑦)。
    # 量的是**写回之后**的 $VTS —— dest 里那些还叫 VTS_01_*, 按组号去 glob 只会量到 0
    for f in "$VTS"/VTS_${g}_*.VOB; do
        [ -f "$f" ] || continue
        sz="$(stat -c%s "$f" 2>/dev/null)"
        case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
        new_sz=$(( new_sz + sz ))
    done
    if [ "$old_sz" != "$new_sz" ]; then
        LAYOUT_CHANGED=1
        info "VTS_$g 布局   : VOB 总字节 $old_sz -> $new_sz —— 变了, 后面要重生成 VMG"
    else
        info "VTS_$g 布局   : VOB 总字节不变($new_sz) —— 原 VMG 的扇区表仍有效, 菜单可保"
    fi

    # 没要菜单的原 _0.VOB 已不在新 IFO 的引用里 —— 留着会让 mkisofs -dvd-video 失败
    # (实测: "Either VIDEO_TS.IFO or VIDEO_TS.VOB is not of correct size")
    if [ -z "$menu" ] && [ -f "$VTS/VTS_${g}_0.VOB" ] && ! [ -f "$dest/VIDEO_TS/VTS_01_0.VOB" ]; then
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
            h="$(fp_run -v error -select_streams v:0 -show_entries stream=height \
                -of csv=p=0 "$v" 2>/dev/null | tr -d '\r' | awk -F, '$1 ~ /^[0-9]+$/ { print $1 }' | tail -1)"
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
    # -o 也走 da_path: 原生 dvdauthor 吃不下 POSIX 路径(与上面 XML 里的 dest 同理)
    dvdauthor -T -o "$(da_path "$DVD_ROOT")" >"$WORK/vmg.log" 2>&1 || { warn "重生成 VIDEO_TS.IFO 失败, 日志: $WORK/vmg.log"; return 1; }
    [ -f "$VTS/VIDEO_TS.IFO" ] || return 1
    return 0
}

# dvdauthor -T 造出来的 VMG 不带菜单: 原来的 VIDEO_TS.VOB(真菜单视频)会变成没人
# 引用的孤儿文件 —— 与 VTS_xx_0.VOB 同理, 留着会让 mkisofs -dvd-video 失败:
#   "Either VIDEO_TS.IFO or VIDEO_TS.VOB is not of correct size"
# 默认只警告(菜单视频是原盘资产, 不替用户删); 要自动挪走就加 MOVE_ORPHAN_VMG=1。
# 真想保住菜单, 正路是别走到这一步 —— 见上面 NEED_VMG 那段判断。
orphan_vmg_menu() {
    [ -f "$VTS/VIDEO_TS.VOB" ] || return 0
    if [ "$MOVE_ORPHAN_VMG" = "1" ]; then
        mv_away "$VTS/VIDEO_TS.VOB" &&
            info "VIDEO_TS.VOB 已挪到备份目录 —— 重生成的 VMG 不含菜单, 留着会让 mkisofs -dvd-video 失败"
    else
        warn "重生成的 VIDEO_TS.IFO 不含菜单, 而 VIDEO_TS.VOB(原菜单视频)还在 —— 它现在是孤儿文件, mkisofs -dvd-video 会因为它失败"
        warn "  要菜单: 备份目录里有原来的 VIDEO_TS.IFO($BACKUP)"
        warn "  只要 ISO: 加 MOVE_ORPHAN_VMG=1 重跑, 把它挪到备份目录"
    fi
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
    # 重不重生成 VMG, 见头部注释 ⑦: 两次实测的结论看着矛盾, 其实取决于 VOB 的
    # 扇区布局变没变 —— 变了不重生成, 正片只读一半(1682s -> 1119s); 没变却重生成,
    # 反而把原菜单弄丢(dvdauthor -T 出来的 VMG 没有菜单)。这里自动判断,
    # 另给 KEEPVMG / REGENVMG 手工指定。
    if [ "$REGENVMG" = "1" ]; then
        do_regen=1; why="REGENVMG=1 强制重生成"
    elif [ "$VMG_BAD" = "1" ]; then
        do_regen=1; why="原 VIDEO_TS.IFO/BUP 缺失或无效 —— 不重生成就没有全盘目录"
    elif [ "$KEEPVMG" = "1" ]; then
        do_regen=0; why="KEEPVMG=1, 且原 VIDEO_TS.IFO 有效"
    elif [ "$LAYOUT_CHANGED" = "1" ]; then
        do_regen=1; why="重建改动了 VOB 的扇区布局, 旧 VMG 那张扇区表已失效(不重生成正片会只读到一半)"
    else
        do_regen=0; why="原 VIDEO_TS.IFO 有效, 且 VOB 布局没变 —— 保留原菜单"
    fi
    if [ "$do_regen" = "1" ]; then
        info "重生成 VMG  : $why"
        if regen_vmg; then
            info "已重生成 VIDEO_TS.IFO / VIDEO_TS.BUP(dvdauthor -T)"
            orphan_vmg_menu
        else
            RC=1
        fi
    else
        info "保留原 VMG  : $why —— 菜单不受影响"
    fi
fi

[ -d "$BACKUP" ] && info "被替换的原件: $BACKUP"
[ "$KEEP_WORK" = "1" ] && info "工作目录保留: $WORK"

if [ "$RC" -ne 0 ]; then
    die "有项目没修好(见上面的警告)"
fi

# 修完再自检一遍 0x0C: 现在对不上, 打包时 -dvd-video 就会卡在这一组
sector_report || warn "上面这些 0x0C 与实际区段对不上 —— genisoimage -dvd-video 会因此失败"

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
