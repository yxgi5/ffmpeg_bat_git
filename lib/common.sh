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
#   streams.stream.0.codec_name / .codec_type / .profile / .pix_fmt
#   streams.stream.0.width / .height / .r_frame_rate / .bit_rate
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
    # 走 fp_run(不是裸 ffprobe): ① 用调用方定位到的那份, 别去 PATH 上另抓一份;
    # ② 原生 Windows 构建吃不了 /cygdrive/c/... 这种 POSIX 路径, fp_run 会改写。
    # FP 没定位过时自己补一次, 不静默失败(调用方应已 find_ffprobe, 见各入口顶部)
    [ -n "${FP:-}" ] || FP="$(find_ffprobe "${FF:-}" 2>/dev/null || command -v ffprobe 2>/dev/null || printf '')"
    raw=$(fp_run -v error -hide_banner -select_streams v:0 \
        -show_entries stream=codec_type,codec_name,profile,pix_fmt,width,height,r_frame_rate,bit_rate:format=size,duration,bit_rate \
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
        # FWD: 调用方(清单驱动)把生效开关收集成的 --key value 数组, 显式转发给每个入口。
        #   为空时(清单驱动没设)按 ${FWD[@]+...} 退化成只传文件名 —— 行为不变。
        bash "$script" "${FWD[@]+"${FWD[@]}"}" "$line" < /dev/null
        rc=$?
        # 退出码 4 = 硬件缺失(契约见 test/README 5.2): 它不是"这个文件转坏了",
        #   而是"这台机器跑不了这个入口"。清单里剩下的条目会一条接一条撞同一堵
        #   墙, 继续跑没有意义 —— 不跳过、直接中止并原样传回 4。
        if [ "$rc" -eq 4 ]; then
            echo -e "\033[43;30m硬件缺失(rc=4): 本入口在这台机器上不可用, 中止整份清单\033[0m"
            exit 4
        fi
        if [ "$rc" -ne 0 ]; then
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
# 优先级:
#   FFMPEG(可执行文件) > 仓库内 ffmpeg/bin
#     > [仅 Linux] /opt/ffmpeg/<构建>/bin > PATH > 常见安装前缀
# 显式指定一旦存在就无条件采用 —— 即使能力不足也只报错、不再往下找(不把用户
# 明确的选择悄悄换掉)。其余各级则**跳过**能力不足的候选并在标准错误里说明原因:
# 只要机器上存在一个能做这件事的构建, 就不会因为 PATH 恰好指错而失败。
# 那个 [仅 Linux] 一档(2026-09-30)是"新构建优先": 发行版 ffmpeg 常年停在 4.x,
# 而 /opt 下那份常是完整 gpl 构建; 它仍是候选、仍参与能力筛选, 不是无条件顶替。
# Cygwin / MINGW64 的 uname 是 CYGWIN* / MINGW* / MSYS*, 构造上不进这一档。
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
    # Linux 守门(WSL2 实测 2026-09-30): 那里 /mnt/c 可见且 .exe 可执行, 于是 Windows
    # 的 gyan.exe 会作为候选被选中 —— 而它吃不了 /tmp/... 这种 Linux 路径, 必然
    # "No such file"。纯 Linux 上本来就不该有 .exe, 这一档对它零影响。
    if [ "${_FF_UNAME:-}" = Linux ]; then
        case "$bin" in *.exe|/mnt/*) return 1 ;; esac
    fi
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
# 内部: /opt 下的构建(Linux 侧"新构建优先"那一档用; 与 _ff_known_prefixes 里的
# 同一批路径重复无所谓 —— _ff_try 按路径去重, 不会重复探测)
_ff_known_opt_prefixes() {
    local u
    for u in /opt/ffmpeg/*/bin/ffmpeg; do
        [ -x "$u" ] && printf '%s\n' "$u"
    done
}

