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
# 探测失败(文件不存在/ffprobe 自身出错, _PROBE_RC != 0)时: 打印错误并 exit 1。
# 这是 2026-09-17 用户裁定修复的"假判据": 原实现写作 local x=$(ffprobe ... | tr)
# 再接 `if [ "$?" -ne 0 ]`, 而 $? 取的是管道末尾 tr 的退出码, 报错分支从未触发过,
# 探测失败一直被静默成"输出空 + rc=0"。现在判 _PROBE_RC, 让该分支真正生效。
# 注意: 入口以 SRC_X=$(check_file_...) 捕获且不查 rc, exit 1 只退出命令替换子 shell --
# 对入口而言失败后果与从前相同(变量为空、后续 set -a 出错), 差别只在多一条可见报错。
function check_file_codec() {
    local codec
    probe_source "$1"
    if [ "$_PROBE_RC" -ne 0 ]; then
        echo -e "\033[41;36m$1 codec检查出错！\033[0m"
        exit 1
    fi
    codec="${_PROBE[streams.stream.0.codec_name]-}"
    echo "$codec"
    return 0
}

# 输出视频帧率(可能为分数形式如 30000/1001)
# 探测失败(文件不存在/ffprobe 自身出错, _PROBE_RC != 0)时: 打印错误并 exit 1。
# 这是 2026-09-17 用户裁定修复的"假判据": 原实现写作 local x=$(ffprobe ... | tr)
# 再接 `if [ "$?" -ne 0 ]`, 而 $? 取的是管道末尾 tr 的退出码, 报错分支从未触发过,
# 探测失败一直被静默成"输出空 + rc=0"。现在判 _PROBE_RC, 让该分支真正生效。
# 注意: 入口以 SRC_X=$(check_file_...) 捕获且不查 rc, exit 1 只退出命令替换子 shell --
# 对入口而言失败后果与从前相同(变量为空、后续 set -a 出错), 差别只在多一条可见报错。
function check_file_framerate() {
    local framerate
    probe_source "$1"
    if [ "$_PROBE_RC" -ne 0 ]; then
        echo -e "\033[41;36m$1 framerate检查出错！\033[0m"
        exit 1
    fi
    framerate="${_PROBE[streams.stream.0.r_frame_rate]-}"
    echo "$framerate"
    return 0
}

