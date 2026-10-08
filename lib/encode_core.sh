#!/bin/bash
# lib/encode_core.sh - 编码入口的公共内核 (TODO.md 阶段 0)
#
# 由 9 个编码入口共用: libx264 / libx265、avc_qsv / hevc_qsv / av1_qsv、
# hevc_nvenc / av1_nvenc、avc_vaapi / hevc_vaapi。
# 抽这块之前它们是 9 份 ~200 行副本(彼此只差 18~33 行), 现在入口里只剩:
#   source 两份 lib + parse_switches + --help 文案 + enc_run <enc> "$@"
#
# 编码器之间的全部差异压成"两张表 + 三个钩子":
#   表1  enc_ffenc / enc_table   编码器 -> ffmpeg 能力筛选名 / 码率表 csv
#   表2  enc_vargs               编码器 -> -c:v:0 系列
#   钩子1 enc_dec_args           解码 / 设备初始化(含 -i 与 -vf 的相对位置)
#   钩子2 enc_gate               硬件能力门(不可用 -> 退出码 4)
#   钩子3 enc_prefer_newbuild    是否把 /opt 下的新构建前置到 PATH
# 另有 enc_tail_args 承担"软编才有的 -sws_flags bicubic"这一处小差异。
#
# 依赖 lib/common.sh 的这些函数(入口已先 source 它):
#   parse_switches / init_ext / check_param_number / check_file_* /
#   find_ffmpeg / find_ffmpeg_for_encoder / find_ffprobe / ffmpeg_build_id /
#   lookup_bitrate / bitrate_from_table / cover_map_gate / ff_run /
#   src_is_10bit / src_hw_decode_hostile / qsv_encoder_ready
#
# 阶段 1 会再加 enc_key=copy(转封装, 无码率表 + moov 前置, 见 TODO.md §6 第 4 项);
# 那时 enc_run 需要给 copy 留三个位: 跳过码率段 / 输出名不带 -compressed /
# 源已是目标容器即退出。公共流程现在**不能**假设"一定有码率表"。

# ---------------------------------------------------------------- 表1: 能力筛选名 + 码率表
# enc_ffenc: 传给 find_ffmpeg_for_encoder 的编码器名。注意 avc_* 这一族在 ffmpeg
#   里叫 h264_*(h264_qsv / h264_vaapi / h264_nvenc), 入口名与编码器名对不上。
function enc_ffenc() {
    case "$1" in
        avc_qsv)   echo "h264_qsv" ;;
        avc_vaapi) echo "h264_vaapi" ;;
        avc_nvenc) echo "h264_nvenc" ;;
        *)         echo "$1" ;;
    esac
}

# enc_table: 该编码器用哪张码率表。映射与 lint 的 P02 family_table(codec) 同源:
#   avc 族 -> bitrate_table_avc.csv, av1 族 -> bitrate_table_av1.csv,
#   其余(hevc 族 + 软编 libx265) -> bitrate_table_hevc.csv(lookup_bitrate 的默认值)。
function enc_table() {
    case "$1" in
        libx264|avc_qsv|avc_vaapi)    echo "bitrate_table_avc.csv" ;;
        av1_qsv|av1_nvenc)            echo "bitrate_table_av1.csv" ;;
        *)                            echo "bitrate_table_hevc.csv" ;;
    esac
}