# 内部: Windows 侧"gyan 优先"那一档(2026-09-30)。与 _ff_known_prefixes 里的同一批
# 路径重复无所谓(_ff_try 按路径去重) —— 这里只负责"排在 PATH 之前"这一件事。
# 路径一律由 cygpath 生成: MSYS2 写 /c/...、Cygwin 写 /cygdrive/c/..., 硬写必错其一。
_ff_known_win_prefixes() {
    local w u
    command -v cygpath >/dev/null 2>&1 || return 0
    for w in 'C:\Program Files\ffmpeg\bin' 'C:\ffmpeg\bin' \
             'C:\Program Files (x86)\ffmpeg\bin'; do
        u="$(cygpath -u "$w" 2>/dev/null)" || continue
        [ -n "$u" ] && printf '%s\n' "$u/ffmpeg" "$u/ffmpeg.exe"
    done
}

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
    # 平台判定只在本次定位里算一次(_ff_try 的 Linux 守门要用, 避免每个候选都起 uname)
    case "$(uname -s 2>/dev/null || printf '')" in
        Linux*) _FF_UNAME=Linux ;;
        *)      _FF_UNAME=Other ;;
    esac

    # ---- 阶段零: FFMPEG 路径规范化(文件式, 2026-10-03) ----
    # Windows 上用户若把 FFMPEG 写成 D:\path\ffmpeg.exe, bash 会把反斜杠当转义序列,
    # 路径被切碎。有 cygpath 时把 Windows 风格(含 \ 或盘符:)统一转成 posix。纯 Linux / WSL 没有 cygpath, 原样不动。
    # 注: 目录式 FFMPEG_BIN 已废弃移除(2026-10-03 决策): 两族统一为文件式 FFMPEG / FFPROBE。
    if command -v cygpath >/dev/null 2>&1; then
        case "${FFMPEG:-}" in
            *\\*|[A-Za-z]:*) FFMPEG="$(cygpath -u -- "$FFMPEG" 2>/dev/null)" || true ;;
        esac
    fi
    # 去尾部斜杠前必须先判空: 调用方(各冒烟脚本)开了 set -u, 裸写 ${FFMPEG%/} 在
    # 用户没设 FFMPEG 时会以"未绑定的变量"当场中止 —— find_ffmpeg 于是静默返回 1,
    # 调用方的 `find_ffmpeg || command -v ffmpeg` 兜底就把 PATH 上那份能力最少的构
    # 建选中了(Cygwin 的 7.1.1 无 libx264、Ubuntu 的 4.4.2), 而 gyan 与 /opt 下的
    # 新构建一次都轮不到。2026-10-03 实测两端同症状, 故改为判空后再处理。
    if [ -n "${FFMPEG:-}" ]; then FFMPEG="${FFMPEG%/}"; fi

    # ---- 阶段一: 显式指定(FFMPEG 指向可执行文件, 最高优先, 不做能力筛选) ----
    if [ -n "${FFMPEG:-}" ]; then
        [ -x "$FFMPEG" ] && { _ff_adopt "$FFMPEG" "$fl" "$en" "$dm" FFMPEG; return $?; }
        _ff_note "FFMPEG=$FFMPEG 不可执行, 继续自动查找"
    fi

    # ---- 阶段二: 自动查找, 跳过能力不足的候选 ----
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    for cand in "$repo_root/ffmpeg/bin/ffmpeg" "$repo_root/ffmpeg/bin/ffmpeg.exe"; do
        _ff_try "$cand" "$fl" "$en" "$dm" && return 0
    done

    # ---- 阶段二点五: Linux 下 /opt 里的新构建优先(2026-09-30) ----
    # 发行版 ffmpeg 常年停在 4.x(本机 4.4.2, 缺 libsvtav1 / av1_nvenc), 而
    # /opt/ffmpeg/<构建>/bin 下那份常是完整 gpl 构建。把它作为**候选**放在 PATH 之前:
    # 两处都能干这件事时优先用新的; 它仍然参与能力筛选 —— 干不了就跳过, 不像
    # ffmpeg_av1_nvenc.sh 早先那段硬编码 `export PATH=/opt/...:$PATH` 那样无条件顶到
    # 最前(那份若换成能力更少的 static 构建, 反而会把 nvenc/vaapi 全废掉)。
    # 只有 Linux 走这一档: Cygwin / MINGW64 的 uname 是 CYGWIN* / MINGW* / MSYS*,
    # 构造上不受影响(它们的 Windows 构建叫 ffmpeg.exe, 也不在 /opt 下)。
    case "$(uname -s 2>/dev/null || printf '')" in
        Linux*)
            while IFS= read -r cand; do
                _ff_try "$cand" "$fl" "$en" "$dm" && return 0
            done < <(_ff_known_opt_prefixes)
            ;;
    esac

    # ---- 阶段二点七五: Windows 侧 gyan 优先(2026-09-30) ----
    # 这些 shell 的 PATH 首项常是自己那份原生构建(MSYS2 的 mingw 8.1、Cygwin 的
    # 7.1.1), 能力不全; 而机器上装着的 gyan full 排在后面。用户的要求是"只要是
    # Windows, sh 侧也优先 gyan, 原生版本只作功能兜底" —— 所以把它插在 PATH 之前。
    # 它**仍参与能力筛选**: gyan 干不了的事(某个 encoder / demuxer)照样往下走, 落到
    # PATH 里的原生构建; 不像 ffmpeg_av1_nvenc.sh 早先那段硬编码 PATH 那样无条件顶替。
    # 只有有 cygpath 的 shell(Cygwin / MSYS2 / Git Bash)进这一档 —— 纯 Linux 与
    # WSL2 没有 cygpath, 顺序与改造前逐字一致。
    if command -v cygpath >/dev/null 2>&1; then
        while IFS= read -r cand; do
            _ff_try "$cand" "$fl" "$en" "$dm" && return 0
        done < <(_ff_known_win_prefixes)
    fi

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
    # 四行套同一对 b/e: 早先只有分隔条与"使用 ffmpeg"上色, ffprobe 与版本两行是纯
    # 文本, 同一块牌子看着像两截(2026-10-03 用户指出), 这里统一成整块反白。
    # 路径与版本串一律走 %s, 不拼进 %b 的格式串 —— 它们可能含 %, 当格式符会出错。
    printf '\n%b%s%b\n' "$b" "$bar" "$e" >&2
    printf '%b%s%b\n' "$b" " 使用 ffmpeg : $ff " "$e" >&2
    if [ -n "$fp" ]; then printf '%b%s%b\n' "$b" " 使用 ffprobe: $fp " "$e" >&2; fi
    printf '%b%s%b\n' "$b" " 版本       : $(ffmpeg_build_id "$ff") " "$e" >&2
    printf '%b%s%b\n' "$b" "$bar" "$e" >&2
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

