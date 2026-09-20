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
rem This file sits two levels below the repo root and is meant to be started
rem from anywhere (drag a movie onto it, double-click it, or call it from a
rem shell), so the current directory proves nothing - anchor on the script
rem location instead. %~dp0..\.. is relative until %%~fI normalizes it to a
rem full path. Without this, "%REPO%\lib\common.bat" collapses to
rem "\lib\common.bat" (a drive-root path) and the call fails with "The system
rem cannot find the path specified." - which the caller then reports as the
rem misleading "ffmpeg/ffprobe not on PATH".
set "REPO=%~dp0..\.."
for %%I in ("%REPO%") do set "REPO=%%~fI"
if not exist "%REPO%\lib\common.bat" goto NO_REPO

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

rem find_ffmpeg takes NO capability argument (a bat-side gate was added on
rem 2026-09-20 and reverted the same day). It built its command line as
rem   "%1\ffmpeg.exe"      caller passes an already-quoted %FFBIN%
rem = ""C:\Program Files\ffmpeg\bin"\ffmpeg.exe" -> the program name parses to the
rem empty string, and the 2>nul on that line hid the resulting error, so every
rem candidate looked incapable. It is the only behaviour change between the last
rem working run and the silent exit reported right after it, so instead of
rem debugging cmd quoting blind (no cmd.exe in the dev sandbox) the gate is gone.
rem Capability-based selection stays on the .sh side, where find_ffmpeg can walk
rem the fallback list: test/sh/bench_calib.sh uses --need-filter libvmaf.
call "%REPO%\lib\common.bat" find_ffmpeg FF_BIN
if errorlevel 1 goto NO_FFMPEG
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
set "FFPROBE_PATH=%FF_BIN%\ffprobe.exe"

"%FFMPEG_PATH%" -hide_banner -filters 2>nul | findstr /c:"libvmaf" >nul || goto NO_VMAF
"%FFMPEG_PATH%" -hide_banner -encoders 2>nul | findstr /c:"%ENC%" >nul || goto NO_ENC

rem Source geometry and duration come from lib\common.bat probe_source (one
rem ffprobe per run), NOT from `for /f ... in (`%FFPROBE_PATH% ...`)`: a
rem for-backtick command is handed to a child cmd /c, where a variable-expanded
rem PROGRAM PATH cannot be written safely -
rem   bare   -> the space in "C:\Program Files\..." splits the command line and
rem             cmd answers "'C:\Program' is not recognized as an internal or
rem             external command" (user report, 2026-09-20);
rem   quoted -> cmd /c's quote rule strips the first and the LAST quote of the
rem             line, so the closing quote of the final argument disappears.
rem Redirecting to a temp file and reading it with for /f "usebackq" is the
rem only form this repo has ever run on a real machine (see :probe_source).
call "%REPO%\lib\common.bat" probe_source "%SRC%"
set "PSRC_RC=%ERRORLEVEL%"
if not "%PSRC_RC%"=="0" goto NO_VIDEO
set "SW=%P_streams.stream.0.width%"
set "SH=%P_streams.stream.0.height%"
set "SS="
for /f "delims=." %%D in ("%P_format.duration%") do set /a SS=%%D/2
if not defined SW goto NO_VIDEO
if not defined SH goto NO_VIDEO
if not defined SS goto NO_VIDEO
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

