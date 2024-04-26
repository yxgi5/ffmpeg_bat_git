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

function pause() {
    read -n 1
}

function check_param_number() {
    # 检查参数个数是否为1
    if [ $1 -ne 1 ]; then
        echo -e "\033[41;36mMore than one parameter. A single file name must given!\033[0m"
        exit 1
    fi
}

function check_file_exists() {
    if ! [ -f "$1" ]; then
        echo -e "\033[41;36mfile not exists!\033[0m"
        exit 1
    fi
}

function check_file_istext() {
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
if [ "$?" -ne 0 ]; then
    exit 1
fi
LIST_FILE="$1"
check_file_exists "${LIST_FILE}"
if [ "$?" -ne 0 ]; then
    exit 1
fi
echo "LIST_FILE = ${LIST_FILE}"

check_file_istext "${LIST_FILE}"



#while IFS= read -r line
#do
#    echo "${line}"
#    #./ffmpeg_lib265.sh "${line}"
#done < "${LIST_FILE}"

for line in $(cat ${LIST_FILE})
do
   echo $line
   ./ffmpeg_lib265.sh "${line}"
   if [ "$?" -ne 0 ]; then
       echo -e "\033[41;36mConvert failed！\033[0m"
       exit 1
   fi
done

# cat ${LIST_FILE} | while IFS= read -r line
# do
#    echo $line
#    ./ffmpeg_lib265.sh "${line}"
#    if [ "$?" -ne 0 ]; then
#        echo -e "\033[41;36mConvert failed！\033[0m"
#        exit 1
#    fi
# done


#rm packup_folder_name_with_space_del.sh
# restore $IFS
IFS=$SAVEIFS