# ================================================================
#  find_ffmpeg_for_encoder <编码器名>
#  先按"必须带这个编码器"筛; 一台机器上谁都没有时, 退回不筛选的 find_ffmpeg。
#
#  为什么不直接用 `find_ffmpeg --need-encoder <名>` 了事(2026-09-30):
#    能力不足时它返回 1, 入口脚本于是**还没碰到输入文件**就退出 —— 而"文件不存在 /
#    后缀不对"这类检查各有自己的退出码(见 exit-code 契约), 提前退出会把它们全盖成 1。
#    退回不筛选则让 ffmpeg 自己报 Unknown encoder '<名>', 走的是改造前那条路径。
#  真正要的是前半段: 发行版 ffmpeg 常缺硬编/新编码器(本机 4.4.2 就没有 av1_nvenc
#  与 libsvtav1), 而能用的那份在 /opt 下且**不在 PATH 上** —— 只有加了能力要求,
#  定位才会跳过 PATH 里第一个去摸 /opt(实测: --need-encoder libsvtav1 命中
#  /opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin/ffmpeg)。
# ================================================================
function find_ffmpeg_for_encoder() {
    local enc="${1:-}" bin
    [ -n "$enc" ] || { find_ffmpeg; return $?; }
    if bin="$(find_ffmpeg --need-encoder "$enc")"; then
        printf '%s\n' "$bin"
        return 0
    fi
    _ff_note "没有任何构建带编码器 $enc —— 退回不做能力筛选的定位(让 ffmpeg 自己报错, 保持原退出码)"
    find_ffmpeg
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
    local a out=() i=0
    for a in "$@"; do
        case "$a" in
            /*) out+=("$(native_path "$a")") ;;
            *)  out+=("$a") ;;
        esac
    done

    # ---- 产物已存在时的策略(2026-09-30 实测) ----
    #   ffmpeg 的 -n 在输出已存在时打印 "File already exists. Exiting." 却**返回 0**
    #   —— 调用方(含 convert_from_list_*)会以为这条转好了, 实际一个字节都没动。
    #   这里把它改成显式行为, 由 FF_ON_EXIST 选:
    #     skip      (默认) 明确打印"已跳过"; 退出码仍为 0, 保住批量续转语义 —— 清单里
    #                      已经转过的条目不该让整批失败
    #     overwrite 把 -n 换成 -y, 真的覆盖重转
    #     fail      打印提示并返回 6, 让调用方能察觉(6 是本仓库新增的"产物已存在"码)
    #   只认命令行末尾固定的 "-n <输出文件>" 形态(所有入口都这么拼); 不带 -n 的调用
    #   (ffprobe 探测、交互模式、dvd 工具链)一字不动。
    if [ $# -ge 2 ] && [ "${@: -2:1}" = "-n" ]; then
        local tgt="${@: -1}"
        if [ -n "$tgt" ] && [ -e "$tgt" ]; then
            case "${FF_ON_EXIST:-skip}" in
                overwrite)
                    printf '[ff_run] 产物已存在, FF_ON_EXIST=overwrite -> 覆盖重转: %s\n' "$tgt" >&2
                    out[$((${#out[@]} - 2))]="-y"
                    ;;
                fail)
                    printf '[ff_run] 产物已存在, FF_ON_EXIST=fail -> 不覆盖, 退出码 6: %s\n' "$tgt" >&2
                    # 用 exit 而不是 return: 入口脚本统一写成 `ff_run ...; if [ $? -ne 0 ];
                    # then exit 1; fi`, return 6 会被那道守卫抹成 1。两族要对齐到同一个
                    # 6, 所以这里直接结束脚本(与 .bat 侧 `exit /b 6` 对等)。traps 照常跑。
                    exit 6
                    ;;
                *)
                    printf '[ff_run] 产物已存在 -> 跳过(未重转): %s\n' "$tgt" >&2
                    printf '[ff_run]   覆盖重转: FF_ON_EXIST=overwrite; 视为失败(6): FF_ON_EXIST=fail\n' >&2
                    return 0
                    ;;
            esac
        fi
    fi

    # ---- "-hwaccel auto" 的 D3D 回退(2026-09-30 实测) ----
    #   Windows 会话处于「已断开 / 锁屏」时 D3D 设备创建被拒, 而 gyan 的 -hwaccel auto
    #   不是优雅降级, 是**直接崩**(0xC0000005 / Segmentation fault) —— 实测三族
    #   (cmd、Cygwin、MINGW64)在同一状态下一起崩, 不带 hwaccel 的 copy_to_mp4 与
    #   dvd 工具链却全过。所以: 只在命令里带 "-hwaccel auto" 时, 把 stderr 收进临时
    #   文件; 失败且 stderr 出现 D3D 特征码, 就去掉这一对参数重跑一次, 编码器与其余
    #   参数一字不动。
    #   不带 -hwaccel auto 的命令(纯软编、QSV/CUDA 专用入口、ffprobe 探测)走老路径,
    #   行为逐字不变; FF_NO_HWACCEL_FALLBACK=1 可整体关掉。
    local has_auto=0
    for ((i = 0; i < ${#out[@]}; i++)); do
        if [ "${out[i]}" = "-hwaccel" ] && [ "${out[i+1]:-}" = "auto" ]; then
            has_auto=1
            break
        fi
    done
    if [ "$has_auto" = 1 ] && [ "${FF_NO_HWACCEL_FALLBACK:-}" != 1 ]; then
        local tmp rc k nout=()
        tmp="${TMPDIR:-/tmp}/ff_hwaccel_$$.err"
        "$exe" ${out[@]+"${out[@]}"} 2> "$tmp"
        rc=$?
        if [ "$rc" -ne 0 ] && grep -qaE 'Failed to create Direct3D device|Device creation failed|Failed to create a device' "$tmp" 2>/dev/null; then
            k=0
            while [ "$k" -lt "${#out[@]}" ]; do
                if [ "${out[k]}" = "-hwaccel" ] && [ "${out[k+1]:-}" = "auto" ]; then
                    k=$((k + 2))
                    continue
                fi
                nout+=("${out[k]}")
                k=$((k + 1))
            done
            cat "$tmp" >&2
            printf '[ff_run] -hwaccel auto 初始化失败(D3D 设备不可用) -> 去掉 hwaccel 重跑\n' >&2
            rm -f "$tmp"
            "$exe" ${nout[@]+"${nout[@]}"}
            return $?
        fi
        cat "$tmp" >&2
        rm -f "$tmp"
        return "$rc"
    fi

    "$exe" ${out[@]+"${out[@]}"}
}
# ================================================================
# dry-run (2026-10-04): 只把将要执行的 ffmpeg 命令打印出来, 一个字节都不跑
#   开关: --dry-run / --dry-run=1(参数式, 见 parse_switches) 或 DRY_RUN=1(环境变量);
#         两族同名同义, .bat 侧见 lib/common.bat 的 :dry_run。
#   只拦 ff_run(ffmpeg 本体): fp_run 是 ffprobe 探测, 必须照跑 —— 不探测就没有
#         分辨率 / 码率, 命令行还没拼出来脚本先散了。
#   多 title 的入口(dvd_hevc)每条 title 各打一条: 先看全再决定跑不跑。
# ================================================================
function ff_dry_run() {
    case "${DRY_RUN:-}" in
        1|true|yes|on|TRUE|YES|ON|True|Yes|On) return 0 ;;
    esac
    return 1
}

function ff_print_cmd() {
    # 打出来的就是真会跑的那条: 与 _ff_native_exec 同一套路径改写(以 / 开头的参数
    # 换原生写法), 参数逐个 %q 引好, 可直接复制粘贴自己跑。
    local exe="$1"; shift
    local a out=()
    for a in "$@"; do
        case "$a" in
            /*) out+=("$(native_path "$a")") ;;
            *)  out+=("$a") ;;
        esac
    done
    printf '%q' "$exe"
    if [ ${#out[@]} -gt 0 ]; then printf ' %q' "${out[@]}"; fi
    printf '\n'
}

function ff_run() {
    if ff_dry_run; then
        # 提示走 stderr: stdout 上只留那条纯命令, 方便直接接管道 / 复制粘贴
        printf '[dry-run] 未执行, 仅打印命令:\n' >&2
        ff_print_cmd "$FF" "$@"
        return 0
    fi
    _ff_native_exec "$FF" "$@"
}
function fp_run() { _ff_native_exec "$FP" "$@"; }

# ================================================================
# Windows 侧 locale 兜底(2026-09-30 实测)
#   Cygwin / MSYS2 里 LANG 常常只是 zh_CN 或为空(没有 .UTF-8 后缀), 于是 shell 把
#   路径字节按 **GBK** 转成 UTF-16 喂给原生 exe —— 而文件系统里存的是 UTF-8 字节,
#   结果连脚本自己的 [ -f "$1" ] 都判"文件不存在"(实测: 中文目录名在 Cygwin 与
#   MINGW64 下都是 file not exists!, 出口换成 LANG=zh_CN.UTF-8 立刻通过; 同一份
#   素材在 cmd 里正常, 因为 cmd 直接用宽字符, 不经这层转换)。
#   所以这里在**有 cygpath 的 shell**(Windows 侧)且当前 locale 不是 UTF-8 时, 挑一个
#   可用的 UTF-8 locale 顶上。三道限制, 免得伤到别人:
#     ① 只在有 cygpath 时动手 —— 纯 Linux 与 WSL2 一行都不执行, 行为逐字不变;
#     ② 已经是 UTF-8 就什么都不做, 不覆盖用户设置;
#     ③ FF_NO_LOCALE=1 可整体关掉(排查"改了 locale 之后显示不对"这类问题时用)。
# ================================================================
if command -v cygpath >/dev/null 2>&1 && [ "${FF_NO_LOCALE:-}" != 1 ]; then
    case "${LC_ALL:-${LANG:-}}" in
        *UTF-8*|*utf8*) : ;;
        *)
            for _l in C.UTF-8 zh_CN.UTF-8 en_US.UTF-8; do
                if LC_ALL="$_l" locale >/dev/null 2>&1; then
                    export LC_ALL="$_l" LANG="$_l"
                    break
                fi
            done
            unset _l
            ;;
    esac
fi

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
    # 顺序刻意 **genisoimage 在前**(2026-09-30 实测): MSYS2 的 PATH 上第一个打包器
    # 是 WinCDEmu 自带的 mkisofs 3.01a24(i686-pc-mingw32, 原生 exe) —— 即便给了
    # D:/... 混合写法, 它照样 `Can't stat <dir>` / `Unable to make a DVD-Video image`,
    # 造盘那一步直接塌, 后面所有用例跟着 FAIL; 而同机的 /mingw64/bin/genisoimage
    # 1.1.11 在同样的路径上一次就过。Cygwin 与 Linux 上 genisoimage 也是现在的事实
    # 标准(README 的安装提示本来就是 apt install genisoimage), 故先挑它,
    # mkisofs 只作兜底。
    for c in genisoimage mkisofs; do
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
    CM_MOV=0
    [ "$_COVER_OK" = 1 ] && COVER_MAP=(-map "0:v:disp:attached_pic?")
    local src="${ABS_NAME:-$SRC_FILE}"
    local probe vt na m i si idx codec type
    # 走 fp_run(不是裸 ffprobe): ① 用调用方定位到的那份, 别去 PATH 上另抓一份, 否则
    # "编码用新构建、流表判断用老构建", 封面下标与位图字幕的判断就可能对不上;
    # ② 原生 Windows 构建吃不了 /cygdrive/c/... 这种 POSIX 路径, fp_run 会改写。
    # FP 没定位过时自己补一次, 不静默失败(调用方应已 find_ffprobe, 见各入口顶部)
    [ -n "${FP:-}" ] || FP="$(find_ffprobe "${FF:-}" 2>/dev/null || command -v ffprobe 2>/dev/null || printf '')"
    probe=$(fp_run -v error -show_entries stream=codec_name,codec_type \
                    -show_entries stream_disposition=attached_pic -of csv=p=0 "$src" 2>/dev/null | tr -d '\r')

    # ②a 位图字幕 -> 负映射逐条排除。**不看 ① 的 disp: 能力**: 老 ffmpeg 一样死在这。
    #    判据要读**整张流表**才能定(见下面那条注释), 所以循环里只记账, 排除动作放到
    #    循环之后 —— 顺序跟 lib\common.bat 的 :cover_map 一致。
    local bmpidx=""
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
            # mov_text 是 mp4 的软字幕格式, matroska 装不下 -> 记下来给 EXT=mkv 用
            [ "$codec" = "mov_text" ] && CM_MOV=1
            case " $_SUB_BITMAP " in
                *" $codec "*) bmpidx="$bmpidx $idx/$codec" ;;
            esac
        done <<< "$probe"
    fi
    # —— EXT=mkv 时出口是 `-c:s copy`, 而 mkv 装得下位图字幕, 不该排除;
    #    例外: 源里同时有 mov_text(CM_MOV=1) -> 文本字幕要转成 ass, 而 ass 同样吃不下
    #    位图, 那时两条路都得排除。这里读的是整张表(不是"看到这一行时的状态"),
    #    所以 [位图在前 / mov_text 在后] 的混合源不会被漏判 —— bat 侧是先数完再判,
    #    两侧必须同一个结果。
    if [ -n "$bmpidx" ] && { [ "${EXT:-mp4}" != "mkv" ] || [ "$CM_MOV" = 1 ]; }; then
        for b in $bmpidx; do
            COVER_MAP+=(-map "-0:s:${b%%/*}")
            printf '[sub] %s 含位图字幕 %s —— 本次决定不保留该条\n' \
                "$(basename "$src")" "${b#*/}" >&2
        done
        printf '[sub] (mp4 装不下位图字幕; EXT=mkv 时若要保住它, 请让源里不要带 mov_text)\n' >&2
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

