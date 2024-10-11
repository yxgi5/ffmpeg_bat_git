#!/bin/bash

# BASH Shell: For Loop File Names With Spaces
# Set $IFS variable
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")


# see ABS(Advanced Bash Shell) $9.1 内部变量(内置变量, 如：PS1，PATH，UID，HOSTNAME，$$，BASHPID，PPID，$?，HISTSIZE)
# echo $0           # 脚本本身的名字(命令本身,包括路径) This is similar to argv[0] in C
# echo "The sctipt name is `basename $0`"
# echo $1           # 传递给该shell脚本的第一个参数 This is similar to argv[1] in C
# echo $2           # 传递给该shell脚本的第二个参数 This is similar to argv[2] in C
# ...
# echo ${10}        # This is similar to argv[10] in C. About `echo $10`, if $1 is first, then $10 is first0
# echo ${11}        # This is similar to argv[11] in C.
# ...
# echo $#           # 传给脚本的参数个数 number of args. This is similar to argc in C. try `bash -c 'echo $#' _ x y z`   `bash -c 'echo $#' _ x y` 
# echo $*           # 传给脚本的所有参数的列表，用双引号("$*")有参数合并成一个字符串，没有双引号($*)和($@)一样
# echo $@           # 传给脚本的所有参数的列表，可以当作数组用
# echo $?           # 上一个执行指令的返回值(0~255, 0代表成功) return value in function just called or exit value of last one command
# echo $$           # current shell PID
# echo $!           # 上一个后台执行指令的PID
# echo $PPID        # 父进程ID

echo ============================================================
echo 欢迎使用ffmpeg视频 intel qsv h265 压缩批处理工具
echo
echo 由 andreas 编写
echo ============================================================


function pause() {
    read -n 1
}

# if command -v ffmpeg &> /dev/null; then
#     echo "命令存在"
# else
#     echo "命令不存在"
# fi

function check_param_number() {
    # 检查参数个数是否为1
    # if [ "$1" -ne 1 ]; then
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
        # echo "命令 '$1' 未找到。"
        return 1
    else
        # echo "命令 '$1' 已找到。"
        return 0
    fi
}

# check_command "ls"


function check_file_exists() {
    if ! [ -f "$1" ]; then
        echo -e "\033[41;36mfile not exists!\033[0m"
        exit 1
    fi
}

function check_file_isvideo() {
    # ffprobe -v error -show_format -show_streams example.mp4
    # file_type=$(ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$1" 2>/dev/null)
    file_type=$(ffprobe -v error -hide_banner -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)

    # 检查编码类型是否包含视频关键字
    if [[ $file_type == *"video"* ]]; then
        # echo "$1 是视频文件"
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
    #echo ${extension^^} # 大写
    #echo ${extension,,} # 大写
    # 开启不区分大小写的比较模式
    #shopt -s nocasematch
    if [ "${extension,,}" == "mp4" ]; then
        echo -e "suffix ${extension,,} 已经是mp4文件，不需要转换"
        exit 0
    else
        echo "suffix ${extension,,} not mp4 file, need to convert"
    fi
    # 关闭不区分大小写的比较模式
    #shopt -u nocasematch
}

# function name_output_file() {
#     # local ABS_NAME="$(realpath "$*")"
#     # local ABS_PATH="$(dirname "$ABS_NAME")"
#     # local filename="$(basename "$ABS_NAME")"

#     local ABS_PATH="$(dirname "$*")"
#     local filename="$(basename "$*")"
#     # 去除后缀
#     local filename_without_suffix="${filename%.*}"
#     # 获取扩展名
#     local extension="${filename#*.}"
#     # 组合目录和文件名
#     local full_path_output="$ABS_PATH/$filename_without_suffix""-compressed.mp4"
#     echo $full_path_output
#     return 0
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
#echo $param_number

if [ "$param_number" -eq 0 ]; then
    echo "请输入待转换视频地址: "
    read SRC_FILE
else
    SRC_FILE="$1"
fi

# echo $SRC_FILE
check_file_exists "$SRC_FILE"

#check_file_isvideo "$SRC_FILE"

check_file_suffix "$SRC_FILE"
# pause

RUN_COM="ffmpeg -hide_banner"

echo "SRC_FILE: $SRC_FILE"
ABS_NAME=$(realpath "$SRC_FILE")

# ABS_NAME=$(readlink -f $SRC_FILE) # try `readlink -f .`
# echo $ABS_NAME
# ABS_NAME=$(realpath $SRC_FILE)
# echo $ABS_NAME

# filepath="$(dirname "$SRC_FILE")"
# echo $filepath
# filename="$(basename "$SRC_FILE")"
# echo $filename
# # 去除后缀
# filename_without_suffix="${filename%.*}"
# echo $filename_without_suffix
# # 获取扩展名
# extension="${filename#*.}"
# echo $extension
# # 组合目录和文件名
# full_path_output="$filepath/$filename_without_suffix"".mp4"
# echo $full_path_output

echo "ABS_NAME: ${ABS_NAME}"
# TARGET_FILE=$(name_output_file ${ABS_NAME})

ABS_PATH="$(dirname "$ABS_NAME")"
# echo "ABS_PATH: ${ABS_PATH}"

filename="$(basename "$ABS_NAME")"
# echo "filename: ${filename}"

# 去除后缀
filename_without_suffix="${filename%.*}"
# echo "filename_without_suffix: ${filename_without_suffix}"

# 获取扩展名
extension="${filename#*.}"
# echo "extension: ${extension}"

# 组合目录和文件名
TARGET_FILE="$ABS_PATH/$filename_without_suffix"".mp4"


echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"

echo "SRC ABS_NAME: ${ABS_NAME}"
echo
RUN_COM="${RUN_COM} -i \"${ABS_NAME}\""
RUN_COM="${RUN_COM} -c:v copy -c:a copy -n \"${TARGET_FILE}\""
echo "RUN_COM: ${RUN_COM}"
# pause
# RUN_COM=${RUN_COM}' -i '\"${ABS_NAME}\"
# RUN_COM=${RUN_COM}' -c:v:0 libx264 -profile:v main -preset veryfast -b:v $TARGET_BITRATE -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 102 -n '\"${TARGET_FILE}\"

# RUN_COM="${RUN_COM} -i \"${ABS_NAME}\""
# RUN_COM="${RUN_COM} -c:v:0 libx264 -profile:v main -preset veryfast -b:v $TARGET_BITRATE -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 102 -n \"${TARGET_FILE}\""
# echo "RUN_COM: ${RUN_COM}"

# `${RUN_COM}`
# $(${RUN_COM})
# $("${RUN_COM}")
eval "${RUN_COM}"
if [ "$?" -ne 0 ]; then
    echo -e "\033[41;36mConvert failed！\033[0m"
    exit 1
fi


# restore $IFS
IFS=$SAVEIFS





