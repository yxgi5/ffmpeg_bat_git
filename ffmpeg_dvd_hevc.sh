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
#    4) 默认按源制式选滤镜(FILT=AUTO): NTSC 29.97i 走 IVTC 还原 23.976p(不做的话
#       按 29.97 编码白扔 20% 码率还留梳状波纹), PAL 25i 走 BWDIF 去交错保留 25p
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
#  编码器(与 .bat 侧同名开关 VENC):
#    空 / auto   依次真跑探测 hevc_nvenc -> hevc_qsv -> libx265, 用第一个能编的
#    显式        直接填 ffmpeg 原生名: hevc_nvenc / hevc_qsv / h264_nvenc /
#                h264_qsv / av1_nvenc / av1_qsv / libx265 / libx264 / libsvtav1
#                (连字符写法 hevc-nvenc 也认; avc_nvenc / avc_qsv 会自动翻译成
#                 h264_nvenc / h264_qsv —— ffmpeg 里没有 avc_* 这个编码器名)
#    显式指定的那个探测通不过 -> 报错退出并列出本机可用的, 不静默降级
#    探测一律"真跑一次小编码", 不看 ffmpeg -encoders 列表: 本机三个 nvenc 都列在
#      表里, 真跑却在 cuInit 处失败(没 N 卡) —— 只看列表会把不可用判成可用
#    码率表跟着编码器走: hevc_* -> hevc 表, h264_* / libx264 -> avc 表,
#      av1_* / libsvtav1 -> av1 表(三张表都 /2, 与仓库其余入口同口径)
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
# 与 .bat 侧同一套定位顺序(见 lib/common.sh 的 find_ffmpeg):
#   FFMPEG_BIN(目录) / FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH 逐项 > 常见前缀
# 不能只问 command -v: 它只回第一个命中, 而"第一个"经常正是缺能力的那个。
# dvdvideo 解复用器依赖 libdvdread/libdvdnav, 精简构建没有 —— 用 --need-demuxer 让
# 定位阶段就跳过不带它的构建(本机实测: PATH 上 ubuntu 4.4.2 没有, /opt 下的 master
# build 有, 于是自动落到 /opt 那份, 不必写死路径)。
# 选中的那份由 ff_report 在标准错误上醒目回显。
if ! FF="$(find_ffmpeg --need-demuxer dvdvideo)"; then
    echo -e "\033[41;36m找不到带 dvdvideo 解复用器的 ffmpeg\033[0m"
    echo "需要带 libdvdread + libdvdnav 的构建(gyan.dev full build 有)"
    echo "也可用 FFMPEG_BIN=<目录> / FFMPEG=<可执行文件> 指定"
    exit 1
fi
if ! FP="$(find_ffprobe "$FF")"; then
    echo -e "\033[41;36m找不到 ffprobe\033[0m"
    echo "可用 FFPROBE=<可执行文件> 指定"
    exit 1
fi
export FF FP

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
# 允许调用方用 PREFIX= 覆盖(与 .bat 侧 if not defined PREFIX 同口径)
PREFIX="${PREFIX:-$(basename "${SRC%.*}")}"
[ -n "$PREFIX" ] || PREFIX="dvd"

# EXT=mkv  推荐: 能同时装 HEVC + 多条原生 AC3 + 多条 DVD 位图字幕
# EXT=mp4  只能 HEVC + AAC + 1 条字幕, 且 AC3 必须重编码
EXT="${EXT:-mkv}"
# 归一成小写: 输出文件后缀是直接取 $EXT 拼的, 不归一的话 EXT=MP4 会产出 ".MP4"
EXT="${EXT,,}"

# AUTO(默认) 按源制式选: NTSC 29.97i -> IVTC 还原 23.976p; PAL 25i -> BWDIF 去交错
#            保留 25p; 源已是 23.976p -> 不加滤镜。判读不到帧率就按高度猜(576/288=PAL,
#            480/240=NTSC)。PAL 盘没有 3:2 pulldown, 硬套 IVTC 会掉到 20fps(实测: 本机
#            两张 720x576 PAL 盘跑 IVTC 出来 r_frame_rate=20/1, 白扔 20% 帧)
# IVTC    3:2 pulldown -> 23.976p, NTSC 动画/电影 DVD 多数是这种
# BWDIF   去交错但保留原帧率(PAL 25i -> 25p)。注意 bwdif=mode=1 是 send_field,
#         帧率直接翻倍(实测 25i -> 50p), 帧数翻倍会把码率摊薄, 故这里用 mode=0
# NONE    原样编码, 不做去交错
FILT="${FILT:-AUTO}"

# 追加到滤镜链末尾的可选处理(默认空: 不改 SAR, 不裁边)
VFILT_EXTRA="${VFILT_EXTRA:-}"

