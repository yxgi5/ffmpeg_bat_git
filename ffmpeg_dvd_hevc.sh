#!/bin/bash
# =========================================================================
#  ffmpeg_dvd_hevc.sh  -  DVD-Video(ISO / VIDEO_TS 目录 / 光驱) -> HEVC
#  ffmpeg_dvd_hevc.bat 的 POSIX 孪生脚本, 行为与开关名一一对应
#
#  用法:
#    ./ffmpeg_dvd_hevc.sh <源> [输出目录] [title号]
#      源       ISO 镜像、含 VIDEO_TS 的目录、或光驱设备(如 /dev/sr0)
#      输出目录 默认 <源所在目录>/HEVC_OUT
#      title号  给了这个就切到 MODE=TITLE 只处理这一条
#
#  与现有 ffmpeg_hevc_nvenc.sh 的关键差异(为什么不能直接复用那个):
#    1) 裸 -i 喂 ISO **不会报错**, ffmpeg 把 UDF 镜像当 MPEG-PS 糊乱揭开,
#       实测只得到 ~130s / 110504 帧的废品(正片其实 55 分钟)。必须 -f dvdvideo
#    2) -c:s mov_text 遇到 DVD 位图字幕必然失败:
#       "Subtitle encoding currently only possible from text to text or bitmap
#        to bitmap"
#    3) 就算改成 copy, mp4 封装也会静默丢掉第 2 条字幕轨
#       (实测 300s 片段: mkv 保留 2 条, mp4 只剩 1 条)
#    4) 不做 IVTC: DVD 里大量内容是 3:2 pulldown 的 23.976p, 按 29.97 编码
#       白扔 20% 码率还留梳状波纹
#
#  通用化设计(刻意不改的两件事):
#    * 不动 SAR, 不裁边。DVD 宽高比要同时看 IFO 与 MPEG-2 序列头, 同一张盘两者
#      都可能不一致, 没有通用写法 —— 让 ffmpeg 从容器透传原始 SAR 最稳。确要修
#      就填 VFILT_EXTRA(追加到滤镜链末尾):
#          VFILT_EXTRA='setsar=32:27'                   # 16:9 变形宽银幕
#          VFILT_EXTRA='crop=704:480:8:0,setsar=40:33'  # 裁过扫边后修 SAR
#    * 不猜测该切哪一章。每张盘的前編/後編分界章号都不同, 由调用方填
#      SPLIT_CHAPTER; 默认 0 = 不切。
#
#  依赖: ffmpeg 需带 libdvdread + libdvdnav(即 dvdvideo 解复用器), 精简构建没有。
#  注意: 本文件保持 UTF-8 编码 + LF 行尾
# =========================================================================

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================

# ---------- 前置检查 ----------
if ! check_command "ffmpeg"; then
    echo -e "\033[41;36mffmpeg command not found!\033[0m"
    exit 1
fi
if ! check_command "ffprobe"; then
    echo -e "\033[41;36mffprobe command not found!\033[0m"
    exit 1
fi

# ff_run / fp_run 要求 FF / FP 已设好; 允许用环境变量覆盖, 与 bat 侧的查找顺序对齐
FF="${FFMPEG:-$(command -v ffmpeg)}"
FP="${FFPROBE:-$(command -v ffprobe)}"
export FF FP

if ! ffmpeg -hide_banner -demuxers 2>/dev/null | grep -qi "dvdvideo"; then
    echo -e "\033[41;36m这份 ffmpeg 没有 dvdvideo 解复用器\033[0m"
    echo "需要带 libdvdread + libdvdnav 的构建(gyan.dev full build 有)"
    exit 1
fi

# ============================ 配置区 ============================
# ---------- 输入 ----------
if [ "$#" -ge 1 ]; then
    SRC="$1"
else
    echo "请输入 DVD 源(ISO / VIDEO_TS 目录 / 光驱设备): "
    read -r SRC
fi
[ -n "$SRC" ] || { echo "没给源"; exit 1; }

# 输出目录 / 前缀
OUTDIR="${2:-}"
if [ -z "$OUTDIR" ]; then
    OUTDIR="$(cd "$(dirname "$SRC")" 2>/dev/null && pwd)/HEVC_OUT"
    [ -n "$OUTDIR" ] || OUTDIR="./HEVC_OUT"
fi
PREFIX="$(basename "${SRC%.*}")"
[ -n "$PREFIX" ] || PREFIX="dvd"

