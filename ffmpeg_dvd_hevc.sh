#!/bin/bash
# =========================================================================
#  ffmpeg_dvd_hevc.sh  -  DVD-Video(ISO / VIDEO_TS 目录 / 光驱) -> HEVC
#  ffmpeg_dvd_hevc.bat 的 POSIX 孪生脚本, 行为与开关名一一对应
#
#  用法:
#    ./ffmpeg_dvd_hevc.sh <源> [输出目录] [title号]
#      源       DVD: ISO 镜像 / 含 VIDEO_TS 的目录 / 光驱设备(如 /dev/sr0)
#               BD : 含 BDMV 的目录(挂载点) / 单个 .m2ts
#      输出目录 默认 <源所在目录>/HEVC_OUT
#      title号  给了这个就切到 MODE=TITLE 只处理这一条(BD 下填序号即可)
#
#  蓝光(BD)这一块的口径与边界(与 .bat 侧逐条对齐):
#    * 一条 BDMV/STREAM/*.m2ts = 一个 title, 走 mpegts 直读, 不用 -f bluray ——
#      实测过的机器上没有一份 ffmpeg 带 bluray 解复用器(MSYS2 的 8.1 配置里写着
#      --enable-libbluray, demuxer 列表里却没有)
#    * .iso 挂载要 root, 脚本不擅自做: 按 DVD 读不到就提示挂载命令后退出
#      (Windows 那一族会自动挂载并在结束时卸载)
#    * 章节写在 mpls 里, 直读 m2ts 拿不到 —— BD 下 SPLIT_CHAPTER 会被忽略
#    * BD 的 MODE 默认也是 ALL(与 DVD 一致: 每个 title 各出一个文件); 想只拿正片
#      显式 MODE=AUTO(自动挑最长那条) —— 盘里 m2ts 多半是菜单/特典碎片
#    * 音频: pcm_bluray(LPCM) 装不进 Matroska, 与 pcm_dvd 同一口径自动转 AAC
#    * 字幕: PGS 只能进 MKV; EXT=mp4 时整条丢弃(实测 -c:s dvdsub 在 PGS 上写
#      trailer 就失败)
#    * 隔行: BD 的 FILT 默认 NONE, 与 DVD 的默认 AUTO 不同(1080i 真隔行硬套
#      IVTC 会掉帧), 要去交错显式 FILT=BWDIF
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

# 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.sh)
#   优先级 参数 > 环境变量 > defaults.cfg; 没给的参数回退 env / cfg(老 set 写法仍兼容)
#   其余位置参数(源 / 输出目录 / title号)交还给 $@, 下方 $1/$2/$3 照常处理
parse_switches "$@"
set -- ${PS_REST[@]+"${PS_REST[@]}"}

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================

# ---------- 输入(先取源: 判定类型要在找 ffmpeg 之前) ----------
# 为什么挪到这里: 源是 DVD 还是 BD 决定了该不该要求 dvdvideo 解复用器 —— BD 走 mpegts
# 直读, 拿"必须有 libdvdread"去找会在只有精简构建的机器上白失败。
if [ "$#" -ge 1 ]; then
    SRC="$1"
else
    echo "请输入 DVD / BD 源(ISO / VIDEO_TS / BDMV 目录 / 光驱设备 / .m2ts): "
    read -r SRC
fi
[ -n "$SRC" ] || { echo "没给源"; exit 1; }

# 只看目录结构就能定的先定: BDMV / VIDEO_TS 是硬指标。.iso 得真读才知道, 归到
# unknown, 等拿到 ffprobe 再判(见下面"源类型"那一节)。
detect_kind_struct() {
    if [ -d "$SRC/BDMV" ];   then SRC_KIND="bd";  BD_ROOT="$SRC"; return 0; fi
    if [ -d "$SRC/VIDEO_TS" ]; then SRC_KIND="dvd"; return 0; fi
    # 直接给到 BDMV 这一层也算
    if [ -d "$SRC/STREAM" ]; then SRC_KIND="bd"; BD_ROOT="$(cd "$SRC/.." 2>/dev/null && pwd)"; return 0; fi
    case "${SRC,,}" in
        *.m2ts|*.mts) SRC_KIND="bd";  BD_ONE="$SRC"; return 0 ;;
        *.iso|*.img)  SRC_KIND="unknown"; return 0 ;;
    esac
    SRC_KIND="dvd"   # 其余后缀 / 光驱设备: 与加 BD 之前同口径
}
SRC_KIND=""; BD_ROOT=""; BD_ONE=""
detect_kind_struct