# 输出视频宽高(空格分隔单行: "1920 720")
# 对照: 原实现把 ffprobe 的两行输出 tr '\n' ' ' 再 sed 去尾空格, 得到
# "W H"(字段缺失时更短); 现在直接拼装并做同款去尾空格(纯内建, 不起进程)
# 探测失败(文件不存在/ffprobe 自身出错, _PROBE_RC != 0)时: 打印错误并 exit 1。
# 这是 2026-09-17 用户裁定修复的"假判据": 原实现写作 local x=$(ffprobe ... | tr)
# 再接 `if [ "$?" -ne 0 ]`, 而 $? 取的是管道末尾 tr 的退出码, 报错分支从未触发过,
# 探测失败一直被静默成"输出空 + rc=0"。现在判 _PROBE_RC, 让该分支真正生效。
# 注意: 入口以 SRC_X=$(check_file_...) 捕获且不查 rc, exit 1 只退出命令替换子 shell --
# 对入口而言失败后果与从前相同(变量为空、后续 set -a 出错), 差别只在多一条可见报错。
function check_file_resolution() {
    local w h out
    probe_source "$1"
    if [ "$_PROBE_RC" -ne 0 ]; then
        echo -e "\033[41;36m$1 resolution检查出错！\033[0m"
        exit 1
    fi
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
# 探测失败(文件不存在/ffprobe 自身出错, _PROBE_RC != 0)时: 打印错误并 exit 1。
# 这是 2026-09-17 用户裁定修复的"假判据": 原实现写作 local x=$(ffprobe ... | tr)
# 再接 `if [ "$?" -ne 0 ]`, 而 $? 取的是管道末尾 tr 的退出码, 报错分支从未触发过,
# 探测失败一直被静默成"输出空 + rc=0"。现在判 _PROBE_RC, 让该分支真正生效。
# 注意: 入口以 SRC_X=$(check_file_...) 捕获且不查 rc, exit 1 只退出命令替换子 shell --
# 对入口而言失败后果与从前相同(变量为空、后续 set -a 出错), 差别只在多一条可见报错。
function check_file_duration() {
    local duration
    probe_source "$1"
    if [ "$_PROBE_RC" -ne 0 ]; then
        echo -e "\033[41;36m$1 duration检查出错！\033[0m"
        exit 1
    fi
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

# ================================================================
# ffmpeg / ffprobe 定位 (2026-09-20)
#
# 背景: sh 侧此前一律依赖 PATH 上的裸 `ffmpeg`, 而 bat 侧早就有四级回退
# (:find_ffmpeg in lib/common.bat)。同一台 Windows 机器上三种 shell 会解析到
# 三个不同的 ffmpeg (见 test/capability_matrix.md): cmd / PowerShell / Git Bash
# 命中 gyan.dev full(全能力), MSYS2 shell 命中 /mingw64/bin 8.1(**无 libvmaf**),
# Cygwin 命中 /usr/bin 7.1.1(无 libx264/libx265)。于是 calib 族在 MSYS2 下必然
# 报 "this ffmpeg build has no libvmaf filter" —— 而机器上其实装着一个完全能用
# 的构建, 只是 PATH 里排在前面。
#
# 契约:
#   find_ffmpeg [--need-filter <名>]... [--need-encoder <名>]... [--need-demuxer <名>]...
#     成功: 标准输出打印 ffmpeg 可执行文件路径(供 FF=$(...) 捕获), 返回 0;
#           同时在**标准错误**醒目回显最终选定的路径与版本(见 ff_report)
#     失败: 返回 1, 诊断信息(跳过了谁/为什么)全部走标准错误
#   find_ffprobe <ffmpeg 路径>
#     成功: 打印同目录(或 PATH 上)的 ffprobe 并返回 0, 失败返回 1
#   ffmpeg_build_id <ffmpeg 路径>
#     打印版本串(如 "8.1" / "2025-05-01-git-707c04fe06-full_build-www.gyan.dev")
#
# 优先级(与 lib/common.bat 的 :find_ffmpeg 对齐):
#   FFMPEG_BIN(目录) / FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH > 常见安装前缀
# 显式指定一旦存在就无条件采用 —— 即使能力不足也只报错、不再往下找(不把用户
# 明确的选择悄悄换掉)。后面三级则**跳过**能力不足的候选并在标准错误里说明原因:
# 只要机器上存在一个能做这件事的构建, 就不会因为 PATH 恰好指错而失败。
# ================================================================

# 内部: 一条定位诊断(标准错误, 前缀统一, 便于检索)
_ff_note() { printf '[find_ffmpeg] %s\n' "$1" >&2; }

# 内部: 列出候选缺少的能力(空串 = 全部满足), 形如 "filter:libvmaf encoder:libx265 demuxer:dvdvideo"
_ff_missing() {
    local bin="$1" fl="$2" en="$3" dm="$4" f e d out=""
    for f in $fl; do
        "$bin" -hide_banner -filters 2>/dev/null | grep -q -- "$f" || out="$out filter:$f"
    done
    for e in $en; do
        "$bin" -hide_banner -encoders 2>/dev/null | grep -q -- " $e " || out="$out encoder:$e"
    done
    # 解复用器列表形如 " D   dvdvideo        DVD-Video": 按独立词匹配(前后是空白或行首/行尾),
    # 既不漏掉行尾那一列, 也不会被描述列里的同名子串骗过
    for d in $dm; do
        "$bin" -hide_banner -demuxers 2>/dev/null \
            | grep -qE "(^|[[:space:]])${d}([[:space:]]|$)" || out="$out demuxer:$d"
    done
    printf '%s' "${out# }"
}

# 内部: 候选是否满足全部能力要求
_ff_capable() { [ -z "$(_ff_missing "$1" "$2" "$3" "$4")" ]; }

# 内部: 采用显式指定的候选; 能力不足时打印原因并返回 1
_ff_adopt() {
    local bin="$1" fl="$2" en="$3" dm="$4" src="$5"
    _ff_capable "$bin" "$fl" "$en" "$dm" && { echo "$bin"; return 0; }
    _ff_note "$src=$bin 缺少 $(_ff_missing "$bin" "$fl" "$en" "$dm") —— 显式指定优先, 不再自动查找"
    return 1
}

# 内部: 试用一个自动候选(已见过/不存在/能力不足都跳过); 命中则打印路径
# 去重按"去掉 .exe 后缀"比较: Git Bash 的 command -v 返回不带后缀的路径,
# 常见安装前缀那里写的是 ffmpeg.exe, 两者往往指向同一个文件, 不必探测两次。
_ff_try() {
    local bin="$1" fl="$2" en="$3" dm="$4" key
    [ -n "$bin" ] || return 1
    [ -x "$bin" ] || return 1
    key="${bin%.exe}"
    case " ${_FF_SEEN:-} " in
        *" $key "*) return 1 ;;
    esac
    _FF_SEEN="${_FF_SEEN:-} $key"
    _ff_capable "$bin" "$fl" "$en" "$dm" && { echo "$bin"; return 0; }
    _ff_note "跳过 $bin —— 缺少 $(_ff_missing "$bin" "$fl" "$en" "$dm")"
    return 1
}

# 内部: 常见安装前缀(逐个打印候选 ffmpeg 路径)。
# Windows 侧的路径**由 cygpath 生成**, 不硬写 /c/... :
#   MSYS2 / Git Bash : /c/Program Files/ffmpeg/bin
#   Cygwin           : /cygdrive/c/Program Files/ffmpeg/bin   (Cygwin 根本没有 /c)
# 2026-09-20 用户报的"两个 shell 行为不一致"就出在这里: 同一条硬写的 /c/... 在
# MSYS2 命中、在 Cygwin 必然落空, 于是 Cygwin 直接报 no ffmpeg with the libvmaf
# filter was found, 而 MSYS2 却找到了(随后倒在别的检查上, 见该日文档记录)。
_ff_known_prefixes() {
    local w u
    if command -v cygpath >/dev/null 2>&1; then
        for w in 'C:\Program Files\ffmpeg\bin' 'C:\ffmpeg\bin' \
                 'C:\Program Files (x86)\ffmpeg\bin'; do
            u="$(cygpath -u "$w" 2>/dev/null)" || continue
            [ -n "$u" ] && printf '%s\n' "$u/ffmpeg" "$u/ffmpeg.exe"
        done
    fi
    # 没有 cygpath 时的兜底字面量(保持改造前行为)
    printf '%s\n' "/c/Program Files/ffmpeg/bin/ffmpeg.exe" "/c/ffmpeg/bin/ffmpeg.exe"
    for u in /opt/ffmpeg/*/bin/ffmpeg; do
        [ -x "$u" ] && printf '%s\n' "$u"
    done
    printf '%s\n' /usr/local/bin/ffmpeg /usr/bin/ffmpeg
}

function _ff_find_core() {
    local fl="" en="" dm="" cand repo_root d oldifs
    local dirs=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --need-filter)  fl="$fl ${2:-}"; shift 2 ;;
            --need-encoder) en="$en ${2:-}"; shift 2 ;;
            --need-demuxer) dm="$dm ${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    _FF_SEEN=""

    # ---- 阶段一: 显式指定(FFMPEG_BIN 指目录, 与 bat 侧同名同义) ----
    if [ -n "${FFMPEG_BIN:-}" ]; then
        for cand in "$FFMPEG_BIN/ffmpeg" "$FFMPEG_BIN/ffmpeg.exe"; do
            [ -x "$cand" ] && { _ff_adopt "$cand" "$fl" "$en" "$dm" FFMPEG_BIN; return $?; }
        done
        _ff_note "FFMPEG_BIN=$FFMPEG_BIN 下没有可执行的 ffmpeg, 继续自动查找"
    fi
    if [ -n "${FFMPEG:-}" ]; then
        [ -x "$FFMPEG" ] && { _ff_adopt "$FFMPEG" "$fl" "$en" "$dm" FFMPEG; return $?; }
        _ff_note "FFMPEG=$FFMPEG 不可执行, 继续自动查找"
    fi

    # ---- 阶段二: 自动查找, 跳过能力不足的候选 ----
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    for cand in "$repo_root/ffmpeg/bin/ffmpeg" "$repo_root/ffmpeg/bin/ffmpeg.exe"; do
        _ff_try "$cand" "$fl" "$en" "$dm" && return 0
    done

    # PATH 必须**逐项**看, 不能只问 command -v: 它只回第一个命中, 而"第一个"经常
    # 正是缺能力那个(MSYS2 的 /mingw64/bin 8.1、Cygwin 的 /usr/bin 7.1.1 都没有
    # libvmaf), 后面那个能用的构建于是永远轮不到 —— 2026-09-20 两个 shell 报错
    # 不同, 根子就在这里。先收进数组再遍历: PATH 条目含空格时(C:\Program Files\
    # ...), 先拼成字符串再按空格切会把它切断。
    oldifs="$IFS"; IFS=":"
    for d in $PATH; do
        [ -n "$d" ] && dirs+=("$d")
    done
    IFS="$oldifs"
    # ${arr[@]+"${arr[@]}"} 是 set -u 下空数组的安全写法(兼容 bash 4.3)
    for d in ${dirs[@]+"${dirs[@]}"}; do
        _ff_try "$d/ffmpeg" "$fl" "$en" "$dm" && return 0
        _ff_try "$d/ffmpeg.exe" "$fl" "$en" "$dm" && return 0
    done

    # ---- 阶段三: 常见安装前缀(Windows 侧路径由 cygpath 生成, Cygwin 也命中) ----
    while IFS= read -r cand; do
        _ff_try "$cand" "$fl" "$en" "$dm" && return 0
    done < <(_ff_known_prefixes)
    _ff_note "已试遍 PATH 各项与常见前缀, 没有满足要求的 ffmpeg"
    return 1
}

# ================================================================
#  ff_report <ffmpeg 路径> [ffprobe 路径]
#  醒目回显最终选定的 ffmpeg(走**标准错误**, 免得污染 FF=$(find_ffmpeg) 的捕获)。
#  定位过程里"跳过谁、为什么"已经由 _ff_note 打出来了, 但那一堆诊断很容易盖过
#  真正被采用的那个 —— 用户问"到底用的哪个 ffmpeg"时看的就是这块牌子。
# ================================================================
function ff_report() {
    local ff="${1:-}" fp="${2:-}" b="" e="" bar
    bar="============================================================"
    # 只在终端里上色; 重定向到文件时留下纯文本, 免得日志里一堆转义序列
    if [ -t 2 ]; then b="\033[1;7m"; e="\033[0m"; fi
    [ -n "$ff" ] || return 0
    printf '\n%b\n' "${b}${bar}${e}" >&2
    printf '%b\n' "${b} 使用 ffmpeg : ${ff} ${e}" >&2
    [ -n "$fp" ] && printf ' 使用 ffprobe: %s\n' "$fp" >&2
    printf ' 版本       : %s\n' "$(ffmpeg_build_id "$ff")" >&2
    printf '%b\n' "${b}${bar}${e}" >&2
}

# 对外入口: 承接 _ff_find_core 的能力筛选, 并在成功时醒目回显选定的那一份
function find_ffmpeg() {
    local bin
    bin="$(_ff_find_core "$@")" || return 1
    ff_report "$bin"
    printf '%s\n' "$bin"
}

function find_ffprobe() {
    local ff="${1:-}" p
    if [ -n "${FFPROBE:-}" ] && [ -x "${FFPROBE}" ]; then echo "${FFPROBE}"; return 0; fi
    if [ -n "$ff" ]; then
        for p in "$(dirname "$ff")/ffprobe" "$(dirname "$ff")/ffprobe.exe"; do
            [ -x "$p" ] && { echo "$p"; return 0; }
        done
    fi
    p="$(command -v ffprobe 2>/dev/null || true)"
    [ -n "$p" ] && { echo "$p"; return 0; }
    return 1
}

function ffmpeg_build_id() {
    "$1" -hide_banner -version 2>/dev/null | awk 'NR==1{print $3; exit}'
}

# ================================================================
# 源文件路径归一化 (2026-09-20)
#
# 把 Windows 风格路径(F:\a\b 或 F:/a/b)转成当前 shell 能 stat 的形式。
#
# 背景(用户报障): 在 MSYS2 里执行
#     test/sh/bench_calib.sh `cygpath "F:\👍 看电影学英语…\The.Princess.Diaries.2.2004.mp4"`
# 得到的是 "ERROR: source video not found" —— 不打印路径, 看着像工具链坏了。可能
# 是 cygpath 没装/不是那一个, 也可能是终端粘贴时把路径编码改掉了; 而当时工具既不肯
# 直接吃 Windows 路径, 也不说它到底拿到了什么。现在两条都补上:
#   ① Windows 路径直接可用(有 cygpath 就转; 没有就原样返回, 纯 Linux 机器不涉及);
#   ② 调用方在报错时把试过的路径原样打出来(见各工具的 "tried: [...]" 行),
#      空串 / 带 CR / 编码错, 一眼可辨。
# ================================================================
function normalize_source_path() {
    local p="${1:-}" u
    case "$p" in
        [A-Za-z]:[\\/]*)
            if command -v cygpath >/dev/null 2>&1; then
                u="$(cygpath -u "$p" 2>/dev/null)"
                [ -n "$u" ] && { printf '%s' "$u"; return 0; }
            fi
            ;;
    esac
    printf '%s' "$p"
}

# ================================================================
# rejoin_split_path <片段> [更多片段...]
#   「路径在 unquoted 命令替换里被 shell 按空格切开」的补救。典型触发:
#     把 cygpath "F:\a b\c.mp4" 这类命令替换写在引号外面(反引号或 $( ) 都一样)。
#   它打印的整条路径被 word-split, $1 只剩 "/cygdrive/f/a", 其余落到 $2..$n。
#   这里把「最长的、拼起来确实是一个已存在文件的」前缀片段粘回一条路径, 让调用方继续跑,
#   而不是以 "source video not found" 收场 —— 那种报错会把人引向错误方向。
#   结果: REJOIN_PATH(原样, 调用方仍要过 normalize_source_path)、REJOIN_N(跨度)。
#   真粘了(REJOIN_N > 1)返回 0, 没粘返回 1。
# ================================================================
REJOIN_PATH=""
REJOIN_N=1
function rejoin_split_path() {
    local first="${1:-}" n=$# i=0 cur="" t="" fbest="" fn=0 dbest="" dn=0
    REJOIN_PATH="$first"; REJOIN_N=1
    [ "$n" -eq 0 ] && return 1
    while [ "$i" -lt "$n" ]; do
        if [ "$i" -eq 0 ]; then cur="$1"; else cur="$cur $1"; fi
        shift
        t="$cur"
        # 片段可能是 Windows 形式(F:\...), test -f 认不出来时换算成 POSIX 再试
        if [ ! -f "$t" ] && [ ! -d "$t" ] && [ "$(type -t normalize_source_path)" = "function" ]; then
            t="$(normalize_source_path "$cur")"
        fi
        if [ -f "$t" ]; then fbest="$cur"; fn=$((i + 1))
        elif [ -d "$t" ]; then dbest="$cur"; dn=$((i + 1))
        fi
        i=$((i + 1))
    done
    if [ "$fn" -gt 1 ]; then REJOIN_PATH="$fbest"; REJOIN_N="$fn"; return 0; fi
    if [ "$dn" -gt 1 ]; then REJOIN_PATH="$dbest"; REJOIN_N="$dn"; return 0; fi
    return 1
}

# ================================================================
# native_path <路径>
#   给"原生"(非 Cygwin/MSYS)的 ffmpeg.exe / ffprobe.exe 用的路径写法。
#
# 背景(用户报障, 2026-09-20 实测): 同一个 gyan full 构建, 同一条路径, 三种 shell 表现不同 ——
#     Cygwin  /cygdrive/f/👍 看电影学英语…/x.mp4  ->  No such file or directory   (rc=1)
#     Cygwin  F:/👍 看电影学英语…/x.mp4           ->  1280                         (rc=0)
#     MSYS2   /f/👍 看电影学英语…/x.mp4           ->  1280                         (rc=0)
# 连纯 ASCII 的 /cygdrive/c/... 也一样失败, 所以不是非 ASCII 字符的问题: Cygwin 不给原生子
# 进程改写 argv 里的路径, MSYS2 会。混合写法 X:/... 两边都认 -> 统一走它。
# 纯 Linux 上没有 cygpath, 原样返回(那里的 ffmpeg 本来就要 POSIX 路径)。
# ================================================================
function native_path() {
    local p="${1:-}" w
    [ -n "$p" ] || return 0
    case "$p" in
        [A-Za-z]:[\\/]*) printf '%s' "$p"; return 0 ;;
    esac
    case "$p" in
        /*)
            if command -v cygpath >/dev/null 2>&1; then
                w="$(cygpath -m "$p" 2>/dev/null)"
                [ -n "$w" ] && { printf '%s' "$w"; return 0; }
            fi
            ;;
    esac
    printf '%s' "$p"
}

# ================================================================================
# dvdauthor 的路径写法 —— 与 ffmpeg 同一个坑, 判别办法不同
#   2026-09-30 实测: MSYS2 里 /mingw64/bin/dvdauthor 是**原生** mingw 构建(不链
#   msys-2.0.dll), 给它 /tmp/... 这种 POSIX 路径会直接
#       ERR: cannot create dir /tmp/.../sample: No such file or directory
#   造盘那一步就塌, 后面所有用例跟着全 FAIL。Cygwin 的 /usr/bin/dvdauthor 链
#   cygwin1.dll, 认 POSIX 路径, 不能改写(改了反而绕远)。
#   判别: 看它链的是不是 cygwin1.dll / msys-2.0.dll; ldd 都没有就按"原生"处理
#   (纯 Linux 上 native_path 原样返回, 不受影响)。
# ================================================================================
function tool_is_posix_aware() {
    local p dep
    p="$(command -v "${1:-}" 2>/dev/null)" || return 1
    [ -n "$p" ] || return 1
    dep="$(ldd "$p" 2>/dev/null)" || return 1
    case "$dep" in
        *cygwin1.dll*|*msys-2.0.dll*) return 0 ;;
    esac
    return 1
}

# da_path <路径> —— 写进 dvdauthor 的 XML(dest / vob file)或 -o 的写法
function da_path() {
    local p="${1:-}"
    [ -n "$p" ] || return 0
    if tool_is_posix_aware dvdauthor; then printf '%s' "$p"; else native_path "$p"; fi
}

# ================================================================
# ff_run / fp_run  ——  会改写路径的 ffmpeg / ffprobe 调用
#   规则: 参数以 / 开头就当成路径, 换成原生写法; 其余(过滤串、-map、数字、编解码器名)
#   原样传递。工具里凡是要读/写文件的调用都走这两个包装, 不要直接 "$FF" / "$FP"。
#   依赖调用方已设好 FF 与 FP(见各工具的 find_ffmpeg 段)。
# ================================================================
function _ff_native_exec() {
    local exe="$1"; shift
    local a out=()
    for a in "$@"; do
        case "$a" in
            /*) out+=("$(native_path "$a")") ;;
            *)  out+=("$a") ;;
        esac
    done
    "$exe" ${out[@]+"${out[@]}"}
}
function ff_run() { _ff_native_exec "$FF" "$@"; }
function fp_run() { _ff_native_exec "$FP" "$@"; }

# ================================================================
# pick_mkisofs / mkisofs_path  ——  打包器(mkisofs / genisoimage)的挑选与调用
#
# 为什么不能只按 mkisofs -> genisoimage 取第一个(2026-09-29 实测, Cygwin 打 DVD):
#   Cygwin 的 PATH 上常有 WinCDEmu 自带的 mkisofs.exe, 它是**原生** Windows 程序。
#   Cygwin 不给原生子进程改写 argv 里的路径(MSYS2 会改写), 于是同一条命令:
#     MSYS2   /h/.../VIDEO_TS           -> 正常
#     Cygwin  /cygdrive/h/.../VIDEO_TS  -> No such file or directory
#   中文路径更糟: 原生 exe 那边直接变乱码(Invalid node - '/cygdrive/h/Downloads/<乱码>')。
#   所以在这类环境里优先挑**shell 自己那一份**(在 /usr/bin 之类, 认 POSIX 路径);
#   实在只剩原生 exe 时, 才把参数改成 native_path 的混合写法 X:/... 喂给它。
#   纯 Linux 没有 cygpath, 两条分支都不进 —— 行为与改造前完全一致(mkisofs 优先)。
#
#   MKISOFS=/path/to/xxx 可强制指定, 与 FFMPEG= / FFPROBE= 的覆盖方式一致。
# ================================================================
function pick_mkisofs() {
    if [ -n "${MKISOFS:-}" ] && [ -x "${MKISOFS}" ]; then printf '%s' "$MKISOFS"; return 0; fi
    local cand="" first="" shell_side=""
    for c in mkisofs genisoimage; do
        command -v "$c" >/dev/null 2>&1 || continue
        cand="$(command -v "$c")"
        [ -n "$first" ] || first="$cand"
        # Cygwin 挂在 /cygdrive 下的是 Windows 盘 -> 那一个是原生 exe;
        # /usr/bin 之类的是 shell 侧构建, 认 POSIX 路径
        case "$cand" in /cygdrive/*) ;; *) shell_side="$cand"; break ;; esac
    done
    case "$(uname -s 2>/dev/null)" in
        CYGWIN*) [ -n "$shell_side" ] && { printf '%s' "$shell_side"; return 0; } ;;
    esac
    [ -n "$first" ] && { printf '%s' "$first"; return 0; }
    return 1
}

# 选中的打包器要不要把路径改成原生写法: 只有「Cygwin + 原生 exe」这一档才要
function mkisofs_path() {
    case "$(uname -s 2>/dev/null)" in
        CYGWIN*) case "${1:-}" in /cygdrive/*) native_path "$1"; return 0 ;; esac ;;
    esac
    printf '%s' "${1:-}"
}

# ================================================================
# src_stamp <文件>  ——  把源文件折算成一小段"身份串", 用来给工作目录命名
#   只取字节数: .bat 侧的 %%\~zI 能算出同一个数, 两族因此可以共用同一份产物;
#   mtime 不行(cmd 的 %%\~tI 是本地化格式, 和 stat/date 的秒数对不上)。
#   区分"换了一个源文件"的强度足够 —— 两部电影字节数撞车的概率可以忽略。
# ================================================================
function src_stamp() {
    local sz=""
    if sz="$(stat -c '%s' "$1" 2>/dev/null)" && [ -n "$sz" ]; then printf '%s' "$sz"; return 0; fi
    wc -c < "$1" 2>/dev/null | tr -d ' \r'
}

# ================================================================
# COVER_MAP / cover_map_gate  ——  封面(attached picture)保留能力门 (2026-09-28)
#
# 用户要求: "如果有封面的尽可能保留封面"。
#
# 为什么不能只写 `-map 0:v`: mkvmerge 写进 mkv 的海报是一条**流**, 不是附件
#   Stream #0:3: Video: mjpeg (attached_pic=1)
# `-map 0:v` 会把这条流也当成输出视频送去重编码, 而 mp4 只允许把封面存成
# mjpeg/png/bmp -> `Could not find tag for codec hevc in stream #1`
# -> 整部片子写 0 字节(用户 2026-09-28 报的 2h13m 事故)。
# 所以编码入口拆成两条映射:
#   -map 0:V                     主视频(排除 attached picture; lint L16 钉住)
#   -map 0:v:disp:attached_pic?  封面: 单独映射, 排在主视频之后
# 复制动作**按输出流号**下发(封面槽位 = 1 / 2), 主视频只被 `-c:v:0` 命中:
#   -c:v:0 <编码器> -profile:v:0 main -preset ... -c:v:1 copy -c:v:2 copy
#
# 2026-09-28 修订: 上一版用的是**不带流号**的 `-c:v copy`(视频默认复制, 再靠
#   `-c:v:0` 把主视频改回编码器)。能跑通, 但 ffmpeg 必报一行
#     [vost#0:0] Multiple -codec/-c/... options specified for stream 0,
#                only the last option '-codec:v:0 ...' will be used.
#   同一条流被两个 -c 命中, 结果全靠"后写的赢" —— 顺序一旦写反, 整片就变成复制,
#   而命令里同时出现 copy 和编码器本身就是让人误判的写法(用户 2026-09-28 报)。
#   改成按流号写之后两条指令互不重叠: 警告消失, 也没有顺序隐患。
#   代价: 复制指令要**按输出流号**写。而流号不是常数 —— `-map 0:V` 把所有非封面视频
#   排在前 m 路, 封面排在 [m, m+n):
#       实测 2026-09-28 (合成 mkv): 单视频 + 2 张封面 -> 槽位 1、2 正确;
#       **2 路视频 + 2 张封面 -> 写死的 1、2 整体错位: 一个打到第 2 路视频上(它被
#       悄悄复制、根本没转码), 第 2 张封面没人管 -> 被送进编码器 ->
#       `Could not find tag for codec h264 in stream #4` -> rc=127 写 0 字节**。
#       这正是本文件上面那段注释要防的事故, 等于换个姿势又踩一次。
#   所以复制下标**由流表算**, 不写死: 见 cover_map_gate 的第 ② 步。
#   不要用 `-c:v:disp:attached_pic copy`: 实测**不生效** —— 输出流的 disposition
#   是在选完编码器之后才从输入流拷贝过来的, 匹配时还没有, 封面拿不到 copy, 直接
#   回到 "Could not find tag for codec h264 in stream #1" 的写 0 字节事故。
#
# 能力门: `disp:` 说明符是 **ffmpeg 7.1 (2024-09, commit 0c9fe2b232)** 才加入的。
# 老构建把它当语法错误(`Trailing garbage after stream specifier`), 而且**结尾的
# `?` 救不了解析错误** —— 于是"保留封面"会变成"整片失败", 这是坏交易。
# 这里探一次: 支持就填 COVER_MAP, 不支持就清空并提示一行(退回"丢封面"的旧行为)。
# 探测用 lavfi 假源 + null 输出: 不碰用户文件, 每个脚本进程只探一次, 且探的正是
# 本入口马上要用的那个 `ffmpeg`(sh 编码入口目前都直接调 PATH 上的 ffmpeg)。
# 与 find_ffmpeg 的 L20 能力筛选是**两种语义**: 那边"不够就报错, 不悄悄换构建",
# 这边"不够就丢掉封面, 不让编码失败" —— 别把两者合并。
# ================================================================
# ---- 位图字幕(2026-09-28): mp4 装不下, 必须排除, 否则整片 0 字节 ----
# 入口都用 `-c:s mov_text`。文本字幕(ass / subrip / mov_text / webvtt)能转, 位图
# 字幕转不了 —— ffmpeg 以 EINVAL 收尾, **整部片子写 0 字节**:
#   [sost#0:2/mov_text] Subtitle encoding currently only possible from
#                       text to text or bitmap to bitmap
# 这不是理论风险: 实测扫用户 838 条转码清单(657 个可访问), **14 个带
# hdmv_pgs_subtitle**(Chernobyl 全 5 集、花と蛇 8 部等) —— 现有一跑就是 0 字节。
# DVD ISO 更狠: 7 个样本全部带 dvd_subtitle, 且裸 -i 喂 ISO 时 ffmpeg 把 UDF 当
# MPEG-PS 胡乱揭开, 有的连字幕都看不见却照样产出半截废品(详见 ffmpeg_dvd_hevc.sh)。
#
# 排除手段是**负映射** `-map -0:s:<i>`(i = 该字幕在 subtitle 里的 per-type 下标),
# 而不是一刀切的 `-map -0:s`: 实测 Chernobyl.E01 = PGS + ass + subrip, 一刀切会把
# 能救的两条文本字幕一起丢掉, 按条排除则产物里仍有 2 条 mov_text。
# 位置也有讲究: 负映射必须排在 `-map 0:s?` **之后**才生效, 而入口把本变量正好插在
# `-map 0:s?` 与 `-c:s mov_text` 之间 —— 所以这事能塞进 COVER_MAP 里, 17 个入口
# 依然零改动(代价: 本变量现在是"闸门产出的附加流指令", 不只是封面映射)。
#
# 位图集合是**封闭**的(DVD / 蓝光 / DivX / DVB 四种来源), 所以列**黑名单**而不是
# 白名单: 没列出的字幕一律维持原行为(ass / subrip 照常进 mov_text), 不会因为漏列
# 而白白丢字幕; 真冒出新的位图字幕也只是回到"跑失败"这个已知状态, 不会静默出错。
_SUB_BITMAP="hdmv_pgs_subtitle dvd_subtitle xsub dvb_subtitle"

COVER_MAP=(-map "0:v:disp:attached_pic?")
_COVER_CHECKED=""
_COVER_OK=1

function cover_map_gate() {
    local ff="${1:-ffmpeg}"
    # ① 能力门: `disp:` 说明符要 ffmpeg 7.1+。判据与文件无关 -> 进程内只探一次。
    if [ -z "$_COVER_CHECKED" ]; then
        _COVER_CHECKED=1
        if ! "$ff" -hide_banner -v error -f lavfi -i color=c=black:s=16x16:r=1 \
             -t 0.04 -map "0:v:disp:attached_pic?" -f null - >/dev/null 2>&1; then
            _COVER_OK=0
            printf '[cover] %s 不认 disp: 流说明符(需 ffmpeg 7.1 或更高) —— 本次运行不保留封面\n' "$ff" >&2
        fi
    fi

    # ② 流表门: 一次 ffprobe 同时办两件事 —— 算封面的输出下标, 以及挑出 mp4 装不下
    #    的位图字幕。每次调用都重算 —— 一个入口进程可能连着处理多个文件, 流表不能
    #    跨文件复用。
    COVER_MAP=()
    [ "$_COVER_OK" = 1 ] && COVER_MAP=(-map "0:v:disp:attached_pic?")
    local src="${ABS_NAME:-$SRC_FILE}"
    local probe vt na m i si idx codec type
    probe=$(ffprobe -v error -show_entries stream=codec_name,codec_type \
                    -show_entries stream_disposition=attached_pic -of csv=p=0 "$src" 2>/dev/null | tr -d '\r')

    # ②a 位图字幕 -> 负映射逐条排除。**不看 ① 的 disp: 能力**: 老 ffmpeg 一样死在这。
    if [ -n "$probe" ]; then
        si=0
        while IFS=, read -r codec type _; do
            # DVD-Video 的导航包(只在 ISO / VOB 里有, 实测 192 个 mpg/m2ts 片源 0 命中,
            # 不会误报): 说明这是 DVD 源, 而通用入口不带 `-f dvdvideo`, ffmpeg 会把
            # UDF 镜像当 MPEG-PS 胡乱揭开 —— 不报错, 但时长和内容都不对, 产物是废品。
            # 只提示, 不改行为: 真要转 DVD 请走 ffmpeg_dvd_hevc.sh。
            if [ "$codec" = "dvd_nav_packet" ]; then
                printf '[dvd] %s 是 DVD-Video(ISO / VOB) —— 本入口不带 -f dvdvideo, 会被当 MPEG-PS 胡乱揭开(不报错但内容不对), 请改用 ffmpeg_dvd_hevc.sh\n' \
                    "$(basename "$src")" >&2
                continue
            fi
            [ "$type" = "subtitle" ] || continue
            idx=$si; si=$((si + 1))
            case " $_SUB_BITMAP " in
                *" $codec "*)
                    COVER_MAP+=(-map "-0:s:$idx")
                    printf '[sub] %s 含位图字幕 %s —— mp4 装不下, 本次不保留该条(要保留请出 mkv)\n' \
                        "$(basename "$src")" "$codec" >&2
                    ;;
            esac
        done <<< "$probe"
    fi

    # ②b 封面: 数出 `-map 0:V` 命中几路(m)和有几张封面(n), 输出下标 = [m, m+n)。
    if [ "$_COVER_OK" != 1 ]; then return 0; fi
    vt=$(printf '%s\n' "$probe" | grep -c ',video,')
    na=$(printf '%s\n' "$probe" | grep -c ',video,1$')
    if [ -z "$vt" ] || [ "$vt" -le 0 ]; then
        COVER_MAP+=(-c:v:1 copy -c:v:2 copy)   # 探测不可用: 退回写死槽位(1~2 张)
        return 0
    fi
    [ "$na" -le 0 ] && return 0                # 无封面: 只留 -map(? 匹配不到, 静默忽略)
    m=$((vt - na)); [ "$m" -lt 1 ] && m=1
    for ((i = m; i < vt; i++)); do COVER_MAP+=(-c:v:$i copy); done
    return 0
}
