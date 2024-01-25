@echo off
::SetLocal
::SetLocal EnableExtensions
::setlocal EnableDelayedExpansion

echo ============================================================
echo 欢迎使用ffmpeg视频 intel qsv h265 压缩批处理工具
echo 您有两种使用方式:
echo 1) 直接将待压缩的视频拖放到批处理上
echo 2) 在下面输入待压缩视频地址
echo.
echo 由 andreas 编写
echo ============================================================

set FFPROBE_PATH=C:\Program Files\ffmpeg\bin\ffprobe.exe
set FFMPEG_PATH=C:\Program Files\ffmpeg\bin\ffmpeg.exe
::if exist ffmpeg.exe set FFMPEG_PATH=ffmpeg.exe
if not defined FFMPEG_PATH goto NO_PATH_ERR
echo 已找到ffmpeg于:%FFMPEG_PATH%
set "RUN_COM="%FFMPEG_PATH%" -hide_banner -threads 0 -hwaccel qsv -hwaccel_output_format qsv"


::echo TARGET_PATH=%TARGET_PATH%
set "TARGET_PATH="
IF [%1] NEQ [] SET TARGET_PATH=%1
IF NOT DEFINED TARGET_PATH SET /P TARGET_PATH=请输入待压缩视频地址:
SET "RUN_COM=%RUN_COM% -i "%TARGET_PATH%""
::SET /P RES=请输入输出分辨率(如854x480,不输入则保持默认):
::IF DEFINED RES SET "RUN_COM=%RUN_COM% -s %RES%"
::SET /P FPS=请输入输出帧率(如15,不输入则保持默认):
::IF DEFINED FPS SET "RUN_COM=%RUN_COM% -r %FPS%"

set "SRC_CODEC="
set "SRC_CODEC="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x "%TARGET_PATH%""
::echo SRC_CODEC=%SRC_CODEC%

::set /p SRC_CODEC1=%SRC_CODEC%
::echo SRC_CODEC1=%SRC_CODEC1%

rem cmd 'cd'== linux 'pwd'
::for /f "delims=" %i in ('cd') do set tt=%i
::in batch 
::for /f "delims=" %%i in ('cd') do set tt=%%i
::for /f "tokens=*" %i in ('tasklist ^| findstr "explorer"') do set VAR=%i
::for /f "tokens=*" %i in ('""C:\Program Files\ffmpeg\bin\ffprobe.exe" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x "D:\BaiduNetdiskDownload\tmp\from\videos\2022110725\[digi-gra] airi natsume なつめ愛莉 hd.mov""') do set VAR=%i


::for /f "delims=" %%i in (%SRC_CODEC%) do echo %%i
::echo i=%%i
::echo SRC_CODEC1=%SRC_CODEC1%

::for /f "delims=" %%i in ('"%SRC_CODEC%"') do set SRC_CODEC1=%%i
::echo SRC_CODEC1=%SRC_CODEC1%
::pause

for /f "delims=" %%i in ('"%SRC_CODEC%"') do set SRC_CODEC=%%i
echo SRC_CODEC=%SRC_CODEC%
::pause


set "SRC_FRAMERATE="
set "SRC_FRAMERATE="%FFPROBE_PATH%" -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "%TARGET_PATH%""
for /f "delims=" %%i in ('"%SRC_FRAMERATE%"') do set SRC_FRAMERATE=%%i
echo SRC_FRAMERATE=%SRC_FRAMERATE%
::pause

set count=1
set "SRC_ROSOLUTION="
set "SRC_ROSOLUTION="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -print_format flat -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 "%TARGET_PATH%""

::for /f "delims=" %%i in ('"%SRC_ROSOLUTION%"') do (
::set VAR=%%i
::)
::echo %VAR%
::pause

::set count=1
::for /f "tokens=* usebackq" %%i in ('"%SRC_ROSOLUTION%"') do (
::set VAR!count!=%%i
::set /a count=!count!+1
::)
::echo VAR1=%VAR1%
::echo VAR2=%VAR2%
::pause

