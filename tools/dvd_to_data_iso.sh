#!/bin/bash
# =========================================================================
#  tools/dvd_to_data_iso.sh  -  文件目录(通常是 HEVC 归档) -> UDF 数据 ISO
#
#  用法:
#    ./tools/dvd_to_data_iso.sh <目录|DVD源> [输出ISO]
#      目录    把里面的文件原样打成数据盘(典型: ffmpeg_dvd_hevc.sh 产出的 MKV)
#      DVD源   ISO 镜像 / 含 VIDEO_TS 的目录 / 光驱设备 —— 先压成 HEVC MKV 再打包
#      输出ISO 默认 <目录旁边>/<目录名>.iso
#
#  开关(环境变量):
#    ENCODE=auto|1|0  是否先压成 HEVC。auto(默认)看源: 是 DVD 就压, 普通目录不压
#    VENC=libx265     HEVC 编码器, 默认软编。有 N 卡想快就填 hevc_nvenc
#    HENC_MODE=ALL    传给 ffmpeg_dvd_hevc.sh 的 MODE: ALL=每条 title 都压(默认),
#                     AUTO=只压最长的那条, TITLE=配合第 3 个参数压指定那条
#    STAGE=<路径>     先压时 MKV 的落点, 默认 <源旁边>/HEVC_OUT
#    KEEP_STAGE=1     打包完保留那份 MKV, 默认跟着工作目录一起删
#    VOLID=NAME       卷标(只保留 [A-Za-z0-9_], 截到 32 字符)
#    CHECK=0          跳过源盘体检(不建议; 体检只在"DVD 目录 + 真的要读它"时做)
#    ALLOW_GAP=1      体检发现补不出来的缺失(VOB 断号)时不拦, 带着缺口继续。
#                     默认拦下并退出(与 dvd_restore.sh / dvd_shrink.sh 同义)
#
#  DVD 机读不了这种盘 —— 这是**数据盘**, 不是 DVD-Video:
#    * 里面是 mkv / mp4 之类的普通文件, 没有 VIDEO_TS, 没有 DVD 菜单;
#    * 能不能播取决于播放器: PC 随便播, 部分电视 / 蓝光机的 USB 或数据盘功能能读,
#      传统 DVD 机只会报"无碟"。
#    * 要的是"能在 DVD 机上放"就走 tools/dvd_restore.sh(原样) 或
#      tools/dvd_shrink.sh(重编码), 那两条路都是真 DVD-Video, 但只能用 MPEG-2。
#
#  为什么加 -udf:
#    ISO9660 单文件上限 2 GiB(Level 3 才放宽), 而 HEVC 归档经常是几个 GB;
#    UDF 桥同时给 Windows / macOS / Linux 都能读的目录, 搭配 -J -r 兼容性最好。
#    注意别加 -dvd-video: 那个选项要求源里有 VIDEO_TS, 且是给 DVD-Video 排序用的。
#
#  依赖: mkisofs / genisoimage; 校验用 xorriso 或 7z(都没有就跳过清单比对);
#        先压时还需要 ffmpeg(带 dvdvideo, 由 ffmpeg_dvd_hevc.sh 负责检查)
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

TAG="[dvd_dataiso]"
info()  { printf '%s %s\n' "$TAG" "$*"; }
warn()  { printf '\033[33m%s 警告: %s\033[0m\n' "$TAG" "$*" >&2; }
err()   { printf '\033[41;36m%s 错误: %s\033[0m\n' "$TAG" "$*" >&2; }
die()   { err "$*"; exit 1; }
usage() { awk 'NR>=3 && /^# =+$/ { exit } NR>=3 { sub(/^# ?/, ""); print }' "$0"; exit "${1:-0}"; }

human_size() {
    awk -v b="$1" 'BEGIN{
        if (b >= 1073741824) printf "%.2f GiB\n", b/1073741824;
        else if (b >= 1048576) printf "%.1f MiB\n", b/1048576;
        else printf "%d B\n", b;
    }'
}

# DVD-5 / DVD-9 参考容量(字节), 只用于给"这张盘塞不塞得下"的量级提示
DVD5=$((2298496 * 2048))
DVD9=$((4173824 * 2048))