# ---------- 前置检查 ----------
# 与 .bat 侧同一套定位顺序(见 lib/common.sh 的 find_ffmpeg):
#   FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH 逐项 > 常见前缀
# 不能只问 command -v: 它只回第一个命中, 而"第一个"经常正是缺能力的那个。
# 选中的那份由 ff_report 在标准错误上醒目回显。
if [ "$SRC_KIND" = "bd" ]; then
    if ! FF="$(find_ffmpeg)"; then
        echo -e "\033[41;36m找不到 ffmpeg\033[0m"
        echo "也可用 FFMPEG=<可执行文件> 指定"
        exit 1
    fi
else
    # dvdvideo 解复用器依赖 libdvdread/libdvdnav, 精简构建没有 —— 用 --need-demuxer 让
    # 定位阶段就跳过不带它的构建(本机实测: PATH 上 ubuntu 4.4.2 没有, /opt 下的 master
    # build 有, 于是自动落到 /opt 那份, 不必写死路径)
    if ! FF="$(find_ffmpeg --need-demuxer dvdvideo)"; then
        echo -e "\033[41;36m找不到带 dvdvideo 解复用器的 ffmpeg\033[0m"
        echo "需要带 libdvdread + libdvdnav 的构建(gyan.dev full build 有)"
        echo "也可用 FFMPEG=<可执行文件> 指定"
        exit 1
    fi
fi
if ! FP="$(find_ffprobe "$FF")"; then
    echo -e "\033[41;36m找不到 ffprobe\033[0m"
    echo "可用 FFPROBE=<可执行文件> 指定"
    exit 1
fi
export FF FP

# ============================ 配置区 ============================
# ---------- 输入 ----------
# SRC 已经在"前置检查"里取过了(判定源类型要用它), 这里不再重复问

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
# 默认值来自 lib/defaults.cfg: DVD 链路单列一个 DVD_EXT 键 —— 公共 EXT 的默认是 mp4,
#   而 mp4 装不下第 2 条 DVD 位图字幕(实测只剩 1 条), 让公共默认值盖过来等于悄悄降级
#   产物。优先级: 命令行/环境显式给的 EXT > DVD_EXT > 公共 EXT > mkv。
#   「是不是显式给的」必须在 load_defaults 之前判: 它只补没设过的键, 跑完就分不清
#   EXT 到底是命令行带来的还是配置文件补的。
EXT_GIVEN="${EXT:+1}"
load_defaults
if [ -z "$EXT_GIVEN" ]; then
    EXT="${DVD_EXT:-${EXT:-mkv}}"
fi
unset EXT_GIVEN
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
# BD 的默认滤镜与 DVD 不同(见文件头), 所以先记下 FILT 是不是调用方显式给的 ——
# 与上面 EXT 那套 EXT_GIVEN 同口径
FILT_GIVEN="${FILT:+1}"
FILT="${FILT:-AUTO}"

# 追加到滤镜链末尾的可选处理(默认空: 不改 SAR, 不裁边)
VFILT_EXTRA="${VFILT_EXTRA:-}"

# AUDIO=copy  MKV 下保留原始 AC3 / DTS / MP2, 零重损失, 最快。
#             唯一例外: 源音轨是 LPCM(pcm_dvd) 时 Matroska 装不下(实测报
#             "No wav codec tag found for codec pcm_dvd"), 会自动转成 AAC
# AUDIO=aac   强制重编码成 AAC 192k(MP4 下强制用这个)
# AUDIO=flac  强制重编码成 FLAC, 无损, 体积约为 LPCM 的一半
AUDIO="${AUDIO:-copy}"

