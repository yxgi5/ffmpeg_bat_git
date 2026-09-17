#!/bin/bash
# lib/common.sh - ffmpeg_bat_git 公共函数库
# 各 ffmpeg_*.sh 通过 source 引用:
#   source "$(dirname "$(realpath "$0")")/lib/common.sh"

# 检查参数个数: 0 个返回 0(交互模式), 1 个返回 1, 多个报错退出
function check_param_number() {
    if [ "$1" -gt 1 ]; then
        echo -e "\033[41;36mMore than one parameter. A single file name or keep it blank!\033[0m"
        exit 1
    else
        if [ "$1" -eq 0 ]; then
            return 0
        else
            return 1
        fi
    fi
}

# 检查命令是否存在 PATH 中
function check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    else
        return 0
    fi
}

# ================================================================
# 一次性源探测缓存 (2026-09-17)
#
# 背景: 原先 7 个 check_file_* 各自起一条 ffprobe, 一个入口走完就是 7~8 个
# 独立进程; 每条还套着一个命令替换管道(tr -d '\r')。Windows/MSYS 下每次
# ffprobe 连 fork + exe 启动约 0.5s, 于是单次入口 9.7~10.6s 里约 5.5s 花在
# "问路"上, 真正编码只占 1.7s (实测 1080p60 2s 片源 / libx265 fast)。
# 冒烟套件是按"入口调用次数"放大这个成本的, 清单用例更是 条目数 x 单次。
#
# 做法: 合并成一次 `-of flat` 探测(键=值, 两族都好解析), 结果存进关联数组;
# 同一文件重复调用直接命中缓存(0 个新进程), 解析全部用 bash 内建
# (不再为每个字段起 tr/sed)。文件换了自动重探。
#
# 契约: 每个 check_file_* 的标准输出内容/返回码/退出码与改造前逐条对齐,
# 见各自函数注释里的"对照"说明。探针与 lint 都不依赖内部实现, 只依赖行为。
# ================================================================
declare -gA _PROBE=()
_PROBE_FILE=""
_PROBE_RC=0

# 探测并按文件路径缓存源元数据; 返回 ffprobe 的退出码(命中缓存时为上次的)
# 字段键名与 ffprobe flat 输出一致, 例如:
#   streams.stream.0.codec_name / .codec_type / .width / .height / .r_frame_rate / .bit_rate
#   format.size / format.duration / format.bit_rate
# -select_streams v:0 会把选中的流重新编号为 stream.0; 无视频流时 stream.* 整体缺失
# (只剩 format.*), 此时 rc 仍为 0 -- 与原实现 v:0 选择器下的表现一致。
function probe_source() {
    local f="$1" k v raw
    if [ "$_PROBE_FILE" = "$f" ]; then
        return "$_PROBE_RC"
    fi
    _PROBE_FILE="$f"
    _PROBE=()
    raw=$(ffprobe -v error -hide_banner -select_streams v:0 \
        -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,bit_rate:format=size,duration,bit_rate \
        -of flat "$f" 2>/dev/null)
    _PROBE_RC=$?
    raw="${raw//$'\r'/}"
    while IFS='=' read -r k v; do
        [ -n "$k" ] || continue
        _PROBE["$k"]="${v%\"}"
        _PROBE["$k"]="${_PROBE[$k]#\"}"
    done <<< "$raw"
    return "$_PROBE_RC"
}

# 检查文件是否存在, 不存在直接退出
function check_file_exists() {
    if ! [ -f "$1" ]; then
        echo -e "\033[41;36mfile not exists!\033[0m"
        exit 1
    fi
}

# 检查清单文件是否为纯文本, 否则退出
# 原各 list 脚本各自内联定义此函数, P1 重构时漏搬进公共库(调用点悬空), 此处统一补回
# 优先用 file --mime; 无 file 命令的环境(git-bash 常见)退化为 NUL 字节探测
function check_file_is_text() {
    local ft total bytes
    if check_command file; then
        ft=$(file --mime "$1" 2>/dev/null)
        [[ $ft == *text* ]] && return 0
    else
        total=$(wc -c < "$1")
        bytes=$(LC_ALL=C tr -d '\0' < "$1" | wc -c)
        [ "$bytes" -eq "$total" ] && return 0
    fi
    echo -e "\033[41;36mNot a plain text file!\033[0m"
    exit 1
}