rem The work dir is scoped to the parameter set:
rem   s<ss>t<len>_<W>x<H>_T<T>_<source bytes>
rem The per-file reuse guards below (if not exist OUT / if exist JS) keep a
rem rerun cheap, so the directory MUST change whenever anything that changes
rem the result changes - and it did not. A run printed "seg 30s" over
rem artifacts left behind by an earlier test at a different segment length and
rem reported their numbers as its own (user report, 2026-09-20: this side said
rem 2039817 bps, the .sh side 1783203 bps on the same source). A scoped dir
rem makes stale reuse impossible without any signature bookkeeping, and its
rem name doubles as a record of what produced the artifacts. Same rule in
rem test\sh\bench_calib.sh.
for %%I in ("%SRC%") do set "SZ=%%~zI"
set "WORK=%TEMP%\ffmpeg_bench_calib_%CODEC%\s%SS%t%LEN%_%W2%x%H2%_T%T%_%SZ%"
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
rem Deliberately NO setlocal here: this subroutine accumulates RECO_REQ /
rem RECO_VM across the five ladder calls, and a setlocal would pop them on
rem return - the caller would then always report "no ladder point reached
rem VMAF 95" even when the per-point lines clearly show one did. (Same lesson
rem as the soft_pair_calib.bat helpers.) The scratch names set here (BR, TAG,
rem OUT, DEL, JS, VM, VM10) collide with nothing in :main and are recomputed
rem on every call.
set "BR=%~1"
set "TAG=%W2%x%H2%_%BR%"
set "OUT=%WORK%\%TAG%.mp4"
if not exist "%OUT%" "%FFMPEG_PATH%" -y -hide_banner -loglevel error -ss %SS% -t %LEN% -i "%SRC%" -vf "%PREP%" -c:v %ENC% -preset %PSET% -b:v %BR% -an "%OUT%" || ( exit /b 1 )
rem Delivered bitrate of our own output: same rule as above, so this goes
rem through lib\common.bat probe_field (quoted command line + temp file)
rem instead of a for-backtick, which cannot carry a program path with a space.
rem The key is a WORD, never "stream=bit_rate": cmd splits batch arguments
rem on the equals sign too, so the old spelling made %4 - the output variable
rem NAME - become bit_rate, and DEL was never set. Symptom: five ladder points
rem with real vmaf but delivered=0 (user report, 2026-09-20). vbr = video
rem stream bitrate, fbr = container average. lint L22 now blocks the old form.
call "%REPO%\lib\common.bat" probe_field "%OUT%" vbr DEL
rem Fallback for containers that carry no per-stream rate: the container
rem average is still a truthful "delivered", and a silent 0 is worse.
if not defined DEL call "%REPO%\lib\common.bat" probe_field "%OUT%" fbr DEL
rem ffprobe prints a literal N/A when a container carries no per-stream
rem rate; that is a miss, not a number (mirrors the sh side's case guard).
for /f "delims=0123456789" %%i in ("%DEL%") do set "DEL="
if not defined DEL set "DEL=0"
rem NOTE: log_path must stay RELATIVE (a C:/ absolute path breaks the
rem filtergraph parser) and the reference leg needs the SAME -ss/-t as
rem the encode leg, or libvmaf pairs frames from different offsets.
set "JS=%WORK%\%TAG%.json"
if exist "%JS%" goto ONE_SCORE
pushd "%WORK%" || ( exit /b 1 )
"%FFMPEG_PATH%" -hide_banner -loglevel error -i "%TAG%.mp4" -ss %SS% -t %LEN% -i "%SRC%" -filter_complex "[1:v]%PREP%[sref];[0:v][sref]libvmaf=model=version=%MODEL%:log_fmt=json:log_path=%TAG%.json" -f null -
rem Read the status BEFORE popd, and outside any ( ) block: inside a block
rem %ERRORLEVEL% is expanded when the block is PARSED, so it would report
rem whatever ran before the block instead of the encoder. (Same lesson as the
rem soft_pair_calib.bat scorer.)
set "VRC=%errorlevel%"
popd
if not "%VRC%"=="0" (
    echo   vmaf leg failed for %TAG% ^(rc=%VRC%^)
    exit /b 1
)
rem The .json is the artifact this leg exists to produce; ffmpeg's own rc never
rem proves an artifact exists (a negative rc is invisible to `if errorlevel`),
rem so judge on the file as well.
if not exist "%JS%" (
    echo   vmaf leg produced no log for %TAG%
    exit /b 1
)
:ONE_SCORE
set "VM="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Content -Raw '%JS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean"`) do set "VM=%%V"
if not defined VM set "VM=0"
set "VM10="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "[int][math]::Floor((Get-Content -Raw '%JS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean * 10)"`) do set "VM10=%%V"
>> "%CSV%" echo %W2%x%H2%,%CODEC%,%BR%,%DEL%,%VM%
echo   %TAG%  req=%BR%  delivered=%DEL%  vmaf=%VM%
rem The five call sites walk the ladder in ASCENDING bitrate order
rem (T/4 <= T/3 <= T/2 <= 3T/4 <= T), so the first point to reach VMAF 95 is
rem already the smallest one - a plain "if not defined" latch is enough, and it
rem avoids comparing against an empty operand on the first call.
if defined VM10 if %VM10% geq 950 if not defined RECO_REQ (
    set "RECO_REQ=%BR%"
    set "RECO_VM=%VM%"
)
exit /b 0

:NO_REPO
echo ERROR: repo not found at "%REPO%" - expected lib\common.bat there.
pause
exit /b 2
:NO_SRC
echo ERROR: source video not found or not given.
pause
exit /b 2
:NO_VIDEO
echo ERROR: could not read video geometry/duration from the source.
echo        (no video stream, unreadable file, or pixel count overflow)
pause
exit /b 2
:NO_FFMPEG
echo ERROR: no ffmpeg.exe found - looked at FFMPEG_BIN, the repo's ffmpeg\bin,
echo        PATH and C:\Program Files\ffmpeg\bin.
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