# AUDIO=copy  MKV 下保留原始 AC3 / DTS / MP2, 零重损失, 最快。
#             唯一例外: 源音轨是 LPCM(pcm_dvd) 时 Matroska 装不下(实测报
#             "No wav codec tag found for codec pcm_dvd"), 会自动转成 AAC
# AUDIO=aac   强制重编码成 AAC 192k(MP4 下强制用这个)
# AUDIO=flac  强制重编码成 FLAC, 无损, 体积约为 LPCM 的一半
AUDIO="${AUDIO:-copy}"

# MODE=ALL    每个 title 各出一个文件(默认)
# MODE=AUTO   自动扫描所有 title, 挑时长最长的那条当正片
# MODE=TITLE  只处理 DVD_TITLE 指定的一条
MODE="${MODE:-ALL}"
# 位置参数优先; 没给位置参数、但环境里设了 DVD_TITLE 也切 TITLE(与 .bat 侧
# `if defined DVD_TITLE set MODE=TITLE` 对齐 —— 否则这个变量会被静默忽略)
if [ "$#" -ge 3 ]; then
    DVD_TITLE="$3"
fi
DVD_TITLE="${DVD_TITLE:-}"
if [ -n "$DVD_TITLE" ]; then
    MODE="TITLE"
fi

# SPLIT_CHAPTER=N  按第 N 章把正片切成两段(如前編/後編), 0 = 不切
#   第 1 段 = 第 1 章到第 N-1 章, 第 2 段 = 第 N 章到结尾
#   查章节点: ffprobe -f dvdvideo -preindex 1 -title 3 -show_chapters <源>
SPLIT_CHAPTER="${SPLIT_CHAPTER:-0}"

# 额外要导出的 title 号, 空格分隔, 留空跳过。例: EXTRA_TITLES="1 4 5"
EXTRA_TITLES="${EXTRA_TITLES:-}"

# 空 = 用 lib/bitrate_table_hevc.csv 查表再 /2(推荐); 填数字则直接覆盖, 如 636k
VBITRATE="${VBITRATE:-}"

# 编码器: 空 / auto = 依次探测 hevc_nvenc -> hevc_qsv -> libx265 取第一个能编的;
#         要指定就填 ffmpeg 原生名(hevc_nvenc / h264_qsv / libx265 ...)。
#         解析与可用性探测都在下面"编码器"那一节做(码率表要先定下来才能查表)
VENC="${VENC:-auto}"
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
    # 关键: libdvdread 的抱怨("CHECK_VALUE failed in src/nav_read.c" 之类)在这个
    # 构建里是打到**标准输出**的, 2>/dev/null 挡不住 —— 它比真正的数值先出现, 于是
    # 后面 awk '{print $3}' 取到的是 "failed", 时长算成 0, AUTO 模式一个 title 都选不中
    # (实测: 2026-09-29 这台机器上的 master build, 报 "一个 title 都没读到")。
    # 按形状过滤, 只留数值行并取最后一行 —— 与 .bat 侧 for /f 的"后读到的覆盖前面的"
    # 行为对齐, 两族结果才一致。
    # 按字段取, 不用行级正则: csv=p=0 打出来是 "720,576," 这种带尾逗号的形式,
    # tr 完变成 "720 576 " 有尾空格, 行级 ^...$ 匹配不上(实测踩过)
    wh="$(fp_run -v error -f dvdvideo -title "$t" \
          -select_streams v:0 -show_entries stream=width,height \
          -of csv=p=0 "$SRC" 2>/dev/null \
          | tr ',' ' ' | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {print $1, $2}' | tail -1)"
    [ -n "$wh" ] || return 1
    # 时长同样先 tr 掉逗号: 有的构建(Windows 真机那台)对单字段也打 "3300.500000," 这种
    # 带尾逗号的形式, 行级 ^...$ 匹配不上 -> dur 恒空 -> "读不到 title N" 全盘跑不动
    # (2026-09-29 本机用带尾逗号的替身 ffprobe 复现出来)
    dur="$(fp_run -v error -f dvdvideo -title "$t" \
           -show_entries format=duration -of csv=p=0 "$SRC" 2>/dev/null \
           | tr ',' ' ' | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ {print $1}' | tail -1)"
    [ -n "$dur" ] || return 1
    printf '%s %s\n' "$wh" "$dur"
}

#  <title> -> 该 title 视频流的帧率, 如 25/1 / 30000/1001; 读不到则空
#  过滤理由同 probe_title: libdvdread 的抱怨是打到标准输出的, 只能按形状挑
probe_rate() {
    fp_run -v error -f dvdvideo -title "$1" \
           -select_streams v:0 -show_entries stream=r_frame_rate \
           -of csv=p=0 "$SRC" 2>/dev/null \
        | tr ',' '\n' | grep -oE '^[0-9]+/[0-9]+$' | tail -1
}