# MODE=ALL    每个 title 各出一个文件(默认, DVD/BD 一致)
# MODE=AUTO   自动扫描所有 title, 挑时长最长的那条当正片(需显式指定)
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
#  in_args <title>  ->  IN_DEMUX(数组) / IN_FILE: 这一条 title 到底喂什么给 ffmpeg
#    DVD: -f dvdvideo -title N + 整张镜像(解复用器自己挑 title)
#    BD : 直接喂那条 m2ts(mpegts 自动识别, 不用 -f)
# =========================================================================
in_args() {
    IN_DEMUX=()
    IN_FILE="$SRC"
    [ "$SRC_KIND" = "bd" ] || { IN_DEMUX=(-f dvdvideo -title "$1"); return 0; }
    if [ -n "$BD_ONE" ]; then IN_FILE="$BD_ONE"; return 0; fi
    local name="${BD_FILES[$(( $1 - 1 ))]:-}"
    [ -n "$name" ] || return 1
    IN_FILE="$BD_ROOT/BDMV/STREAM/$name"
    return 0
}

#  BDMV 下的流清单(按文件名排序), 一条 m2ts = 一个 title
#  为什么是 m2ts 而不是 mpls 播放列表: 播不了播放列表 —— 实测过的机器上没有一份
#  ffmpeg 带 bluray 解复用器; 而 m2ts 是普通 MPEG-TS, 任何构建都读得动。
bd_list() {
    BD_FILES=()
    if [ -n "$BD_ONE" ]; then
        BD_FILES=( "$(basename "$BD_ONE")" )
    else
        local d="$BD_ROOT/BDMV/STREAM" f
        [ -d "$d" ] || return 1
        while IFS= read -r f; do
            [ -n "$f" ] && BD_FILES+=("$f")
        done < <(cd "$d" && ls -1 2>/dev/null | grep -i '\.m2ts$' | LC_ALL=C sort)
    fi
    BD_N=${#BD_FILES[@]}
    [ "$BD_N" -gt 0 ]
}

# =========================================================================
#  probe_title <title>  ->  "宽 高 时长";  读不到则非 0
#  libdvdnav 那句 "Unable to open device file" 会打到 stderr, 是误报, 丢掉即可
# =========================================================================
DUR_UNKNOWN=""
probe_title() {
    local t="$1" wh dur
    in_args "$t" || return 1
    # 关键: libdvdread 的抱怨("CHECK_VALUE failed in src/nav_read.c" 之类)在这个
    # 构建里是打到**标准输出**的, 2>/dev/null 挡不住 —— 它比真正的数值先出现, 于是
    # 后面 awk '{print $3}' 取到的是 "failed", 时长算成 0, AUTO 模式一个 title 都选不中
    # (实测: 2026-09-29 这台机器上的 master build, 报 "一个 title 都没读到")。
    # 按形状过滤, 只留数值行并取最后一行 —— 与 .bat 侧 for /f 的"后读到的覆盖前面的"
    # 行为对齐, 两族结果才一致。
    # 按字段取, 不用行级正则: csv=p=0 打出来是 "720,576," 这种带尾逗号的形式,
    # tr 完变成 "720 576 " 有尾空格, 行级 ^...$ 匹配不上(实测踩过)
    wh="$(fp_run -v error ${IN_DEMUX[@]+"${IN_DEMUX[@]}"} \
          -select_streams v:0 -show_entries stream=width,height \
          -of csv=p=0 "$IN_FILE" 2>/dev/null \
          | tr -d '\r' | tr ',' ' ' | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {print $1, $2}' | tail -1)"
    [ -n "$wh" ] || return 1
    # 时长同样先 tr 掉逗号: 有的构建(Windows 真机那台)对单字段也打 "3300.500000," 这种
    # 带尾逗号的形式, 行级 ^...$ 匹配不上 -> dur 恒空 -> "读不到 title N" 全盘跑不动
    # (2026-09-29 本机用带尾逗号的替身 ffprobe 复现出来)
    dur="$(fp_run -v error ${IN_DEMUX[@]+"${IN_DEMUX[@]}"} \
           -show_entries format=duration -of csv=p=0 "$IN_FILE" 2>/dev/null \
           | tr -d '\r' | tr ',' ' ' | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ {print $1}' | tail -1)"
    # 时长读不出来记 0, 而不是判这条 title 读不到: 宽高已经探到说明 title 在, 缺时长
    # 只影响"挑最长那条"和体积估算(下面有 if 保护)。合成盘实测 format=duration 就是
    # N/A(2026-09-30), 按老写法脚本在第一条 title 处就 exit 1, 整盘压不了。
    [ -n "$dur" ] || { dur=0; DUR_UNKNOWN="${DUR_UNKNOWN:+$DUR_UNKNOWN,}$t"; }
    printf '%s %s\n' "$wh" "$dur"
}

#  <title> -> 该 title 视频流的帧率, 如 25/1 / 30000/1001; 读不到则空
#  过滤理由同 probe_title: libdvdread 的抱怨是打到标准输出的, 只能按形状挑
probe_rate() {
    in_args "$1" || return 1
    fp_run -v error ${IN_DEMUX[@]+"${IN_DEMUX[@]}"} \
           -select_streams v:0 -show_entries stream=r_frame_rate \
           -of csv=p=0 "$IN_FILE" 2>/dev/null \
        | tr ',' '\n' | grep -oE '^[0-9]+/[0-9]+$' | tail -1
}

#  <title> -> 该 title 所有音轨的 codec 名(空格分隔), 如 "ac3" / "pcm_dvd"; 读不到则空
probe_acodec() {
    in_args "$1" || return 1
    # 同上: 带尾逗号时 "ac3," 过不了 ^...$, LPCM 例外会静默失效
    fp_run -v error ${IN_DEMUX[@]+"${IN_DEMUX[@]}"} \
           -select_streams a -show_entries stream=codec_name \
           -of csv=p=0 "$IN_FILE" 2>/dev/null \
        | tr -d '\r' | tr ',' '\n' | grep -oE '^[a-z0-9_]+$' | tr '\n' ' '
}

# =========================================================================
#  源类型定案: .iso 到底是不是 DVD, 以及 BD 的两个默认值
# =========================================================================
if [ "$SRC_KIND" = "unknown" ]; then
    # 按 DVD 读得到就是 DVD; 读不到就是蓝光 —— 而蓝光在 POSIX 这边要 loop 挂载
    # (得 root), 脚本不擅自做, 把命令打给调用方
    if [ -n "$(probe_title 1 2>/dev/null)" ]; then
        SRC_KIND="dvd"
    else
        echo -e "\033[41;36m按 DVD-Video 读不到: 这是蓝光镜像, 请先挂载再把挂载点传进来\033[0m"
        echo "  Linux: sudo mkdir -p /mnt/bd && sudo mount -o loop \"$SRC\" /mnt/bd"
        echo "  macOS: hdiutil attach \"$SRC\""
        echo "  Windows: 用 ffmpeg_dvd_hevc.bat, 它会自动挂载并在结束时卸载"
        exit 1
    fi
fi

if [ "$SRC_KIND" = "bd" ]; then
    bd_list || { echo -e "\033[41;36mBDMV/STREAM 下没找到 .m2ts\033[0m"; exit 1; }
    TITLE_MAX="$BD_N"
    # BD 的 1080i 多是真隔行, DVD 那套 NTSC29 -> IVTC 会掉帧 —— 默认原样编码
    [ -n "$FILT_GIVEN" ] || FILT="NONE"
    echo "源类型   : Blu-ray（BDMV, m2ts 直读, 共 $BD_N 条）"
else
    TITLE_MAX=99
    echo "源类型   : DVD-Video（dvdvideo）"
fi

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
    # BEST 从 -1 起: 时长全读不出来(dur=0)时也要能选中第一条, 否则下面那句
    # "一个 title 都没读到" 会把整盘拦下
    BEST=-1; DVD_TITLE=""; MAIN=""; miss=0
    n=1
    while [ "$n" -le "$TITLE_MAX" ]; do
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
    # 同一张盘上各 title 分辨率一致, 用"第一条读得到的"定码率档位即可。
    # 不能死盯 title 1: BD 的 m2ts 里头几条常常没有视频流(实测 BD-M28 的 00007 /
    # 00008 / 00009 就是 1MB 上下的碎片), 盯死会在开跑前就把整盘拦下。
    MAIN=""; REF_TITLE=""
    n=1
    while [ "$n" -le "$TITLE_MAX" ]; do
        if MAIN="$(probe_title "$n" 2>/dev/null)"; then REF_TITLE="$n"; break; fi
        n=$(( n + 1 ))
    done
    [ -n "$REF_TITLE" ] || { echo -e "\033[41;36m一个 title 都没读到, 检查源路径 / 是否受保护\033[0m"; exit 1; }
fi
read -r SRC_W SRC_H SRC_DUR <<<"$MAIN"
if [ "${SRC_DUR:-0}" = 0 ]; then
    echo "正片: ${SRC_W}x${SRC_H}  时长读不出来(title ${DUR_UNKNOWN:-?}; 合成盘 / 无导航信息时常见, 只影响体积估算)"
else
    echo "正片: ${SRC_W}x${SRC_H}  时长 ${SRC_DUR}s"
fi
SRC_PIX=$(( SRC_W * SRC_H ))

# 制式 / 音轨探测用哪条 title: ALL 模式上面已经记下用来定码率档位的那条, 其余是正片那条
if [ "$MODE" != "ALL" ]; then REF_TITLE="$DVD_TITLE"; fi
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
    # 没有文件参数(-f null -), 改写是恒等的; 仍走 ff_run, 好让"有没有直调 $FF"
    # 这类检查可以直接 grep 出来, 不必逐个判断这一处到底有没有路径
    ff_run -hide_banner -v error -f lavfi -i testsrc2=s=320x240:r=25:d=1 \
          -c:v "$1" -frames:v 2 -f null - >/dev/null 2>&1
}

