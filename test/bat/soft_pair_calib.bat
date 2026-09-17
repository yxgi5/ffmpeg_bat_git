@echo off
rem ============================================================
rem soft_pair_calib.bat - software-codec equal-quality pair calibration
rem                       (SVT-AV1 p8 vs libx265 fast)
rem                                                  *** ASCII ONLY / CRLF ***
rem
rem The .bat twin of test/sh/soft_pair_calib.sh. bench_calib.bat answers
rem "what target bitrate keeps THIS source good"; this tool answers the
rem codec-family question "at equal VMAF, how many bits does software AV1
rem need relative to software HEVC". It is the software counterpart of
rem nvenc_pair_calib.bat (the hardware NVENC pair).
rem
rem Usage:
rem   double-click / drag nothing   -> full  (720p + 1080p + 2160p)
rem   soft_pair_calib.bat 1080      -> 1080p clips only (light cross-check)
rem   soft_pair_calib.bat probe     -> toolchain check only
rem
rem Clips: 10s h264 samples from test-videos.co.uk (Big Buck Bunny /
rem Sintel). References are near-transparent x264 crf10 slow transcodes
rem normalized to fps30/yuv420p, and BOTH codecs encode from that same
rem reference so VMAF compares like with like. The 2160p reference is an
rem upscaled 1080p (no downloadable 4K master) - that caveat applies
rem equally to both codecs, so only the 4K ratio is meaningful.
rem
rem Output: <work>\results.csv  (clip,codec,br_req,br_delivered,vmaf,model)
rem Solve the equal-quality ratio from that CSV with:
rem   python test\py\eq_quality_solve.py "<work>\results.csv"
rem
rem Requirements: ffmpeg/ffprobe with libvmaf + libx265 + libsvtav1
rem (gyan.dev full / master builds qualify), and curl.exe for the first
rem run (Windows 10 1803+ ships it).
rem Work dir: %TEMP%\ffmpeg_soft_pair_calib, or SOFT_PAIR_WORK if set.
rem Env: SKIP_DOWNLOAD=1 -> never touch the network; you then must have
rem      placed the src_*.mp4 clips into the work dir yourself.
rem
rem NOTE on libvmaf: log_path must stay RELATIVE (an absolute C:/ path
rem breaks the filtergraph parser with a drive-letter colon), so the
rem scoring step pushd's into the log dir and passes a bare file name.
rem Exit code: 0 = results written / probe ok; 1 = some ladder point
rem failed; 2 = setup error (no ffmpeg / encoder / clip).
rem ============================================================
setlocal
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main
setlocal EnableExtensions
set "REPO=%~dp0..\.."
for %%I in ("%REPO%") do set "REPO=%%~fI"
if not exist "%REPO%\lib\common.bat" goto NO_REPO

rem ---- mode: full (default) | 1080 | probe (also /probe, --probe) ----
set "MODE=%~1"
if not defined MODE set "MODE=full"
if /I "%MODE%"=="/probe"  set "MODE=probe"
if /I "%MODE%"=="-probe"  set "MODE=probe"
if /I "%MODE%"=="--probe" set "MODE=probe"
if /I not "%MODE%"=="full" if /I not "%MODE%"=="1080" if /I not "%MODE%"=="probe" goto BAD_ARG

if defined SOFT_PAIR_WORK (
    set "WORK=%SOFT_PAIR_WORK%"
) else (
    set "WORK=%TEMP%\ffmpeg_soft_pair_calib"
)
if not exist "%WORK%\logs" mkdir "%WORK%\logs" >nul 2>&1
if not exist "%WORK%\ref"  mkdir "%WORK%\ref"  >nul 2>&1
if not exist "%WORK%\enc"  mkdir "%WORK%\enc"  >nul 2>&1
pushd "%WORK%" || goto NO_WORK

call "%REPO%\lib\common.bat" find_ffmpeg FF_BIN
if errorlevel 1 goto NO_FFMPEG
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
set "FFPROBE_PATH=%FF_BIN%\ffprobe.exe"

echo === toolchain check ===
"%FFMPEG_PATH%" -hide_banner -encoders 2>nul | findstr /c:"libsvtav1" >nul || goto NO_SVT
"%FFMPEG_PATH%" -hide_banner -encoders 2>nul | findstr /c:"libx265"   >nul || goto NO_X265
"%FFMPEG_PATH%" -hide_banner -filters  2>nul | findstr /c:"libvmaf"   >nul || goto NO_VMAF
if /I "%MODE%"=="probe" (
    echo toolchain OK
    pause
    exit /b 0
)

