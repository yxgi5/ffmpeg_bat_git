@echo off
::SetLocal
::SetLocal EnableExtensions
::setlocal EnableDelayedExpansion

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

SET SRC_FILE=%~1
::echo %SRC_FILE:~0,1%

IF [%1] NEQ [] (
echo Aaaaaaaa=%RUN_COM%
) else (
SET /P SRC_FILE=�������ѹ����Ƶ��ַ:
)

IF not defined SRC_FILE (
    echo û�������ļ�
    exit /b 1
)

set SRC_FILE=%SRC_FILE:"=%
echo SRC_FILE="%SRC_FILE%"
::pause

SET "RUN_COM=%RUN_COM% -i "%SRC_FILE%""
echo BbbbbbBbbbbb=%RUN_COM%
::SET /P RES=����������ֱ���(��854x480,�������򱣳�Ĭ��):
::IF DEFINED RES SET "RUN_COM=%RUN_COM% -s %RES%"
::SET /P FPS=���������֡��(��15,�������򱣳�Ĭ��):
::IF DEFINED FPS SET "RUN_COM=%RUN_COM% -r %FPS%"

set "SRC_CODEC="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x "%SRC_FILE%""
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

%SRC_CODEC% > "temp"
set /p SRC_CODEC=<"temp"
del "temp"
::for /f "delims=" %%i in ('"%SRC_CODEC%"') do set SRC_CODEC=%%i
echo SRC_CODEC=%SRC_CODEC%
::pause

::set "SRC_FRAMERATE="
set "SRC_FRAMERATE="%FFPROBE_PATH%" -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "%SRC_FILE%""
::for /f "delims=" %%i in ('"%SRC_FRAMERATE%"') do set SRC_FRAMERATE=%%i
%SRC_FRAMERATE% > "temp"
set /p SRC_FRAMERATE=<"temp"
del "temp"
echo SRC_FRAMERATE=%SRC_FRAMERATE%
set /a SRC_FRAMERATE=%SRC_FRAMERATE%
::echo SRC_FRAMERATE=%SRC_FRAMERATE%

if %SRC_FRAMERATE% gtr 31 (
    SET RUN_COM=%RUN_COM% -r 30
    echo TEAR DOWN TARGET FRAME RATE TO 30
    echo cccccccccc=%RUN_COM%
)
::goto :eof
::pause

set count=1
::set "SRC_ROSOLUTION="
set "SRC_ROSOLUTION="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -print_format flat -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1:nokey=1 "%SRC_FILE%""

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

set "SRC_W=0"
set "SRC_H=0"
setlocal EnableDelayedExpansion
set "output_cnt=0"
%SRC_ROSOLUTION% >  "temp.txt"
for /F "delims=" %%f in (temp.txt) do (
    set /a output_cnt+=1
    set "output[!output_cnt!]=%%f"
)
del "temp.txt"
::for /L %%n in (1 1 !output_cnt!) DO (
::echo %%n
::echo !output[%%n]!
::)
::set "SRC_W="
::set "SRC_H="
set SRC_W=!output[1]!
set SRC_H=!output[2]!
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
rem pass local var to global var
endlocal & set SRC_W=%SRC_W% & set SRC_H=%SRC_H%
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
set /a SRC_PIX=%SRC_W%*%SRC_H%
echo SRC_PIX=%SRC_PIX%
::pause

set "SRC_SIZE="%FFPROBE_PATH%" -v error -hide_banner -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "%SRC_FILE%""
echo SRC_SIZE=%SRC_SIZE%
%SRC_SIZE% > "size"
set /p SRC_SIZE=<"size"
del "size"
echo SRC_SIZE=%SRC_SIZE%

set "SRC_DURATION="%FFPROBE_PATH%" -v error -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%SRC_FILE%""
%SRC_DURATION% > "duration"
set /p SRC_DURATION=<"duration"
del "duration"
echo SRC_DURATION=%SRC_DURATION%


