#!/bin/bash
# =========================================================================
#  tools/dvd_restore.sh  -  解压出来的 DVD 目录 -> 可刻录 / 可播放的 DVD-Video ISO
#
#  用法:
#    ./tools/dvd_restore.sh <源目录> [输出ISO]
#      源目录   含 VIDEO_TS 的 DVD 根目录(通常还带一个空的 AUDIO_TS);
#               也可以直接指到 VIDEO_TS 目录本身, 两种都认
#      输出ISO  默认 <源目录名>.iso, 写在源目录**旁边**。
#               故意不放进源目录: 见下面第 1 条踩坑。
#
#  开关(环境变量, 写在命令之前):
#    VOLID=NAME      卷标。默认取源目录名, 只保留 [A-Za-z0-9_], 截到 32 字符
#    BURN=/dev/sr0   打好 ISO 后立刻刻录。默认不刻录, 只出 ISO
#    FIX=1           缺失/不等长的 *.BUP 用同名 *.IFO 覆盖(DVD 规范: 二者应逐字节相同)。
#                    反向(缺 IFO)与整组 IFO/BUP 全丢请改用 tools/dvd_repair.sh
#    DEEP=1          校验阶段把 ISO 解开逐字节比对(最稳, 但要额外读写一份 1.x GB)
#    CHECK=0         跳过结构检查(不建议; 检查项见下)
#
#  为什么不能"打个 iso 就完事"——四条实测踩坑:
#    1) 输出 ISO 不能落在源目录里面。mkisofs 是先扫目录树再造镜像, ISO 正在被写、
#       目录树正在被扫, 镜像里会多出一份数百 MB~(半个自己)的垃圾, 严重的直接失败。
#       本脚本检测到输出路径在源目录内就直接退出, 不做"静默加 -x 排除"这种自作聪明的事。
#    2) 裸 mkisofs **不加 -dvd-video** 出来的镜像文件顺序是目录序(实测同一份源):
#           无 -dvd-video: BUP(26) IFO(32) VOB(38) BUP(58) IFO(71) VOB(84) VOB(524371)
#           有 -dvd-video: IFO(279) VOB(285) BUP(305) IFO(311) VOB(324) VOB(524611) BUP(619264)
#       括号里是起始 LBA。-dvd-video 会排序 + 在文件之间补 padding, 家用 DVD 机靠
#       这个布局做连续读取; 顺序不对的表现是挑盘、跳帧、读到一半卡住 —— 而 ISO 在电脑上
#       看着完全正常, 很容易误判成"盘刻坏了"。
#    3) 文件名必须全大写。mkisofs 手册写明 -dvd-video 的排序只在大写名下生效;
#       小写文件名不报错, 只是悄悄不排序, 于是掉进第 2 条。
#    4) -dvd-video 隐含 UDF(实测产出镜像: 扇区 18=BEA01, 19=NSR02, 20=TEA01),
#       所以不要再叠 -J / -R: DVD 机不认这些扩展, 白白增加镜像复杂度。
#
#  依赖:
#    必需  mkisofs / genisoimage(带 -dvd-video)。Debian/Ubuntu: apt install genisoimage
#    校验  xorriso 或 7z(二选一即可, 都没有就跳过清单比对)
#    刻录  growisofs(优先)或 wodim, 仅 BURN= 时需要
#
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[dvd_restore]"
info() { printf '%s %s\n' "$TAG" "$*"; }
warn() { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()  { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()  { err "$*"; exit 1; }

DVD5_SECTORS=2298496   # 单层 4.7 GB: 2298496 x 2048 = 4707319808 字节
DVD9_SECTORS=4173824   # 双层 8.5 GB: 4173824 x 2048 = 8548618240 字节
MAX_FILE=$((1024 * 1024 * 1024))   # DVD-Video 单文件上限 1 GiB

usage() {
    awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"
    exit "${1:-0}"
}

# 字节数 -> "1234 MB" 这种人能读的形式
human_size() {
    awk -v b="$1" 'BEGIN{
        if (b >= 1073741824) printf "%.2f GiB\n", b/1073741824;
        else if (b >= 1048576) printf "%.1f MiB\n", b/1048576;
        else printf "%d B\n", b;
    }'
}

# 退出时收尾: 暂存树(仅 VIDEO_TS 直传模式)与校验临时文件
STAGE=""
exp_file=""; act_file=""
cleanup() {
    [ -n "$STAGE" ]     && rm -rf "$STAGE"
    [ -n "$exp_file" ]  && rm -f "$exp_file" "$act_file" "${exp_file}.s" "${act_file}.s"
}
trap cleanup EXIT

# =========================================================================
#  参数与路径
# =========================================================================
SRC_TOP="${1:-}"
OUT="${2:-}"

[ -n "$SRC_TOP" ] || usage 1
case "$SRC_TOP" in
    -h|--help) usage 0 ;;