rem ---- source clips (existing files are reused; nothing is re-downloaded) ----
if /I "%MODE%"=="full" (
    call :GET bbb_720  "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_10MB.mp4"
    call :GET sil_720  "https://test-videos.co.uk/vids/sintel/mp4/h264/720/Sintel_720_10s_10MB.mp4"
)
call :GET bbb_1080 "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4"
call :GET sil_1080 "https://test-videos.co.uk/vids/sintel/mp4/h264/1080/Sintel_1080_10s_30MB.mp4"
if not exist "%WORK%\src_bbb_1080.mp4" if not exist "%WORK%\src_sil_1080.mp4" goto NO_CLIPS

rem ---- pick the 4K model once (outside any ()-block: a variable set inside
rem      a block is not visible to an echo on a later line of that block) ----
set "MODEL4K=vmaf_v0.6.1"
if not "%MODE%"=="full" goto MODEL_DONE
"%FFMPEG_PATH%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x240:rate=30 -t 1 -f lavfi -i testsrc2=size=320x240:rate=30 -t 1 -lavfi "libvmaf=model=version=vmaf_4k_v0.6.1" -f null - >nul 2>&1
if not errorlevel 1 set "MODEL4K=vmaf_4k_v0.6.1"
echo 4k model: %MODEL4K%
:MODEL_DONE

set "CSV=%WORK%\results.csv"
> "%CSV%" echo clip,codec,br_req,br_delivered,vmaf,model
set /a PAIRFAIL=0
echo work   : %WORK%
echo.

rem 1080p first: the 2160p reference is upscaled from ref_bbb_1080.
call :KEY bbb_1080 1920 1080
call :KEY sil_1080 1920 1080
if not "%MODE%"=="full" goto SUMMARY
call :KEY bbb_720 1280 720
call :KEY sil_720 1280 720
call :KEY bbb_2160 3840 2160

:SUMMARY
echo.
echo ==== results ====
type "%CSV%"
echo.
echo Rows with vmaf=NA are points whose JSON could not be read.
echo Solve the equal-quality ratio (r = AV1/HEVC) with:
echo   python test\py\eq_quality_solve.py "%CSV%"
echo.
if not "%PAIRFAIL%"=="0" (
    echo %PAIRFAIL% ladder point^(s^) failed - see the enc/vmaf FAIL lines above.
    pause
    exit /b 1
)
pause
exit /b 0

rem ---------------------------------------------------------------- helpers
rem :GET <name> <url> - fetch src_<name>.mp4 unless it is already there.
rem Returns non-zero when it did not obtain the file (skip or failure);
rem the caller only hard-fails when NO clip is available at all.
:GET
set "GN=%~1"
if exist "%WORK%\src_%GN%.mp4" ( echo have  src_%GN%.mp4 & exit /b 0 )
if defined SKIP_DOWNLOAD ( echo SKIP  src_%GN%.mp4 ^(SKIP_DOWNLOAD set^) & exit /b 1 )
where curl >nul 2>&1 || goto NO_CURL
echo get   src_%GN%.mp4
curl -fsSL -m 300 -o "%WORK%\src_%GN%.part" "%~2"
if errorlevel 1 (
    echo FAIL  %~2
    del /q "%WORK%\src_%GN%.part" >nul 2>&1
    exit /b 1
)
move /y "%WORK%\src_%GN%.part" "%WORK%\src_%GN%.mp4" >nul
exit /b 0

rem :KEY <key> <w> <h> - prep the reference for one clip and walk its ladder.
rem NOTE: no setlocal in these three helpers on purpose - the failure
rem counter must live in :main's scope, and a setlocal in a nested helper
rem would be popped before the counter reached it.
:KEY
set "K=%~1"
set "W2=%~2"
set "H2=%~3"
if not exist "%WORK%\src_%K%.mp4" ( echo skip  %K% - no source clip & exit /b 0 )
set "LADDER=1500k 3300k 6600k"
set "MODEL=vmaf_v0.6.1"
if %H2% equ 720 set "LADDER=800k 1600k 3200k"
if %H2% equ 2160 (
    set "LADDER=4000k 8000k 16000k"
    set "MODEL=%MODEL4K%"
)
if exist "%WORK%\ref\ref_%K%.mp4" goto KEY_LOOP
echo prep  ref_%K% %W2%x%H2%
if %H2% equ 2160 (
    "%FFMPEG_PATH%" -y -hide_banner -loglevel error -i "%WORK%\ref\ref_bbb_1080.mp4" -vf "scale=%W2%:%H2%:flags=lanczos,setsar=1,format=yuv420p" -c:v libx264 -crf 10 -preset slow -an "%WORK%\ref\ref_%K%.mp4"
) else (
    "%FFMPEG_PATH%" -y -hide_banner -loglevel error -i "%WORK%\src_%K%.mp4" -vf "scale=%W2%:%H2%:flags=lanczos,setsar=1,fps=30,format=yuv420p" -c:v libx264 -crf 10 -preset slow -an "%WORK%\ref\ref_%K%.mp4"
)
if errorlevel 1 (
    echo   prep FAIL %K%
    set /a PAIRFAIL+=1
    exit /b 1
)
:KEY_LOOP
for %%B in (%LADDER%) do call :POINT %K% %%B
exit /b 0

