@echo off
rem ============================================================
rem nvenc_pair_calib.bat - AV1 vs HEVC equal-quality calibration  *** ASCII ONLY / CRLF ***
rem
rem Measures the bitrate ratio r = bitrate(AV1) / bitrate(HEVC)
rem at equal VMAF for THIS machine's hardware encoders:
rem hevc_nvenc vs av1_nvenc, both preset p4 CBR - exactly the
rem parameterisation the repo's entry scripts use in production.
rem
rem The repo's bitrate tables currently assume r = 0.65..0.70
rem (stepped ladder). This bench turns that assumption into a
rem measured number for your GPU.
rem
rem Usage:
rem   drag any video file onto this bat, or
rem   nvenc_pair_calib.bat "D:\path\movie.mkv"
rem
rem What it does:
rem   1. cuts a silent 10s segment from the middle of the file
rem   2. builds near-transparent x264 (crf 10) references at
rem      720p and 1080p (4K only if the source is 4K)
rem   3. encodes a 3-point bitrate ladder with hevc_nvenc and
rem      av1_nvenc (p4 CBR)
rem   4. scores every encode with libvmaf against its reference
rem   5. writes results.csv - paste its content back to the
rem      assistant to solve the equal-quality bitrate ratio
rem      (the curve fitting is done off-box, not in batch)
rem
rem Requirements: ffmpeg/ffprobe with libvmaf on PATH
rem               (gyan.dev full/master builds qualify),
rem               NVIDIA GPU with HEVC NVENC + AV1 NVENC (Ada).
rem Work dir:     %TEMP%\ffmpeg_bat_nvenc_pair  (safe to delete)
rem Exit code:    0 = results.csv written; 2 = setup error
rem ============================================================
setlocal
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main
setlocal EnableExtensions
set "SRC=%~1"
if not defined SRC (
    echo Drag a video file onto this bat, or enter its full path:
    set /p "SRC=> "
)
if not defined SRC goto NO_SRC
if not exist "%SRC%" goto NO_SRC
where ffmpeg >nul 2>&1 || goto NO_FFMPEG
where ffprobe >nul 2>&1 || goto NO_FFMPEG
ffmpeg -hide_banner -filters 2>nul | findstr /c:"libvmaf" >nul || goto NO_VMAF
ffmpeg -hide_banner -encoders 2>nul | findstr /c:"av1_nvenc" >nul || goto NO_AV1NVENC
ffmpeg -hide_banner -encoders 2>nul | findstr /c:"hevc_nvenc" >nul || goto NO_HEVCNVENC

set "WORK=%TEMP%\ffmpeg_bat_nvenc_pair"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
set "CSV=%WORK%\results.csv"
> "%CSV%" echo res,codec,br_req,br_delivered,vmaf

for /f "usebackq delims=" %%W in (`ffprobe -v error -select_streams v:0 -show_entries stream^=width -of csv^=p^=0 "%SRC%"`) do set "SW=%%W"
if not defined SW goto NO_VIDEO
for /f "usebackq delims=." %%D in (`ffprobe -v error -show_entries format^=duration -of csv^=p^=0 "%SRC%"`) do set /a SS=%%D/2
echo source : %SRC%
echo width  : %SW%   segment start: %SS%s
echo work   : %WORK%

call :DORES 1280 720 "800k 1600k 3200k" vmaf_v0.6.1
if %SW% GEQ 1920 call :DORES 1920 1080 "1500k 3300k 6600k" vmaf_v0.6.1
if %SW% GEQ 3840 call :DORES 3840 2160 "4000k 8000k 16000k" vmaf_4k_v0.6.1

echo.
echo ==== results ====
type "%CSV%"
echo.
echo Send %CSV%
echo (or paste the table above) back to the assistant to solve the
echo equal-quality bitrate ratio r = AV1 / HEVC.
pause
exit /b 0

:DORES
setlocal
set "W=%~1"
set "H=%~2"
set "LAD=%~3"
set "MODEL=%~4"
set "REF=%WORK%\ref_%W%x%H%.mp4"
echo.
echo ==== reference %W%x%H% ====
ffmpeg -y -hide_banner -loglevel error -ss %SS% -t 10 -i "%SRC%" -vf "scale=%W%:%H%:flags=lanczos,setsar=1,fps=30,format=yuv420p" -c:v libx264 -crf 10 -preset slow -an "%REF%" || ( endlocal & exit /b 1 )
for %%B in (%LAD%) do (
    call :ONE %W% %H% hevc_nvenc %%B "%REF%" "%MODEL%"
    call :ONE %W% %H% av1_nvenc %%B "%REF%" "%MODEL%"
)
endlocal
exit /b 0

:ONE
setlocal
set "W=%~1"
set "H=%~2"
set "CODEC=%~3"
set "BR=%~4"
set "REF=%~5"
set "MODEL=%~6"
set "TAG=%W%x%H%_%BR%_%CODEC%"
set "OUT=%WORK%\%TAG%.mp4"
set "JS=%WORK%\%TAG%.json"
if not exist "%OUT%" ffmpeg -y -hide_banner -loglevel error -i "%REF%" -c:v %CODEC% -preset p4 -rc cbr -b:v %BR% -an "%OUT%" || ( endlocal & exit /b 1 )
for /f "usebackq delims=" %%R in (`ffprobe -v error -select_streams v:0 -show_entries stream^=bit_rate -of csv^=p^=0 "%OUT%"`) do set "DEL=%%R"
rem NOTE: log_path must be RELATIVE. An absolute path like C:/... breaks
rem       the filtergraph parser (the drive colon is read as a separator
rem       -> "No option name near ..." and every VMAF step fails silently).
rem       pushd into WORK and use the bare tag name instead.
set "JSABS=%WORK%\%TAG%.json"
if not exist "%JSABS%" (
    pushd "%WORK%" || ( endlocal & exit /b 1 )
    ffmpeg -hide_banner -loglevel error -i "%OUT%" -i "%REF%" -lavfi "libvmaf=model=version=%MODEL%:log_fmt=json:log_path=%TAG%.json" -f null -
    popd
    if errorlevel 1 ( endlocal & exit /b 1 )
)
set "VM="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Content -Raw '%JSABS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean"`) do set "VM=%%V"
>> "%CSV%" echo %W%x%H%,%CODEC%,%BR%,%DEL%,%VM%
echo   %TAG%  delivered=%DEL%  vmaf=%VM%
endlocal
exit /b 0

:NO_SRC
echo ERROR: source video not found or not given.
pause
exit /b 2
:NO_VIDEO
echo ERROR: ffprobe found no video stream in the source.
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
:NO_AV1NVENC
echo ERROR: no av1_nvenc here - AV1 NVENC needs an Ada (RTX 40) or newer GPU.
pause
exit /b 2
:NO_HEVCNVENC
echo ERROR: no hevc_nvenc in this ffmpeg build.
pause
exit /b 2
