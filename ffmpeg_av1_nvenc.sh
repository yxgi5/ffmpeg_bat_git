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
echo 欢迎使用ffmpeg视频压缩批处理工具
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
    local size

    size=$(ffprobe -v error -hide_banner \
        -show_entries format=size \
        -of default=noprint_wrappers=1:nokey=1 \
        "$1" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$size" ]; then
        size=$(stat -c%s "$1" 2>/dev/null) # $(du -b "$1" 2>/dev/null | cut -f1)
    fi

    if [ $? -ne 0 ] || [ -z "$size" ]; then
        echo -e "\033[41;36m$1 size检查出错！\033[0m"
        return 1
    fi

    echo "$size"
    return 0
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
    local file="$1"
    local bitrate

    bitrate=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$file" 2>/dev/null)

    # fallback: format bitrate
    if [ -z "$bitrate" ] || ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
        bitrate=$(ffprobe -v error \
            -show_entries format=bit_rate \
            -of default=noprint_wrappers=1:nokey=1 \
            "$file" 2>/dev/null)
    fi

    # 再次校验
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
        echo 0
        return 1
    fi

    echo "$bitrate"
    return 0
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
    echo "请输入待压缩视频地址: "
    read SRC_FILE
else
    SRC_FILE="$1"
fi

# echo $SRC_FILE
check_file_exists "$SRC_FILE"

check_file_isvideo "$SRC_FILE"

SRC_CODEC=$(check_file_codec "$SRC_FILE")
# echo $SRC_CODEC

SRC_FRAMERATE=$(check_file_framerate "$SRC_FILE")
# echo $SRC_FRAMERATE

if [[ $SRC_FRAMERATE == *"/"* ]]; then
    # echo "$1 是视频文件"
    ratenum=$(echo $SRC_FRAMERATE | awk -F'/' '{print $1}')
    rateden=$(echo $SRC_FRAMERATE | awk -F'/' '{print $2}')
    # echo "帧率数字部分："
    # echo "分子: $ratenum"
    # echo "分母: $rateden"
    framerate=$(expr $ratenum / $rateden)
    # echo "$framerate"
    SRC_FRAMERATE=$framerate
fi
# echo $SRC_FRAMERATE

RUN_COM="ffmpeg -hide_banner -threads 0 -v verbose"

# 使用ffprobe获取视频的分辨率信息
# RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv="p=0" "$VIDEO_PATH")
SRC_ROSOLUTION=$(check_file_resolution "$SRC_FILE")
# echo $SRC_ROSOLUTION
# SRC_W=$(echo $SRC_ROSOLUTION | cut -d ',' -f 1)
# SRC_H=$(echo $SRC_ROSOLUTION | cut -d ',' -f 2)
# echo "SRC_W: $SRC_W"
# echo "SRC_H: $SRC_H"
SRC_W=$(echo $SRC_ROSOLUTION | cut -d ' ' -f 1)
SRC_H=$(echo $SRC_ROSOLUTION | cut -d ' ' -f 2)
echo "SRC_W: "$SRC_W
echo "SRC_H: "$SRC_H

SRC_PIX=$(($SRC_W * $SRC_H))
# echo $SRC_PIX

SRC_SIZE=$(check_file_size "$SRC_FILE")
# echo $SRC_SIZE

SRC_DURATION=$(check_file_duration "$SRC_FILE")
# echo $SRC_DURATION
# echo $SRC_DURATION | awk '{print int($0)}'

SRC_BITRATE=$(check_file_bitrate "$SRC_FILE")

if ! [[ "$SRC_BITRATE" =~ ^[0-9]+$ ]] || [ "$SRC_BITRATE" -le 0 ]; then
    TMP=$(( SRC_SIZE * 8 ))
    DURATION_INT=$(printf "%.0f" "$SRC_DURATION")
    
    if [ "$DURATION_INT" -le 0 ]; then
        echo "duration异常"
        exit 1
    fi

    SRC_BITRATE=$(( $TMP / $(echo $SRC_DURATION | awk '{print int($0)}') ))
fi

echo "SRC_BITRATE: $SRC_BITRATE"

if [[ ${SRC_PIX} -le 12288 ]]; then
    BIT=73763
elif [[ ${SRC_PIX} -le 19200 ]]; then
    BIT=104234
elif [[ ${SRC_PIX} -le 21120 ]]
then
    BIT=112222
elif [[ ${SRC_PIX} -le 25344 ]]; then
    BIT=129248
elif [[ ${SRC_PIX} -le 38400 ]]; then
    BIT=178335
elif [[ ${SRC_PIX} -le 64000 ]]; then
    BIT=264923
elif [[ ${SRC_PIX} -le 76800 ]]; then
    BIT=305117
elif [[ ${SRC_PIX} -le 84480 ]]; then
    BIT=328501
elif [[ ${SRC_PIX} -le 96000 ]]; then
    BIT=362702
elif [[ ${SRC_PIX} -le 101376 ]]; then
    BIT=378342
elif [[ ${SRC_PIX} -le 103680 ]]; then
    BIT=384987
elif [[ ${SRC_PIX} -le 112320 ]]; then
    BIT=409618
elif [[ ${SRC_PIX} -le 120000 ]]; then
    BIT=431155
elif [[ ${SRC_PIX} -le 128000 ]]; then
    BIT=453262
elif [[ ${SRC_PIX} -le 153600 ]]; then
    BIT=522032
elif [[ ${SRC_PIX} -le 168960 ]]; then
    BIT=562039
elif [[ ${SRC_PIX} -le 202752 ]]; then
    BIT=647312
elif [[ ${SRC_PIX} -le 224000 ]]; then
    BIT=699275
elif [[ ${SRC_PIX} -le 230400 ]]; then
    BIT=714706
elif [[ ${SRC_PIX} -le 307200 ]]; then
    BIT=893154
elif [[ ${SRC_PIX} -le 337920 ]]; then
    BIT=961604
elif [[ ${SRC_PIX} -le 345600 ]]; then
    BIT=978494
elif [[ ${SRC_PIX} -le 368640 ]]; then
    BIT=1028665
elif [[ ${SRC_PIX} -le 384000 ]]; then
    BIT=1061719
elif [[ ${SRC_PIX} -le 405504 ]]; then
    BIT=1107500
elif [[ ${SRC_PIX} -le 407040 ]]; then
    BIT=1110749
elif [[ ${SRC_PIX} -le 409920 ]]; then
    BIT=1116833
elif [[ ${SRC_PIX} -le 414720 ]]; then
    BIT=1126952
elif [[ ${SRC_PIX} -le 460800 ]]; then
    BIT=1222805
elif [[ ${SRC_PIX} -le 480000 ]]; then
    BIT=1262097
elif [[ ${SRC_PIX} -le 518400 ]]; then
    BIT=1339642
elif [[ ${SRC_PIX} -le 552960 ]]; then
    BIT=1408330
elif [[ ${SRC_PIX} -le 589824 ]]; then
    BIT=1480541
elif [[ ${SRC_PIX} -le 614400 ]]; then
    BIT=1528115
elif [[ ${SRC_PIX} -le 786432 ]]; then
    BIT=1850203
elif [[ ${SRC_PIX} -le 912384 ]]; then
    BIT=2075894
elif [[ ${SRC_PIX} -le 921600 ]]; then
    BIT=2092121
elif [[ ${SRC_PIX} -le 983040 ]]; then
    BIT=2199392
elif [[ ${SRC_PIX} -le 995328 ]]; then
    BIT=2220663
elif [[ ${SRC_PIX} -le 1024000 ]]; then
    BIT=2270066
elif [[ ${SRC_PIX} -le 1049088 ]]; then
    BIT=2313039
elif [[ ${SRC_PIX} -le 1228800 ]]; then
    BIT=2614484
elif [[ ${SRC_PIX} -le 1296000 ]]; then
    BIT=2724592
elif [[ ${SRC_PIX} -le 1310720 ]]; then
    BIT=2748538
elif [[ ${SRC_PIX} -le 1440000 ]]; then
    BIT=2956332
elif [[ ${SRC_PIX} -le 1470000 ]]; then
    BIT=3003939
elif [[ ${SRC_PIX} -le 1555200 ]]; then
    BIT=3137972
elif [[ ${SRC_PIX} -le 1622016 ]]; then
    BIT=3241927
elif [[ ${SRC_PIX} -le 1638400 ]]; then
    BIT=3267270
elif [[ ${SRC_PIX} -le 1764000 ]]; then
    BIT=3459709
elif [[ ${SRC_PIX} -le 1920000 ]]; then
    BIT=3694472
elif [[ ${SRC_PIX} -le 2073600 ]]; then
    BIT=3921463
elif [[ ${SRC_PIX} -le 2211840 ]]; then
    BIT=4122524
elif [[ ${SRC_PIX} -le 2304000 ]]; then
    BIT=4255002
elif [[ ${SRC_PIX} -le 2359296 ]]; then
    BIT=4333909
elif [[ ${SRC_PIX} -le 2457600 ]]; then
    BIT=4473172
elif [[ ${SRC_PIX} -le 2592000 ]]; then
    BIT=4661561
elif [[ ${SRC_PIX} -le 2688000 ]]; then
    BIT=4794775
elif [[ ${SRC_PIX} -le 2764800 ]]; then
    BIT=4900577
elif [[ ${SRC_PIX} -le 3145728 ]]; then
    BIT=5416004
elif [[ ${SRC_PIX} -le 3686400 ]]; then
    BIT=6124157
elif [[ ${SRC_PIX} -le 4085760 ]]; then
    BIT=6632171
elif [[ ${SRC_PIX} -le 4096000 ]]; then
    BIT=6645045
elif [[ ${SRC_PIX} -le 4953600 ]]; then
    BIT=7691832
elif [[ ${SRC_PIX} -le 5038848 ]]; then
    BIT=7794295
elif [[ ${SRC_PIX} -le 5184000 ]]; then
    BIT=7975558
elif [[ ${SRC_PIX} -le 5242880 ]]; then
    BIT=8045653
elif [[ ${SRC_PIX} -le 5760000 ]]; then
    BIT=8653917
elif [[ ${SRC_PIX} -le 5880000 ]]; then
    BIT=8793275
elif [[ ${SRC_PIX} -le 6000000 ]]; then
    BIT=8931995
elif [[ ${SRC_PIX} -le 6144000 ]]; then
    BIT=9097637
elif [[ ${SRC_PIX} -le 6291456 ]]; then
    BIT=9266412
elif [[ ${SRC_PIX} -le 6553600 ]]; then
    BIT=9564109
elif [[ ${SRC_PIX} -le 7372800 ]]; then
    BIT=10477944
elif [[ ${SRC_PIX} -le 7680000 ]]; then
    BIT=10814634
elif [[ ${SRC_PIX} -le 8294400 ]]; then
    BIT=11479171
elif [[ ${SRC_PIX} -le 8847360 ]]; then
    BIT=12067672
elif [[ ${SRC_PIX} -le 9216000 ]]; then
    BIT=12455445
elif [[ ${SRC_PIX} -le 11059200 ]]; then
    BIT=14345280
elif [[ ${SRC_PIX} -le 12000000 ]]; then
    BIT=15281931
elif [[ ${SRC_PIX} -le 12582912 ]]; then
    BIT=15854062
elif [[ ${SRC_PIX} -le 14745600 ]]; then
    BIT=17926925
elif [[ ${SRC_PIX} -le 16384000 ]]; then
    BIT=19451772
elif [[ ${SRC_PIX} -le 20358144 ]]; then
    BIT=23016147
elif [[ ${SRC_PIX} -le 20971520 ]]; then
    BIT=23551619
elif [[ ${SRC_PIX} -le 26214400 ]]; then
    BIT=27996515
elif [[ ${SRC_PIX} -le 30720000 ]]; then
    BIT=31657036
elif [[ ${SRC_PIX} -le 33177600 ]]; then
    BIT=33525231
elif [[ ${SRC_PIX} -le 35389440 ]]; then
    BIT=35325067
elif [[ ${SRC_PIX} -le 36864000 ]]; then
    BIT=36460175
elif [[ ${SRC_PIX} -le 44236800 ]]; then
    BIT=42068888
elif [[ ${SRC_PIX} -le 67108864 ]]; then
    BIT=58072869
elif [[ ${SRC_PIX} -le 132710400 ]]; then
    BIT=98361831
elif [[ ${SRC_PIX} -le 141557760 ]]; then
    BIT=103405226
else
    echo -e "\033[41;36mManual handle it!\033[0m"
    exit 2
fi
# echo $BIT

# 检查变量是否为空
if [[ -z ${BIT} ]]; then
  echo -e "\033[41;36mBitrate not found!\033[0m"
  exit 1
fi

TARGET_BITRATE=$((${BIT} / 2))
echo "ref TARGET_BITRATE: $TARGET_BITRATE"

percentage=$(( $((${TARGET_BITRATE} * 100 )) / ${SRC_BITRATE} ))
echo "compress percentage: "$percentage"%"

# pause
if [[ ${percentage} -ge 100 ]]
then
   # echo -e "\033[41;36msource bitrate too low, no need to compress\033[0m"
   # exit 3
   TARGET_BITRATE=${SRC_BITRATE}
fi

if [[ ${percentage} -le 0 ]]
then
   echo "bitrate unnomal, please check"
   echo -e "\033[41;36mbitrate unnomal, please check\033[0m"
   exit 4
fi

if [ "$param_number" -eq 0 ]; then
    echo "请输入输出码率(如1150k,不输入则保持默认): "
    read TARGET_BITRATE_1
    # 检查变量是否为空
    if ! [[ -z ${TARGET_BITRATE_1} ]]; then
        TARGET_BITRATE = "$TARGET_BITRATE_1"
	fi
fi
echo "real TARGET_BITRATE = $TARGET_BITRATE"

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
TARGET_FILE="$ABS_PATH/$filename_without_suffix""-compressed.mp4"


echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"


echo "ABS_NAME: ${ABS_NAME}"
# RUN_COM="${RUN_COM} -hwaccel auto -i \"${ABS_NAME}\""
RUN_COM="${RUN_COM} -hwaccel cuvid -hwaccel_output_format cuda -i \"${ABS_NAME}\" -vf \"hwdownload, format=nv12\""

if [ "$SRC_FRAMERATE" -gt 31 ]; then
    RUN_COM="$RUN_COM -r 30"
    echo "DOWN TARGET FRAME RATE TO 30"
fi
# echo $RUN_COM

RUN_COM="${RUN_COM} -c:v av1_nvenc -profile:v main -preset p4 -tune:v hq -rc vbr -b_ref_mode middle -aq-strength 8 -temporal-aq 1 -spatial-aq 1 -multipass fullres -lookahead_level auto -rc-lookahead 32 -b:v $TARGET_BITRATE -maxrate $TARGET_BITRATE -bufsize $((TARGET_BITRATE*2)) -pix_fmt nv12 -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 -n \"${TARGET_FILE}\""
#RUN_COM="${RUN_COM} -c:v av1_nvenc -profile:v main -preset p4 -tune:v hq -rc cbr -b:v $TARGET_BITRATE -fps_mode cfr -pix_fmt yuv420p -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 -n \"${TARGET_FILE}\""
echo "RUN_COM: ${RUN_COM}"

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