# ================================================================
# 10bit / 硬解能力判定 (2026-09-30 实测)
#
# 两种 10bit 源, 症状不同、修法也不同, 别混为一谈:
#
#   ① H.264 High 10 (profile 110) 源 —— 卡在**解码**侧:
#        [h264 @ ...] Codec h264 profile 110 not supported for hardware decode.
#        Failed setup for format vaapi: hwaccel initialisation returned error.
#      QSV 与 VAAPI 的 H.264 解码器都不吃 High 10。硬解一挂, 帧退回系统内存
#      (还是 10bit), 而编码器要的是硬件表面, 于是
#        Impossible to convert between the formats ... auto_scale_0
#      -> rc=1 / 产物 0 字节。编码器本身没毛病, 所以上一轮给 avc_qsv 加的
#      scale_qsv=format=nv12 修不了这一路(它假定帧已经在 QSV 表面上)。
#      修法: 认出这种源就**不用硬解**(软解), 再把 8bit 帧 upload 上去:
#        实测 h264_qsv / hevc_qsv + H.264 High 10 源 -> rc=0, 产物 yuv420p;
#        h264_vaapi / hevc_vaapi 同款 -> rc=0。
#
#   ② HEVC Main10 源 —— 卡在**编码**侧:
#      硬解没问题(帧已在硬件表面), 但编码器不吃 10bit:
#        h264_qsv  : "some encoding parameters are not supported by the QSV runtime"
#        hevc_vaapi: 脚本写死的 -profile:v:0 main 不接受 10bit 输入
#      修法: 在硬件内部降到 nv12 —— scale_qsv=format=nv12 / scale_vaapi=format=nv12。
#      不能用软滤镜 format=nv12(帧在硬件表面, auto_scale 接不上, 见 avc_qsv 注释)。
#
# 判定只读 probe_source 已缓存的 profile / pix_fmt, 不起新进程。
# ================================================================

