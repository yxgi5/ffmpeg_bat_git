@echo off
chcp 65001

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo 您有两种使用方式:
echo 1) 直接将待压缩的视频拖放到批处理上
echo 2) 在下面输入待压缩视频地址
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
rem cut string

if not defined SRC_FILE (
    SET /P SRC_FILE=请输入待转换视频地址:
)

IF not defined SRC_FILE (
    echo 没有输入文件
    exit /b 1
)

set SRC_FILE="%SRC_FILE:"=%"

echo SRC_FILE:%SRC_FILE%

if defined SRC_FILE call :get_suffix %SRC_FILE% SUFFIX
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
if defined SRC_FILE call :extract %SRC_FILE% TARGET_PATH TARGET_NAME
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

:numOK
setlocal EnableDelayedExpansion
set numA=%~1
set numB=%~2

set decimals=4
set /A one=1, decimalsP1=decimals+1
for /L %%i in (1,1,2) do set "one=!one!0"

set "fpA=%numA:.=%"
set "fpB=%numB:.=%"
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one

set /a check=fpA*one
if !check! lss 0 (
    set /a fpA=fpA/10
    set /a fpB=fpB/10
)
set /A div=fpA*one/fpB

set /a ret = !div!
endlocal & set /a %~3=%ret%
exit /b 0

:calc_bitrate_fromsize
setlocal EnableDelayedExpansion
set numA=%~1
set numB=%~2

set decimals=1
set /A one=1, decimalsP1=decimals+1
for /L %%i in (1,1,1) do set "one=!one!0"

set "fpA=%numA:.=%"
echo !fpA!
set "fpB=%numB:~0%"
echo !fpB!
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one, div=fpA/fpB

echo %numA% / %numB% = !div!
set /a ret = 8*!div!
echo ret=%ret%
endlocal & set /a %~3=%ret%
exit /b 0

:extract
rem 获取到文件路径
echo in extract()
echo %~dp1
set %~2="%~dp1"
rem 获取到文件盘符
echo %~d1
rem 获取到文件名称
echo "%~n1"
rem 获取到文件后缀
echo %~x1
set %~3="%~n1.mp4"
echo "%~n1.mp4"
exit /b 0

:NO_PATH_ERR
echo 找不到ffmpeg.exe,请检查文件目录
pause
exit /b 0

:get_suffix
rem 获取到文件后缀
echo %~x1
set %~2=%~x1
exit /b 0