# 挑一份"有 dvdvideo 解复用器 + 有指定编码器"的 ffmpeg。
# 逐个候选真跑一遍 -demuxers / -encoders, 而不是只问 command -v: PATH 上第一个
# 常常是缺能力的发行版构建(这台机器 /usr/bin/ffmpeg 就没编 dvdvideo)。
pick_ffmpeg() {
    local enc="$1" d c
    if [ -n "${FFMPEG:-}" ] && [ -x "${FFMPEG}" ]; then echo "$FFMPEG"; return 0; fi
    for c in $(IFS=:; for d in ${PATH:-/usr/bin}; do [ -n "$d" ] && echo "$d/ffmpeg"; done) \
             /opt/ffmpeg/*/bin/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg; do
        [ -x "$c" ] || continue
        "$c" -hide_banner -demuxers 2>/dev/null | awk '{ if ($1 == "D" && $2 == "dvdvideo") f = 1 } END{ exit !f }' || continue
        "$c" -hide_banner -encoders 2>/dev/null | awk -v e="$enc" '{ if ($2 == e) f = 1 } END{ exit !f }' || continue
        echo "$c"; return 0
    done
    return 1
}

SRC="${1:-}"
OUT="${2:-}"
[ -n "$SRC" ] || usage 1
case "$SRC" in -h|--help) usage 0 ;; esac
[ -e "$SRC" ] || die "源不存在: $SRC"

# 去掉结尾斜杠, 否则 basename 拿到空串
SRC="${SRC%/}"
[ -n "$SRC" ] || SRC="/"

# ---- 判断是不是 DVD 源(决定要不要先压一遍) ----
is_dvd=0
if [ -b "$SRC" ]; then
    is_dvd=1
elif [ -f "$SRC" ]; then
    case "$(printf '%s' "$SRC" | tr 'A-Z' 'a-z')" in
        *.iso) is_dvd=1 ;;
        *)     warn "$SRC 是普通文件, 当普通目录内容处理不了 —— 请传目录; 这里按非 DVD 处理, 稍后会因为不是目录而退出" ;;
    esac
elif [ -d "$SRC" ]; then
    [ -d "$SRC/VIDEO_TS" ] && is_dvd=1
    [ "$(basename "$SRC")" = "VIDEO_TS" ] && is_dvd=1
fi

ENCODE="${ENCODE:-auto}"
if [ "$ENCODE" = "auto" ]; then
    [ "$is_dvd" = 1 ] && ENCODE=1 || ENCODE=0
fi

# 工作目录: 只在"先压一遍"时才需要, 压完就删(除非 KEEP_STAGE=1)
STAGE=""
cleanup() {
    if [ -n "$STAGE" ] && [ "${KEEP_STAGE:-0}" != 1 ] && [ "$ENCODE" = 1 ]; then
        rm -rf "$STAGE"
    fi
}
trap cleanup EXIT

echo =========================================================================
info "源          : $SRC"
info "判定        : $([ "$is_dvd" = 1 ] && echo 'DVD-Video 源' || echo '普通目录')"

# =========================================================================
#  先压: 交给同仓库的 ffmpeg_dvd_hevc.sh, 不在这里复制它的坑(dvdvideo 解复用、
#  位图字幕、IVTC 都在那边处理好了)
# =========================================================================
# =========================================================================
#  体检门: 只在"源是 DVD **目录** 且真的要读它(ENCODE=1)"时才做
#  同 dvd_shrink.sh 那道门: 退出码 0 完好 / 1 都能补 / 2 补不出来; 本脚本不替你补。
#  ISO / 光驱源跳过: dvd_repair.sh 只认目录, 喂 ISO 会被当成"没有 VIDEO_TS", 那是假警报。
# =========================================================================
if [ "$ENCODE" = 1 ] && [ "${CHECK:-1}" != "0" ] && [ -d "$SRC" ] && [ "$is_dvd" = 1 ]; then
    info "体检源盘结构 ..."
    CHECK_ONLY=1 bash "$SCRIPT_DIR/dvd_repair.sh" "$SRC"
    case "$?" in
        0) info "体检通过    : IFO/BUP 成对齐全, VOB 编号连续" ;;
        1)
            err "源盘有缺失(清单见上) —— 缺的那些 title 压不出来, 先修再压"
            die "修复命令:
       APPLY=1 bash \"$SCRIPT_DIR/dvd_repair.sh\" \"$SRC\"
   (不想要这道门就 CHECK=0)"
            ;;
        2)
            if [ "${ALLOW_GAP:-0}" = "1" ]; then
                warn "有补不出来的缺失 —— ALLOW_GAP=1, 继续; 缺的那一段不会出现在产物里"
            else
                err "源盘有补不出来的缺失(VOB 断号): 那一整段的音视频真没了"
                die "确认要带着缺口继续就加 ALLOW_GAP=1 重跑:
       ALLOW_GAP=1 $0 \"$SRC\" ${OUT:+\"$OUT\"}"
            fi
            ;;
        *) die "体检失败(dvd_repair.sh 退出码非 0/1/2), 先单独跑它看报错" ;;
    esac
fi

if [ "$ENCODE" = 1 ]; then
    [ "$is_dvd" = 1 ] || die "ENCODE=1 但源不是 DVD-Video(没有 VIDEO_TS), 不知道该压什么"
    HENC="$REPO_ROOT/ffmpeg_dvd_hevc.sh"
    [ -f "$HENC" ] || die "找不到 $HENC(先压这条路由它完成)"
    STAGE="${STAGE:-$(cd "$(dirname "$SRC")" 2>/dev/null && pwd)/HEVC_OUT}"
    [ -n "$STAGE" ] || STAGE="./HEVC_OUT"
    rm -rf "$STAGE"; mkdir -p "$STAGE" || die "建不了中间目录: $STAGE"

    # 默认软编: 归档重编码常常跑在没有 N 卡的机器上, 而 hevc_nvenc 在这台机器上
    # 直接不可用(nvidia-smi 连不上驱动)—— 用 nvenc 当默认值会变成"一跑就失败"
    VENC="${VENC:-libx265}"

    # 挑一份"有 dvdvideo 解复用器 + 有 $VENC 编码器"的 ffmpeg。
    # 不能指望 PATH 上第一个: 这台机器 /usr/bin/ffmpeg 就没有 dvdvideo。
    # 而且必须连 PATH 一起给子进程: ffmpeg_dvd_hevc.sh 的能力检查用的是裸
    # `ffmpeg`(实测因此在这台机器上直接 exit 1), 光 export FFMPEG= 救不了它。
    FFMPEG="$(pick_ffmpeg "$VENC")" || die "找不到同时具备 dvdvideo 解复用器与 $VENC 编码器的 ffmpeg(可用 FFMPEG=/path/to/ffmpeg 指定)"
    FFPROBE="$(dirname "$FFMPEG")/ffprobe"
    [ -x "$FFPROBE" ] || FFPROBE="$(command -v ffprobe)"
    export FFMPEG FFPROBE

    info "先压 HEVC  : -> $STAGE (VENC=$VENC MODE=${HENC_MODE:-ALL})"
    echo -----------------------------------------------------------------
    HENC_ARGS=("$SRC" "$STAGE")
    [ -n "${3:-}" ] && HENC_ARGS+=("$3")     # 第三个参数一给, 子脚本会切到 MODE=TITLE
    PATH="$(dirname "$FFMPEG"):$PATH" VENC="$VENC" MODE="${HENC_MODE:-ALL}" EXT=mkv \
        bash "$HENC" "${HENC_ARGS[@]}" \
        || die "HEVC 编码失败(见上面 ffmpeg 的报错; 查 title 列表: ffprobe -f dvdvideo -i \"$SRC\")"
    echo -----------------------------------------------------------------
    DIR="$STAGE"
else
    [ -d "$SRC" ] || die "不是目录也没要求先压: $SRC(传 DVD 的 ISO 请保持 ENCODE=auto)"
    DIR="$SRC"
fi

[ -d "$DIR" ] || die "要打包的目录不存在: $DIR"
DIR="$(cd "$DIR" && pwd)"
n_file="$(find "$DIR" -type f | wc -l | tr -d ' ')"
[ "$n_file" -gt 0 ] || die "$DIR 里一个文件都没有, 没什么可打的"
total="$(find "$DIR" -type f -printf '%s\n' 2>/dev/null | awk '{s += $1} END{printf "%d", s}')"
[ -n "$total" ] && [ "$total" -gt 0 ] || die "算不出目录体积: $DIR"

info "打包目录    : $DIR ($n_file 个文件, $(human_size "$total"))"

# =========================================================================
#  输出路径: 与 dvd_restore.sh 同款踩坑 —— ISO 不能落在被打包的目录里面,
#  否则 mkisofs 一边扫目录一边写 ISO, 镜像里会多出半个自己
# =========================================================================
OUT="${OUT:-$(dirname "$DIR")/$(basename "$DIR").iso}"
OUT="$(realpath -m "$OUT")"
case "$OUT" in
    "$DIR"/*|"$DIR") die "输出 ISO 不能放在要打包的目录里面($OUT 在 $DIR 下), 换一个路径, 例如 $(dirname "$DIR")/$(basename "$DIR").iso" ;;
esac
OUT_DIR="$(dirname "$OUT")"
[ -d "$OUT_DIR" ] || mkdir -p "$OUT_DIR" || die "建不了输出目录: $OUT_DIR"

VOLID="${VOLID:-$(basename "$DIR")}"
VOLID="$(printf '%s' "$VOLID" | tr -cd 'A-Za-z0-9_' | cut -c1-32)"
[ -n "$VOLID" ] || VOLID="DATA"

# 挑打包器: 不能盲选 PATH 上第一个 —— Cygwin 下那常常是 WinCDEmu 的原生
# mkisofs.exe, 它吃不下 POSIX 路径(见 lib/common.sh 的 pick_mkisofs)
declare -F pick_mkisofs >/dev/null 2>&1 || die "lib/common.sh 未加载(pick_mkisofs 缺失) —— 请在完整仓库里运行本脚本"
MKISOFS="$(pick_mkisofs)" || die "找不到 mkisofs / genisoimage。安装: sudo apt install genisoimage"
HAVE_XORRISO=0; command -v xorriso >/dev/null 2>&1 && HAVE_XORRISO=1
HAVE_7Z=0;      command -v 7z      >/dev/null 2>&1 && HAVE_7Z=1
[ "$HAVE_XORRISO" = 1 ] || [ "$HAVE_7Z" = 1 ] || warn "xorriso 与 7z 都没有 —— 打包后只做大小检查, 跳过文件清单比对"

info "输出 ISO    : $OUT"
info "卷标        : $VOLID"
echo =========================================================================

# ---- 容量提示(数据盘一样要能塞进 DVD) ----
if [ "$total" -gt "$DVD9" ]; then
    warn "$(human_size "$total") 超过 DVD-9 双层容量 —— 只能当 ISO 存着, 刻不进任何 DVD"
elif [ "$total" -gt "$DVD5" ]; then
    warn "$(human_size "$total") 超过 DVD-5 单层容量 —— 需要 DVD-9 双层空白盘"
else
    info "容量        : 单层 DVD-5 装得下"
fi

# =========================================================================
#  打包: UDF 桥 + Joliet + Rock Ridge
# =========================================================================
info "开始打包($MKISOFS -udf) ..."
# 只有「Cygwin + 原生 exe」这一档才把路径换成 X:/... 混合写法, 其余原样
"$MKISOFS" -udf -iso-level 3 -J -r -allow-limited-size -V "$VOLID" -o "$(mkisofs_path "$OUT")" "$(mkisofs_path "$DIR")"
rc=$?
[ "$rc" -eq 0 ] || die "打包失败(rc=$rc)"
ISO_SZ="$(stat -c%s "$OUT")"
info "ISO 已生成  : $OUT ($(human_size "$ISO_SZ"))"

# =========================================================================
#  校验: UDF 锚点 + 文件清单逐一对大小
# =========================================================================
echo =========================================================================
info "校验 ..."

if command -v dd >/dev/null 2>&1; then
    vrs="$(dd if="$OUT" bs=2048 skip=16 count=8 2>/dev/null | tr -cd '[:print:]')"
    case "$vrs" in
        *BEA01*TEA01*) info "UDF 卷识别序列: 存在(BEA01 ... TEA01)" ;;
        *) warn "没找到 UDF 卷识别序列 —— $MKISOFS 可能没真加上 UDF" ;;
    esac
fi

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
    find "$DIR" -type f -print | while IFS= read -r f; do
        printf '%s %s\n' "$(stat -c%s "$f")" "${f#$DIR/}"
    done > "$exp_file"
    iso_list "$OUT" | awk '{ p=$2; sub(/^\//, "", p); print $1, p }' > "$act_file"

    LC_ALL=C sort "$exp_file" > "${exp_file}.s"
    LC_ALL=C sort "$act_file" > "${act_file}.s"
    exp_n=$(wc -l < "${exp_file}.s" | tr -d ' ')
    act_n=$(wc -l < "${act_file}.s" | tr -d ' ')
    if diff -q "${exp_file}.s" "${act_file}.s" >/dev/null 2>&1; then
        info "文件清单    : 一致($exp_n 个, 大小逐个对得上)"
    else
        warn "文件清单不一致: 源 $exp_n 个 / 镜像 $act_n 个(-J -r 会把名字规整过, 大小写与非法字符的差异不影响读取)"
        diff "${exp_file}.s" "${act_file}.s" | head -10 >&2
    fi
    rm -f "$exp_file" "$act_file" "${exp_file}.s" "${act_file}.s"
fi

echo =========================================================================
info "完成        : $OUT"
info "这是数据盘, 不是 DVD-Video: PC 直接打开就能播; DVD 机读不了, 要能在 DVD 机上放请走 dvd_restore.sh / dvd_shrink.sh"
if [ "$ENCODE" = 1 ] && [ "${KEEP_STAGE:-0}" = 1 ]; then
    info "HEVC 中间产物保留: $STAGE"
elif [ "$ENCODE" = 1 ]; then
    info "HEVC 中间产物已随工作结束清理(要留设 KEEP_STAGE=1)"
fi
exit 0