# EXT=mkv  推荐: 能同时装 HEVC + 多条原生 AC3 + 多条 DVD 位图字幕
# EXT=mp4  只能 HEVC + AAC + 1 条字幕, 且 AC3 必须重编码
EXT="${EXT:-mkv}"

# IVTC    3:2 pulldown -> 23.976p, 动画/电影 DVD 多数是这种, 默认用它
# BWDIF   去交错但保留 29.97p, 只有确认是真隔行(摄像机/现场录像)才用
# NONE    原样 29.97 直接编码
FILT="${FILT:-IVTC}"

# 追加到滤镜链末尾的可选处理(默认空: 不改 SAR, 不裁边)
VFILT_EXTRA="${VFILT_EXTRA:-}"

# AUDIO=copy  MKV 下保留原始 AC3, 零重损失, 最快
# AUDIO=aac   必须重编码(MP4 下强制用这个)
AUDIO="${AUDIO:-copy}"

# MODE=AUTO   自动扫描所有 title, 挑时长最长的那条当正片(默认, 最通用)
# MODE=TITLE  只处理 DVD_TITLE 指定的一条
# MODE=ALL    每个 title 各出一个文件
MODE="${MODE:-AUTO}"
if [ "$#" -ge 3 ]; then
    DVD_TITLE="$3"
    MODE="TITLE"
fi
DVD_TITLE="${DVD_TITLE:-}"

# SPLIT_CHAPTER=N  按第 N 章把正片切成两段(如前編/後編), 0 = 不切
#   第 1 段 = 第 1 章到第 N-1 章, 第 2 段 = 第 N 章到结尾
#   查章节点: ffprobe -f dvdvideo -preindex 1 -title 3 -show_chapters <源>
SPLIT_CHAPTER="${SPLIT_CHAPTER:-0}"

# 额外要导出的 title 号, 空格分隔, 留空跳过。例: EXTRA_TITLES="1 4 5"
EXTRA_TITLES="${EXTRA_TITLES:-}"

# 空 = 用 lib/bitrate_table_hevc.csv 查表再 /2(推荐); 填数字则直接覆盖, 如 636k
VBITRATE="${VBITRATE:-}"

# 编码器: 默认 hevc_nvenc; 无 N 卡时设 VENC=libx265 走软编
VENC_NAME="${VENC:-hevc_nvenc}"
# ==================================================================

mkdir -p "$OUTDIR" || { echo "无法创建输出目录: $OUTDIR"; exit 1; }

echo "SOURCE : $SRC"
echo "OUTDIR : $OUTDIR"

# =========================================================================
#  probe_title <title>  ->  "宽 高 时长";  读不到则非 0
#  libdvdnav 那句 "Unable to open device file" 会打到 stderr, 是误报, 丢掉即可
# =========================================================================
probe_title() {
    local t="$1" wh dur
    wh="$(fp_run -v error -f dvdvideo -title "$t" \
          -select_streams v:0 -show_entries stream=width,height \
          -of csv=p=0 "$SRC" 2>/dev/null | tr ',' ' ')"
    [ -n "$wh" ] || return 1
    dur="$(fp_run -v error -f dvdvideo -title "$t" \
           -show_entries format=duration -of csv=p=0 "$SRC" 2>/dev/null)"
    [ -n "$dur" ] || return 1
    printf '%s %s\n' "$wh" "$dur"
}

# ---------- 选定要处理的 title ----------
if [ "$MODE" = "ALL" ]; then
    :
elif [ "$MODE" = "TITLE" ]; then
    MAIN="$(probe_title "$DVD_TITLE")" || {
        echo -e "\033[41;36m读不到 title $DVD_TITLE, 检查源路径 / 是否受 CSS 保护\033[0m"
        exit 1
    }
else
    # MODE=AUTO: 扫所有 title, 挑时长最长的
    # 不能"读不到就 break": DVD 的 title 编号**不连续**(本盘实测缺 title 2,
    # 一 break 就只看到 84s 的 title 1, 而 55 分钟的正片是 title 3)。
    # 改成容忍连续缺失 MISS_MAX 次才收尾。
    MISS_MAX="${MISS_MAX:-5}"
    BEST=0; DVD_TITLE=""; MAIN=""; miss=0
    n=1
    while [ "$n" -le 99 ]; do
        if line="$(probe_title "$n")"; then
            miss=0
            d="$(awk '{printf "%d", $3}' <<<"$line")"
            if [ "$d" -gt "$BEST" ]; then
                BEST="$d"; DVD_TITLE="$n"; MAIN="$line"
            fi
        else
            miss=$(( miss + 1 ))
            [ "$miss" -ge "$MISS_MAX" ] && break
        fi
        n=$(( n + 1 ))
    done
    [ -n "$DVD_TITLE" ] || {
        echo -e "\033[41;36m一个 title 都没读到, 检查源路径 / 是否受 CSS 保护\033[0m"
        exit 1
    }
    echo "自动选定: title $DVD_TITLE（共 ${BEST}s, 最长）"