VENC_LIST_ALL="hevc_nvenc h264_nvenc av1_nvenc hevc_qsv h264_qsv av1_qsv libx265 libx264 libsvtav1"

venc_avail_list() {
    local e out=""
    for e in $VENC_LIST_ALL; do
        venc_usable "$e" && out="${out:+$out }$e"
    done
    # ${...} 里不能塞中文: 中文 Windows 的 MSYS2/Git Bash 会继承 LANG=zh_CN(GBK),
    # bash 按 GBK 解析 UTF-8 源码时会吞掉闭合引号 -> 整条语句变成语法错误
    # (2026-09-30 实测, 见 environment_matrix.md 第 58 条)。故用变量中转。
    [ -n "$out" ] || out="一个都没有"
    printf '%s' "$out"
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
    VBITRATE="$(bitrate_from_table "$BIT")"
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
        _rate_txt="${SRC_RATE:-}"; [ -n "$_rate_txt" ] || _rate_txt="读不到帧率"
        echo "源制式  : ${FSYS} @ ${_rate_txt}"
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
        # AUDIO=copy 下唯一例外: LPCM 装不进 Matroska(DVD 的 pcm_dvd 实测写头就失败
        # "No wav codec tag found for codec pcm_dvd"; BD 的 pcm_bluray 同样是 Invalid
        # argument), 撞上就自动转 AAC
        if [ "$AUDIO" = "copy" ]; then
            case "$SRC_ACODEC" in
                *pcm_dvd*|*pcm_bluray*)
                    AENC=(-c:a aac -b:a 192k)
                    echo "注意: 参考 title $REF_TITLE 的音轨是 LPCM, Matroska 装不下 -> 自动转 AAC 192k（要无损设 AUDIO=flac；ALL 模式下其余 title 逐条重新探测）"
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
        if [ "$SRC_KIND" = "bd" ]; then
            # BD 的字幕是 PGS, mp4 装不下: 实测 -c:s dvdsub 在 PGS 上写 trailer 就
            # 失败(rc=-22), 所以整条丢弃而不是让它炸
            echo "注意: BD 的 PGS 位图字幕装不进 MP4, 已丢弃全部字幕轨; 要保留请用 EXT=mkv"
            SENC=()
            SMAP=()
        fi
        ;;
    *)
        echo "EXT 只能是 mkv 或 mp4"
        exit 3
        ;;
