#!/bin/bash

# BASH Shell: For Loop File Names With Spaces
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================

function pause() {
    read -n 1
}

function check_param_number() {
    # 检查参数个数是否为1
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

function check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    else
        return 0
    fi
}

function check_file_exists() {
    if ! [ -f "$1" ]; then
        echo -e "\033[41;36mfile not exists!\033[0m"
        exit 1
    fi
}

function check_file_isvideo() {
    file_type=$(ffprobe -v error -hide_banner -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)

    # 检查编码类型是否包含视频关键字
    if [[ $file_type == *"video"* ]]; then
        return 0
    else
        echo -e "\033[41;36m$1 不是视频文件!\033[0m"
        exit 1
    fi
}

function check_file_codec() {
    local codec=$(ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x "$1" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36m$1 codec检查出错！\033[0m"
        exit 1
    else
        echo "$codec"
        return 0
    fi
}

function check_file_framerate() {
    local framerate=$(ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$1" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36m$1 codec检查出错！\033[0m"
        exit 1
    else
        echo "$framerate"
        return 0
    fi
}

function check_file_resolution() {
    local resolution=$(ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -print_format flat -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36m$1 resolution检查出错！\033[0m"
        exit 1
    else
        echo "$resolution"
        return 0
    fi
}

function check_file_size() {
    local size=$(ffprobe -v error -hide_banner -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36m$1 size检查出错！\033[0m"
        exit 1
    else
        echo "$size"
        return 0
    fi
}

function check_file_duration() {
    local duration=$(ffprobe -v error -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36m$1 duration检查出错！\033[0m"
        exit 1
    else
        echo "$duration"
        return 0
    fi
}

function check_file_bitrate() {
    local bitrate=$(ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0:s=x "$1" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36m$1 bitrate检查出错！\033[0m"
        exit 1
    else
        echo "$bitrate"
        return 0
    fi
}

function check_file_suffix() {
    local filename="$(basename "$*")"
    local extension="${filename#*.}"
    # 开启不区分大小写的比较模式
    if [ "${extension,,}" == "mp4" ]; then
        echo -e "suffix ${extension,,} 已经是mp4文件，不需要转换"
        exit 0
    else
        echo "suffix ${extension,,} not mp4 file, need to convert"
    fi
    # 关闭不区分大小写的比较模式
}

#     # 去除后缀
#     # 获取扩展名
#     # 组合目录和文件名
# }

if ! check_command "ffmpeg"; then
    echo -e "\033[41;36mffmpeg command not found!\033[0m"
    exit 1
fi

if ! check_command "ffprobe"; then
    echo -e "\033[41;36mffprobe command not found!\033[0m"
    exit 1
fi

check_param_number "$#"
param_number=$?

if [ "$param_number" -eq 0 ]; then
    echo "请输入待转换视频地址: "
    read SRC_FILE
else
    SRC_FILE="$1"
fi

check_file_exists "$SRC_FILE"

check_file_suffix "$SRC_FILE"

RUN_COM="ffmpeg -hide_banner"

echo "SRC_FILE: $SRC_FILE"
ABS_NAME=$(realpath "$SRC_FILE")

# # 去除后缀
# # 获取扩展名
# # 组合目录和文件名

echo "ABS_NAME: ${ABS_NAME}"

ABS_PATH="$(dirname "$ABS_NAME")"

filename="$(basename "$ABS_NAME")"

# 去除后缀
filename_without_suffix="${filename%.*}"

# 获取扩展名
extension="${filename#*.}"

# 组合目录和文件名
TARGET_FILE="$ABS_PATH/$filename_without_suffix"".mp4"

echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"

echo
RUN_COM="${RUN_COM} -i \"${ABS_NAME}\""
RUN_COM="${RUN_COM} -c:v copy -c:a copy -n \"${TARGET_FILE}\""
echo "RUN_COM: ${RUN_COM}"

eval "${RUN_COM}"
if [ "$?" -ne 0 ]; then
    echo -e "\033[41;36mConvert failed！\033[0m"
    exit 1
fi

IFS=$SAVEIFS