esac
[ -d "$SRC_TOP" ] || die "源目录不存在: $SRC_TOP"

# 去掉结尾的斜杠, 否则 basename 拿到空串
SRC_TOP="${SRC_TOP%/}"
[ -n "$SRC_TOP" ] || SRC_TOP="/"

if [ -d "$SRC_TOP/VIDEO_TS" ]; then
    DVD_ROOT="$SRC_TOP"
    VTS="$SRC_TOP/VIDEO_TS"
    MODE=root          # 用户给的是 DVD 根: 整个根打进去(根目录里别的东西也保留)
elif [ "$(basename "$SRC_TOP")" = "VIDEO_TS" ]; then
    DVD_ROOT="$(dirname "$SRC_TOP")"
    VTS="$SRC_TOP"
    MODE=stage         # 用户直接给了 VIDEO_TS: 造一个只含 VIDEO_TS/AUDIO_TS 的暂存树再打,
                       # 免得把同级的无关文件(解压残留、样本图、md5 之类)一起卷进来。
                       # 试过 -graft-points "/VIDEO_TS=<路径>", genisoimage 认不出来:
                       #   "Could not find correct 'VIDEO_TS' directory" —— 它的 -dvd-video
                       #   是在**源路径**里找名为 VIDEO_TS 的目录, 不是看嫁接后的名字。
else
    die "源目录里没有 VIDEO_TS, 也不叫 VIDEO_TS: $SRC_TOP"
fi

VTS="$(cd "$VTS" && pwd)"
DVD_ROOT="$(cd "$DVD_ROOT" && pwd)"
AUDIO_TS="$DVD_ROOT/AUDIO_TS"

# 默认输出: 源目录旁边。放源目录里面会掉进上面第 1 条踩坑。
# 名字取 DVD_ROOT(而不是用户传进来的那个目录), 这样直接传 VIDEO_TS 时不会得到
# "VIDEO_TS.iso" 这种倒霉名字, 卷标也不会变成 VIDEO_TS。
BASE_NAME="$(basename "$DVD_ROOT")"
[ -n "$BASE_NAME" ] && [ "$BASE_NAME" != "/" ] || BASE_NAME="DVDVIDEO"
OUT="${OUT:-$(dirname "$DVD_ROOT")/${BASE_NAME}.iso}"

