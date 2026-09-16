@echo off
rem ============================================================
rem cp65001 relaunch guard (ASCII only - do NOT add non-ASCII here)
rem cmd.exe parses a .bat with the codepage active when the file was
rem opened; an in-file chcp 65001 can misalign the parser on UTF-8
rem lines (known cmd bug: a split line fragment is executed as a
rem command). We chcp first, then restart ourselves as a child
rem process, so the whole file is parsed under a UTF-8 console
rem from byte 0. See code_review_report.md for details.
if /I "%~1"=="__cp65001" (
    shift
    goto main
)
chcp 65001 >nul
cmd /c call "%~f0" __cp65001 %*
exit /b %errorlevel%

:main

rem ============================================================
rem ffmpeg_copy_to_mp4.bat - 封装修复/转 mp4 (remux, 无重编码)
rem 用法: 拖放视频文件到本 bat 上, 或双击后输入视频地址
rem 公共函数: lib\common.bat
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

set FFPROBE_PATH=C:\Program Files\ffmpeg\bin\ffprobe.exe
set FFMPEG_PATH=C:\Program Files\ffmpeg\bin\ffmpeg.exe
if not defined FFMPEG_PATH goto NO_PATH_ERR
echo 已找到ffmpeg于:%FFMPEG_PATH%
set "RUN_COM="%FFMPEG_PATH%" -hide_banner"

SET "SRC_FILE="

if [%1] neq [] (
    SET SRC_FILE=%1
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

if defined SRC_FILE call "%~dp0lib\common.bat" get_suffix %SRC_FILE% SUFFIX
echo SUFFIX:%SUFFIX%

if /I "%SUFFIX%" == ".mp4" (
    echo "suffix is mp4, no need to convert"
    goto :eof
) else (
    echo "suffix is not mp4, need to convert"
)

SET "RUN_COM=%RUN_COM% -i %SRC_FILE:&=^&% -c:v copy -c:a copy"
echo RUN_COM0=%RUN_COM%

echo.
echo SRC_FILE:%SRC_FILE%
if defined SRC_FILE call "%~dp0lib\common.bat" extract_mp4 %SRC_FILE% TARGET_PATH TARGET_NAME
set TARGET_FILE="%TARGET_PATH:"=%%TARGET_NAME:"=%"
echo TARGET_FILE:%TARGET_FILE%

IF not [%1] NEQ [] SET /P TARGET_FILE=请输入输出文件(如output.mp4,不输入则输出到相同文件夹):
IF NOT DEFINED TARGET_FILE SET TARGET_FILE=output.mp4
echo SRC_FILE=%SRC_FILE%
echo TARGET_FILE=%TARGET_FILE%

rem handler name with ) (   call set
IF not [%1] NEQ [] (
    echo executing 1
    SET RUN_COM=%RUN_COM% %TARGET_FILE%
) else (
    echo executing 2
    SET RUN_COM=%RUN_COM% -n %TARGET_FILE%
)

echo RUN_COM2:%RUN_COM%
echo.
call %RUN_COM%

echo ERRORLEVEL:%ERRORLEVEL%
echo 转换已出错或完成, 默认不替换, 请手动确认输出文件完整性

exit /b 0

:NO_PATH_ERR
echo 找不到ffmpeg.exe,请检查文件目录
pause
exit /b 0