# ---------------------------------------------------------------- 表2: 编码参数
# 直接往调用方的 CMD 数组追加(不 echo 字符串再切词, 免得 profile 名里的空格踩坑)。
# 依赖全局 $TARGET_BITRATE。
function enc_vargs() {
    case "$1" in
        libx264)
            CMD+=(-c:v:0 libx264 -profile:v:0 high -preset fast -b:v "$TARGET_BITRATE")
            # 软编要显式钉住像素格式与色彩标签, 否则 libx264 会按源猜
            CMD+=(-pix_fmt yuv420p -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709)
            ;;
        libx265)
            CMD+=(-c:v:0 libx265 -profile:v:0 main -preset fast -b:v "$TARGET_BITRATE")
            CMD+=(-pix_fmt nv12 -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709)
            ;;
        avc_qsv)
            CMD+=(-c:v:0 h264_qsv -profile:v:0 main -preset veryfast -b:v "$TARGET_BITRATE")
            ;;
        hevc_qsv)
            CMD+=(-c:v:0 hevc_qsv -profile:v:0 main -preset veryfast -b:v "$TARGET_BITRATE")
            ;;
        av1_qsv)
            CMD+=(-c:v:0 av1_qsv -profile:v:0 main -preset fast -b:v "$TARGET_BITRATE")
            ;;
        hevc_nvenc)
            CMD+=(-c:v:0 hevc_nvenc -profile:v:0 main -preset p4 -tune:v hq -rc cbr -b:v "$TARGET_BITRATE")
            ;;
        av1_nvenc)
            # av1_nvenc 不接受 -profile:v:0(实测报未知参数), 所以这行比 hevc_nvenc 少一段
            CMD+=(-c:v:0 av1_nvenc -preset p4 -tune:v hq -rc cbr -b:v "$TARGET_BITRATE")
            ;;
        avc_vaapi)
            CMD+=(-c:v:0 h264_vaapi -profile:v:0 main -b:v "$TARGET_BITRATE")
            ;;
        hevc_vaapi)
            CMD+=(-c:v:0 hevc_vaapi -profile:v:0 main -b:v "$TARGET_BITRATE")
            ;;
        *)
            echo "enc_vargs: 不认识的编码器 '$1'" >&2
            return 1
            ;;
    esac
}

# GOP + 音频尾巴。只有软编多一个 -sws_flags bicubic(硬件链路上 scaling 滤镜由
# scale_qsv / scale_vaapi 负责, 再给 -sws_flags 反而会打架)。
function enc_tail_args() {
    CMD+=(-g 250 -keyint_min 25)
    case "$1" in
        libx264|libx265) CMD+=(-sws_flags bicubic) ;;
    esac
    CMD+=(-ar 44100 -b:a 128k -c:a aac -ac 2)
}