#  <title> -> 该 title 所有音轨的 codec 名(空格分隔), 如 "ac3" / "pcm_dvd"; 读不到则空
probe_acodec() {
    # 同上: 带尾逗号时 "ac3," 过不了 ^...$, LPCM 例外会静默失效
    fp_run -v error -f dvdvideo -title "$1" \
           -select_streams a -show_entries stream=codec_name \
           -of csv=p=0 "$SRC" 2>/dev/null \
        | tr -d '\r' | tr ',' '\n' | grep -oE '^[a-z0-9_]+$' | tr '\n' ' '
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

# 制式 / 音轨探测用哪条 title: ALL 模式上面是用 title 1 定码率档位的, 其余模式是正片那条
if [ "$MODE" = "ALL" ]; then REF_TITLE=1; else REF_TITLE="$DVD_TITLE"; fi
SRC_RATE="$(probe_rate "$REF_TITLE" 2>/dev/null)"
SRC_ACODEC="$(probe_acodec "$REF_TITLE" 2>/dev/null)"

# =========================================================================
#  编码器: VENC 空 / auto 时依次探测 hevc_nvenc -> hevc_qsv -> libx265, 用第一
#  个真能编的; 显式给了名字就用那个, 探测不过就报错退出(并列出本机可用的)。
#
#  探测一律"真跑一次小编码", 不看 ffmpeg -encoders 列表 —— 本机三个 nvenc 都挂在
#  列表里, 真跑却在 cuInit 处失败(没 N 卡), 只看列表会把"不可用"判成可用。
#  尺寸取 320x240: 再小(128x128) NVENC 自己就拒绝初始化, 反过来会把"可用"判成
#  不可用(仓库 test/README.md 记过这个假 SKIP)。
# =========================================================================
venc_usable() {
    "$FF" -hide_banner -v error -f lavfi -i testsrc2=s=320x240:r=25:d=1 \
          -c:v "$1" -frames:v 2 -f null - >/dev/null 2>&1
}

VENC_LIST_ALL="hevc_nvenc h264_nvenc av1_nvenc hevc_qsv h264_qsv av1_qsv libx265 libx264 libsvtav1"

venc_avail_list() {
    local e out=""
    for e in $VENC_LIST_ALL; do
        venc_usable "$e" && out="${out:+$out }$e"
    done
    printf '%s' "${out:-一个都没有}"
}

# 名字归一: 连字符写法(hevc-nvenc)统一成下划线; avc_* 翻成 ffmpeg 真名 h264_*
VENC_NAME="${VENC:-auto}"
VENC_NAME="${VENC_NAME//-/_}"
case "$VENC_NAME" in
    avc_nvenc) VENC_NAME="h264_nvenc" ;;
    avc_qsv)   VENC_NAME="h264_qsv"   ;;
esac

if [ "$VENC_NAME" = "auto" ]; then
    VENC_NAME=""
    for c in hevc_nvenc hevc_qsv libx265; do
        if venc_usable "$c"; then VENC_NAME="$c"; break; fi
    done
    [ -n "$VENC_NAME" ] || {
        echo -e "\033[41;36mhevc_nvenc / hevc_qsv / libx265 三个候选本机都不可用\033[0m"
        exit 1
    }
    echo "编码器  : auto -> $VENC_NAME（依次探测 hevc_nvenc / hevc_qsv / libx265）"
else
    # 先认名字再探测: 拼错的名字不至于被当成"本机不可用"这种误导性报错
    case " $VENC_LIST_ALL " in
        *" $VENC_NAME "*) : ;;
        *)
            echo -e "\033[41;36m不认识的编码器: $VENC_NAME\033[0m"
            echo "认这些: $VENC_LIST_ALL"
            exit 1
            ;;
    esac
    venc_usable "$VENC_NAME" || {
        echo -e "\033[41;36m指定的编码器 $VENC_NAME 本机不可用\033[0m"
        echo "常见原因: 没装对应驱动 / 这份 ffmpeg 没编进该编码器 / 显卡不支持该格式"
        echo "本机实测可用: $(venc_avail_list)"
        exit 1
    }
    echo "编码器  : $VENC_NAME（显式指定）"
fi

# 参数模板(不含 -b:v, 码率算完再追加) + 该用哪张码率表
case "$VENC_NAME" in
    hevc_nvenc) VENC_BASE="-profile:v main -preset p4 -tune:v hq -rc cbr";  BTAB=hevc ;;
    hevc_qsv)   VENC_BASE="-profile:v main -preset veryfast";               BTAB=hevc ;;
    libx265)    VENC_BASE="-profile:v main -preset fast";                   BTAB=hevc ;;
    h264_nvenc) VENC_BASE="-profile:v high -preset p4 -tune:v hq -rc cbr";  BTAB=avc  ;;
    h264_qsv)   VENC_BASE="-profile:v main -preset veryfast";               BTAB=avc  ;;
    libx264)    VENC_BASE="-profile:v high -preset fast";                   BTAB=avc  ;;
    av1_nvenc)  VENC_BASE="-preset p4 -tune:v hq -rc cbr";                  BTAB=av1  ;;
    av1_qsv)    VENC_BASE="-profile:v main -preset fast";                   BTAB=av1  ;;
    libsvtav1)  VENC_BASE="-preset 8";                                      BTAB=av1  ;;
