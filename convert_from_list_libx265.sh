#!/bin/bash

# BASH Shell: For Loop File Names With Spaces
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

function pause() {
    read -n 1
}

#     # 检查参数个数是否为1
# }

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

function check_file_exists() {
    if ! [ -f "$1" ]; then
        echo -e "\033[41;36mList file not exists!\033[0m"
        exit 1
    fi
}

function check_file_is_text() {
    # 使用file命令检查文件类型
    local file_type=$(file --mime "$1")
    
    # 检查输出是否包含“text”
    if [[ $file_type == *text* ]]; then
        return 0
    else
        echo -e "\033[41;36mNot a plain text file!\033[0m"
        exit 1
    fi
}

LIST_FILE=""
check_param_number "$#"
param_number=$?
if [ "$param_number" -eq 0 ]; then
    LIST_FILE="list.txt"
else
    LIST_FILE="$1"
fi

check_file_exists "${LIST_FILE}"
if [ "$?" -ne 0 ]; then
    exit 1
fi
echo "LIST_FILE = ${LIST_FILE}"

check_file_is_text "${LIST_FILE}"

#do

for line in $(cat ${LIST_FILE})
do
    echo $line
    ./ffmpeg_libx265.sh "${line}"

    if [ "$?" -ne 0 ]; then
        echo -e "\033[41;36mConvert failed！\033[0m"
        exit 1
    fi
done

# do

IFS=$SAVEIFS