esac

# AENC_BASE = 不含任何单条 title 音轨成分的基线 -c:a，每条 title 编码前据此重算
AENC_BASE=(${AENC[@]+"${AENC[@]}"})

# =========================================================================
#  enc <title> <输出名(无扩展)> [chapter_start] [chapter_end]
#  刻意不用 -ss: dvdvideo 解复用器 seek 后时间轴不可靠, 实测会让章节整体偏移,
#  靠 -chapter_start/-chapter_end 才是准的
# =========================================================================
#  按单条 title 的音轨重设全局 AENC
#  为什么不能只探一次: ALL / EXTRA_TITLES 会处理多条 title, 各条音轨可以不一样
#  (2026-10-01 实测 FRY001.ISO: title 1 = AC3 能 copy, title 2 = LPCM; 拿 title 1
#   的结果套 title 2 -> 写头失败 "No wav codec tag found for codec pcm_dvd")
#  只对 AUDIO=copy + MKV 生效: 其余组合的 -c:a 与源音轨无关, 不用逐条重探
# =========================================================================
set_aenc_for_title() {
    AENC=(${AENC_BASE[@]+"${AENC_BASE[@]}"})
    [ "$AUDIO" = "copy" ] || return 0
    [ "$EXT" = "mkv" ]    || return 0
    local tac
    tac="$(probe_acodec "$1" 2>/dev/null)"
    case "$tac" in
        *pcm_dvd*|*pcm_bluray*)
            AENC=(-c:a aac -b:a 192k)
            echo "  本条音轨是 LPCM -> 自动转 AAC 192k（要无损设 AUDIO=flac）"
            ;;
    esac
}