# src_is_10bit <文件> —— 源像素格式是 10bit(yuv420p10le / p010 ...) 返回 0
function src_is_10bit() {
    probe_source "$1"
    case "${_PROBE[streams.stream.0.pix_fmt]-}" in
        *10le*|*10be*|*p010*) return 0 ;;
    esac
    return 1
}

# src_hw_decode_hostile <文件> —— 硬件解码器吃不下这个源时返回 0
#
# 目前只有一种: H.264 High 10(QSV / VAAPI 的 H.264 解码器均不支持)。
# profile 取不到时返回 1(保守: 维持原来的硬解路径, 让 ffmpeg 自己报错)。
function src_hw_decode_hostile() {
    probe_source "$1"
    [ "${_PROBE[streams.stream.0.codec_name]-}" = "h264" ] || return 1
    case "${_PROBE[streams.stream.0.profile]-}" in
        *10*) return 0 ;;      # "High 10" / "High 10 Intra"
    esac
    return 1
}

# qsv_encoder_ready <编码器名> —— 该 QSV 编码器在本机真能开起来返回 0
#
# 用 320x240 的 1 帧 lavfi 源试开一次编码器: 不碰用户文件、不落盘。
# 320x240 而不是 128x128 —— NVENC 在过小尺寸上拒绝初始化
#   ("InitializeEncoder failed: invalid argument"), 会把一台 GPU 正常的机器
#   判成不支持(2026-09-16 实测, 见冒烟套件同款注释)。
# 用途: av1_qsv 这类"编码器编进 ffmpeg 了、硬件却不支持"的入口
#   (UHD 770 实测: ffmpeg -encoders 有 av1_qsv, 一开就
#    "Current codec type is unsupported" / rc=-40, 产物 0 字节)。
#   与其让它跑到底留下 0 字节, 不如在动源文件之前就说清楚。
function qsv_encoder_ready() {
    local enc="${1:-}"
    [ -n "$enc" ] || return 1
    ff_run -hide_banner -v error -init_hw_device qsv=hw -filter_hw_device hw \
        -f lavfi -i color=c=black:s=320x240:r=30 -frames:v 1 \
        -vf "format=nv12,hwupload=extra_hw_frames=64" -c:v "$enc" -f null - >/dev/null 2>&1
}