OUT="$(realpath -m "$OUT")"
# 输出落在 DVD_ROOT 里(含 VIDEO_TS 里)一律拒绝
case "$OUT" in
    "$DVD_ROOT"/*|"$DVD_ROOT") die "输出 ISO 不能放在源目录里面($OUT 在 $DVD_ROOT 下), 否则镜像会把正在写的 ISO 自己也扫进去。换一个路径, 例如 $(dirname "$DVD_ROOT")/${BASE_NAME}.iso" ;;
esac

# 卷标: ISO9660 卷标只允许 [A-Za-z0-9_], 且不超过 32 字符
VOLID="${VOLID:-$BASE_NAME}"
VOLID="$(printf '%s' "$VOLID" | tr -cd 'A-Za-z0-9_' | cut -c1-32)"
[ -n "$VOLID" ] || VOLID="DVDVIDEO"

OUT_DIR="$(dirname "$OUT")"
[ -d "$OUT_DIR" ] || mkdir -p "$OUT_DIR" || die "建不了输出目录: $OUT_DIR"

echo ============================================================
info "源 DVD 根   : $DVD_ROOT"
info "VIDEO_TS    : $VTS"
info "输出 ISO    : $OUT"
info "卷标        : $VOLID"
echo ============================================================

# =========================================================================
#  依赖
# =========================================================================
# 挑打包器: 不能盲选 PATH 上第一个 —— Cygwin 下那常常是 WinCDEmu 的原生
# mkisofs.exe, 它吃不下 POSIX 路径(见 lib/common.sh 的 pick_mkisofs)
declare -F pick_mkisofs >/dev/null 2>&1 || die "lib/common.sh 未加载(pick_mkisofs 缺失) —— 请在完整仓库里运行本脚本"
MKISOFS="$(pick_mkisofs)" || die "找不到 mkisofs / genisoimage。安装: sudo apt install genisoimage"

HAVE_XORRISO=0; command -v xorriso >/dev/null 2>&1 && HAVE_XORRISO=1
HAVE_7Z=0;      command -v 7z      >/dev/null 2>&1 && HAVE_7Z=1
[ "$HAVE_XORRISO" = 1 ] || [ "$HAVE_7Z" = 1 ] || warn "xorriso 与 7z 都没有 —— 打包后只能做大小检查, 跳过文件清单比对"

# =========================================================================
#  结构检查
# =========================================================================
if [ "${CHECK:-1}" != "0" ]; then
    info "检查源目录结构 ..."

    # ① 必备文件
    if [ ! -f "$VTS/VIDEO_TS.IFO" ]; then
        # 大小写不敏感地找一下: 名字对、只是全小写, 是最常见的一种"看不出来"的错
        for c in "$VTS"/[Vv][Ii][Dd][Ee][Oo]_[Tt][Ss].[Ii][Ff][Oo]; do
            [ -f "$c" ] && die "找到的是 $(basename "$c") 而不是 VIDEO_TS.IFO —— 请改成全大写再跑(mkisofs -dvd-video 只认大写文件名)"
        done
        die "缺少 VIDEO_TS.IFO —— 没有它就不是 DVD-Video。整个 IFO/BUP 没了要用 dvdauthor 重建, 本脚本不做这件事, 用 tools/dvd_repair.sh"
    fi
    [ -f "$VTS/VIDEO_TS.BUP" ] || warn "缺少 VIDEO_TS.BUP(菜单 IFO 的备份)。FIX=1 可用 IFO 补一个"

    vts_ifo=0; vob=0
    for f in "$VTS"/VTS_*_0.IFO; do [ -f "$f" ] && vts_ifo=$((vts_ifo + 1)); done
    for f in "$VTS"/*.VOB;       do [ -f "$f" ] && vob=$((vob + 1)); done
    [ "$vts_ifo" -gt 0 ] || die "VIDEO_TS 里没有任何 VTS_*_0.IFO"
    [ "$vob"      -gt 0 ] || die "VIDEO_TS 里没有任何 .VOB"
    info "标题集(IFO) : $vts_ifo 个, VOB: $vob 个"

    # ①b 正片 VOB 的编号必须是连续的 _1.._N: 中间缺一个就是那一整段音视频真没了,
    #     补不出来(只能重新抓), 但至少要在打包前说出来 —— 否则镜像看着正常, 播到
    #     缺的那段才断。完整体检用 tools/dvd_repair.sh
    gap_n=0
    for g in $(for f in "$VTS"/VTS_*_*.VOB; do
                   [ -f "$f" ] || continue
                   n="$(basename "$f")"; s="${n#VTS_}"; printf '%s\n' "${s%%_*}"
               done | sort -nu); do
        max=0
        for f in "$VTS"/VTS_${g}_*.VOB; do
            [ -f "$f" ] || continue
            n="$(basename "$f")"; s="${n#VTS_}"; rest="${s#*_}"; idx="${rest%%.*}"
            case "$idx" in 0|*[!0-9]*) continue ;; esac
            [ "$idx" -gt "$max" ] && max="$idx"
        done
        i=1
        while [ "$i" -le "$max" ]; do
            if [ ! -f "$VTS/VTS_${g}_${i}.VOB" ]; then
                warn "缺 VTS_${g}_${i}.VOB(编号断号) —— 这一段的音视频真没了, 补不出来"
                gap_n=$((gap_n + 1))
            fi
            i=$((i + 1))
        done
    done

    # ② 文件名大小写 + 扇区对齐 + 单文件上限 + 目录里的多余文件
    bad_case=0; bad_align=0; junk=""
    total=0
    for f in "$VTS"/*; do
        [ -f "$f" ] || continue
        n="$(basename "$f")"
        sz=$(stat -c%s "$f")
        total=$((total + sz))

        # 只认 VIDEO_TS.* / VTS_xx_y.{IFO,BUP,VOB}; 其余算夹带物 —— 解压盘里常混进
        # readme / nfo / 样本图, 它们本来就不该在 VIDEO_TS 里, 只提示、不拿 DVD 的规矩卡它们
        # (否则一个 readme.txt 就能把整次打包拦下来, 而它根本不影响播放)
        case "$n" in
            VIDEO_TS.IFO|VIDEO_TS.BUP|VIDEO_TS.VOB) ;;
            VTS_??_?.IFO|VTS_??_?.BUP|VTS_??_?.VOB) ;;
            VTS_?_?.IFO|VTS_?_?.BUP|VTS_?_?.VOB)    ;;
            *) junk="$junk $n"; continue ;;
        esac

        # 出现小写字母 -> -dvd-video 不排序(踩坑第 3 条)
        case "$n" in
            *[a-z]*) bad_case=$((bad_case + 1)); printf '   小写文件名: %s\n' "$n" >&2 ;;
        esac

        # DVD-Video 的文件都是 2048 字节的整数倍; 不是整数倍基本意味着这个 VOB 是断的
        if [ $((sz % 2048)) -ne 0 ]; then
            bad_align=$((bad_align + 1))
            printf '   未按 2048 对齐: %s (%d 字节)\n' "$n" "$sz" >&2
        fi

        if [ "$sz" -gt "$MAX_FILE" ]; then
            die "$n 有 $(human_size "$sz"), 超过 DVD-Video 单文件上限 1 GiB —— 这种盘刻出来也读不了, 需要先重新分片"
        fi
    done
    [ "$bad_case"  -eq 0 ] || die "VIDEO_TS 里有 $bad_case 个含小写字母的文件名。mkisofs 的 -dvd-video 排序只认全大写, 小写名会被悄悄跳过排序(见头部第 3 条)。请先改名再跑"
    [ "$bad_align" -eq 0 ] || die "VIDEO_TS 里有 $bad_align 个文件不是 2048 字节整数倍 —— 多半是 VOB 抓坏了/传输中断。确实要硬打就 CHECK=0"
    [ -z "$junk" ] || warn "VIDEO_TS 里有非 DVD-Video 标准文件:$junk —— 会被一起打进镜像(DVD 机一般忽略, 但严格来说不合规)"

    # ③ IFO / BUP 成对: DVD 规范里 BUP 就是 IFO 的逐字节备份, 少了或不等长都是坏盘征兆
    for ifo in "$VTS"/VIDEO_TS.IFO "$VTS"/VTS_*_0.IFO; do
        [ -f "$ifo" ] || continue
        n="$(basename "$ifo")"
        bup="$VTS/${n%.IFO}.BUP"
        if [ ! -f "$bup" ]; then
            if [ "${FIX:-0}" = "1" ]; then
                cp -f "$ifo" "$bup" && info "FIX: 已用 $n 生成 ${n%.IFO}.BUP"
            else
                warn "缺少 ${n%.IFO}.BUP(IFO 的备份)。FIX=1 可用 IFO 补一个"
            fi
            continue
        fi
        if [ "$(stat -c%s "$bup")" -ne "$(stat -c%s "$ifo")" ]; then
            if [ "${FIX:-0}" = "1" ]; then
                cp -f "$ifo" "$bup" && info "FIX: ${n%.IFO}.BUP 已用 $n 覆盖"
            else
                warn "${n%.IFO}.BUP 与 $n 大小不一致(DVD 规范要求逐字节相同)。FIX=1 可用 IFO 覆盖"
            fi
        fi
    done
    # 反向: 有 BUP 却没有 IFO —— 这也是能补的, 不是只能报。BUP 就是 IFO 的逐字节备份
    #   (实测 DVD001(Canndy) 的 3 对 IFO/BUP 的 md5 完全相同), 反向拷贝同样成立。
    #   别被"ffprobe 照样读得出 title"骗了: 那是 libdvdread 会自动退回 BUP, 硬件 DVD 机
    #   和 mkisofs -dvd-video 都没这待遇, 后者直接 "Failed to open VTS info" 打包失败。
    #   本脚本只做检查与打包, 补齐统一交给 tools/dvd_repair.sh(它还会先核对本盘其余
    #   IFO/BUP 对是否真的一致, 不一致的盘不擅自补)。
    for bup in "$VTS"/*.BUP; do
        [ -f "$bup" ] || continue
        n="$(basename "$bup")"
        [ -f "$VTS/${n%.BUP}.IFO" ] || warn "$n 没有对应的 ${n%.BUP}.IFO —— 用 tools/dvd_repair.sh 可以反过来用 BUP 补齐"
    done

    # ④ AUDIO_TS: DVD-Video 规范要求存在, 空目录即可
    if [ ! -d "$AUDIO_TS" ]; then
        if mkdir -p "$AUDIO_TS" 2>/dev/null; then
            info "已补建空的 AUDIO_TS(DVD-Video 规范要求)"
        else
            warn "没有 AUDIO_TS 目录且建不出来(源目录不可写)。多数 DVD 机不在意, 严格规范需要它"
        fi
    fi

    # ⑤ DVD 根里的多余内容: root 模式会把整个根打进镜像, 先说一声
    #    JACKET_P / OpenDVD 是"标准件", 不算夹带: JACKET_P 是 DVD-Video 规范里的封面图
    #    目录(实测这批盘 3 张都带), OpenDVD 是刻录软件附的 PC 播放目录, 两者都该留着。
    if [ "$MODE" = "root" ]; then
        extra=""
        for f in "$DVD_ROOT"/*; do
            [ -e "$f" ] || continue
            n="$(basename "$f")"
            case "$n" in
                VIDEO_TS|AUDIO_TS|JACKET_P|OpenDVD) ;;
                *) extra="$extra $n" ;;
            esac
        done
        [ -z "$extra" ] || warn "DVD 根里还有:$extra —— 会一起进镜像(只想打包 VIDEO_TS 就把 VIDEO_TS 目录直接当源传进来)"
    fi

    # ⑥ 容量: 按扇区算, 目录本身也占一点, 这里只做量级判断
    sectors=$(( (total + 2047) / 2048 ))
    info "内容合计    : $(human_size "$total") ($sectors 扇区)"
    if [ "$sectors" -gt "$DVD9_SECTORS" ]; then
        warn "超过 DVD-9 双层容量($(human_size $((DVD9_SECTORS * 2048)))) —— 刻不进 DVD, 只能当 ISO 用播放器播"
    elif [ "$sectors" -gt "$DVD5_SECTORS" ]; then
        warn "超过 DVD-5 单层容量($(human_size $((DVD5_SECTORS * 2048)))) —— 需要 DVD-9 双层空白盘"
    else
        info "容量        : 单层 DVD-5 装得下"
    fi
    echo ============================================================
fi

# =========================================================================
#  打包
# =========================================================================
if [ "$MODE" = "stage" ]; then
    # 暂存树放在源目录旁边(同一文件系统 -> 硬链接一定成功, 不复制 1.x GB 的数据)
    STAGE="$(dirname "$VTS")/.dvd_restore_stage"
    rm -rf "$STAGE"
    mkdir -p "$STAGE/VIDEO_TS" || die "建不了暂存目录: $STAGE"
    for f in "$VTS"/*; do
        [ -f "$f" ] || continue
        n="$(basename "$f")"
        ln "$f" "$STAGE/VIDEO_TS/$n" 2>/dev/null || cp "$f" "$STAGE/VIDEO_TS/$n" || die "暂存不了: $f"
    done
    [ -d "$AUDIO_TS" ] && mkdir -p "$STAGE/AUDIO_TS"
    SRC_DIR="$STAGE"
    info "暂存树      : $STAGE/VIDEO_TS (硬链接, 不额外占空间)"
else
    SRC_DIR="$DVD_ROOT"
fi

info "开始打包($MKISOFS -dvd-video) ..."
# 只有「Cygwin + 原生 exe」这一档才把路径换成 X:/... 混合写法, 其余原样
"$MKISOFS" -dvd-video -V "$VOLID" -o "$(mkisofs_path "$OUT")" "$(mkisofs_path "$SRC_DIR")"
rc=$?
[ "$rc" -eq 0 ] || die "打包失败(rc=$rc)"

iso_sz=$(stat -c%s "$OUT")
info "ISO 已生成  : $OUT ($(human_size "$iso_sz"))"

# =========================================================================
#  校验
# =========================================================================
echo ============================================================
info "校验 ..."

# ① UDF 卷识别序列: DVD-Video 必须有。实测这份镜像: 扇区 16=ISO9660 PVD, 17=终止符,
#    18=BEA01, 19=NSR02, 20=TEA01 —— 所以取 16~23 号扇区(不能只取 4 个, 会漏掉 TEA01)
if command -v dd >/dev/null 2>&1; then
    vrs="$(dd if="$OUT" bs=2048 skip=16 count=8 2>/dev/null | tr -cd '[:print:]')"
    case "$vrs" in
        *BEA01*TEA01*) info "UDF 卷识别序列: 存在(BEA01 ... TEA01)" ;;
        *) warn "没找到 UDF 卷识别序列 —— 这台机器上的 $MKISOFS 可能没按 DVD-Video 产出 UDF, 换 genisoimage/mkisofs 再试" ;;
    esac
fi

# ② 文件清单与大小逐一比对
iso_list() {
    local iso="$1"
    if [ "$HAVE_XORRISO" = 1 ]; then
        xorriso -indev "$iso" -find / -type f -exec lsdl -- 2>/dev/null |
            awk '{ p=$NF; gsub(/^'"'"'|'"'"'$/, "", p); print $5, p }'
    elif [ "$HAVE_7Z" = 1 ]; then
        7z l -slt "$iso" 2>/dev/null |
            awk '/^Path = /{p=substr($0,8)} /^Size = /{s=substr($0,8); if (s != "" && p != "") print s, p}'
    else
        return 1
    fi
}

if [ "$HAVE_XORRISO" = 1 ] || [ "$HAVE_7Z" = 1 ]; then
    exp_file="$(mktemp)"; act_file="$(mktemp)"
    : > "$exp_file"
    for f in "$VTS"/*; do
        [ -f "$f" ] || continue
        printf '%s /VIDEO_TS/%s\n' "$(stat -c%s "$f")" "$(basename "$f")" >> "$exp_file"
    done
    # xorriso 给的路径带前导 /, 7z 不带 —— 统一成 "/VIDEO_TS/..." 再比;
    # 只比 VIDEO_TS 里的东西(DVD 根上如果有别的文件, 本来就不在比对的范围内)
    iso_list "$OUT" | awk '{ p=$2; sub(/^\//, "", p); print $1, "/" p }' | grep ' /VIDEO_TS/' > "$act_file"

    # 整行 + LC_ALL=C 排序再 diff。别用 `sort -k2` + comm: -k2 排出来的顺序不是整行顺序,
    # comm 会报 "file 1 is not in sorted order" 并把每一行都算成不一致(实测踩过)。
    LC_ALL=C sort "$exp_file" > "${exp_file}.s"
    LC_ALL=C sort "$act_file" > "${act_file}.s"
    exp_n=$(wc -l < "${exp_file}.s" | tr -d ' ')
    act_n=$(wc -l < "${act_file}.s" | tr -d ' ')
    if diff -q "${exp_file}.s" "${act_file}.s" >/dev/null 2>&1; then
        info "文件清单    : 一致($exp_n 个, 大小逐个对得上)"
    else
        warn "文件清单不一致: 源 $exp_n 个 / 镜像 $act_n 个(VIDEO_TS 里的夹带文件名会被 mkisofs 转成大写, 这种差异不影响播放)"
        diff "${exp_file}.s" "${act_file}.s" | head -10 >&2
    fi
fi

# ③ DEEP: 解开镜像逐字节比对源目录
if [ "${DEEP:-0}" = "1" ]; then
    tmp="$(mktemp -d)"
    if [ "$HAVE_7Z" = 1 ]; then
        7z x -y -o"$tmp" "$OUT" >/dev/null 2>&1 && \
            diff -r --brief "$VTS" "$tmp/VIDEO_TS" && info "DEEP 比对    : 逐字节一致"
    elif [ "$HAVE_XORRISO" = 1 ]; then
        xorriso -osirrox on -indev "$OUT" -extract /VIDEO_TS "$tmp/VIDEO_TS" >/dev/null 2>&1 && \
            diff -r --brief "$VTS" "$tmp/VIDEO_TS" && info "DEEP 比对    : 逐字节一致"
    else
        warn "DEEP=1 需要 7z 或 xorriso, 两个都没有 —— 跳过"
    fi
    rm -rf "$tmp"
fi

# =========================================================================
#  刻录(可选)
# =========================================================================
if [ -n "${BURN:-}" ]; then
    echo ============================================================
    [ -e "$BURN" ] || die "刻录设备不存在: $BURN"
    info "刻录到 $BURN ..."
    if command -v growisofs >/dev/null 2>&1; then
        growisofs -dvd-compat -Z "$BURN=$OUT" || die "刻录失败(growisofs)"
    elif command -v wodim >/dev/null 2>&1; then
        wodim -v dev="$BURN" -dao "$OUT" || die "刻录失败(wodim)"
    else
        die "没有刻录工具(growisofs / wodim)。安装: sudo apt install dvd+rw-tools"
    fi
    info "刻录完成"
fi

echo ============================================================
info "完成: $OUT"
info "下一步: 直接刻盘(growisofs -dvd-compat -Z /dev/sr0=\"$OUT\") 或用播放器打开 ISO 验证菜单"
exit 0
