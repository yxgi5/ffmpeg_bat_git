@echo off
rem ============================================================
rem bench_calib.bat - derive a quality-preserving target bitrate  *** ASCII ONLY / CRLF ***
rem                 for ONE source video (software encoders)
rem
rem Purpose: for special cases where quality matters most, cut a
rem segment from the middle of the source, encode a bitrate ladder
rem with the codec's SOFTWARE encoder (the same baseline the bitrate
rem tables are calibrated against), score every point with libvmaf
rem against the source itself, and report the smallest ladder point
rem reaching VMAF 95. Full curve fitting: paste results.csv back to
rem the assistant (or run test/sh/bench_calib.sh, which solves it).
rem
rem Usage:
rem   drag any video onto this bat                -> codec = hevc
rem   bench_calib.bat avc "D:\path\movie.mkv"     -> explicit codec
rem   bench_calib.bat av1 "D:\video.mkv" 1080 30  -> + height cap, seconds
rem
rem Ladder: table lookup T at the (optionally capped) pixel count,
rem then 5 points: T/4, T/3, T/2, 3T/4, T.  Defaults: 30s segment,
rem no height cap.
rem
rem Requirements: ffmpeg/ffprobe with libvmaf, found by
rem lib\common.bat find_ffmpeg (PATH or FFMPEG_BIN; gyan full /
rem master builds qualify), software encoder libx264 / libx265 /
rem libsvtav1. Work dir: %TEMP%\ffmpeg_bench_calib_<codec>
rem Exit code: 0 = results.csv written; 2 = setup error
rem ============================================================
setlocal
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main
setlocal EnableExtensions
set "CODEC=hevc"
set "A1=%~1"
set "A2=%~2"
set "A3=%~3"
set "A4=%~4"
if /I "%A1%"=="avc"  (set "CODEC=avc"  & set "A1=%A2%" & set "A2=%A3%" & set "A3=%A4%" & set "A4=")
if /I "%A1%"=="hevc" (set "CODEC=hevc" & set "A1=%A2%" & set "A2=%A3%" & set "A3=%A4%" & set "A4=")
if /I "%A1%"=="av1"  (set "CODEC=av1"  & set "A1=%A2%" & set "A2=%A3%" & set "A3=%A4%" & set "A4=")

set "ENC=libx265"
set "PSET=fast"
set "CSVN=bitrate_table_hevc.csv"
if /I "%CODEC%"=="avc"  set "ENC=libx264"   & set "CSVN=bitrate_table_avc.csv"
if /I "%CODEC%"=="av1"  set "ENC=libsvtav1" & set "PSET=8" & set "CSVN=bitrate_table_av1.csv"

set "SRC=%A1%"
set "CAP=%A2%"
set "LEN=%A3%"
if not defined CAP set "CAP=0"
if not defined LEN set "LEN=30"
if not defined SRC (
    echo Drag a video file onto this bat, or enter its full path:
    set /p "SRC=> "
)
if not defined SRC goto NO_SRC
if not exist "%SRC%" goto NO_SRC

call "%REPO%\lib\common.bat" find_ffmpeg FF_BIN
if errorlevel 1 goto NO_FFMPEG
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
set "FFPROBE_PATH=%FF_BIN%\ffprobe.exe"

"%FFMPEG_PATH%" -hide_banner -filters 2>nul | findstr /c:"libvmaf" >nul || goto NO_VMAF
"%FFMPEG_PATH%" -hide_banner -encoders 2>nul | findstr /c:"%ENC%" >nul || goto NO_ENC

for /f "usebackq delims=" %%W in (`%FFPROBE_PATH% -v error -select_streams v:0 -show_entries stream^=width -of csv^=p^=0 "%SRC%"`) do set "SW=%%W"
for /f "usebackq delims=" %%H in (`%FFPROBE_PATH% -v error -select_streams v:0 -show_entries stream^=height -of csv^=p^=0 "%SRC%"`) do set "SH=%%H"
for /f "usebackq delims=." %%D in (`%FFPROBE_PATH% -v error -show_entries format^=duration -of csv^=p^=0 "%SRC%"`) do set /a SS=%%D/2
if not defined SW goto NO_VIDEO
if not defined SH goto NO_VIDEO
set "W2=%SW%"
set "H2=%SH%"
if %CAP% gtr 0 if %SH% gtr %CAP% (
    set /a W2=SW*CAP/SH
    set /a W2=W2-W2%%2
    set /a H2=CAP-CAP%%2
)
set /a PIX=W2*H2
if %PIX% lss 0 goto NO_VIDEO
call "%REPO%\lib\common.bat" lookup_bitrate %PIX% T %CSVN%
if errorlevel 1 goto NO_TABLE

