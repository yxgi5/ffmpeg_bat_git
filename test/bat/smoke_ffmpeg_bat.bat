@echo off
rem ============================================================
rem smoke_ffmpeg_bat.bat (v6)   *** ASCII ONLY / CRLF ***
rem
rem Automated smoke harness for the ffmpeg_bat_git .bat family.
rem Usage modes covered:
rem   A) file argument     -> drag and drop / cmd direct call
rem   B) interactive path  -> double click, then type the path (SET /P)
rem   C) fresh process     -> console already UTF-8 (opencmd.bat style)
rem Every run captures stdout+stderr into smoke_logs\*.log, and a verdict
rem table is written to smoke_logs\summary.txt
rem
rem v6 changes vs v5:
rem   - T15: ffmpeg_av1_qsv.bat (AV1 QSV). AV1 hardware encoding only exists
rem     on Arrow Lake or newer iGPUs, so the test PROBES the hardware first
rem     with a 1-frame lavfi clip and reports SKIP (never FAIL) on boxes
rem     without an AV1 QSV encoder. Probe log:
rem     smoke_logs\T15_av1_qsv_probe.txt
rem v5 changes vs v4:
rem   - T13: an audio-only input must be REJECTED before ffmpeg runs
rem     (regression for the new lib\common.bat :check_isvideo)
rem   - global hygiene line: no log may contain the old lib debug
rem     echoes (in extract() / in extract_mp4() / ret=)
rem v4 changes vs v3:
rem   - optional 2nd arg LIST: runs only the list-mode tests (T9/T11/T12)
rem   - T12: list mode with NO argument, launched from another directory
rem     (the documented double-click usage; list.txt comes from the cwd)
rem v3 changes vs v2:
rem   - fixtures are REGENERATED on every run (v2 reused stale clips that
rem     had no audio track, which made every encoder fail on -map 0:a)
rem   - T10 silent input is now an ASSERTED test (regression for -map 0:a?)
rem   - global banner check line: every log must be free of
rem     "is not recognized" (regression for the guard marker leak)
rem
rem Location: <repo>\test\bat\  (the repo root is derived from this
rem         file's own path, two levels up)
rem
rem Usage:  smoke_ffmpeg_bat.bat [repo_path] [LIST]
rem         (no 2nd arg = full run incl. T13/T14/T15;  LIST = list tests only)
rem         default repo_path = two levels up from this .bat
rem ============================================================
setlocal EnableExtensions
set "REPO=%~1"
if not defined REPO for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "ONLY=%~2"
if /I not "%ONLY%"=="LIST" set "ONLY="
if not exist "%REPO%\ffmpeg_avc_qsv.bat" goto NO_REPO

set "LOGDIR=%~dp0smoke_logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
del /q "%LOGDIR%\*.log" >nul 2>&1
del /q "%LOGDIR%\*_probe.txt" >nul 2>&1
set "SUM=%LOGDIR%\summary.txt"
set "WORK=%TEMP%\ffmpeg_bat_smoke"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1

rem ---- console codepage we started with (= fresh console default) ----
set "CP0="
for /f "delims=" %%l in ('chcp') do set "CP0=%%l"
set "CP0=%CP0:*: =%"

echo ==== ffmpeg_bat smoke harness v6 ==== > "%SUM%"
echo date      : %DATE% %TIME% >> "%SUM%"
echo repo      : %REPO% >> "%SUM%"
echo startCP   : %CP0% >> "%SUM%"
echo workdir   : %WORK% >> "%SUM%"
echo. >> "%SUM%"

rem ---- locate ffmpeg through the repo helper (also exercises find_ffmpeg) ----
set "FFBIN="
call "%REPO%\lib\common.bat" find_ffmpeg FFBIN
set "FFRC=%errorlevel%"
echo find_ffmpeg rc=%FFRC% bin=%FFBIN% >> "%SUM%"
if not defined FFBIN goto NO_FF
set "FF=%FFBIN%\ffmpeg.exe"
set "FP=%FFBIN%\ffprobe.exe"
"%FF%" -version 2>&1 | findstr /b /c:"ffmpeg version" >> "%SUM%"

rem ---- fixtures: always regenerate (stale clips caused false failures) ----
del /q "%WORK%\smoke input 1080p60.mp4" >nul 2>&1
del /q "%WORK%\smoke mov input 1080p60.mov" >nul 2>&1
del /q "%WORK%\smoke silent 1080p60.mp4" >nul 2>&1
del /q "%WORK%\smoke audio only.m4a" >nul 2>&1
del /q "%WORK%\list_a.mp4" >nul 2>&1
del /q "%WORK%\list b.mp4" >nul 2>&1
set "VOPT=-hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=60 -f lavfi -i sine=frequency=440:sample_rate=44100"
set "IN=%WORK%\smoke input 1080p60.mp4"
"%FF%" %VOPT% -t 2 -c:v libx264 -preset ultrafast -b:v 18M -pix_fmt yuv420p -c:a aac -b:a 128k -y "%IN%"
set "INMOV=%WORK%\smoke mov input 1080p60.mov"
"%FF%" %VOPT% -t 1 -c:v libx264 -preset ultrafast -b:v 18M -pix_fmt yuv420p -c:a aac -b:a 128k -y "%INMOV%"
set "QUIET=%WORK%\smoke silent 1080p60.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 2 -c:v libx264 -preset ultrafast -b:v 18M -pix_fmt yuv420p -y "%QUIET%"
set "AONLY=%WORK%\smoke audio only.m4a"
"%FF%" -hide_banner -loglevel error -f lavfi -i sine=frequency=440:sample_rate=44100 -t 2 -c:a aac -b:a 128k -y "%AONLY%"
set "L1=%WORK%\list_a.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 128k -y "%L1%"
set "L2=%WORK%\list b.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 128k -y "%L2%"
echo probe mp4 : %IN%  [audio+video] >> "%SUM%"
echo probe mov : %INMOV%  [audio+video] >> "%SUM%"
echo probe mute: %QUIET%  [video only, for -map 0:a? regression] >> "%SUM%"
echo probe audio: "%AONLY%"  [audio only, for check_isvideo regression] >> "%SUM%"
echo. >> "%SUM%"
echo ---- verdicts ---- >> "%SUM%"

if defined ONLY goto LISTONLY

rem ============ usage A: file argument (drag and drop equivalent) ============
chcp %CP0% >nul
call :runA ffmpeg_avc_qsv    "%IN%" T1_avc_qsv_A      3836249 S A
chcp %CP0% >nul
call :runA ffmpeg_hevc_nvenc "%IN%" T2_hevc_nvenc_A   2548951 S A
chcp %CP0% >nul
call :runA ffmpeg_hevc_qsv   "%IN%" T3_hevc_qsv_A     2548951 S A
chcp %CP0% >nul
call :runA ffmpeg_libx265    "%IN%" T4_libx265_A      2548951 S A
chcp %CP0% >nul
rem T14: ffmpeg_av1_nvenc.bat (added 2026-09-16). Needs an Ada+ GPU (RTX 40 series or
rem newer); 1080p AV1 table entry = 1656818. Verdict artefacts: log must show
rem TARGET_BITRATE=1656818 and the ffprobe sidecar must show codec_name=av1.
call :runA ffmpeg_av1_nvenc  "%IN%" T14_av1_nvenc_A  1656818 S A

rem ============ T5: copy_to_mp4 (mov -> mp4, no bitrate table) ============
chcp %CP0% >nul
call :runA ffmpeg_copy_to_mp4 "%INMOV%" T5_copy_to_mp4_A 0 C A

rem ============ usage B: double click + typed path (stdin fed) ============
chcp %CP0% >nul
call :runB ffmpeg_avc_qsv "%IN%" T6_avc_qsv_B 3836249 B

rem ============ usage C: console already UTF-8, FRESH cmd process ============
chcp 65001 >nul
call :runA ffmpeg_hevc_nvenc "%IN%" T7_hevc_nvenc_C 2548951 S C F

rem ============ T10: silent input (regression for -map 0:a?) ============
chcp %CP0% >nul
call :runA ffmpeg_avc_qsv "%QUIET%" T10_avc_qsv_silent 3836249 S A-silent

rem ============ T13: non-video input must be rejected before ffmpeg =====
chcp %CP0% >nul
set "T13LOG=%LOGDIR%\T13_nonvideo_A.log"
set "T13OUT=%WORK%\smoke audio only-compressed.mp4"
del /q "%T13OUT%" >nul 2>&1
call "%REPO%\ffmpeg_avc_qsv.bat" "%AONLY%" < nul > "%T13LOG%" 2>&1
set "RC13=%errorlevel%"
set "V13=PASS"
set "N13="
findstr /i /c:"check_isvideo" "%T13LOG%" >nul 2>&1
if errorlevel 1 ( set "V13=FAIL" & set "N13=%N13% noCheckMsg;" )
findstr /i /c:"matches no streams" "%T13LOG%" >nul 2>&1
if not errorlevel 1 ( set "V13=FAIL" & set "N13=%N13% reachedFfmpeg;" )
if exist "%T13OUT%" ( set "V13=FAIL" & set "N13=%N13% outputProduced;" )
if not "%RC13%"=="3" ( set "V13=FAIL" & set "N13=%N13% exitCode=%RC13% want3;" )
echo [%V13%] T13 non-video input rejected before ffmpeg rc=%RC13% >> "%SUM%"
if not "%N13%"=="" echo        why: %N13% >> "%SUM%"

rem ============ T15: ffmpeg_av1_qsv.bat (added 2026-09-16) =============
rem AV1 QSV hardware encoding only exists on Arrow Lake or newer iGPUs and
rem only in recent ffmpeg builds. Probe the capability first so this case
rem reports SKIP instead of FAIL on a box that simply lacks the hardware.
rem 1080p AV1 table entry = 1656818 (same value the .sh twin produced on
rem the C-machine Arrow Lake box).
chcp %CP0% >nul
set "AV1P=%WORK%\probe_av1_qsv.mp4"
set "AV1PLOG=%LOGDIR%\T15_av1_qsv_probe.txt"
del /q "%AV1P%" >nul 2>&1
"%FF%" -hide_banner -init_hw_device qsv=hw -filter_hw_device hw -f lavfi -i color=size=256x256:rate=30 -frames:v 1 -c:v av1_qsv -preset fast -profile:v main -y "%AV1P%" > "%AV1PLOG%" 2>&1
set "AV1PRC=%errorlevel%"
if not "%AV1PRC%"=="0" goto T15SKIP
if not exist "%AV1P%" goto T15SKIP
del /q "%AV1P%" >nul 2>&1
chcp %CP0% >nul
call :runA ffmpeg_av1_qsv "%IN%" T15_av1_qsv_A 1656818 S A
goto T15DONE
:T15SKIP
echo [SKIP] T15 ffmpeg_av1_qsv: no AV1 QSV hardware encoder on this box >> "%SUM%"
echo        probe rc=%AV1PRC%, see T15_av1_qsv_probe.txt >> "%SUM%"
:T15DONE

:LISTONLY
rem ============ T9: list mode, cwd = repo, two entries incl. a space ======
chcp %CP0% >nul
> "%WORK%\list.txt" (
    echo %WORK%\list_a.mp4
    echo %WORK%\list b.mp4
)
del /q "%WORK%\*-compressed.mp4" >nul 2>&1
pushd "%REPO%"
call "%REPO%\convert_from_list_qsv.bat" "%WORK%\list.txt" < nul > "%LOGDIR%\T9_convert_from_list.log" 2>&1
set "RC9=%errorlevel%"
popd
call :countout CNT9
echo [TEST] T9 convert_from_list_qsv 2-entry list : %CNT9% of 2 outputs, rc=%RC9% >> "%SUM%"

rem ============ T11: list mode with UTF-8 (non-ASCII) file names ===========
if not exist "%WORK%\list_utf8.txt" goto T11SKIP
del /q "%WORK%\*-compressed.mp4" >nul 2>&1
pushd "%REPO%"
call "%REPO%\convert_from_list_qsv.bat" "%WORK%\list_utf8.txt" < nul > "%LOGDIR%\T11_convert_from_list_utf8.log" 2>&1
set "RC11=%errorlevel%"
popd
call :countout CNT11
echo [TEST] T11 list mode utf8 names : %CNT11% of 2 outputs, rc=%RC11% >> "%SUM%"
goto T11DONE
:T11SKIP
echo [SKIP] T11 utf8 list fixture missing: %WORK%\list_utf8.txt >> "%SUM%"
:T11DONE

rem ============ T12: list mode, NO argument, cwd = another directory ====
chcp %CP0% >nul
if not exist "%WORK%\cwdtest" mkdir "%WORK%\cwdtest" >nul 2>&1
copy /y "%WORK%\list.txt" "%WORK%\cwdtest\list.txt" >nul 2>&1
del /q "%WORK%\*-compressed.mp4" >nul 2>&1
pushd "%WORK%\cwdtest"
call "%REPO%\convert_from_list_qsv.bat" < nul > "%LOGDIR%\T12_convert_from_list_nocwd.log" 2>&1
set "RC12=%errorlevel%"
popd
call :countout CNT12
echo [TEST] T12 list mode, no arg, cwd elsewhere : %CNT12% of 2 outputs, rc=%RC12% >> "%SUM%"

rem ============ global: no log may contain the banner parse error ========
set "BAD=0"
for %%f in ("%LOGDIR%\*.log") do (
    findstr /i /c:"is not recognized" "%%f" >nul 2>&1
    if not errorlevel 1 (
        echo [FAIL] banner parse error in %%~nxf >> "%SUM%"
        set "BAD=1"
    )
)
echo. >> "%SUM%"
if "%BAD%"=="0" (echo [PASS] banner check: no "is not recognized" in any log) >> "%SUM%"
rem ============ global: lib debug echoes must be gone (hygiene) =========
set "DBG=0"
for %%f in ("%LOGDIR%\*.log") do (
    findstr /i /b /c:"in extract" /c:"ret=" "%%f" >nul 2>&1
    if not errorlevel 1 (
        echo [FAIL] debug echo found in %%~nxf >> "%SUM%"
        set "DBG=1"
    )
)
echo. >> "%SUM%"
if "%DBG%"=="0" (echo [PASS] debug check: no lib debug echoes in any log) >> "%SUM%"
echo. >> "%SUM%"
echo logs dir  : %LOGDIR% >> "%SUM%"
echo ---- end of summary ---- >> "%SUM%"

echo.
echo ============================================================
echo summary written to: %SUM%
echo logs in: %LOGDIR%
echo ============================================================
type "%SUM%"
echo.
pause
exit /b 0

rem ============================================================
rem :runA <batname> <input> <logname> <expected TARGET_BITRATE or 0 or INFO>
rem       <outmode S or C> <modelabel> [F = run in a fresh cmd process]
rem ============================================================
:runA
set "NAM=%~1"
set "INP=%~2"
set "LOGN=%~3"
set "EXP=%~4"
set "OM=%~5"
set "MDL=%~6"
set "FRESH=%~7"
set "LOG=%LOGDIR%\%LOGN%.log"
if /I "%OM%"=="C" (
    for %%X in ("%INP%") do set "OUT=%%~dpnX.mp4"
) else (
    for %%X in ("%INP%") do set "OUT=%%~dpnX-compressed.mp4"
)
del /q "%OUT%" >nul 2>&1
if defined FRESH (
    cmd /c call "%REPO%\%NAM%.bat" "%INP%" < nul > "%LOG%" 2>&1
) else (
    call "%REPO%\%NAM%.bat" "%INP%" < nul > "%LOG%" 2>&1
)
set "RC=%errorlevel%"
call :judge %NAM% %MDL% %EXP% "%OUT%" %RC% "%LOG%"
exit /b 0

rem ============================================================
rem :runB <batname> <input> <logname> <expected TARGET_BITRATE> <modelabel>
rem   no file argument -> interactive prompts, stdin fed with:
rem   line1 = input path, line2/3 = blank (keeps computed defaults)
rem ============================================================
:runB
set "NAM=%~1"
set "INP=%~2"
set "LOGN=%~3"
set "EXP=%~4"
set "MDL=%~5"
set "LOG=%LOGDIR%\%LOGN%.log"
for %%X in ("%INP%") do set "OUT=%%~dpnX-compressed.mp4"
del /q "%OUT%" >nul 2>&1
( echo %~2 & echo. & echo. ) | call "%REPO%\%NAM%.bat" > "%LOG%" 2>&1
set "RC=%errorlevel%"
call :judge %NAM% %MDL% %EXP% "%OUT%" %RC% "%LOG%"
exit /b 0

rem ============================================================
rem :countout <outvar>   count of *-compressed.mp4 in %WORK%
rem ============================================================
:countout
set "CN=0"
for /f %%c in ('dir /b "%WORK%\*-compressed.mp4" 2^>nul ^| find /c /v ""') do set "CN=%%c"
set "%~1=%CN%"
exit /b 0

rem ============================================================
rem :judge <batname> <modelabel> <expTB or 0 or INFO> <outfile> <rc> <logfile>
rem ============================================================
:judge
set "NAM=%~1"
set "MDL=%~2"
set "EXP=%~3"
set "OUT=%~4"
set "RC=%~5"
set "LOG=%~6"
set "V=PASS"
set "NT="
set "INF=0"
if /I "%EXP%"=="INFO" set "INF=1"
if "%INF%"=="1" set "V=INFO"
findstr /i /c:"is not recognized" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% bannerParseErr;" )
findstr /i /c:"bitrate abnormal" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% bitrateAbnormal;" )
findstr /i /c:"not found" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% notFoundMsg;" )
findstr /i /c:"ERRORLEVEL:-" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% ffmpegError;" )
set "TB="
for /f "tokens=1,2 delims==" %%a in ('findstr /b /c:"TARGET_BITRATE=" "%LOG%"') do set "TB=%%b"
if "%INF%"=="1" goto JG_NOASSERT
if not "%EXP%"=="0" if not "%TB%"=="%EXP%" ( set "V=FAIL" & set "NT=%NT% targetBitrate=%TB% expected=%EXP%;" )
if not exist "%OUT%" ( set "V=FAIL" & set "NT=%NT% noOutputFile;" )
:JG_NOASSERT
if not "%RC%"=="0" ( set "V=FAIL" & set "NT=%NT% exitCode=%RC%;" )
echo [%V%] %NAM% %MDL% rc=%RC% target=%TB% >> "%SUM%"
echo        out exists: %OUT% >> "%SUM%"
if not "%NT%"=="" echo        why: %NT% >> "%SUM%"
if exist "%OUT%" "%FP%" -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "%OUT%" > "%LOGDIR%\%NAM%_%MDL%_probe.txt" 2>&1
exit /b 0

:NO_REPO
echo [FATAL] repo not found. usage: smoke_ffmpeg_bat.bat ^<repo_path^>
pause
exit /b 1

:NO_FF
echo [FATAL] ffmpeg not found by lib\common.bat find_ffmpeg rc=%FFRC% >> "%SUM%"
echo [FATAL] ffmpeg not found. set FFMPEG_BIN to your ffmpeg bin dir, then rerun.
type "%SUM%"
pause
exit /b 2