# ---------------------------------------------------------------- 钩子1: 解码 / 设备初始化
# 负责从 CMD 头一路建到 -i 之后(含输出滤镜)。三种拓扑:
#   软编   : 可选 -hwaccel, 不加设备初始化
#   qsv    : -init_hw_device qsv=hw + 硬解/软解二选一 + 10bit 降位
#   vaapi  : -init_hw_device 只在"改软解"分支才需要(硬解走 -vaapi_device)
#   nvenc  : 只用 cuda, 不碰任何 QSV 设备(旧版残留 -init_hw_device 在 cygwin
#            ffmpeg 下会因 MFX 会话创建失败直接报错, 且对 nvenc 流程毫无作用)
# 依赖全局 $FF / $ABS_NAME / $SRC_FRAMERATE。$SRC_FRAMERATE 的 -r 30 收敛在这里收尾,
# 保证它排在输入选项之后、编码参数之前(ffmpeg 的位置敏感点)。
function enc_dec_args() {
    local enc="$1"
    CMD=("$FF" -hide_banner -threads 0 -v verbose)
    case "$enc" in
        libx264|libx265)
            # CPU 软编码, 不依赖任何硬件加速器; -hwaccel auto 仅用于解码加速, 失败自动回退软解
            # 解码加速器可配置: FF_HWACCEL=none(默认, 2026-10-05 改: 软编实时显示进度,
            #   不再吞 stderr) / cuda / qsv / vaapi / d3d11va / dxva2 / none。
            # 原先写死 auto —— 由 ffmpeg 挑第一个能初始化的(核显与 N 卡并存时选谁不可控),
            #   且锁屏/断开会话下 D3D 会直接崩; ff_run 里那条回退只认字面量 auto
            #   (见 lib/common.sh), 显式指定时不再回退。纯 N 卡机器可钉成 cuda;
            #   想彻底不碰硬件设 none(一次 -hwaccel 都不加)。只影响解码, 编码器仍是本入口的。
            if [ "${FF_HWACCEL:-none}" != none ]; then
                CMD+=(-hwaccel "${FF_HWACCEL:-auto}")
            fi
            CMD+=(-i "$ABS_NAME")
            ;;
        avc_qsv|hevc_qsv|av1_qsv)
            # QSV 解码+编码流程需要显式初始化 QSV 设备
            CMD+=(-init_hw_device qsv=hw -filter_hw_device hw)
            # 10bit 源: 两种症状, 两种修法(2026-09-30 实测):
            # ① H.264 High 10(profile 110): 卡在**解码**侧 —— QSV 的 H.264 解码器不吃 High 10,
            #    硬解一挂帧退回系统内存, 编码器要硬件表面 -> auto_scale 接不上 -> rc=1 / 0 字节。
            #    修法: 这种源**不用硬解**, 软解后 hwupload 送上去。
            # ② HEVC Main10 等: 硬解正常(帧已在 QSV 表面), 但 hevc_qsv -profile main(8bit) 吃不
            #    下 10bit 输入 -> 编码器报错 / 产物异常。修法: 在 QSV 硬件内部 scale_qsv=format=nv12
            #    降到 8bit。不能用软滤镜 format=nv12(帧在硬件表面, auto_scale 照样接不上)。
            # 判据与另一情形的区别见 lib/common.sh 的 src_is_10bit / src_hw_decode_hostile。
            # -hwaccel 是**输入选项**, 必须排在 -i 之前; -vf 是输出滤镜, 排在 -i 之后。
            local HW_DEC=1
            if src_hw_decode_hostile "$ABS_NAME"; then
                HW_DEC=0
                echo "H.264 High 10 源 -> QSV 硬解不支持, 改软解 + hwupload"
            else
                CMD+=(-hwaccel qsv -hwaccel_output_format qsv)
            fi
            CMD+=(-i "$ABS_NAME")
            if [ "$HW_DEC" = 0 ]; then
                CMD+=(-vf "format=nv12,hwupload=extra_hw_frames=64")
            elif src_is_10bit "$ABS_NAME"; then
                echo "10bit 源 -> scale_qsv=format=nv12 (QSV 硬件内降 8bit)"
                CMD+=(-vf "scale_qsv=format=nv12")
            fi
            ;;
        avc_vaapi|hevc_vaapi)
            # VAAPI 解码+编码需要显式指定渲染设备 (仅 Linux 可用)
            # 10bit 源: 两种症状, 两种修法(与 qsv 同源, 判据函数共用):
            # ① H.264 High 10 卡在**解码**侧("Codec h264 profile 110 not supported for
            #    hardware decode.") -> 改软解再 hwupload。
            # ② HEVC Main10 硬解正常、卡在**编码**侧(本族写死 -profile:v:0 main, Main 不吃
            #    10bit) -> scale_vaapi=format=nv12 在 VAAPI 硬件内降到 8bit。
            # 8bit 源的命令行一字不改。
            local HW_DEC=1
            if src_hw_decode_hostile "$ABS_NAME"; then
                HW_DEC=0
                echo "H.264 High 10 源 -> VAAPI 硬解不支持, 改软解 + hwupload"
                CMD+=(-init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va)
            else
                CMD+=(-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128)
            fi
            CMD+=(-i "$ABS_NAME")
            if [ "$HW_DEC" = 0 ]; then
                CMD+=(-vf "format=nv12,hwupload")
            elif src_is_10bit "$ABS_NAME"; then
                echo "10bit 源 -> scale_vaapi=format=nv12 (VAAPI 硬件内降 8bit)"
                CMD+=(-vf "scale_vaapi=format=nv12")
            fi
            ;;
        hevc_nvenc|av1_nvenc)
            CMD+=(-hwaccel cuda -hwaccel_output_format cuda)
            CMD+=(-i "$ABS_NAME")
            ;;
        *)
            echo "enc_dec_args: 不认识的编码器 '$1'" >&2
            return 1
            ;;
    esac

    # 高帧率源统一收敛到 30(必须在 -i 之后: -r 是输出选项)
    if [ "$SRC_FRAMERATE" -gt 31 ]; then
        CMD+=(-r 30)
        echo "DOWN TARGET FRAME RATE TO 30"
    fi
}