fi

if [ "$MODE" = "ALL" ]; then
    # 同一张 DVD 上所有 title 分辨率一致, 用 title 1 定码率档位即可
    MAIN="$(probe_title 1)" || { echo -e "\033[41;36m读不到 title 1\033[0m"; exit 1; }
fi
read -r SRC_W SRC_H SRC_DUR <<<"$MAIN"
echo "正片: ${SRC_W}x${SRC_H}  时长 ${SRC_DUR}s"
SRC_PIX=$(( SRC_W * SRC_H ))

# ---------- 算目标码率(复用仓库的 power-law 模型) ----------
if [ -z "$VBITRATE" ]; then
    BIT="$(lookup_bitrate "$SRC_PIX" bitrate_table_hevc.csv)"
    if [ $? -ne 0 ] || [ -z "$BIT" ]; then
        echo -e "\033[41;36mManual handle it! (${SRC_PIX} px 不在码率表范围内)\033[0m"
        exit 2
    fi
    # 与 .bat / ffmpeg_hevc_nvenc.sh 同口径: 查表值 /2, 单位 bits/s(裸数字),
    # 不加 k —— 636021 就是 636 kbps; 加了 k 会变成 636 Mbps 被 NVENC 拒
    VBITRATE="$(awk -v b="$BIT" 'BEGIN{printf "%d", b/2}')"
fi
echo "ref TARGET_BITRATE = ${VBITRATE} bit/s (~$(( VBITRATE / 1000 )) kbps)"

# ---------- 组滤镜链 ----------
VFILT=""
case "$FILT" in
    IVTC)  VFILT="fieldmatch=mode=pc:combmatch=full,yadif=deint=interlaced,decimate" ;;
    BWDIF) VFILT="bwdif=mode=1" ;;
    NONE)  VFILT="" ;;
esac
if [ -n "$VFILT_EXTRA" ]; then
    if [ -n "$VFILT" ]; then VFILT="${VFILT},${VFILT_EXTRA}"; else VFILT="$VFILT_EXTRA"; fi
fi
if [ -n "$VFILT" ]; then echo "滤镜链: $VFILT"; else echo "滤镜链: [无]"; fi

# ---------- 容器相关选项(数组, 无 eval) ----------
# 编码器参数按 VENC 分档; -c:v 由 enc() 统一追加, 保证 -i 一定在 -c:v 之前
case "$VENC_NAME" in
    hevc_nvenc) VENC_ARGS=(-profile:v main -preset p4 -tune:v hq -rc cbr -b:v "$VBITRATE") ;;
    libx265)    VENC_ARGS=(-preset medium -x265-params "log-level=error" -b:v "$VBITRATE") ;;
    *)          VENC_ARGS=(-b:v "$VBITRATE") ;;
esac

case "$EXT" in
    mkv)
        [ "$AUDIO" = "aac" ] && AENC=(-c:a aac -b:a 192k) || AENC=(-c:a copy)
        SENC=(-c:s copy)
        SMAP=(-map 0:s?)
        ;;
    mp4)
        echo "注意: MP4 只能保留 1 条 DVD 位图字幕, 其余会丢; 要全留请用 EXT=mkv"
        AENC=(-c:a aac -b:a 192k)
        SENC=(-c:s dvdsub)
        SMAP=(-map 0:s:0?)
        ;;
    *)
        echo "EXT 只能是 mkv 或 mp4"
        exit 3
        ;;
esac