enc() {
    local t="$1" out="$2" cs="${3:-0}" ce="${4:-0}"
    in_args "$t" || { echo -e "\033[41;36mtitle $t 取不到输入文件\033[0m"; return 1; }
    set_aenc_for_title "$t"
    local chop=()
    [ "$cs" != "0" ] && chop+=(-chapter_start "$cs")
    [ "$ce" != "0" ] && chop+=(-chapter_end "$ce")

    echo "------------------------------------------------------------"
    echo "> title $t -> ${out}.${EXT}  ${chop[*]:-}"

    local CMD=(ff_run -y -hide_banner -v error -stats
               ${IN_DEMUX[@]+"${IN_DEMUX[@]}"} ${chop[@]+"${chop[@]}"})
    CMD+=(-i "$IN_FILE")
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
    OUT_FILES+=("${OUTDIR}/${out}.${EXT}")
    return 0
}

enc_extra() {
    local t="$1" out="$2"
    in_args "$t" || { echo -e "\033[41;36mtitle $t 取不到输入文件\033[0m"; return 1; }
    set_aenc_for_title "$t"
    echo "> 附加 title $t -> ${out}.${EXT}"
    local CMD=(ff_run -y -hide_banner -v error -stats
               ${IN_DEMUX[@]+"${IN_DEMUX[@]}"})
    CMD+=(-i "$IN_FILE")
    CMD+=(-map 0:V -map 0:a?)
    [ -n "$VFILT" ] && CMD+=(-vf "$VFILT")
    CMD+=(-c:v "$VENC_NAME")
    CMD+=(${VENC_ARGS[@]+"${VENC_ARGS[@]}"} ${AENC[@]+"${AENC[@]}"}
          "${OUTDIR}/${out}.${EXT}")
    "${CMD[@]}" || return 1
    OUT_FILES+=("${OUTDIR}/${out}.${EXT}")
    return 0
}

# ---------- 开跑 ----------
# 逐个跑完再统一判失败: 一个 title 挂掉不该让后面的特典连跑都不跑,
# 但退出码必须真的传出去(与 .bat 侧的 exit /b 1 对齐)。
RC=0
OUT_FILES=()      # 本次真正写出的产物, 结尾据此统计"产物合计"(比估算准)
ALL_DUR=0         # MODE=ALL 下各 title 时长之和(体积估算的正确口径)
N_TITLE=0
if [ "$MODE" = "ALL" ]; then
    MISS_MAX="${MISS_MAX:-5}"
    miss=0
    n=1
    while [ "$n" -le "$TITLE_MAX" ]; do
        # probe_title 顺带回了该 title 的时长, 这里攒起来而不是丢掉: 结尾的体积
        # 估算必须按"全部 title 合计"算 —— 只用 title 1 的时长会把一张 3 title
        # 的盘估成 5MB(2026-10-01 实测同一张盘实际产出 845MB)
        if line="$(probe_title "$n" 2>/dev/null)"; then
            miss=0
            ALL_DUR=$(( ALL_DUR + $(awk '{printf "%d", $3}' <<<"$line") ))
            N_TITLE=$(( N_TITLE + 1 ))
            # BD 用流文件名当产物名(00005.m2ts -> _00005): 比纯序号好认哪条是正片
            if [ "$SRC_KIND" = "bd" ]; then
                # %.* 而不是 %.m2ts: 实测真盘两种都有(BD-M28 是小写 .m2ts,
                # 规范与 tools/bd_make_sample.sh 出的夹具是大写 .M2TS), 写死小写
                # 时产物名会带着 .M2TS 后缀出去
                enc "$n" "${PREFIX}_${BD_FILES[$(( n - 1 ))]%.*}" || RC=1
            else
                enc "$n" "${PREFIX}_title${n}" || RC=1
            fi
        else
            miss=$(( miss + 1 ))
            [ "$miss" -ge "$MISS_MAX" ] && break
        fi
        n=$(( n + 1 ))
    done