::set "SRC_BITRATE="
set "SRC_BITRATE="%FFPROBE_PATH%" -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0:s=x "%SRC_FILE%""
::for /f "delims=" %%i in ('"%SRC_BITRATE%"') do set SRC_BITRATE=%%i
%SRC_BITRATE% > "temp"
set /p SRC_BITRATE=<"temp"
del "temp"
echo SRC_BITRATE=%SRC_BITRATE%
set /a SRC_BITRATE=%SRC_BITRATE%
IF not %ERRORLEVEL% NEQ 0 ( 
  if %SRC_BITRATE% GTR 0 (
     echo ddddddddddd
     echo SRC_BITRATE=%SRC_BITRATE%
  ) else (
     echo eeeeeeeeeee
     ::set /a SRC_BITRATE=8 * %SRC_SIZE% / %SRC_DURATION%
     call :calc_bitrate_fromsize %SRC_SIZE% %SRC_DURATION% SRC_BITRATE
  )
) else (
echo fffffffff
::set /a SRC_BITRATE=8 * %SRC_SIZE% / %SRC_DURATION%
call :calc_bitrate_fromsize %SRC_SIZE% %SRC_DURATION% SRC_BITRATE
)
echo SRC_BITRATE=%SRC_BITRATE%
::pause

::set "BIT="
if %SRC_PIX% leq 12288 (
    set /a BIT=95892
) else if %SRC_PIX% leq 19200 (
    set /a BIT=135504
) else if %SRC_PIX% leq 21120 (   rem Xmax*60%=2.58M
    set /a BIT=145888
) else if %SRC_PIX% leq 25344 (   rem Xmax*55%=2.58M
    set /a BIT=168023
) else if %SRC_PIX% leq 38400 (   rem Xmax*50%=2.58M
    set /a BIT=231836
) else if %SRC_PIX% leq 64000 (   rem Xmax*45%=2.58M
    set /a BIT=344400
) else if %SRC_PIX% leq 76800 (   rem 5M<br<5M, 45%
    set /a BIT=396653
) else if %SRC_PIX% leq 84480 (   rem 5M<br<7.5M, 45%
    set /a BIT=427051
) else if %SRC_PIX% leq 96000 (   rem 7.5M<br<10M, 40%
    set /a BIT=471513
) else if %SRC_PIX% leq 101376 (   rem 10M<br<12M, 35%
    set /a BIT=491844
) else if %SRC_PIX% leq 103680 (   rem 12M<br<16M, 30%
    set /a BIT=500483
) else if %SRC_PIX% leq 112320 (   rem 12M<br<16M, 30%
    set /a BIT=532503
) else if %SRC_PIX% leq 120000 (   rem 12M<br<16M, 30%
    set /a BIT=560501
) else if %SRC_PIX% leq 128000 (   rem 12M<br<16M, 30%
    set /a BIT=589240
) else if %SRC_PIX% leq 153600 (   rem 12M<br<16M, 30%
    set /a BIT=678641
) else if %SRC_PIX% leq 153600 (   rem 12M<br<16M, 30%
    set /a BIT=678641
) else if %SRC_PIX% leq 168960 (   rem 12M<br<16M, 30%
    set /a BIT=730651
) else if %SRC_PIX% leq 168960 (   rem 12M<br<16M, 30%
    set /a BIT=730651
) else if %SRC_PIX% leq 202752 (   rem 12M<br<16M, 30%
    set /a BIT=841506
) else if %SRC_PIX% leq 202752 (   rem 12M<br<16M, 30%
    set /a BIT=841506
) else if %SRC_PIX% leq 224000 (
     set /a BIT=909058    
) else if %SRC_PIX% leq 230400 (
     set /a BIT=929118    
) else if %SRC_PIX% leq 307200 (
     set /a BIT=1161100    
) else if %SRC_PIX% leq 337920 (
     set /a BIT=1250085    
) else if %SRC_PIX% leq 345600 (
     set /a BIT=1272042    
) else if %SRC_PIX% leq 368640 (
     set /a BIT=1337264    
) else if %SRC_PIX% leq 384000 (
     set /a BIT=1380235    
) else if %SRC_PIX% leq 405504 (
     set /a BIT=1439750    
) else if %SRC_PIX% leq 407040 (
     set /a BIT=1443974    
) else if %SRC_PIX% leq 409920 (
     set /a BIT=1451883    
) else if %SRC_PIX% leq 414720 (
     set /a BIT=1465038    
) else if %SRC_PIX% leq 460800 (
     set /a BIT=1589646    
) else if %SRC_PIX% leq 480000 (
     set /a BIT=1640726    
) else if %SRC_PIX% leq 518400 (
     set /a BIT=1741534    
) else if %SRC_PIX% leq 552960 (
     set /a BIT=1830829    
) else if %SRC_PIX% leq 589824 (
     set /a BIT=1924703    
) else if %SRC_PIX% leq 614400 (
     set /a BIT=1986550    
) else if %SRC_PIX% leq 614400 (
     set /a BIT=1986550    
) else if %SRC_PIX% leq 786432 (
     set /a BIT=2405264    
) else if %SRC_PIX% leq 912384 (
     set /a BIT=2698662    
) else if %SRC_PIX% leq 921600 (
     set /a BIT=2719757    
) else if %SRC_PIX% leq 983040 (
     set /a BIT=2859210    
) else if %SRC_PIX% leq 995328 (
     set /a BIT=2886862    
) else if %SRC_PIX% leq 1024000 (
     set /a BIT=2951086    
) else if %SRC_PIX% leq 1049088 (
     set /a BIT=3006950    
) else if %SRC_PIX% leq 1228800 (
     set /a BIT=3398829    
) else if %SRC_PIX% leq 1296000 (
     set /a BIT=3541970    
) else if %SRC_PIX% leq 1310720 (
     set /a BIT=3573100    
) else if %SRC_PIX% leq 1440000 (
     set /a BIT=3843232    
) else if %SRC_PIX% leq 1470000 (
     set /a BIT=3905121    
) else if %SRC_PIX% leq 1555200 (
     set /a BIT=4079363    
) else if %SRC_PIX% leq 1622016 (
     set /a BIT=4214505    
) else if %SRC_PIX% leq 1638400 (
     set /a BIT=4247451    
) else if %SRC_PIX% leq 1764000 (
     set /a BIT=4497612    
) else if %SRC_PIX% leq 1920000 (
     set /a BIT=4802813    
) else if %SRC_PIX% leq 2073600 (
     set /a BIT=5097902    
) else if %SRC_PIX% leq 2211840 (
     set /a BIT=5359291    
) else if %SRC_PIX% leq 2304000 (
     set /a BIT=5531503    
) else if %SRC_PIX% leq 2359296 (
     set /a BIT=5634083    
) else if %SRC_PIX% leq 2457600 (
     set /a BIT=5815124    
) else if %SRC_PIX% leq 2592000 (
     set /a BIT=6060029    
) else if %SRC_PIX% leq 2688000 (
     set /a BIT=6233208    
) else if %SRC_PIX% leq 2764800 (
     set /a BIT=6370750    
) else if %SRC_PIX% leq 3145728 (
     set /a BIT=7040805    
) else if %SRC_PIX% leq 3686400 (
     set /a BIT=7961404    
) else if %SRC_PIX% leq 3686400 (
     set /a BIT=7961404    
) else if %SRC_PIX% leq 4085760 (
     set /a BIT=8621822    
) else if %SRC_PIX% leq 4096000 (
     set /a BIT=8638559    
) else if %SRC_PIX% leq 4953600 (
     set /a BIT=10009382    
) else if %SRC_PIX% leq 5038848 (
     set /a BIT=10142584    
) else if %SRC_PIX% leq 5184000 (
     set /a BIT=10368225    
) else if %SRC_PIX% leq 5242880 (
     set /a BIT=10459349    
) else if %SRC_PIX% leq 5760000 (
     set /a BIT=11250092    
) else if %SRC_PIX% leq 5880000 (
     set /a BIT=11431258    
) else if %SRC_PIX% leq 6000000 (
     set /a BIT=11611594    
) else if %SRC_PIX% leq 6144000 (
     set /a BIT=11826928    
) else if %SRC_PIX% leq 6291456 (
     set /a BIT=12046256    
) else if %SRC_PIX% leq 6553600 (
     set /a BIT=12433341    
) else if %SRC_PIX% leq 7372800 (
     set /a BIT=13621327    
) else if %SRC_PIX% leq 7680000 (
     set /a BIT=14059024    
) else if %SRC_PIX% leq 8294400 (
     set /a BIT=14922822    
) else if %SRC_PIX% leq 8847360 (
     set /a BIT=15687974    
) else if %SRC_PIX% leq 9216000 (
     set /a BIT=16192079    
) else if %SRC_PIX% leq 11059200 (
     set /a BIT=18648764    
) else if %SRC_PIX% leq 12000000 (
     set /a BIT=19866510    
) else if %SRC_PIX% leq 12582912 (
     set /a BIT=20610182    
) else if %SRC_PIX% leq 14745600 (
     set /a BIT=23305002    
) else if %SRC_PIX% leq 16384000 (
     set /a BIT=25287203    
) else if %SRC_PIX% leq 20358144 (
     set /a BIT=29920991    
) else if %SRC_PIX% leq 20971520 (
     set /a BIT=30617105    
) else if %SRC_PIX% leq 26214400 (
     set /a BIT=36395470    
) else if %SRC_PIX% leq 30720000 (
     set /a BIT=41154247    
) else if %SRC_PIX% leq 33177600 (
     set /a BIT=43682800    
) else if %SRC_PIX% leq 35389440 (
     set /a BIT=45922587    
) else if %SRC_PIX% leq 36864000 (
     set /a BIT=47398228    
) else if %SRC_PIX% leq 44236800 (
     set /a BIT=54589555    
) else if %SRC_PIX% leq 67108864 (
     set /a BIT=75394630    
) else if %SRC_PIX% leq 132710400 (
     set /a BIT=127870381    
) else if %SRC_PIX% leq 141557760 (
     set /a BIT=134426794    
) else (   rem > 16M, 25%
    echo "Manual handle it"
    exit /b 2
)