# ================================================================
# 公共默认值 / 公共开关 (2026-10-02)
#
# 由来: 输出容器(EXT)原先在每个入口各写一份"默认值 + 校验 + -c:s 怎么选",
#   加一个容器要改 20 个文件。现在: 默认值集中在 lib/defaults.cfg 的一行里,
#   校验与派生值集中在下面三个函数里, 各入口只剩一句调用。
# ================================================================
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# FB_DEFAULTS: 换一份配置文件(批量里按清单给不同口径时用得着), 缺省是本文件旁边的
#   defaults.cfg。环境变量会被子进程继承, 所以清单驱动设一次, 每条条目都按它走。
_DEFAULTS_CFG_DEFAULT="${_LIB_DIR}/defaults.cfg"

# 去掉首尾空白(纯 bash 内建, 不起 sed/tr): "$(_trim "  mkv ")" -> "mkv"
function _trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# 把 defaults.cfg 里的 KEY=VALUE 装进环境: 已经设过的不覆盖
#   —— 命令行临时值优先, 文件只补没设过的键。文件缺失直接返回 0: 入口有内置
#   兜底值, 不该因为少一个配置文件就全线跑不起来。
function load_defaults() {
    local line k v cfg="${FB_DEFAULTS:-$_DEFAULTS_CFG_DEFAULT}"
    [ -f "$cfg" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        k="$(_trim "${line%%=*}")"
        v="$(_trim "${line#*=}")"
        [ -n "$k" ] || continue
        if [ -z "${!k+x}" ]; then
            export -- "$k=$v"
        fi
    done < "$cfg"
}

# ---------- 输出容器开关 EXT ----------
# 默认值(lib/defaults.cfg) -> 校验 -> 定出 -c:s 的写法。
#   导出 EXT(去空白 + 转小写) 与 SENC 数组("-c:s mov_text" / "-c:s copy")。
#   mp4 是默认值: 命令行与改动前逐字相同。
#   认不出来的值报错返回 1(调用方 exit 1), 不静默回退 mp4 —— EXT 拼错就该当场说,
#   而不是产出一个没人要的 mp4。
# mkv 时 -c:s copy 装不下 mov_text 软字幕(实测 rc=-40 / 0 字节产物), 那种源要在
#   封面闸门之后换成 -c:s ass —— 判定在入口里, 因为要先数过整张流表才知道。
function init_ext() {
    load_defaults
    EXT="$(_trim "${EXT:-}")"
    EXT="${EXT,,}"
    case "$EXT" in
        mp4) SENC=(-c:s mov_text) ;;
        mkv) SENC=(-c:s copy) ;;
        '')  EXT=mp4; SENC=(-c:s mov_text) ;;
        *)   printf 'EXT 只能是 mp4 或 mkv: %s\n' "$EXT" >&2; return 1 ;;
    esac
    export EXT
    return 0
}