# 检查文件是否为视频(含 video 流), 否则退出
# 退出码 3 = 无视频流, 与 .bat 侧 check_isvideo 调用点(exit /b 3)数值一致
# 对照: 原实现取"全部流"的 codec_type 找 video 子串; v:0 选择器下有视频流时
# 必有 streams.stream.0.codec_type="video", 无视频流时 stream.* 整体缺失,
# 两种输入的判定结果与原实现一致
function check_file_isvideo() {
    probe_source "$1"
    if [ "${_PROBE[streams.stream.0.codec_type]-}" = "video" ]; then
        return 0
    else
        echo -e "\033[41;36m$1 不是视频文件!\033[0m"
        exit 3
    fi
}

# 输出第一个视频流的编码名
# 注: 原实现写作 local x=$(ffprobe ... | tr -d '\r') 再接 `if [ "$?" -ne 0 ]`,
# 而 $? 取的是管道末尾 tr 的退出码, 所以那个报错分支从未触发过:
# 探测失败时它的实际行为是"输出空 + rc=0"。本轮改造承诺只换实现不改行为,
# 故此处沿用该实际行为。若哪天要让它真正报错(exit 1), 判 _PROBE_RC 即可。
function check_file_codec() {
    local codec
    probe_source "$1"
    codec="${_PROBE[streams.stream.0.codec_name]-}"
    echo "$codec"
    return 0
}

# 输出视频帧率(可能为分数形式如 30000/1001)
# 注: 原实现写作 local x=$(ffprobe ... | tr -d '\r') 再接 `if [ "$?" -ne 0 ]`,
# 而 $? 取的是管道末尾 tr 的退出码, 所以那个报错分支从未触发过:
# 探测失败时它的实际行为是"输出空 + rc=0"。本轮改造承诺只换实现不改行为,
# 故此处沿用该实际行为。若哪天要让它真正报错(exit 1), 判 _PROBE_RC 即可。
function check_file_framerate() {
    local framerate
    probe_source "$1"
    framerate="${_PROBE[streams.stream.0.r_frame_rate]-}"
    echo "$framerate"
    return 0
}