if not defined BIT (
    exit /b 3
)

::echo TARGET_BITRATE=%BIT%
set TARGET_BITRATE=%BIT%
echo TARGET_BITRATE=%TARGET_BITRATE%
set "percentage="

::set "TARGET_BITRATE="
::if defined TARGET_BITRATE (echo 1) else (echo 0)

::set "TARGET_BITRATE="
::if %TARGET_BITRATE% neq [] (
::    set /a percentage=(24459900*100^)/45000000
::    echo percentage=%percentage%%%
::) else (
::    set /a percentage=(%TARGET_BITRATE%*100^)/%SRC_BITRATE%
::    echo percentage=%percentage%%%
::)


::if defined TARGET_BITRATE (
    set /a percentage=(%TARGET_BITRATE%*100^)/%SRC_BITRATE%
    ::echo percentage=%percentage%%%
    ::set /a tmp=%TARGET_BITRATE%*100
    ::echo tmp=%tmp%
    ::call :numOK "%tmp%" %SRC_BITRATE% percentage
    call :numOK "%TARGET_BITRATE%" %SRC_BITRATE% percentage
    echo percentage=%percentage%%%
::)

if %percentage% gtr 100 (
   echo bitrate too low, no need to compress
   exit /b 4
)

if %percentage% lss 0 (
   echo bitrate unnomal, please check
   exit /b 5
)