::set count=1
::set VAR!count!=a
::set /a count=!count!+1
::set VAR!count!=b
::echo %VAR1%
::echo %VAR2%
::pause

::set count=1
::set VAR%count%=a
::set /a count=%count%+1
::set VAR%count%=b
::echo %VAR1%
::echo %VAR2%
::pause

::set count=1
::for /f "delims=" %%i in ('"%SRC_ROSOLUTION%"') do (
::set VAR%count%=%%i
::set /a count=%count%+1
::)
::echo %VAR1%
::echo %VAR2%
::pause

::set count=1
::for /f "tokens=* usebackq" %%i in ('"%SRC_ROSOLUTION%"') do (
::set "VAR!count!=%%i"
::set /a count+=1
::)
::echo VAR1=%VAR1%
::echo VAR2=%VAR2%
::pause


set "output_cnt=0"
for /F "delims=" %%f in ('"%SRC_ROSOLUTION%"') do (
    set /a output_cnt+=1
    set "output[!output_cnt!]=%%f"
)
::for /L %%n in (1 1 !output_cnt!) DO (
::echo %%n
::echo !output[%%n]!
::)
set "SRC_W="
set "SRC_H="
set SRC_W=!output[1]!
set SRC_H=!output[2]!
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
::pause

set "SRC_BITRATE="
set "SRC_BITRATE="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0:s=x "%TARGET_PATH%""
for /f "delims=" %%i in ('"%SRC_BITRATE%"') do set SRC_BITRATE=%%i
echo SRC_BITRATE=%SRC_BITRATE%

set "BIT="
echo BIT init=%BIT%
if /i %SRC_CODEC%==h264 (
rem SRC_BITRATE less than 2.58M
::echo im here
    if %SRC_BITRATE% lss 2705326 (
        echo here1
        call :calc_bitrate 70 BIT
        echo BIT=%BIT%
    ) else (
        echo here2
        set /a BIT=%SRC_BITRATE%*100/25
        echo BIT before funtion=%BIT%
        call :calc_bitrate 25 BIT
        echo BIT=%BIT%
    )
    echo here3
    echo SRC_BITRATE=%SRC_BITRATE%
    set TARGET_BITRATE=%BIT%
    echo TARGET_BITRATE=%TARGET_BITRATE%
) else if %SRC_CODEC%==h265 (
    if %SRC_BITRATE% lss 2705326 (  rem SRC_BITRATE less than 2.58M
        echo 码率太低，不要转换
        pause
        exit /b 0
    )
)

pause


:calc_bitrate
::SetLocal EnableExtensions
::SetLocal EnableDelayedExpansion
set "BIT="
set /a BIT=%SRC_BITRATE%*100/%~1
echo BIT in funtion=%BIT%
SET %~2 %BIT%
echo BIT=%BIT%
echo return
::endlocal & endlocal
exit /b 0

SET /P BIT=请输入输出码率(如128k,不输入则保持默认):
::IF DEFINED BIT SET "RUN_COM=%RUN_COM% -b %BIT%"
if not defined BIT set BIT=2.58M
echo BITRATE=%BIT%
if defined BIT set "RUN_COM=%RUN_COM% -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -b:v %BIT%  -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024"
SET /P OUT=请输入输出文件(如output.mp4,不输入则输出output.mp4):
IF NOT DEFINED OUT SET OUT=output.mp4
SET "RUN_COM=%RUN_COM% "%OUT%""
echo RUN_COM:%RUN_COM%
%RUN_COM%
::echo.
echo 转换已完成
::echo 正在打开输出文件
::%OUT%
pause
exit /b 0

:::DivideByInteger
::    if defined PiDebug echo.DivideByInteger %1 %2
::    set /a DBI_Carry = 0
::    for /L %%i in (!MaxQuadIndex!, -1, 0) do (
::        set /a DBI_Digit = DBI_Carry*10000 + %1_%%i
::        set /a DBI_Carry = DBI_Digit %% %2
::        set /a %1_%%i = DBI_Digit / %2
::    )
::    goto :EOF


:NO_PATH_ERR
echo 找不到ffmpeg.exe,请检查文件目录
pause
exit /b 0
