@echo off
rem ============================================================
rem cp65001 relaunch guard (ASCII only - do NOT add non-ASCII here)
rem cmd.exe reads a .bat with the codepage of the process that reads
rem it; an in-file chcp can misalign that reader, and the split line
rem fragment is then executed as a command (garbled banner line). So:
rem switch the console to UTF-8 and restart ourselves in a FRESH cmd
rem process, which reads this whole file from byte 0 under UTF-8.
rem Do NOT use a marker ARGUMENT + SHIFT here: SHIFT overwrites %0 as
rem well (documented), so every path derived from the script directory
rem would then resolve against the marker instead of this script. An
rem environment variable keeps %0 and all arguments untouched.
rem SELF_DIR is captured first and used for every sub-call below.
rem SETLOCAL first: the marker must stay inside THIS invocation.
rem Without it the marker leaks into the CALLER environment, so a
rem caller that uses CALL (convert_from_list_*.bat) or a second run
rem in the same cmd session skips the guard and the garbled banner
rem line comes back. The child cmd /c below still inherits it.
setlocal
set "SELF_DIR=%~dp0"
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main

rem ============================================================
rem ffmpeg_copy_to_mp4.bat - 封装修复/转 mp4 (remux, 无重编码)
rem 用法: 拖放视频文件到本 bat 上, 或双击后输入视频地址
rem 公共函数: lib\common.bat
rem ------------------------------------------------------------
rem 路径/命令行拼接规则「第六轮实测, 勿改回 set 包装写法」:
rem   本脚本的 RUN_COM / SRC_CODEC / SRC_FILE / TARGET_FILE 里存的是
rem   「已用双引号包好的路径, 或整条已拼好的命令行」。
rem   set 的包装写法 set "VAR=值" 要求「值里不能出现字面量双引号」;
rem   一旦出现, 例如值以 %FFMPEG_PATH% 的带引号形式开头, 或值里又嵌了带引号的
rem   %SRC_FILE%, 包装引号就会与值里第一个引号配对闭合,
rem   后面的路径段落落进「未加引号区」, 路径里的与号和小括号立刻被 cmd
rem   当成语法字符, 命令行当场被截断。
rem   日志实证: 给 SRC_FILE 赋值那行用的是非包装写法, 路径含「A 与 B 2020」,
rem             结果完整正确; 而拼接 RUN_COM 那行用包装写法加同一路径,
rem             结果 RUN_COM 在 -i 处就被截断, 并报 B is not recognized。
rem   结论: 值里会出现引号的 set 一律用非包装写法 set VAR=值, 这样整行引号
rem   配对是平衡的, 路径里的与号 / 小括号 / 脱字符全落在引号内被保护;
rem   只有值内确定没有引号的常量赋值, 才可以用包装写法。
rem   原版曾用「把与号替换成 脱字符 再跟与号」来补偿包装写法造成的不配对,
rem   在非包装写法下必须去掉, 否则脱字符会进到真实路径里, 勿恢复。
rem ------------------------------------------------------------
rem 注意: 本文件必须保持 CRLF 行尾
rem ============================================================

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo 您有两种使用方式:
echo 1) 直接将待压缩的视频拖放到批处理上
echo 2) 在下面输入待转换视频地址
echo.
echo 由 andreas 编写
echo ============================================================

call "%SELF_DIR%lib\common.bat" find_ffmpeg FF_BIN
if errorlevel 1 goto NO_PATH_ERR
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
set "FFPROBE_PATH=%FF_BIN%\ffprobe.exe"
echo 已找到ffmpeg于:%FFMPEG_PATH%
set RUN_COM="%FFMPEG_PATH%" -hide_banner

SET "SRC_FILE="

if not "%~1"=="" (
    set "SRC_FILE=%~1"
)

if not defined SRC_FILE (
    SET /P SRC_FILE=请输入待转换视频地址:
)

IF not defined SRC_FILE (
    echo 没有输入文件
    exit /b 1
)

set SRC_FILE="%SRC_FILE:"=%"

echo SRC_FILE:%SRC_FILE%

if defined SRC_FILE call "%SELF_DIR%lib\common.bat" get_suffix %SRC_FILE% SUFFIX
echo SUFFIX:%SUFFIX%