# ---------- 目标码率口径 ----------
# 历史口径是把查表值再 /2(三张表都这么写)。BITRATE_NO_HALF=1 时跳过这一步,
#   直接用查表原值 —— 开关的默认值与含义都写在 lib/defaults.cfg, 两族同口径。
#   交互模式手输的码率不经过这里(那是显式指定, 不做任何换算)。
function bitrate_from_table() {
    local raw="$1"
    load_defaults
    case "${BITRATE_NO_HALF:-0}" in
        1) printf '%s\n' "$raw" ;;
        *) printf '%s\n' "$(( raw / 2 ))" ;;
    esac
}

# ================================================================
# 命令行开关解析 (2026-10-03) —— 把 `--key value` / `--key=value` 转成同名大写
# 环境变量。目的: 让 bat / sh / PowerShell 用逐字相同的参数调用, 不再依赖
# 「环境变量前缀赋值」那种只有 bash 认的语法(见 readme 的 FF_ON_EXIST 小节)。
#   优先级: 参数 > 环境变量 > lib/defaults.cfg
#     本函数无条件 export 解析到的值(覆盖已存在的同名 env); 之后调用的
#     load_defaults 只补「没设过」的键 —— 于是参数稳赢 env, env 稳赢 cfg。
#   兼容性: 老的 `set EXT=mkv` / `EXT=mkv ./x.sh` 仍有效(没给参数时 env 自然兜底)。
#   已知开关列在 SWITCH_KEYS; 不在表里的一律当「位置参数」(文件名 / 清单路径)退回,
#   存入 PS_REST, 供调用方 `set -- ${PS_REST[@]+"${PS_REST[@]}"}` 还原。
# ================================================================
SWITCH_KEYS=(ext bitrate_no_half ff_on_exist ff_hwaccel dvd_ext \
             mode dvd_title prefix filt vfilt_extra audio split_chapter \
             extra_titles vbitrate venc dec dry_run)

# 布尔开关(不取值): 这类开关后面紧跟的通常就是文件名, 若按 "--key value" 的老规矩
# 取下一个参数当值, 文件名会被开关吃掉(实测 --dry-run a.mp4 之后脚本再也拿不到
# 输入文件)。两族同名同义, 见 lib/common.bat 的 :parse_switches。
SWITCH_FLAGS=(dry_run)

# 脚本自带的开关键表(默认空 = 用上面的公共 SWITCH_KEYS)。
#   tools/* 用它声明"本脚本自己的开关": 那批键有近百个, 且与入口同名不同义
#   (VENC / MODE / AUDIO / FORMAT ...), 一旦混进公共表就会被 convert_from_list_*
#   的 FWD 转发塞给编码入口。见 TODO.md 阶段 2 的风险 5。
PS_KEYS=()

function _switch_env() {
    # 小写 key -> 大写 env 名(键都是 [a-z_], tr 足够)
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

# 连字符写法(--dry-run)与下划线写法(--dry_run)都认: 环境变量名里不能有 -
function _switch_is_flag() {
    local k="${1//-/_}" f
    for f in ${SWITCH_FLAGS[@]+"${SWITCH_FLAGS[@]}"}; do
        [ "$f" = "${k,,}" ] && return 0
    done
    return 1
}

function parse_switches() {
    PS_REST=()
    # 键表: 调用方用 PS_KEYS 声明过就用它的(tools/*), 否则用公共 SWITCH_KEYS。
    # PS_KEYS 在本文件里已初始化为空数组, 这里可以放心取 ${#PS_KEYS[@]}(set -u 下
    # 也不会因未绑定而中止 —— 那正是 find_ffmpeg 曾经踩过的坑)。
    local -a KEYS=()
    if [ ${#PS_KEYS[@]} -gt 0 ]; then
        KEYS=("${PS_KEYS[@]}")
    else
        KEYS=("${SWITCH_KEYS[@]}")
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --?*)
                local raw="${1#--}" key val=""
                if [[ "$raw" == *=* ]]; then
                    val="${raw#*=}"; key="${raw%%=*}"
                else
                    key="$raw"
                fi
                # 连字符归一: env 名里不能有 -, --dry-run 与 --dry_run 都收
                key="${key//-/_}"
                local lkey="${key,,}" known=0 k
                for k in "${KEYS[@]}"; do
                    if [ "$k" = "$lkey" ]; then known=1; break; fi
                done
                # 先判"是不是已知开关", 再决定要不要吃掉下一个参数: 未知的(--help
                # 之类)整条原样交还脚本, 否则它后面的文件名会被当成开关的值吞掉
                # (老实现就吞 —— tools/scene_detect.sh 的 --help 会因此失效)
                if [ "$known" = 0 ]; then
                    PS_REST+=("$1")
                    shift
                    continue
                fi
                if [ -z "$val" ]; then
                    if _switch_is_flag "$key"; then
                        # 布尔开关默认不取值(后面紧跟的通常是文件名); 但透传层可能
                        # 转发成 "--dry_run 1" 这种带值形式, 那时把那个布尔字面量
                        # 吃掉, 免得它漏成第二个位置参数("More than one parameter")
                        case "${2:-}" in
                            1|0|true|false|yes|no|on|off|TRUE|FALSE|YES|NO|ON|OFF|True|False|Yes|No|On|Off)
                                val="$2"; shift ;;
                            *) val=1 ;;
                        esac
                    else
                        val="${2:-}"; shift
                    fi
                fi
                key="$(_switch_env "$key")"
                export -- "$key=$val"
                ;;
            *)
                PS_REST+=("$1")
                ;;
        esac
        shift
    done
}

