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
rem ffmpeg_hevc_qsv.bat - HEVC QSV 硬件加速压缩 (P1 重构版)
rem 用法: 拖放视频文件到本 bat 上, 或双击后输入视频地址
rem 码率查表: lib\bitrate_table_hevc.csv | 公共函数: lib\common.bat
rem 注意: 本文件必须保持 CRLF 行尾
rem ============================================================

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo 您有两种使用方式:
echo 1) 直接将待压缩的视频拖放到批处理上
echo 2) 在下面输入待压缩视频地址
echo.
echo 由 andreas 编写
echo ============================================================

call "%SELF_DIR%lib\common.bat" find_ffmpeg FF_BIN
if errorlevel 1 goto NO_PATH_ERR
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
set "FFPROBE_PATH=%FF_BIN%\ffprobe.exe"
echo 已找到ffmpeg于:%FFMPEG_PATH%
set "RUN_COM="%FFMPEG_PATH%" -hide_banner -threads 0 -init_hw_device qsv=hw -filter_hw_device hw -hwaccel qsv -hwaccel_output_format qsv"

SET "SRC_FILE="

if not "%~1"=="" (
    set "SRC_FILE=%~1"
)

if not defined SRC_FILE (
    SET /P SRC_FILE=请输入待压缩视频地址:
)

IF not defined SRC_FILE (
    echo 没有输入文件
    exit /b 1
)

set SRC_FILE="%SRC_FILE:"=%"

echo SRC_FILE:%SRC_FILE%

rem 输入必须含视频流: 无视频流的输入产不出有意义的成品, 提前拒绝(与 .sh 的 check_file_isvideo 对齐)
call "%SELF_DIR%lib\common.bat" check_isvideo %SRC_FILE%
if errorlevel 1 exit /b 3
SET "RUN_COM=%RUN_COM% -i %SRC_FILE%"
echo RUN_COM0=%RUN_COM%

rem 唯一临时文件: 替代固定名 temp/temp.txt/size/duration/bit_rate, 避免并行冲突
set "FB_TMP=%TEMP%\ffmpeg_bat_%RANDOM%%RANDOM%.tmp"

set "SRC_CODEC="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x %SRC_FILE%"
%SRC_CODEC% > "%FB_TMP%"
set /p SRC_CODEC=<"%FB_TMP%"
del "%FB_TMP%" 2>nul
echo SRC_CODEC=%SRC_CODEC%

set "SRC_FRAMERATE="%FFPROBE_PATH%" -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate %SRC_FILE%"
%SRC_FRAMERATE% > "%FB_TMP%"
set /p SRC_FRAMERATE=<"%FB_TMP%"
del "%FB_TMP%" 2>nul
echo SRC_FRAMERATE=%SRC_FRAMERATE%
set /a SRC_FRAMERATE=%SRC_FRAMERATE%

if %SRC_FRAMERATE% gtr 31 (
    set "RUN_COM=%RUN_COM% -r 30"
    echo TURN DOWN TARGET FRAME RATE TO 30
)

set "SRC_RESOLUTION="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -print_format flat -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 %SRC_FILE%"

rem SRC_RESOLUTION 的执行刻意放在 delayed 块外: 块内 %VAR% 的展开结果
rem 还要再过一遍延迟展开扫描, 片名里的感叹号会被成对吃掉从而丢失字符
%SRC_RESOLUTION% >  "%FB_TMP%"
set "SRC_W=0"
set "SRC_H=0"
setlocal EnableDelayedExpansion
set "output_cnt=0"
for /F "usebackq delims=" %%f in ("%FB_TMP%") do (
    set /a output_cnt+=1
    set "output[!output_cnt!]=%%f"
)
del "%FB_TMP%" 2>nul
set SRC_W=!output[1]!
set SRC_H=!output[2]!
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
rem pass local var to global var
endlocal & set SRC_W=%SRC_W% & set SRC_H=%SRC_H%
set /a SRC_PIX=%SRC_W%*%SRC_H%
echo SRC_PIX=%SRC_PIX%

set "SRC_SIZE="%FFPROBE_PATH%" -v error -hide_banner -show_entries format=size -of default=noprint_wrappers=1:nokey=1 %SRC_FILE%"
%SRC_SIZE% > "%FB_TMP%"
set /p SRC_SIZE=<"%FB_TMP%"
del "%FB_TMP%" 2>nul
if %SRC_SIZE% leq 0 (
   for %%A in (%SRC_FILE%) do set SRC_SIZE=%%~zA
)
echo SRC_SIZE=%SRC_SIZE%