rem :POINT <key> <br> - both codecs at one ladder point.
:POINT
call :ENC %~1 %~2 x265 libx265 "-preset fast"
call :ENC %~1 %~2 av1  libsvtav1 "-preset 8"
exit /b 0

rem :ENC <key> <br> <tag> <encoder> <options> - encode + score one point.
:ENC
set "TAG=%~1_%~2_%~3"
set "ENCN=%~4"
set "OPT=%~5"
set "OUT=%WORK%\enc\%TAG%.mp4"
set "JS=%WORK%\logs\%TAG%.json"
if exist "%OUT%" goto ENC_SCORE
echo enc   %TAG%
"%FFMPEG_PATH%" -y -hide_banner -loglevel error -i "%WORK%\ref\ref_%~1.mp4" -c:v %ENCN% %OPT% -b:v %~2 -an "%OUT%"
if errorlevel 1 (
    echo   encode FAIL %TAG%
    set /a PAIRFAIL+=1
    exit /b 1
)
:ENC_SCORE
set "DEL=0"
for /f "usebackq delims=" %%R in (`"%FFPROBE_PATH%" -v error -select_streams v:0 -show_entries stream^=bit_rate -of csv^=p^=0 "%OUT%"`) do set "DEL=%%R"
if not defined DEL set "DEL=0"
if exist "%JS%" goto ENC_READ
echo vmaf  %TAG% ^(delivered %DEL% bps^)
pushd "%WORK%\logs"
"%FFMPEG_PATH%" -hide_banner -loglevel error -i "..\enc\%TAG%.mp4" -i "..\ref\ref_%~1.mp4" -lavfi "libvmaf=model=version=%MODEL%:log_fmt=json:log_path=%TAG%.json" -f null -
rem capture the status BEFORE popd: do not rely on popd leaving errorlevel alone
set "VRC=%errorlevel%"
popd
if not "%VRC%"=="0" (
    echo   vmaf FAIL %TAG%
    set /a PAIRFAIL+=1
    exit /b 1
)
:ENC_READ
set "VM="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Content -Raw '%JS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean"`) do set "VM=%%V"
if not defined VM set "VM=NA"
>> "%CSV%" echo %~1,%~3,%~2,%DEL%,%VM%,model=version=%MODEL%
echo   %TAG%  delivered=%DEL%  vmaf=%VM%
exit /b 0

rem ---------------------------------------------------------------- errors
:BAD_ARG
echo usage: soft_pair_calib.bat [full^|1080^|probe]
pause
exit /b 2
:NO_REPO
echo ERROR: repo not found at "%REPO%" - expected lib\common.bat there.
pause
exit /b 2
:NO_WORK
echo ERROR: cannot enter work dir "%WORK%".
pause
exit /b 2
:NO_FFMPEG
echo ERROR: ffmpeg/ffprobe not found - install ffmpeg or set FFMPEG_BIN
echo        to its bin dir (lib\common.bat find_ffmpeg uses the same rule).
pause
exit /b 2
:NO_SVT
echo ERROR: this ffmpeg build has no libsvtav1 encoder - use a gyan.dev full or master build.
pause
exit /b 2
:NO_X265
echo ERROR: this ffmpeg build has no libx265 encoder.
pause
exit /b 2
:NO_VMAF
echo ERROR: this ffmpeg build has no libvmaf filter - use a gyan.dev full or master build.
pause
exit /b 2
:NO_CURL
echo ERROR: curl.exe not found - install curl, or set SKIP_DOWNLOAD=1 and put the
echo        src_*.mp4 clips into "%WORK%" yourself.
pause
exit /b 2
:NO_CLIPS
echo ERROR: no source clips available in "%WORK%"
echo        (offline? pre-place src_bbb_1080.mp4 / src_sil_1080.mp4 and set SKIP_DOWNLOAD=1)
pause
exit /b 2