set "PREP=fps=30,format=yuv420p,setsar=1"
if not "%W2%"=="%SW%" set "PREP=scale=%W2%:%H2%:flags=lanczos,%PREP%"
set "MODEL=vmaf_v0.6.1"
if %H2% geq 2160 set "MODEL=vmaf_4k_v0.6.1"

set "WORK=%TEMP%\ffmpeg_bench_calib_%CODEC%"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
set "CSV=%WORK%\results.csv"
> "%CSV%" echo res,codec,br_req,br_delivered,vmaf

set /a B1=T/4
set /a B2=T/3
set /a B3=T/2
set /a B4=T*3/4
set "RECO_REQ="
set "RECO_VM="

echo source : %SRC%
echo encode : %W2%x%H2% fps30  seg %LEN%s from %SS%s  encoder %ENC% (%PSET%)
echo table  : %CSVN% -^> T=%T%   ladder: T/4 T/3 T/2 3T/4 T
echo vmaf   : model %MODEL% (reference = the source itself)
echo work   : %WORK%
echo.

call :ONE %B1%
call :ONE %B2%
call :ONE %B3%
call :ONE %B4%
call :ONE %T%

echo.
echo ==== results ====
type "%CSV%"
echo.
if defined RECO_REQ (
    echo RECOMMENDATION: smallest ladder point with VMAF^>=95 is %RECO_REQ% bps ^(VMAF %RECO_VM%^)
) else (
    echo RECOMMENDATION: no ladder point reached VMAF 95 - raise the ladder and rerun.
)
echo For the full curve fit (VMAF 90/93/95/97 crossings) run
echo   bash test/sh/bench_calib.sh %CODEC% "%SRC%" %CAP% %LEN%
echo or paste %CSV% back to the assistant.
pause
exit /b 0

:ONE
setlocal
set "BR=%~1"
set "TAG=%W2%x%H2%_%BR%"
set "OUT=%WORK%\%TAG%.mp4"
if not exist "%OUT%" "%FFMPEG_PATH%" -y -hide_banner -loglevel error -ss %SS% -t %LEN% -i "%SRC%" -vf "%PREP%" -c:v %ENC% -preset %PSET% -b:v %BR% -an "%OUT%" || ( endlocal & exit /b 1 )
set "DEL="
for /f "usebackq delims=" %%R in (`"%FFPROBE_PATH%" -v error -select_streams v:0 -show_entries stream^=bit_rate -of csv^=p^=0 "%OUT%"`) do set "DEL=%%R"
if not defined DEL set "DEL=0"
rem NOTE: log_path must stay RELATIVE (a C:/ absolute path breaks the
rem filtergraph parser) and the reference leg needs the SAME -ss/-t as
rem the encode leg, or libvmaf pairs frames from different offsets.
set "JS=%WORK%\%TAG%.json"
if not exist "%JS%" (
    pushd "%WORK%" || ( endlocal & exit /b 1 )
    "%FFMPEG_PATH%" -hide_banner -loglevel error -i "%TAG%.mp4" -ss %SS% -t %LEN% -i "%SRC%" -filter_complex "[1:v]%PREP%[sref];[0:v][sref]libvmaf=model=version=%MODEL%:log_fmt=json:log_path=%TAG%.json" -f null -
    popd
    if errorlevel 1 ( endlocal & exit /b 1 )
)
set "VM="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Content -Raw '%JS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean"`) do set "VM=%%V"
if not defined VM set "VM=0"
set "VM10="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "[int][math]::Floor((Get-Content -Raw '%JS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean * 10)"`) do set "VM10=%%V"
>> "%CSV%" echo %W2%x%H2%,%CODEC%,%BR%,%DEL%,%VM%
echo   %TAG%  req=%BR%  delivered=%DEL%  vmaf=%VM%
if defined VM10 if %VM10% geq 950 (
    if not defined RECO_REQ set "RECO_REQ=%BR%" & set "RECO_VM=%VM%"
)
if defined VM10 if %VM10% geq 950 if defined RECO_REQ if %BR% lss %RECO_REQ% set "RECO_REQ=%BR%" & set "RECO_VM=%VM%"
endlocal
exit /b 0

:NO_SRC
echo ERROR: source video not found or not given.
pause
exit /b 2
:NO_VIDEO
echo ERROR: ffprobe failed / pixel count overflow on this source.
pause
exit /b 2
:NO_FFMPEG
echo ERROR: ffmpeg/ffprobe not on PATH.
pause
exit /b 2
:NO_VMAF
echo ERROR: this ffmpeg build has no libvmaf filter - use a gyan.dev full or master build.
pause
exit /b 2
:NO_ENC
echo ERROR: encoder %ENC% not in this ffmpeg build (gyan full builds carry libx264/libx265/libsvtav1).
pause
exit /b 2
:NO_TABLE
echo ERROR: pixel count %PIX% outside %CSVN% range.
pause
exit /b 2