# 输出视频宽高(空格分隔单行: "1920 720")
# 对照: 原实现把 ffprobe 的两行输出 tr '\n' ' ' 再 sed 去尾空格, 得到
# "W H"(字段缺失时更短); 现在直接拼装并做同款去尾空格(纯内建, 不起进程)
# 注: 原实现写作 local x=$(ffprobe ... | tr -d '\r') 再接 `if [ "$?" -ne 0 ]`,
# 而 $? 取的是管道末尾 tr 的退出码, 所以那个报错分支从未触发过:
# 探测失败时它的实际行为是"输出空 + rc=0"。本轮改造承诺只换实现不改行为,
# 故此处沿用该实际行为。若哪天要让它真正报错(exit 1), 判 _PROBE_RC 即可。
function check_file_resolution() {
    local w h out
    probe_source "$1"
    w="${_PROBE[streams.stream.0.width]-}"
    h="${_PROBE[streams.stream.0.height]-}"
    out="$w $h"
    out="${out%"${out##*[! ]}"}"
    echo "$out"
    return 0
}

# 输出文件字节数, ffprobe 失败时回退 stat
function check_file_size() {
    local size

    probe_source "$1"
    size="${_PROBE[format.size]-}"

    if [ "$_PROBE_RC" -ne 0 ] || [ -z "$size" ]; then
        size=$(stat -c%s "$1" 2>/dev/null | tr -d '\r')
    fi

    if [ $? -ne 0 ] || [ -z "$size" ]; then
        echo -e "\033[41;36m$1 size检查出错！\033[0m"
        return 1
    fi

    echo "$size"
    return 0
}

# 输出视频时长(秒, 浮点)
# 注: 原实现写作 local x=$(ffprobe ... | tr -d '\r') 再接 `if [ "$?" -ne 0 ]`,
# 而 $? 取的是管道末尾 tr 的退出码, 所以那个报错分支从未触发过:
# 探测失败时它的实际行为是"输出空 + rc=0"。本轮改造承诺只换实现不改行为,
# 故此处沿用该实际行为。若哪天要让它真正报错(exit 1), 判 _PROBE_RC 即可。
function check_file_duration() {
    local duration
    probe_source "$1"
    duration="${_PROBE[format.duration]-}"
    echo "$duration"
    return 0
}

# 输出码率(bps), 优先视频流码率, 回退容器码率, 均无效时输出 0 并返回 1
function check_file_bitrate() {
    local bitrate

    probe_source "$1"

    bitrate="${_PROBE[streams.stream.0.bit_rate]-}"
    if [ -z "$bitrate" ] || ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
        bitrate="${_PROBE[format.bit_rate]-}"
    fi

    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
        echo 0
        return 1
    fi

    echo "$bitrate"
    return 0
}

# 码率查表: 按像素总数返回目标码率(bps)
# 数据文件 lib/ 下, 格式: max_pixels,bitrate (按阈值升序):
#   bitrate_table_hevc.csv  HEVC power-law 模型 (源自 bitrate_calc.xlsx output 页 G 列, 去重后 94 项)
#   bitrate_table_avc.csv   AVC  模型 (源自同页 H 列 H7~H105)
#   bitrate_table_av1.csv   AV1  模型 (HEVC 表按分辨率档位打折)
# 查到输出码率并返回 0; 超出表范围或文件缺失输出空并返回 2
function lookup_bitrate() {
    # 用法: lookup_bitrate <像素总数> [csv文件名]
    #   csv 文件名可选, 默认 bitrate_table_hevc.csv;
    #   AVC 编码传入 bitrate_table_avc.csv, AV1 编码传入 bitrate_table_av1.csv
    local pixels="$1"
    local csv_name="${2:-bitrate_table_hevc.csv}"
    local csv_file result

    csv_file="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/${csv_name}"

    if [ ! -f "$csv_file" ]; then
        echo -e "\033[41;36m${csv_name} not found: $csv_file\033[0m" >&2
        return 2
    fi

    result=$(awk -F',' -v p="$pixels" '
        NR > 1 && $1 != "" && p <= $1 { print $2; exit }
    ' "$csv_file")

    if [ -z "$result" ]; then
        return 2
    fi

    echo "$result"
    return 0
}

# 对清单文件逐行执行指定脚本 (P1 重构新增)
# 用法: run_list <清单文件> <目标脚本路径>
# 说明: 用 while read 替代旧的 for line in $(cat ...) 写法, 兼容含空格的文件名; 空行跳过; 任一行失败立即退出
#       兼容 Windows 记事本清单: 去行尾 CR(CRLF) 与首行 BOM, 否则 \r 会被当成文件名的一部分
#       子进程 stdin 必须重定向到 /dev/null: 循环体以 "done < $list_file" 提供输入,
#       子进程继承该 fd 后, Linux 版 ffmpeg 会从 stdin 读走 1 字节(键盘交互探测,
#       实测 native 4.4.2 与 master-git 均有此行为, ffprobe 无), 结果是清单第 2 条
#       起路径被吃掉开头字符 -> file not exists! 提前退出
function run_list() {
    local list_file="$1"
    local script="$2"
    local line first=1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [ "$first" -eq 1 ]; then
            line="${line#$'\xEF\xBB\xBF'}"
            first=0
        fi
        [ -z "$line" ] && continue
        echo "$line"
        bash "$script" "$line" < /dev/null
        if [ $? -ne 0 ]; then
            echo -e "\033[41;36mConvert failed！\033[0m"
            exit 1
        fi
    done < "$list_file"
}