# ---------------------------------------------------------------- 钩子2: 硬件能力门
# 有编码器 != 硬件支持。返回 0 = 可用, 1 = 本机打不开(enc_run 据此 exit 4)。
function enc_gate() {
    case "$1" in
        av1_qsv)
            # ffmpeg -encoders 里列着 av1_qsv, 但 UHD 770 一开编码器就是
            #   [av1_qsv @ ...] Current codec type is unsupported
            #   some encoding parameters are not supported by the QSV runtime.
            #   Error while opening encoder ... rc=-40
            # 跑到底的结果是命令行看着"跑过了", 却只留下一个 0 字节的 mp4。所以在动源文件
            # 之前先拿 1 帧 lavfi 源试开一次: 开不起来就把原因说清楚, 不产空文件。
            # (AV1 QSV 需要 Arrow Lake 及更新的核显; 冒烟套件对它的 SKIP 判定是同一件事,
            #  那边靠先跑一遍整个入口, 这里把判断搬进入口, 直接跑入口时也能得到明确结论。)
            if ! qsv_encoder_ready av1_qsv; then
                echo -e "\033[43;30m本机没有可用的 AV1 QSV 编码器(需 Arrow Lake 或更新的核显) —— 未生成产物\033[0m"
                return 1
            fi
            ;;
    esac
    return 0
}

# ---------------------------------------------------------------- 钩子3: 新构建优先
# 发行版那份 ffmpeg 常缺新硬件编码器 / 有已修的 bug, 若 /opt 下有新构建就前置 PATH。
# 软偏好: 目录不存在就什么都不做, 回退发行版。
function enc_prefer_newbuild() {
    case "$1" in
        av1_qsv)
            # 发行版 ffmpeg 常缺 av1 硬编编码器
            ;;
        hevc_vaapi)
            # 发行版 4.4.2 实测报 "Failed to end picture encode issue: 24", 新版构建实测通过
            ;;
        *)
            return 0
            ;;
    esac
    case "$(uname -s)" in
        Linux*)
            if [ -d /opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin ]; then
                export PATH=/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin:$PATH
            fi
            ;;
    esac
}