# =========================================================================
#  enc <title> <输出名(无扩展)> [chapter_start] [chapter_end]
#  刻意不用 -ss: dvdvideo 解复用器 seek 后时间轴不可靠, 实测会让章节整体偏移,
#  靠 -chapter_start/-chapter_end 才是准的
# =========================================================================
enc() {
    local t="$1" out="$2" cs="${3:-0}" ce="${4:-0}"
    local chop=()
    [ "$cs" != "0" ] && chop+=(-chapter_start "$cs")
    [ "$ce" != "0" ] && chop+=(-chapter_end "$ce")

    echo "------------------------------------------------------------"
    echo "> title $t -> ${out}.${EXT}  ${chop[*]:-}"

    local CMD=(ff_run -y -hide_banner -v error -stats
               -f dvdvideo -title "$t" ${chop[@]+"${chop[@]}"})
    CMD+=(-i "$SRC")
    CMD+=(-map 0:v -map 0:a? ${SMAP[@]+"${SMAP[@]}"})
    [ -n "$VFILT" ] && CMD+=(-vf "$VFILT")
    CMD+=(-c:v "$VENC_NAME")
    CMD+=(${VENC_ARGS[@]+"${VENC_ARGS[@]}"}
          ${AENC[@]+"${AENC[@]}"}
          ${SENC[@]+"${SENC[@]}"}
          -map_chapters 0 -map_metadata 0
          -rtbufsize 120m -max_muxing_queue_size 1024
          "${OUTDIR}/${out}.${EXT}")

    "${CMD[@]}"
    if [ $? -ne 0 ]; then
        echo -e "\033[41;36mtitle $t 编码失败\033[0m"
        echo "常见原因: 1) -c:s 处理不了位图字幕  2) MP4 下 AC3 没转成 AAC"
        echo "          3) ${VENC_NAME} 不可用 -> 换 VENC=libx265"
        return 1
    fi
    return 0
}

enc_extra() {
    local t="$1" out="$2"
    echo "> 附加 title $t -> ${out}.${EXT}"
    local CMD=(ff_run -y -hide_banner -v error -stats
               -f dvdvideo -title "$t")
    CMD+=(-i "$SRC")
    CMD+=(-map 0:v -map 0:a?)
    [ -n "$VFILT" ] && CMD+=(-vf "$VFILT")
    CMD+=(-c:v "$VENC_NAME")
    CMD+=(${VENC_ARGS[@]+"${VENC_ARGS[@]}"} ${AENC[@]+"${AENC[@]}"}
          "${OUTDIR}/${out}.${EXT}")
    "${CMD[@]}"
}

# ---------- 开跑 ----------
# 逐个跑完再统一判失败: 一个 title 挂掉不该让后面的特典连跑都不跑,
# 但退出码必须真的传出去(与 .bat 侧的 exit /b 1 对齐)。
RC=0
if [ "$MODE" = "ALL" ]; then
    MISS_MAX="${MISS_MAX:-5}"
    miss=0
    n=1
    while [ "$n" -le 99 ]; do
        if probe_title "$n" >/dev/null 2>&1; then
            miss=0
            enc "$n" "${PREFIX}_title${n}" || RC=1
        else
            miss=$(( miss + 1 ))
            [ "$miss" -ge "$MISS_MAX" ] && break
        fi
        n=$(( n + 1 ))
    done
else
    if [ "$SPLIT_CHAPTER" -gt 0 ]; then
        enc "$DVD_TITLE" "${PREFIX}_part1" 1 $(( SPLIT_CHAPTER - 1 )) || RC=1
        enc "$DVD_TITLE" "${PREFIX}_part2" "$SPLIT_CHAPTER" 0 || RC=1
    else
        enc "$DVD_TITLE" "$PREFIX" || RC=1
    fi
    for t in $EXTRA_TITLES; do
        enc_extra "$t" "${PREFIX}_title${t}" || RC=1
    done
fi

if [ "$RC" -ne 0 ]; then
    echo -e "\033[41;36m至少一个 title 编码失败\033[0m"
    exit 1
fi

echo
echo ============================================================
echo " 输出目录: $OUTDIR"
if [ -n "$SRC_DUR" ]; then
    DI="$(awk '{printf "%d", $1}' <<<"$SRC_DUR")"
    # VBITRATE 可能是裸 bits/s, 也可能被覆盖成 "636k" / "2m"
    case "$VBITRATE" in
        *[kK]) VBN=$(( ${VBITRATE%[kK]} * 1000 )) ;;
        *[mM]) VBN=$(( ${VBITRATE%[mM]} * 1000000 )) ;;
        *)     VBN="$VBITRATE" ;;
    esac
    # 先 /1024 再乘时长, 避免大数(与 sh 的 64 位无关, 纯粹为了和 .bat 的 32 位
    # set /a 保持同一套算式, 两边结果才会一致)
    EST_MB=$(( VBN / 1024 * DI / 8192 ))
    echo " 体积估算: 视频 ~$(( VBN / 1000 )) kbps x ${DI}s ≈ ${EST_MB} MB（另加音频）"
fi
echo ============================================================
exit 0
