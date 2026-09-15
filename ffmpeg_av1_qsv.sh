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

#     # 去除后缀
#     # 获取扩展名
#     # 组合目录和文件名
# }

OS=$(uname -s)

case "$OS" in
    Linux*)
        export PATH=/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin:$PATH
        ;;
    CYGWIN*)
        ;;
    MSYS*)
        ;;
    MINGW*)
        ;;
    *)
        ;;
esac

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
    echo "请输入待压缩视频地址: "
    read SRC_FILE
else
    SRC_FILE="$1"
fi

check_file_exists "$SRC_FILE"

check_file_isvideo "$SRC_FILE"

SRC_CODEC=$(check_file_codec "$SRC_FILE")

SRC_FRAMERATE=$(check_file_framerate "$SRC_FILE")

if [[ $SRC_FRAMERATE == *"/"* ]]; then
    ratenum=$(echo $SRC_FRAMERATE | awk -F'/' '{print $1}')
    rateden=$(echo $SRC_FRAMERATE | awk -F'/' '{print $2}')
    framerate=$(expr $ratenum / $rateden)
    SRC_FRAMERATE=$framerate
fi

RUN_COM="ffmpeg -hide_banner -threads 0 -v verbose"

# 使用ffprobe获取视频的分辨率信息
SRC_RESOLUTION=$(check_file_resolution "$SRC_FILE")
SRC_W=$(echo $SRC_RESOLUTION | cut -d ' ' -f 1)
SRC_H=$(echo $SRC_RESOLUTION | cut -d ' ' -f 2)
echo "SRC_W: "$SRC_W
echo "SRC_H: "$SRC_H

SRC_PIX=$(($SRC_W * $SRC_H))

SRC_SIZE=$(check_file_size "$SRC_FILE")

SRC_DURATION=$(check_file_duration "$SRC_FILE")

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
    BIT=71919
elif [[ ${SRC_PIX} -le 19200 ]]; then
    BIT=101628
elif [[ ${SRC_PIX} -le 21120 ]]
then
    BIT=109416
elif [[ ${SRC_PIX} -le 25344 ]]; then
    BIT=126017
elif [[ ${SRC_PIX} -le 38400 ]]; then
    BIT=162285
elif [[ ${SRC_PIX} -le 64000 ]]; then
    BIT=241080
elif [[ ${SRC_PIX} -le 76800 ]]; then
    BIT=277657
elif [[ ${SRC_PIX} -le 84480 ]]; then
    BIT=298936
elif [[ ${SRC_PIX} -le 96000 ]]; then
    BIT=330059
elif [[ ${SRC_PIX} -le 101376 ]]; then
    BIT=344291
elif [[ ${SRC_PIX} -le 103680 ]]; then
    BIT=350338
elif [[ ${SRC_PIX} -le 112320 ]]; then
    BIT=372752
elif [[ ${SRC_PIX} -le 120000 ]]; then
    BIT=392351
elif [[ ${SRC_PIX} -le 128000 ]]; then
    BIT=412468
elif [[ ${SRC_PIX} -le 153600 ]]; then
    BIT=475049
elif [[ ${SRC_PIX} -le 168960 ]]; then
    BIT=511456
elif [[ ${SRC_PIX} -le 202752 ]]; then
    BIT=589054
elif [[ ${SRC_PIX} -le 224000 ]]; then
    BIT=636341
elif [[ ${SRC_PIX} -le 230400 ]]; then
    BIT=650383
elif [[ ${SRC_PIX} -le 307200 ]]; then
    BIT=812770
elif [[ ${SRC_PIX} -le 337920 ]]; then
    BIT=875060
elif [[ ${SRC_PIX} -le 345600 ]]; then
    BIT=890429
elif [[ ${SRC_PIX} -le 368640 ]]; then
    BIT=936085
elif [[ ${SRC_PIX} -le 384000 ]]; then
    BIT=966165
elif [[ ${SRC_PIX} -le 405504 ]]; then
    BIT=1007825
elif [[ ${SRC_PIX} -le 407040 ]]; then
    BIT=1010782
elif [[ ${SRC_PIX} -le 409920 ]]; then
    BIT=1016318
elif [[ ${SRC_PIX} -le 414720 ]]; then
    BIT=1025527