if /I "%SUFFIX%" == ".mp4" (
    echo "suffix is mp4, no need to convert"
    goto :eof
) else (
    echo "suffix is not mp4, need to convert"
)

rem 输入必须含视频流: 无视频流的输入产不出有意义的成品, 提前拒绝(与 .sh 的 check_file_isvideo 对齐)
call "%SELF_DIR%lib\common.bat" check_isvideo %SRC_FILE%
if errorlevel 1 exit /b 3
rem moov 前置 (faststart): 默认 mp4 把索引 moov 写在 mdat 后面,
rem 播放器要拿到文件末尾才能起播;本仓库的成品常被拷走/边下边播,
rem 所以 remux 出口统一加 -movflags +faststart, 把 moov 挑到文件头部.
rem 实测 (2026-09-17, 320x240/3s): 不加 = ftyp/free/mdat/moov, 加了 =
rem ftyp/moov/free/mdat, 且两者字节数完全相同(ffmpeg 就地搬移索引, 不涨体积).
set RUN_COM=%RUN_COM% -i %SRC_FILE% -c:v copy -c:a copy -map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0 -movflags +faststart
echo RUN_COM0=%RUN_COM%

echo.
echo SRC_FILE:%SRC_FILE%
if defined SRC_FILE call "%SELF_DIR%lib\common.bat" extract_mp4 %SRC_FILE% TARGET_PATH TARGET_NAME
set TARGET_FILE="%TARGET_PATH:"=%%TARGET_NAME:"=%"
echo TARGET_FILE:%TARGET_FILE%

IF "%~1"=="" SET /P TARGET_FILE=请输入输出文件(如output.mp4,不输入则输出到相同文件夹):
if not defined TARGET_FILE set "TARGET_FILE=output.mp4"
rem 统一给输出路径补引号: 用户手输的可能不带引号, 而不带引号的路径
rem 一旦含 空格/&/( ) 就会被 RUN_COM 的展开拆开
if defined TARGET_FILE set TARGET_FILE="%TARGET_FILE:"=%"
echo SRC_FILE=%SRC_FILE%
echo TARGET_FILE=%TARGET_FILE%

rem handler name with ) (   call set
IF "%~1"=="" (
    echo executing 1
    set RUN_COM=%RUN_COM% %TARGET_FILE%
) else (
    echo executing 2
    set RUN_COM=%RUN_COM% -n %TARGET_FILE%
)

echo RUN_COM2:%RUN_COM%
echo.
%RUN_COM%
rem 负退出码陷阱 (2026-09-17 实测根因): Windows 版 ffmpeg 失败时常常
rem 返回「负」的 AVERROR 值 —— 本机 av1_qsv 拿不到编码器时 ffmpeg.exe
rem 退出码是 -40 (Function not implemented), 而 cmd 的 `if errorlevel N`
rem 是「带符号」比较, -40 >= 1 不成立 → 守卫不会触发,
rem 真失败一路落到文件末尾的 exit /b 0 (探针因此报 rc=0 假 OK).
rem 改成「不等于 0」判定: 它同时兜住负数与正数, 且赋值到变量后
rem 走字符串相等比较, 不依赖 cmd 对负数的数值解析;
rem 值空时也会判成失败(安全侧), 而 if errorlevel 写法在值为空时
rem 只会报语法错误并继续往下跑.
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" (
    echo.
    echo Convert failed! rc=%FB_RC%
    rem 与 .sh 孪生对齐: ffmpeg 失败必须传回 1, 不能吞成 0.
    rem 探针/冒烟/convert_from_list 都依赖这个非零退出码(见 test/README 退出码契约).
    exit /b 1
)


echo ERRORLEVEL:%ERRORLEVEL%
echo 转换已出错或完成, 默认不替换, 请手动确认输出文件完整性

exit /b 0

:NO_PATH_ERR
echo 找不到 ffmpeg.exe: 请安装 ffmpeg(默认查找 C:\Program Files\ffmpeg\bin)
echo 或设置环境变量 FFMPEG_BIN 指向其 bin 目录后重试
pause
exit /b 1