set "SRC_DURATION="%FFPROBE_PATH%" -v error -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 %SRC_FILE%"
%SRC_DURATION% > "%FB_TMP%"
set /p SRC_DURATION=<"%FB_TMP%"
del "%FB_TMP%" 2>nul
echo SRC_DURATION=%SRC_DURATION%

set "SRC_BITRATE="%FFPROBE_PATH%" -v error -hide_banner -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 %SRC_FILE%"
%SRC_BITRATE% > "%FB_TMP%"
set /p SRC_BITRATE=<"%FB_TMP%"
del "%FB_TMP%" 2>nul
set /a SRC_BITRATE=%SRC_BITRATE%
IF not %ERRORLEVEL% NEQ 0 (
  if %SRC_BITRATE% == 0 (
     call "%SELF_DIR%lib\common.bat" calc_bitrate_fromsize %SRC_SIZE% %SRC_DURATION% SRC_BITRATE
  )
) else (
    call "%SELF_DIR%lib\common.bat" calc_bitrate_fromsize %SRC_SIZE% %SRC_DURATION% SRC_BITRATE
)
echo SRC_BITRATE=%SRC_BITRATE%

rem ---------- 码率查表: lib\bitrate_table_hevc.csv (替代原 190 行 if-elif) ----------
set "BIT="
call "%SELF_DIR%lib\common.bat" lookup_bitrate %SRC_PIX% BIT bitrate_table_hevc.csv
if not defined BIT (
    echo SRC_PIX=%SRC_PIX% 超出码率表范围, Manual handle it
    exit /b 2
)
set /a BIT=%BIT% / 2
set TARGET_BITRATE=%BIT%
echo TARGET_BITRATE=%TARGET_BITRATE%
set "percentage="

    set /a percentage=(%TARGET_BITRATE%*100^)/%SRC_BITRATE%
    call "%SELF_DIR%lib\common.bat" numOK "%TARGET_BITRATE%" %SRC_BITRATE% percentage

    echo percentage=%percentage%%%

if %percentage% geq 100 if "%~1"=="" (
    set BIT=%SRC_BITRATE%
)

if %percentage% leq 0 if "%~1"=="" (
   echo bitrate abnormal, please check
   exit /b 5
)

IF "%~1"=="" SET /P BIT=请输入输出码率(如1150k,不输入则保持默认):
echo TARGET_BITRATE=%BIT%
if defined BIT set "RUN_COM=%RUN_COM% -c:v hevc_qsv -profile:v main -preset veryfast -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
echo RUN_COM2:%RUN_COM%

echo.
echo SRC_FILE:%SRC_FILE%
if defined SRC_FILE call "%SELF_DIR%lib\common.bat" extract %SRC_FILE% TARGET_PATH TARGET_NAME
set TARGET_FILE="%TARGET_PATH:"=%%TARGET_NAME:"=%"
echo TARGET_FILE:%TARGET_FILE%

IF "%~1"=="" SET /P TARGET_FILE=请输入输出文件(如output.mp4,不输入则输出到相同文件夹并加后缀):
if not defined TARGET_FILE set "TARGET_FILE=output.mp4"
rem 统一给输出路径补引号: 用户手输的可能不带引号, 而不带引号的路径
rem 一旦含 空格/&/( ) 就会被 RUN_COM 的展开拆开
if defined TARGET_FILE set "TARGET_FILE="%TARGET_FILE:"=%""
echo SRC_FILE=%SRC_FILE%
echo TARGET_FILE=%TARGET_FILE%

echo RUN_COM3:%RUN_COM%
rem handler name with ) (   call set
IF "%~1"=="" (
    echo executing 1
    set "RUN_COM=%RUN_COM% %TARGET_FILE%"
) else (
    echo executing 2
    set "RUN_COM=%RUN_COM% -n %TARGET_FILE%"
)

echo RUN_COM4:%RUN_COM%
echo.
%RUN_COM%

echo ERRORLEVEL:%ERRORLEVEL%
echo 转换已出错或完成, 默认不替换, 请手动确认输出文件完整性

echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
echo SRC_PIX=%SRC_PIX%
echo SRC_BITRATE=%SRC_BITRATE%
echo TARGET_BITRATE=%TARGET_BITRATE%
echo percentage=%percentage%
echo TARGET_FILE:%TARGET_FILE%

exit /b 0

:NO_PATH_ERR
echo 找不到 ffmpeg.exe: 请安装 ffmpeg(默认查找 C:\Program Files\ffmpeg\bin)
echo 或设置环境变量 FFMPEG_BIN 指向其 bin 目录后重试
pause
exit /b 0