else
    # BD 按 m2ts 直读, 章节写在 mpls 里拿不到; 而且 -chapter_start/-chapter_end 是
    # dvdvideo 专用选项, 喂给 mpegts 会被当成未知参数
    if [ "$SRC_KIND" = "bd" ] && [ "$SPLIT_CHAPTER" -gt 0 ]; then
        echo "注意: BD 直读 m2ts 拿不到章节（章节写在 mpls 里），SPLIT_CHAPTER 已忽略"
        SPLIT_CHAPTER=0
    fi
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

# 产物合计: 编码已经跑完, 直接统计本次真正写出的文件 —— 比按码率估准, 而且天然
# 覆盖 MODE=ALL 的每个 title / SPLIT_CHAPTER 的两段 / EXTRA_TITLES 的附加 title
if [ ${#OUT_FILES[@]} -gt 0 ]; then
    TOTAL_BYTES=0; N_OUT=0
    for f in "${OUT_FILES[@]}"; do
        [ -f "$f" ] || continue
        sz="$(wc -c <"$f" 2>/dev/null | tr -d ' ')"
        case "$sz" in ''|*[!0-9]*) continue ;; esac
        TOTAL_BYTES=$(( TOTAL_BYTES + sz ))
        N_OUT=$(( N_OUT + 1 ))
    done
    if [ "$N_OUT" -gt 0 ]; then
        echo " 产物合计: ${N_OUT} 个文件, $(( TOTAL_BYTES / 1048576 )) MB"
    fi
fi

# 体积估算: 时长口径必须是"本次实际处理的全部 title 合计"。MODE=ALL 下 SRC_DUR
# 只是拿来定码率档位的 title 1 的时长, 拿它估算会差两个数量级(实测 5MB vs 845MB)
if [ "$MODE" = "ALL" ]; then EST_DUR="$ALL_DUR"; else EST_DUR="${SRC_DUR:-}"; fi
if [ -n "$EST_DUR" ] && [ "$EST_DUR" != 0 ]; then
    DI="$(awk '{printf "%d", $1}' <<<"$EST_DUR")"
    # VBITRATE 可能是裸 bits/s, 也可能被覆盖成 "636k" / "2m"
    case "$VBITRATE" in
        *[kK]) VBN=$(( ${VBITRATE%[kK]} * 1000 )) ;;
        *[mM]) VBN=$(( ${VBITRATE%[mM]} * 1000000 )) ;;
        *)     VBN="$VBITRATE" ;;
    esac
    # 先 /1024 再乘时长, 避免大数(与 sh 的 64 位无关, 纯粹为了和 .bat 的 32 位
    # set /a 保持同一套算式, 两边结果才会一致)
    EST_MB=$(( VBN / 1024 * DI / 8192 ))
    if [ "$MODE" = "ALL" ]; then
        echo " 体积估算: 视频 ~$(( VBN / 1000 )) kbps x ${DI}s（${N_TITLE} 个 title 合计）≈ ${EST_MB} MB（另加音频）"
    else
        echo " 体积估算: 视频 ~$(( VBN / 1000 )) kbps x ${DI}s ≈ ${EST_MB} MB（另加音频）"
    fi
fi
echo ============================================================
exit 0