# ---------------------------------------------------------------- 公共主流程
# 用法: enc_run <enc> "$@"    (<enc> 见表1/表2 的 case 分支; "$@" 是源文件, 0 或 1 个)
# 退出码契约见 test/README.md §5.2: 1 参数/输入/找不到 ffmpeg/转码失败 / 2 码率查表未命中
# / 3 输入不是视频 / 4 硬件缺失 / 5 码率异常。
function enc_run() {
    local enc="$1"
    shift

    echo ============================================================
    echo 欢迎使用ffmpeg视频压缩批处理工具
    echo
    echo 由 andreas 编写
    echo ============================================================

    # ---------- 输出容器开关 EXT: mp4(默认) / mkv ----------
    # 默认值写在 lib/defaults.cfg(两族共用一份), 校验 / 去空白 / -c:s 的选法统统在
    # lib/common.sh 的 init_ext 里 —— 加容器、改默认都只动那一处, 入口不再各写一遍。
    # 命令行 EXT=mkv 优先于配置文件(load_defaults 只补没设过的键)。
    init_ext || exit 1

    # ---------- 新构建优先(必须在 find_ffmpeg 之前) ----------
    enc_prefer_newbuild "$enc"

    # ---------- 前置检查 ----------
    # ffmpeg 定位走 lib/common.sh 的 find_ffmpeg, 与 .bat 侧同序:
    #   FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH 逐项 > 常见前缀
    # 不能只信 command -v: 它只回第一个命中, 而"第一个"经常正是缺能力的那个
    #   (Linux 上就是发行版那份 4.4.2), 后面那个能用的构建于是永远轮不到
    # find_ffmpeg_for_encoder 先按"必须带 <enc> 编码器"筛 —— 发行版 ffmpeg 常缺它,
    #   能用的那份往往在 /opt 下且不在 PATH 上; 谁都没有时退回不筛选(保持原有报错路径)
    local ffenc
    ffenc="$(enc_ffenc "$enc")"
    if ! FF="$(find_ffmpeg_for_encoder "$ffenc")"; then
        echo -e "\033[41;36mffmpeg command not found!\033[0m"
        exit 1
    fi
    if ! FP="$(find_ffprobe "$FF")"; then
        echo -e "\033[41;36mffprobe command not found!\033[0m"
        exit 1
    fi
    export FF FP
    echo "ffmpeg : $FF ($(ffmpeg_build_id "$FF"))"

    check_param_number "$#"
    local param_number=$?

    # ---------- 输入文件 ----------
    local SRC_FILE
    if [ "$param_number" -eq 0 ]; then
        echo "请输入待压缩视频地址: "
        read -r SRC_FILE
    else
        SRC_FILE="$1"
    fi

    check_file_exists "$SRC_FILE"
    check_file_isvideo "$SRC_FILE"

    # ---------- 源视频信息 ----------
    local SRC_CODEC
    SRC_CODEC=$(check_file_codec "$SRC_FILE")

    local SRC_FRAMERATE
    SRC_FRAMERATE=$(check_file_framerate "$SRC_FILE")
    if [[ $SRC_FRAMERATE == *"/"* ]]; then
        local ratenum=${SRC_FRAMERATE%%/*}
        local rateden=${SRC_FRAMERATE##*/}
        SRC_FRAMERATE=$(( ratenum / rateden ))
    fi

    # check_file_resolution 已归一为空格分隔单行("1280 720")
    local SRC_RESOLUTION
    SRC_RESOLUTION=$(check_file_resolution "$SRC_FILE")
    local SRC_W SRC_H
    read -r SRC_W SRC_H <<< "$SRC_RESOLUTION"
    echo "SRC_W: $SRC_W"
    echo "SRC_H: $SRC_H"

    local SRC_PIX=$(( SRC_W * SRC_H ))

    local SRC_SIZE SRC_DURATION SRC_BITRATE
    SRC_SIZE=$(check_file_size "$SRC_FILE")
    SRC_DURATION=$(check_file_duration "$SRC_FILE")
    SRC_BITRATE=$(check_file_bitrate "$SRC_FILE")

    # 码率兜底: check_file_bitrate 已优先 stream.bit_rate, 再 format.bit_rate;
    #          均无效则按 文件大小*8/时长 估算(需有效时长)
    if ! [[ "$SRC_BITRATE" =~ ^[0-9]+$ ]] || [ "$SRC_BITRATE" -le 0 ]; then
        local DURATION_INT=$(printf "%.0f" "$SRC_DURATION" 2>/dev/null || echo 0)
        if [ "${DURATION_INT:-0}" -gt 0 ]; then
            SRC_BITRATE=$(( SRC_SIZE * 8 / DURATION_INT ))
        fi
    fi

    # 时长兜底: format.duration 不可用时, 用 size*8/bitrate 反推(需有效码率)
    if ! [[ "$SRC_DURATION" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(printf '%.0f' "$SRC_DURATION" 2>/dev/null || echo 0)" -le 0 ]; then
        if [[ "$SRC_BITRATE" =~ ^[0-9]+$ ]] && [ "$SRC_BITRATE" -gt 0 ]; then
            DURATION_INT=$(( SRC_SIZE * 8 / SRC_BITRATE ))
            [ "$DURATION_INT" -gt 0 ] && SRC_DURATION="$DURATION_INT"
        fi
    fi

    echo "SRC_BITRATE: $SRC_BITRATE"

    # ---------- 码率查表 ----------
    local BIT
    BIT=$(lookup_bitrate "$SRC_PIX" "$(enc_table "$enc")")
    if [ $? -ne 0 ] || [ -z "$BIT" ]; then
        echo -e "\033[41;36mManual handle it!\033[0m"
        exit 2
    fi

    # 目标码率口径在同一处: BITRATE_NO_HALF=1 时跳过 /2(见 lib/common.sh)
    local TARGET_BITRATE
    TARGET_BITRATE=$(bitrate_from_table "$BIT")
    echo "ref TARGET_BITRATE: $TARGET_BITRATE"

    local percentage
    if [ "${SRC_BITRATE:-0}" -gt 0 ]; then
        percentage=$(( TARGET_BITRATE * 100 / SRC_BITRATE ))
        echo "compress percentage: ${percentage}%"
        if [ "$percentage" -ge 100 ]; then
            TARGET_BITRATE=$SRC_BITRATE
        fi
    else
        percentage=0
        echo "compress percentage: N/A (源码率未知)"
    fi

    # 码率异常: 退出码 5, 与 .bat 侧(exit /b 5)数值一致
    if [ "$TARGET_BITRATE" -le 0 ]; then
        echo "bitrate abnormal, please check"
        echo -e "\033[41;36mbitrate abnormal, please check\033[0m"
        exit 5
    fi

    # ---------- 交互模式可覆盖码率 ----------
    if [ "$param_number" -eq 0 ]; then
        echo "请输入输出码率(如1150k,不输入则保持默认): "
        local TARGET_BITRATE_1
        read -r TARGET_BITRATE_1
        if [ -n "$TARGET_BITRATE_1" ]; then
            TARGET_BITRATE="$TARGET_BITRATE_1"
        fi
    fi
    echo "real TARGET_BITRATE = $TARGET_BITRATE"

    # ---------- 输出路径 ----------
    echo "SRC_FILE: $SRC_FILE"
    local ABS_NAME ABS_PATH filename filename_without_suffix TARGET_FILE
    ABS_NAME=$(realpath "$SRC_FILE")
    ABS_PATH=$(dirname "$ABS_NAME")
    filename=$(basename "$ABS_NAME")
    filename_without_suffix="${filename%.*}"
    TARGET_FILE="${ABS_PATH}/${filename_without_suffix}-compressed.${EXT}"

    echo "ABS_NAME: ${ABS_NAME}"
    echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"

    # ---------- 硬件能力门: 有编码器 != 硬件支持 ----------
    if ! enc_gate "$enc"; then
        # 退出码 4 = 硬件缺失(契约见 test/README 5.2), 与"转码失败"(1)分开:
        #   前者对清单里每一个文件都成立, convert_from_list_* 因此直接中止而不是
        #   逐条重试; 后者只是这一个文件的问题。
        exit 4
    fi

    # ---------- 构建并执行 ffmpeg 命令 (数组, 无 eval) ----------
    CMD=()
    enc_dec_args "$enc" || exit 1
    enc_vargs "$enc" || exit 1
    enc_tail_args "$enc"
    cover_map_gate "$FF"
    # EXT=mkv 时字幕默认原样复制(-c:s copy): mkv 装得下位图字幕, 比 mp4 少丢东西。
    # 唯一例外是源里带 mov_text —— mp4 的软字幕格式, matroska 装不下, 实测
    # -c:s copy 在这里直接 rc=-40 / 0 字节 —— 所以这种源把文本字幕转成 ass。
    # CM_MOV 由上面的封面闸门顺路数出来, 没有额外起 ffprobe。
    # SENC 的初值是 init_ext 给的(mp4 -> -c:s mov_text, mkv -> -c:s copy), 这里
    # 只在"mkv 且源里有 mov_text"时改写它。**别把它声明成 local** —— 那样会把
    # init_ext 设的全局值清空, 产物直接丢掉字幕流参数。
    if [ "$EXT" = mkv ] && [ "${CM_MOV:-0}" = 1 ]; then SENC=(-c:s ass); fi
    CMD+=(-map 0:V -map 0:a? -map 0:s? ${COVER_MAP[@]+"${COVER_MAP[@]}"} "${SENC[@]}" -map_metadata 0 -map_chapters 0)
    CMD+=(-rtbufsize 120m -max_muxing_queue_size 1024 -n "$TARGET_FILE")

    printf 'RUN_COM:'
    printf ' %q' "${CMD[@]}"
    printf '\n'

    # 走 ff_run 而不是直接执行数组: 它会把以 / 开头的参数改写成原生路径
    # (Cygwin/MINGW64 下选到原生 Windows 构建时, POSIX 路径会 No such file); Linux 上恒等
    ff_run "${CMD[@]:1}"
    if [ $? -ne 0 ]; then
        echo -e "\033[41;36mConvert failed！\033[0m"
        exit 1
    fi
}