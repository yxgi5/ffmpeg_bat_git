#!/bin/bash
# ffmpeg_copy_to_mp4.sh - 无损转封装为 mp4 (P1 重构版)
# 用法: ./ffmpeg_copy_to_mp4.sh [视频文件]
#   不带参数: 交互输入文件路径
# 行为: 视频流/音频流直接 copy, 仅重新封装容器; 已是 mp4 后缀则直接退出

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# 检查后缀是否已是 mp4 (不区分大小写)
function check_file_suffix() {
    local filename extension
    filename="$(basename "$1")"
    extension="${filename#*.}"
    # EXT 决定"已经是目标容器就退出"的那个后缀: EXT=mkv 时 .mp4 源照样要转
    if [ "${extension,,}" == "${EXT}" ]; then
        echo -e "suffix ${extension,,} 已经是${EXT}文件，不需要转换"
        exit 0
    else
        echo "suffix ${extension,,} not ${EXT} file, need to convert"
    fi
}

# ---------- 输出容器开关 EXT: mp4(默认) / mkv ----------
# 默认值写在 lib/defaults.cfg(两族共用一份), 校验 / 去空白 / -c:s 的选法统统在
# lib/common.sh 的 init_ext 里 —— 加容器、改默认都只动那一处, 入口不再各写一遍。
# 命令行 EXT=mkv 优先于配置文件(load_defaults 只补没设过的键)。
init_ext || exit 1
# ---------- 前置检查 ----------
# ffmpeg 定位走 lib/common.sh 的 find_ffmpeg, 与 .bat 侧同序:
#   FFMPEG_BIN(目录) / FFMPEG(可执行文件) > 仓库内 ffmpeg/bin > PATH 逐项 > 常见前缀
# 不能只信 command -v: 它只回第一个命中, 而"第一个"经常正是缺能力的那个
#   (Linux 上就是发行版那份 4.4.2), 后面那个能用的构建于是永远轮不到
# 本脚本是 -c copy, 哪个构建都能干, 所以不传能力要求
if ! FF="$(find_ffmpeg)"; then
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
param_number=$?

# ---------- 输入文件 ----------
if [ "$param_number" -eq 0 ]; then
    echo "请输入待转换视频地址: "
    read -r SRC_FILE
else
    SRC_FILE="$1"
fi

check_file_exists "$SRC_FILE"
check_file_suffix "$SRC_FILE"

# ---------- 输出路径 ----------
echo "SRC_FILE: $SRC_FILE"
ABS_NAME=$(realpath "$SRC_FILE")
echo "ABS_NAME: ${ABS_NAME}"

ABS_PATH="$(dirname "$ABS_NAME")"
filename="$(basename "$ABS_NAME")"
filename_without_suffix="${filename%.*}"
TARGET_FILE="${ABS_PATH}/${filename_without_suffix}.${EXT}"

echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"
echo

# EXT=mkv 而 matroska 装不下 mov_text 软字幕(实测 rc=-40 / 0 字节), 所以要先
# 知道源里有没有 —— 顺路用一次封面闸门, 它已经把每条流的 codec 数过一遍了。
if [ "$EXT" = mkv ]; then
    cover_map_gate "$FF"
    [ "${CM_MOV:-0}" = 1 ] && SENC=(-c:s ass)
fi

# ---------- 构建并执行 ffmpeg 命令 (数组, 无 eval) ----------
CMD=("$FF" -hide_banner)
CMD+=(-i "$ABS_NAME")
CMD+=(-c:v copy -c:a copy)
# 流映射与 11 个编码入口完全一致 (2026-09-17 用户裁定): 默认选流只留 1 视频 + 1 音频,
# 多音轨/多字幕会被静默丢掉; 图形字幕(PGS/VobSub)转 mov_text 会失败, 属已知代价。
CMD+=(-map 0:v -map 0:a? -map 0:s? "${SENC[@]}" -map_metadata 0 -map_chapters 0)
# moov 前置 (faststart): 默认 mp4 把索引 moov 写在 mdat 后面, 播放器必须
# 拿到文件末尾才能起播;成品常被拷走/边下边播, 故统一加 faststart.
# 实测: 不加 = ftyp/free/mdat/moov, 加了 = ftyp/moov/free/mdat, 字节数相同.
CMD+=(-movflags +faststart)
CMD+=(-n "$TARGET_FILE")

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