::pause


IF not [%1] NEQ [] SET /P BIT=�������������(��128k,�������򱣳�Ĭ��):
::IF DEFINED BIT SET "RUN_COM=%RUN_COM% -b %BIT%"
::if not defined BIT set BIT=2.58M
echo TARGET_BITRATE=%BIT%
::pause

if defined BIT set "RUN_COM=%RUN_COM% -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -b:v %BIT%  -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024"

::echo %SRC_FILE%
if defined SRC_FILE call :extract "%SRC_FILE%" TARGET_PATH TARGET_NAME
echo %TARGET_PATH%%TARGET_NAME%
set TARGET_FILE=%TARGET_PATH%%TARGET_NAME%
::goto :eof

::set OriginStr="C:/Demo/myproject/example.txt"
::echo %OriginStr%
::call :extract %OriginStr%
::pause
::goto :eof

IF not [%1] NEQ [] SET /P TARGET_FILE=����������ļ�(��output.mp4,���������������ͬ�ļ��в��Ӻ�׺):
IF NOT DEFINED TARGET_FILE SET TARGET_FILE=output.mp4
echo SRC_FILE=%SRC_FILE%
echo TARGET_FILE=%TARGET_FILE%

echo RUN_COM:%RUN_COM%
rem handler name with ) (   call set 
IF not [%1] NEQ [] (
    call SET "RUN_COM=%%RUN_COM%% -xerror -abort_on empty_output "%%TARGET_FILE%%""
) else (
    call SET "RUN_COM=%%RUN_COM%% -xerror -abort_on empty_output -n "%%TARGET_FILE%%""
)

echo RUN_COM:%RUN_COM%
echo gggggggggg
::pause
%RUN_COM%
::echo %ERRORLEVEL%
IF %ERRORLEVEL% NEQ 0 ( 
   echo ת������
) else (
   echo ת����ȡ�������, Ĭ�ϲ��滻Ŀ��λ���Ѿ����ڵ��ļ�, ���ֶ�ȷ������ļ�������
)
::echo.
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
echo SRC_PIX=%SRC_PIX%
echo SRC_BITRATE=%SRC_BITRATE%
echo TARGET_BITRATE=%TARGET_BITRATE%
echo percentage=%percentage%

::echo ���ڴ�����ļ�
::%TARGET_FILE%
::IF not [%1] NEQ [] pause
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

:numOK
setlocal EnableDelayedExpansion
set numA=%~1
::echo numA=%numA%
set numB=%~2
::echo numB=%numB%

set decimals=4
set /A one=1, decimalsP1=decimals+1
::for /L %%i in (1,1,%decimals%) do set "one=!one!0"
for /L %%i in (1,1,2) do set "one=!one!0"

set "fpA=%numA:.=%"
set "fpB=%numB:.=%"
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one, div=fpA*one/fpB

::echo %numA% + %numB% = !add:~0,-%decimals%!.!add:~-%decimals%!
::echo %numA% - %numB% = !sub:~0,-%decimals%!.!sub:~-%decimals%!
::echo %numA% * %numB% = !mul:~0,-%decimals%!.!mul:~-%decimals%!
::echo %numA% / %numB% = !div:~0,-%decimals%!.!div:~-%decimals%!

::echo fpA=!fpA!
::echo one=!one!
::echo fpB=!fpB!
::echo div=!div!
::set /a ret = !div:~0,-%decimals%!
set /a ret = !div!
::echo ret=%ret%
endlocal & set /a %~3=%ret%
exit /b 0

:calc_bitrate_fromsize
setlocal EnableDelayedExpansion
set numA=%~1
::echo numA=%numA%
set numB=%~2
::echo numB=%numB%

set decimals=1
set /A one=1, decimalsP1=decimals+1
::for /L %%i in (1,1,%decimals%) do set "one=!one!0"
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
rem ��ȡ���ļ�·��
::echo in extract()
::echo %~dp1
set %~2=%~dp1
rem ��ȡ���ļ��̷�
::echo %~d1
rem ��ȡ���ļ�����
::echo %~n1
rem ��ȡ���ļ���׺
::echo %~x1
set %~3=%~n1-compressed%~x1
exit /b 0



:NO_PATH_ERR
echo �Ҳ���ffmpeg.exe,�����ļ�Ŀ¼
pause
exit /b 0