elif [[ ${SRC_PIX} -le 460800 ]]; then
    BIT=1112752
elif [[ ${SRC_PIX} -le 480000 ]]; then
    BIT=1148508
elif [[ ${SRC_PIX} -le 518400 ]]; then
    BIT=1219074
elif [[ ${SRC_PIX} -le 552960 ]]; then
    BIT=1281580
elif [[ ${SRC_PIX} -le 589824 ]]; then
    BIT=1347292
elif [[ ${SRC_PIX} -le 614400 ]]; then
    BIT=1390585
elif [[ ${SRC_PIX} -le 786432 ]]; then
    BIT=1683685
elif [[ ${SRC_PIX} -le 912384 ]]; then
    BIT=1889063
elif [[ ${SRC_PIX} -le 921600 ]]; then
    BIT=1903830
elif [[ ${SRC_PIX} -le 983040 ]]; then
    BIT=2001447
elif [[ ${SRC_PIX} -le 995328 ]]; then
    BIT=2020803
elif [[ ${SRC_PIX} -le 1024000 ]]; then
    BIT=2065760
elif [[ ${SRC_PIX} -le 1049088 ]]; then
    BIT=2104865
elif [[ ${SRC_PIX} -le 1228800 ]]; then
    BIT=2379180
elif [[ ${SRC_PIX} -le 1296000 ]]; then
    BIT=2479379
elif [[ ${SRC_PIX} -le 1310720 ]]; then
    BIT=2501170
elif [[ ${SRC_PIX} -le 1440000 ]]; then
    BIT=2690262
elif [[ ${SRC_PIX} -le 1470000 ]]; then
    BIT=2733585
elif [[ ${SRC_PIX} -le 1555200 ]]; then
    BIT=2855554
elif [[ ${SRC_PIX} -le 1622016 ]]; then
    BIT=2950154
elif [[ ${SRC_PIX} -le 1638400 ]]; then
    BIT=2973216
elif [[ ${SRC_PIX} -le 1764000 ]]; then
    BIT=2923448
elif [[ ${SRC_PIX} -le 1920000 ]]; then
    BIT=3121828
elif [[ ${SRC_PIX} -le 2073600 ]]; then
    BIT=3313636
elif [[ ${SRC_PIX} -le 2211840 ]]; then
    BIT=3483539
elif [[ ${SRC_PIX} -le 2304000 ]]; then
    BIT=3595477
elif [[ ${SRC_PIX} -le 2359296 ]]; then
    BIT=3662154
elif [[ ${SRC_PIX} -le 2457600 ]]; then
    BIT=3779831
elif [[ ${SRC_PIX} -le 2592000 ]]; then
    BIT=3939019
elif [[ ${SRC_PIX} -le 2688000 ]]; then
    BIT=4051585
elif [[ ${SRC_PIX} -le 2764800 ]]; then
    BIT=4140988
elif [[ ${SRC_PIX} -le 3145728 ]]; then
    BIT=4576523
elif [[ ${SRC_PIX} -le 3686400 ]]; then
    BIT=5174913
elif [[ ${SRC_PIX} -le 4085760 ]]; then
    BIT=5604184
elif [[ ${SRC_PIX} -le 4096000 ]]; then
    BIT=5615063
elif [[ ${SRC_PIX} -le 4953600 ]]; then
    BIT=6506098
elif [[ ${SRC_PIX} -le 5038848 ]]; then
    BIT=6592680
elif [[ ${SRC_PIX} -le 5184000 ]]; then
    BIT=6739346
elif [[ ${SRC_PIX} -le 5242880 ]]; then
    BIT=6798577
elif [[ ${SRC_PIX} -le 5760000 ]]; then
    BIT=7312560
elif [[ ${SRC_PIX} -le 5880000 ]]; then
    BIT=7430318
elif [[ ${SRC_PIX} -le 6000000 ]]; then
    BIT=7547536
elif [[ ${SRC_PIX} -le 6144000 ]]; then
    BIT=7687503
elif [[ ${SRC_PIX} -le 6291456 ]]; then
    BIT=7830066
elif [[ ${SRC_PIX} -le 6553600 ]]; then
    BIT=8081672
elif [[ ${SRC_PIX} -le 7372800 ]]; then
    BIT=8853863