# ================================================================
# 统一的 --help / -help / -h
#   用法: ff_help_guard "$0" "$@" [ -- <标题> <用法行> [专属开关行...] ]
#         必须放在脚本刚 parse_switches 完的位置 —— 要早于任何"把 $1 当文件用"的代码,
#         否则 -h 会被当成路径去开, 报一句"文件不存在", 看着像工具坏了。
#   命中后的输出有两种形态:
#     - 给了 `--` 之后的文本: 按 ff_usage_block 的**统一版式**打印(两族同款);
#     - 没给: 打印本脚本文件头那段注释(tools/* 走这条: 它们没有 bat 孪生, 头部
#       注释本身比固定开关表更全, 例如 OS 分发说明)。
#   只认精确相等的三个 token(不做前缀匹配): 免得把 --filt -h 这类**值**误判成求助。
#   脚本自己的 usage() 全部保留(内部 die / 参数缺失时还在用), 这里只是入口。
# ================================================================
function ff_print_usage() {
    # 从第 2 行(标题行)开始, 打到哪儿为止:
    #   - `# ===` 包裹标记: 跳过(tools/* 的头部第一行就是它, 打印出来只是噪声)
    #   - 第一个非注释行(含空行): 停 —— 入口脚本的头部没有包裹标记, 只靠这条收尾
    # 从第 3 行起会丢掉入口脚本的标题行(它们的标题在第 2 行, tools 的在第 3 行)。
    awk 'NR>=2 && !/^#/ { exit } NR>=2 && /^# =+$/ { next } NR>=2 { sub(/^# ?/, ""); print }' "$1"
}

# 用法版式: 与 lib/common.bat 的 :usage **逐字同款**(标题 / 用法行 / 通用开关表 /
# 专属开关行 / 指向 readme)。两族必须打印基本一样的信息, 只有确实有差异的地方才不同
# (脚本名 .sh vs .bat、"拖到 bat 上"这种 bat 独有的用法), 所以文案与版式各只维护一份:
# 改这里要记得同步改 :usage, 反之亦然(lint 不管这个, 靠人守)。
function ff_usage_block() {
    printf '%s\n' '============================================================'
    printf ' %s\n' "$1"; shift
    printf '\n'
    printf ' %s\n' "$1"; shift
    printf '\n'
    printf ' 通用开关（两族同名；也可写成环境变量，参数优先）:\n'
    printf '   --ext mp4,mkv            输出容器（编码类默认 mp4，DVD 类默认 mkv）\n'
    printf '   --dry-run                只打印将要执行的 ffmpeg 命令，不转码\n'
    printf '   --bitrate_no_half 1      目标码率不除以 2\n'
    printf '   --ff_hwaccel auto,none,cuda,qsv,vaapi,d3d11va,dxva2\n'
    printf '                           解码加速器（默认 auto；none = 一次 -hwaccel 都不加）\n'
    printf '   --ff_on_exist skip,overwrite,fail\n'
    printf '                           产物已存在时的策略（默认 skip：打印已跳过，rc=0）\n'
    local a
    for a in "$@"; do printf '   %s\n' "$a"; done
    printf '\n'
    printf ' 完整开关表 / 平台差异 / 退出码契约见 readme.md\n'
    printf '%s\n' '============================================================'
}

function ff_help_guard() {
    local script="$1"; shift
    local a want=0
    for a in "$@"; do
        case "$a" in
            --) break ;;
            --help|-help|-h) want=1; break ;;
        esac
    done
    if [ "$want" != 1 ]; then return 0; fi
    local -a text=()
    local seen=0
    for a in "$@"; do
        if [ "$a" = "--" ]; then seen=1; continue; fi
        [ "$seen" = 1 ] && text+=("$a")
    done
    if [ ${#text[@]} -gt 0 ]; then
        ff_usage_block ${text[@]+"${text[@]}"}
    else
        ff_print_usage "$script"
    fi
    exit 0
    # 没命中也返回 0, 且调用点写成 `declare -F ff_help_guard ... && ff_help_guard ... || :`:
    # tools 里不少脚本开了 set -e, 守卫若以非 0 结束(无论是"没命中"还是"common.sh
    # 缺失、函数不存在"), 整条 && 链都会是非 0, 脚本当场被当成失败静默退掉
    # (实测: 加了守卫之后 dvd_aud_gap.sh 连用法都不打就退出)。调用方不需要用返回值。
}
