@echo off
SetLocal EnableExtensions

echo ============================================================
echo ��ӭʹ��ffmpeg��Ƶ intel qsv h265 ѹ����������
echo ��������ʹ�÷�ʽ:
echo 1) ֱ�ӽ���ѹ������Ƶ�Ϸŵ���������
echo 2) �����������ѹ����Ƶ��ַ
echo.
echo �� andreas ��д
echo ============================================================

set FFPROBE_PATH=C:\Program Files\ffmpeg\bin\ffprobe.exe
set FFMPEG_PATH=C:\Program Files\ffmpeg\bin\ffmpeg.exe
::if exist ffmpeg.exe set FFMPEG_PATH=ffmpeg.exe
if not defined FFMPEG_PATH goto NO_PATH_ERR
echo ���ҵ�ffmpeg��:%FFMPEG_PATH%
set "RUN_COM="%FFMPEG_PATH%" -hide_banner -threads 0 -hwaccel qsv -hwaccel_output_format qsv"


::echo TARGET_PATH=%TARGET_PATH%
IF [%1] NEQ [] SET TARGET_PATH=%1
IF NOT DEFINED TARGET_PATH SET /P TARGET_PATH=�������ѹ����Ƶ��ַ:
SET "RUN_COM=%RUN_COM% -i "%TARGET_PATH%""
::SET /P RES=����������ֱ���(��854x480,�������򱣳�Ĭ��):
::IF DEFINED RES SET "RUN_COM=%RUN_COM% -s %RES%"
::SET /P FPS=���������֡��(��15,�������򱣳�Ĭ��):
::IF DEFINED FPS SET "RUN_COM=%RUN_COM% -r %FPS%"

set "SRC_CODEC="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x "%TARGET_PATH%""
::echo SRC_CODEC=%SRC_CODEC%

::set /p SRC_CODEC1=%SRC_CODEC%
::echo SRC_CODEC1=%SRC_CODEC1%

rem cmd 'cd'== linux 'pwd'
::for /f "delims=" %i in ('cd') do set tt=%i
::in batch 
::for /f "delims=" %%i in ('cd') do set tt=%%i
::for /f "tokens=*" %i in ('tasklist ^| findstr "explorer"') do set VAR=%i
::for /f "tokens=*" %i in ('""C:\Program Files\ffmpeg\bin\ffprobe.exe" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x "D:\BaiduNetdiskDownload\tmp\from\videos\2022110725\[digi-gra] airi natsume �ʤĤ���� hd.mov""') do set VAR=%i


::for /f "delims=" %%i in (%SRC_CODEC%) do echo %%i
::echo i=%%i
::echo SRC_CODEC1=%SRC_CODEC1%

::for /f "delims=" %%i in ('"%SRC_CODEC%"') do set SRC_CODEC1=%%i
::echo SRC_CODEC1=%SRC_CODEC1%
::pause

for /f "delims=" %%i in ('"%SRC_CODEC%"') do set SRC_CODEC=%%i
echo SRC_CODEC=%SRC_CODEC%
::pause

set "SRC_FRAMERATE="%FFPROBE_PATH%" -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "%TARGET_PATH%""
for /f "delims=" %%i in ('"%SRC_FRAMERATE%"') do set SRC_FRAMERATE=%%i
echo SRC_FRAMERATE=%SRC_FRAMERATE%
::pause

set count=1
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

setlocal EnableDelayedExpansion
set "output_cnt=0"
for /F "delims=" %%f in ('"%SRC_ROSOLUTION%"') do (
    set /a output_cnt+=1
    set "output[!output_cnt!]=%%f"
)
::for /L %%n in (1 1 !output_cnt!) DO (
::echo %%n
::echo !output[%%n]!
::)
set SRC_W=!output[1]!
set SRC_H=!output[2]!
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
::pause

set "SRC_BITRATE="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0:s=x "%TARGET_PATH%""
for /f "delims=" %%i in ('"%SRC_BITRATE%"') do set SRC_BITRATE=%%i
echo SRC_BITRATE=%SRC_BITRATE%
if /i %SRC_CODEC%==h264  (
    if %SRC_BITRATE% lss 2705326 (          rem SRC_BITRATE less than 2.58M
        set /a BIT=SRC_BITRATE/70*100
    ) else if %SRC_BITRATE% lss 4162040 (   rem Xmax*65%=2.58M
        set /a BIT=SRC_BITRATE/65*100
    ) else if %SRC_BITRATE% lss 4508877 (   rem Xmax*60%=2.58M
        set /a BIT=SRC_BITRATE/60*100
    ) else if %SRC_BITRATE% lss 4918775 (   rem Xmax*55%=2.58M
        set /a BIT=SRC_BITRATE/55*100
    ) else if %SRC_BITRATE% lss 5410652 (   rem Xmax*50%=2.58M
        set /a BIT=SRC_BITRATE/50*100
    ) else if %SRC_BITRATE% lss 6011836 (   rem Xmax*45%=2.58M
        set /a BIT=SRC_BITRATE/45*100
    ) else if %SRC_BITRATE% lss 6763315 (   rem Xmax*40%=2.58M
        set /a BIT=SRC_BITRATE/40*100
    ) else if %SRC_BITRATE% lss 7729503 (   rem Xmax*35%=2.58M
        set /a BIT=SRC_BITRATE/35*100
    ) else if %SRC_BITRATE% lss 9017753 (   rem Xmax*30%=2.58M
        set /a BIT=SRC_BITRATE/30*100
    ) else if %SRC_BITRATE% lss 10821304 (   rem Xmax*25%=2.58M
        set /a BIT=SRC_BITRATE/25*100
    ) else if %SRC_BITRATE% lss 10821304 (   rem Xmax*25%=2.58M
        set /a BIT=SRC_BITRATE/25*100
    ) else (   rem 
        echo here
        set /a BIT=SRC_BITRATE/25*100
    )
    echo SRC_BITRATE=%SRC_BITRATE%
    echo TARGET_BITRATE=%BIT%
    ::call :DivideByInteger %TARGET_BITRATE% %SRC_BITRATE%
    pause
    set /a percentage=(%TARGET_BITRATE%*100)/%SRC_BITRATE%
    echo percentage=%percentage%%
) else if %SRC_CODEC%==h265 (
    if %SRC_BITRATE% lss 2705326 (  rem SRC_BITRATE less than 2.58M
        echo ����̫�ͣ���Ҫת��
        pause
        exit /b 0
    )
)

pause


SET /P BIT=�������������(��128k,�������򱣳�Ĭ��):
::IF DEFINED BIT SET "RUN_COM=%RUN_COM% -b %BIT%"
if not defined BIT set BIT=2.58M
echo BITRATE=%BIT%
if defined BIT set "RUN_COM=%RUN_COM% -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -b:v %BIT%  -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024"
SET /P OUT=����������ļ�(��output.mp4,�����������output.mp4):
IF NOT DEFINED OUT SET OUT=output.mp4
SET "RUN_COM=%RUN_COM% "%OUT%""
echo RUN_COM:%RUN_COM%
%RUN_COM%
::echo.
echo ת�������
::echo ���ڴ�����ļ�
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
echo �Ҳ���ffmpeg.exe,�����ļ�Ŀ¼
pause
exit /b 0