esac

# ---------- 算目标码率(复用仓库的 power-law 模型) ----------
if [ -z "$VBITRATE" ]; then
    BIT="$(lookup_bitrate "$SRC_PIX" "bitrate_table_${BTAB}.csv")"
    if [ $? -ne 0 ] || [ -z "$BIT" ]; then
        echo -e "\033[41;36mManual handle it! (${SRC_PIX} px 不在码率表范围内)\033[0m"
        exit 2
    fi
    # 与 .bat / ffmpeg_hevc_nvenc.sh 同口径: 查表值 /2, 单位 bits/s(裸数字),
    # 不加 k —— 636021 就是 636 kbps; 加了 k 会变成 636 Mbps 被 NVENC 拒
    # 表按编码器选(hevc/avc/av1), 三张表都是 /2, 与仓库其余入口同口径
    VBITRATE="$(awk -v b="$BIT" 'BEGIN{printf "%d", b/2}')"
fi
echo "ref TARGET_BITRATE = ${VBITRATE} bit/s (~$(( VBITRATE / 1000 )) kbps)"

# ---------- 组滤镜链 ----------
FILT_IVTC="fieldmatch=mode=pc:combmatch=full,yadif=deint=interlaced,decimate"
FILT_BW="bwdif=mode=0"
VFILT=""
case "$FILT" in
    IVTC)  VFILT="$FILT_IVTC" ;;
    BWDIF) VFILT="$FILT_BW" ;;
    NONE)  VFILT="" ;;
    AUTO)
        case "$SRC_RATE" in
            30000/1001|30/1|60000/1001|60/1) FSYS="NTSC 29.97i";  VFILT="$FILT_IVTC" ;;
            24000/1001|24/1)                 FSYS="NTSC 23.976p"; VFILT=""          ;;
            25/1|50/1)                       FSYS="PAL 25i";      VFILT="$FILT_BW"  ;;
            *)
                case "$SRC_H" in
                    576|288) FSYS="PAL(按高度猜)";   VFILT="$FILT_BW"   ;;
                    480|240) FSYS="NTSC(按高度猜)";  VFILT="$FILT_IVTC" ;;
                    *)       FSYS="未知";            VFILT=""           ;;
                esac
                ;;
        esac
        echo "源制式  : ${FSYS} @ ${SRC_RATE:-读不到帧率}"
        ;;
esac
if [ -n "$VFILT_EXTRA" ]; then
    if [ -n "$VFILT" ]; then VFILT="${VFILT},${VFILT_EXTRA}"; else VFILT="$VFILT_EXTRA"; fi
fi
if [ -n "$VFILT" ]; then echo "滤镜链: $VFILT"; else echo "滤镜链: [无]"; fi

# ---------- 容器相关选项(数组, 无 eval) ----------
# 参数模板 + 码率 -> 数组。模板里都是固定字面量, 用 read -a 切词即可(不用 eval);
# -c:v 由 enc() 统一追加, 保证 -i 一定在 -c:v 之前
read -r -a VENC_ARGS <<<"${VENC_BASE} -b:v ${VBITRATE}"
echo "编码参数: ${VENC_ARGS[*]}"

case "$EXT" in
    mkv)
        AENC=(-c:a copy)
        [ "$AUDIO" = "aac" ]  && AENC=(-c:a aac -b:a 192k)
        [ "$AUDIO" = "flac" ] && AENC=(-c:a flac)
        # AUDIO=copy 下唯一例外: LPCM(pcm_dvd) 装不进 Matroska(实测写头就失败:
        # "No wav codec tag found for codec pcm_dvd"), 撞上就自动转 AAC
        if [ "$AUDIO" = "copy" ]; then
            case "$SRC_ACODEC" in
                *pcm_dvd*)
                    AENC=(-c:a aac -b:a 192k)
                    echo "注意: 源音轨是 LPCM(pcm_dvd), Matroska 装不下 -> 自动转 AAC 192k（要无损设 AUDIO=flac）"
                    ;;
            esac
        fi
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
    CMD+=(-map 0:V -map 0:a? ${SMAP[@]+"${SMAP[@]}"})
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
        echo "          3) ${VENC_NAME} 参数不被接受 -> 换 VENC=libx265 或 VENC=auto"
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
    CMD+=(-map 0:V -map 0:a?)
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