elif [[ ${SRC_PIX} -le 7680000 ]]; then
    BIT=9138366
elif [[ ${SRC_PIX} -le 8294400 ]]; then
    BIT=9699834
elif [[ ${SRC_PIX} -le 8847360 ]]; then
    BIT=10197183
elif [[ ${SRC_PIX} -le 9216000 ]]; then
    BIT=10524851
elif [[ ${SRC_PIX} -le 11059200 ]]; then
    BIT=12121697
elif [[ ${SRC_PIX} -le 12000000 ]]; then
    BIT=12913232
elif [[ ${SRC_PIX} -le 12582912 ]]; then
    BIT=13396618
elif [[ ${SRC_PIX} -le 14745600 ]]; then
    BIT=15148251
elif [[ ${SRC_PIX} -le 16384000 ]]; then
    BIT=16436682
elif [[ ${SRC_PIX} -le 20358144 ]]; then
    BIT=19448644
elif [[ ${SRC_PIX} -le 20971520 ]]; then
    BIT=19901118
elif [[ ${SRC_PIX} -le 26214400 ]]; then
    BIT=23657056
elif [[ ${SRC_PIX} -le 30720000 ]]; then
    BIT=26750261
elif [[ ${SRC_PIX} -le 33177600 ]]; then
    BIT=28393820
elif [[ ${SRC_PIX} -le 35389440 ]]; then
    BIT=29849682
elif [[ ${SRC_PIX} -le 36864000 ]]; then
    BIT=30808848
elif [[ ${SRC_PIX} -le 44236800 ]]; then
    BIT=35483211
elif [[ ${SRC_PIX} -le 67108864 ]]; then
    BIT=49006510
elif [[ ${SRC_PIX} -le 132710400 ]]; then
    BIT=76722229
elif [[ ${SRC_PIX} -le 141557760 ]]; then
    BIT=80656076 
else
    echo -e "\033[41;36mManual handle it!\033[0m"
    exit 2
fi

# 检查变量是否为空
if [[ -z ${BIT} ]]; then
  echo -e "\033[41;36mBitrate not found!\033[0m"
  exit 1
fi

TARGET_BITRATE=$((${BIT} / 2))
echo "ref TARGET_BITRATE: $TARGET_BITRATE"

percentage=$(( $((${TARGET_BITRATE} * 100 )) / ${SRC_BITRATE} ))
echo "compress percentage: "$percentage"%"

if [[ ${percentage} -ge 100 ]]
then
   TARGET_BITRATE=${SRC_BITRATE}
fi

if [[ ${percentage} -le 0 ]]
then
   echo "bitrate abnormal, please check"
   echo -e "\033[41;36mbitrate abnormal, please check\033[0m"
   exit 4
fi

if [ "$param_number" -eq 0 ]; then
    echo "请输入输出码率(如1150k,不输入则保持默认): "
    read TARGET_BITRATE_1
    # 检查变量是否为空
    if ! [[ -z ${TARGET_BITRATE_1} ]]; then
        TARGET_BITRATE="$TARGET_BITRATE_1"
	fi
fi
echo "real TARGET_BITRATE = $TARGET_BITRATE"

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
TARGET_FILE="$ABS_PATH/$filename_without_suffix""-compressed.mp4"

echo -e "\033[42;31mTARGET_FILE: '$TARGET_FILE'\033[0m"

echo "ABS_NAME: ${ABS_NAME}"
RUN_COM="${RUN_COM} -init_hw_device qsv=hw:0 -filter_hw_device hw -hwaccel qsv -hwaccel_output_format qsv -i \"${ABS_NAME}\""

if [ "$SRC_FRAMERATE" -gt 31 ]; then
    RUN_COM="$RUN_COM -r 30"
    echo "DOWN TARGET FRAME RATE TO 30"
fi

RUN_COM="${RUN_COM} -c:v av1_qsv -profile:v main -preset fast -b:v $TARGET_BITRATE -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:v -map 0:a -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024 -n \"${TARGET_FILE}\""
echo "RUN_COM: ${RUN_COM}"

eval "${RUN_COM}"
if [ "$?" -ne 0 ]; then
    echo -e "\033[41;36mConvert failed！\033[0m"
    exit 1
fi

IFS=$SAVEIFS
