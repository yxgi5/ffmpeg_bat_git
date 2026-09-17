@echo off
rem ============================================================
rem check_env.bat - "what can I actually run on THIS box?"   *** ASCII ONLY / CRLF ***
rem
rem This is a REPORT, not a regression test. It answers the question
rem "which entries of this repo are usable in the current environment"
rem without pretending that an unusable entry is a bug.
rem
rem It is the twin of test\sh\check_env.sh: same status vocabulary and the
rem same table shape, so the two reports can be compared line by line.
rem
rem   (default)   QUICK  - static capability inventory: ffmpeg build
rem                        features, video controllers, encoders.
rem   /probe      DEEP   - additionally runs every candidate entry on a
rem                        tiny 3s clip and reports its real exit code.
rem
rem Status vocabulary:
rem   OK           usable here (static evidence, or rc=0 from PROBE)
rem   NO-ENCODER   the ffmpeg build has no such encoder
rem   NO-DEVICE    encoder exists but this machine has no usable GPU
rem   N/A-OS       entry is meaningless on Windows (VAAPI is a Linux API)
rem   UNKNOWN      static check cannot decide -> rerun with /probe
rem   PROBE-OK     PROBE ran it and it produced a real output file
rem   PROBE-FAIL   PROBE ran it and it failed: non-zero rc, or rc=0 with
rem                no/empty output artifact. Every entry .bat ends with an
rem                unconditional "exit /b 0" (interactive design), so the
rem                exit code alone proves nothing - the artifact is the
rem                only honest evidence that the encoder really ran.
rem
rem Location: <repo>\test\bat\  (the repo root is derived from this file's
rem           own path, two levels up)
rem
rem Usage:  check_env.bat [/probe] [repo_path]
rem         /probe | -probe | --probe (or legacy positional PROBE) =
rem         deep mode. No flag = quick report. Default repo_path is
rem         two levels up from this .bat; the legacy form
rem         "check_env.bat "" PROBE" keeps working.
rem
rem Exit code: 0 = report produced (statuses are data, not failures)
rem            2 = setup error (repo missing / ffmpeg missing)
rem
rem NOTE on style: every `if` that must stop the subroutine uses a
rem parenthesised block. `if cond call :x & exit /b 0` would run the
rem `exit /b` UNCONDITIONALLY, because `&` binds looser than `if`.
rem ============================================================
setlocal
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main
setlocal EnableExtensions

rem ---- argument parsing: flags anywhere, positional repo_path optional.
rem      /probe (or -probe, --probe) turns on deep mode; the legacy
rem      "" PROBE form keeps working because an empty arg is skipped. ----
set "REPO="
set "DOPROBE="
for %%a in (%*) do call :onearg "%%~a"
if not defined REPO for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
if not exist "%REPO%\ffmpeg_avc_qsv.bat" goto NO_REPO

set "WORK=%TEMP%\ffmpeg_bat_check_env"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
set "TMPENC=%WORK%\encoders.txt"
set "TMPGPU=%WORK%\video_controllers.txt"
set "TMPREQ=%WORK%\requirements.txt"

rem ---- locate ffmpeg through the repo helper (same path as the smoke harness) ----
set "FFBIN="
call "%REPO%\lib\common.bat" find_ffmpeg FFBIN
if not defined FFBIN goto NO_FF
set "FF=%FFBIN%\ffmpeg.exe"
if not exist "%FF%" goto NO_FF

set "COUNT_OK=0"
set "COUNT_NO=0"
set "COUNT_UNK=0"
set "P_OK=0"
set "P_FAIL=0"

echo ==== ffmpeg_bat_git environment capability report ====
echo date     : %DATE% %TIME%
echo host     : %COMPUTERNAME%  [%PROCESSOR_ARCHITECTURE%]
echo os scope : windows - this report covers the .bat family
echo repo     : %REPO%
"%FF%" -version 2>&1 | findstr /b /c:"ffmpeg version"
echo which    : ffmpeg=%FF%
if defined DOPROBE (
    echo mode     : DEEP - PROBE: each candidate is really run
) else (
    echo mode     : QUICK - static inventory; pass PROBE to really run them
)
echo.

rem ---- video controllers: the only static way to tell which GPU families exist ----
rem PowerShell first: wmic (deprecated, and its UTF-16 output garbles under
rem chcp 65001 and defeats findstr) is only the fallback.
del /q "%TMPGPU%" >nul 2>&1
powershell -NoProfile -Command "(Get-CimInstance Win32_VideoController).Name" > "%TMPGPU%" 2>nul
if not exist "%TMPGPU%" if exist "%SystemRoot%\System32\wbem\wmic.exe" "%SystemRoot%\System32\wbem\wmic.exe" path win32_VideoController get name > "%TMPGPU%" 2>nul
set "HASINTEL="
set "HASNVIDIA="
findstr /i /c:"Intel" "%TMPGPU%" >nul 2>&1
if not errorlevel 1 set "HASINTEL=1"
findstr /i /c:"NVIDIA" "%TMPGPU%" >nul 2>&1
if not errorlevel 1 set "HASNVIDIA=1"

echo ---- host capability facts ----
echo   video controllers:
findstr /v /i /c:"Name" "%TMPGPU%" 2>nul
echo.
echo   encoder availability in this ffmpeg build:
"%FF%" -hide_banner -encoders > "%TMPENC%" 2>&1
for %%e in (libx264 libx265 h264_qsv hevc_qsv av1_qsv h264_vaapi hevc_vaapi h264_nvenc hevc_nvenc av1_nvenc) do call :hasenc %%e
echo.

rem ---- entry to requirement map: <entry>|<encoder>|<device>|<note> ----
rem device: none | qsv | nvidia. Written to a file and read back with for /f so
rem the note text may contain spaces without breaking the parse.
del /q "%TMPREQ%" >nul 2>&1
>> "%TMPREQ%" echo ffmpeg_libx264.bat^|libx264^|none^|software H.264 - always available with a full build
>> "%TMPREQ%" echo ffmpeg_libx265.bat^|libx265^|none^|software HEVC - always available with a full build
>> "%TMPREQ%" echo ffmpeg_avc_qsv.bat^|h264_qsv^|qsv^|Intel Quick Sync needs an Intel GPU
>> "%TMPREQ%" echo ffmpeg_hevc_qsv.bat^|hevc_qsv^|qsv^|Intel Quick Sync needs an Intel GPU
>> "%TMPREQ%" echo ffmpeg_av1_qsv.bat^|av1_qsv^|qsv^|AV1 QSV needs Arrow Lake or newer iGPU
>> "%TMPREQ%" echo ffmpeg_hevc_nvenc.bat^|hevc_nvenc^|nvidia^|NVIDIA NVENC HEVC
>> "%TMPREQ%" echo ffmpeg_av1_nvenc.bat^|av1_nvenc^|nvidia^|AV1 NVENC needs Ada RTX 40 or newer
>> "%TMPREQ%" echo ffmpeg_copy_to_mp4.bat^|-^|none^|remux only - no encoder involved

echo ---- entries ----
call :hdr
for /f "usebackq tokens=1-4 delims=|" %%a in ("%TMPREQ%") do call :classify "%%a" "%%b" "%%c" "%%d"
call :wrapper convert_from_list_cuda.bat ffmpeg_hevc_nvenc.bat
call :wrapper convert_from_list_libx265.bat ffmpeg_libx265.bat
call :wrapper convert_from_list_qsv.bat ffmpeg_hevc_qsv.bat
call :wrapper repack_from_list.bat ffmpeg_copy_to_mp4.bat
echo.

rem ---- tooling and data inventory ----
echo ---- repo tooling ----
for %%t in (test\lint\lint.py test\lint\selftest.py test\sh\smoke_ffmpeg.sh test\sh\check_env.sh test\bat\check_env.bat test\bat\smoke_ffmpeg.bat test\README.md) do call :have "%%t"
echo ---- bitrate tables ----
for %%c in (lib\bitrate_table_avc.csv lib\bitrate_table_hevc.csv lib\bitrate_table_av1.csv) do call :rows "%%c"
echo.

rem ---- deep probe: really run every candidate on a tiny clip ----
if not defined DOPROBE goto SUMMARY
echo ---- deep probe - each entry is really run on a 3s clip ----
set "TINY=%WORK%\probe_clip.mp4"
if exist "%TINY%" goto HAVE_CLIP
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x240:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 3 -c:v libx264 -preset ultrafast -b:v 200k -pix_fmt yuv420p -c:a aac -b:a 64k -shortest -y "%TINY%"
if not exist "%TINY%" goto NO_FIXTURE
:HAVE_CLIP
call :hdr
rem copy_to_mp4 is a remuxer: it refuses mp4-in/mp4-out and writes the
rem output next to the input, so it probes with a .mkv-named copy (same
rem fixture trick as smoke case T5). Everything else is an encoder entry.
for %%f in ("%REPO%\ffmpeg_*.bat") do (
    if /I "%%~nxf"=="ffmpeg_copy_to_mp4.bat" (
        call :probe_entry "%%~nxf" remux
    ) else (
        call :probe_entry "%%~nxf" enc
    )
)
for %%f in ("%REPO%\convert_from_list_*.bat") do call :probe_list "%%~nxf" enc
call :probe_list repack_from_list.bat remux
echo.
echo probe logs: %WORK%\^<entry name^>\run.log
echo.

:SUMMARY
echo ==== summary ====
echo entries usable ^(OK^): %COUNT_OK%
echo entries not usable here: %COUNT_NO%   ^(NO-ENCODER / NO-DEVICE / N/A-OS / NO-ENTRY^)
echo entries needing PROBE: %COUNT_UNK%
if defined DOPROBE echo probe results: ok=%P_OK% fail=%P_FAIL%
echo.
echo NOTE: a status here is a statement about THIS machine, not about the
echo       entry itself. NO-DEVICE just means the hardware is absent.
exit /b 0

rem ===============================================================
rem subroutines
rem ===============================================================

:onearg
rem classify one argument: probe flags, or the first positional repo_path
set "ARG=%~1"
if not defined ARG exit /b 0
if /I "%ARG%"=="/probe" ( set "DOPROBE=1" & exit /b 0 )
if /I "%ARG%"=="-probe" ( set "DOPROBE=1" & exit /b 0 )
if /I "%ARG%"=="--probe" ( set "DOPROBE=1" & exit /b 0 )
if /I "%ARG%"=="PROBE" ( set "DOPROBE=1" & exit /b 0 )
if not defined REPO set "REPO=%~1"
exit /b 0

rem :hdr - the column header, used by both tables
:hdr
echo STATUS       ENTRY                          NOTE
echo ------------ ------------------------------ ------------------------------------
exit /b 0

rem :hasenc <encoder> - one line of the encoder inventory.
rem "-encoders" rows look like " V....D libx264   ..." = leading space +
rem 7-char flag field + space + name, so the regex needs SEVEN dots before
rem the name (six dots would end on the last flag char and always fail).
:hasenc
findstr /r /b /c:"....... %1 " "%TMPENC%" >nul 2>&1
if errorlevel 1 (
    echo   enc  %1 : NO
) else (
    echo   enc  %1 : yes
)
exit /b 0

rem :hasenc_set <encoder> - sets ENCOK when the build has that encoder
:hasenc_set
set "ENCOK="
findstr /r /b /c:"....... %~1 " "%TMPENC%" >nul 2>&1
if not errorlevel 1 set "ENCOK=1"
exit /b 0

rem :classify <entry> <encoder> <device> <note>
:classify
set "E=%~1"
set "ENC=%~2"
set "DEV=%~3"
set "NOTE=%~4"
if not exist "%REPO%\%E%" (
    call :emit NO-ENTRY "%E%" "file missing from the repo"
    exit /b 0
)
if "%ENC%"=="-" (
    call :emit OK "%E%" "%NOTE%"
    exit /b 0
)
call :hasenc_set "%ENC%"
if not defined ENCOK (
    call :emit NO-ENCODER "%E%" "ffmpeg build has no %ENC% - %NOTE%"
    exit /b 0
)
if "%DEV%"=="none" (
    call :emit OK "%E%" "%NOTE%"
    exit /b 0
)
if "%DEV%"=="qsv" (
    call :classify_qsv "%E%" "%NOTE%"
    exit /b 0
)
if "%DEV%"=="nvidia" (
    call :classify_nvidia "%ENC%" "%E%" "%NOTE%"
    exit /b 0
)
call :emit UNKNOWN "%E%" "%NOTE% - static check cannot decide"
exit /b 0

rem On Windows the iGPU is reached through the Intel driver, never through
rem /dev/dri, so an Intel controller in the list is the strongest static hint -
rem but only PROBE can prove that Quick Sync really initialises.
:classify_qsv
if defined HASINTEL (
    call :emit UNKNOWN "%~1" "%~2 - rerun with PROBE to decide"
    exit /b 0
)
call :emit NO-DEVICE "%~1" "no Intel GPU in this machine - %~2"
exit /b 0

:classify_nvidia
if not defined HASNVIDIA (
    call :emit NO-DEVICE "%~2" "no NVIDIA GPU in this machine - %~3"
    exit /b 0
)
if "%~1"=="av1_nvenc" (
    call :emit UNKNOWN "%~2" "%~3 - rerun with PROBE to decide"
    exit /b 0
)
call :emit OK "%~2" "%~3"
exit /b 0

rem :wrapper <file> <expected target entry> - a list script inherits the status
rem of the encoder it drives. The expected target is passed in AND verified
rem against the file, so a rewritten wrapper cannot silently go stale here.
:wrapper
set "W=%~1"
set "WT=%~2"
if not exist "%REPO%\%W%" (
    call :emit NO-ENTRY "%W%" "file missing from the repo"
    exit /b 0
)
findstr /i /c:"%WT%" "%REPO%\%W%" >nul 2>&1
if errorlevel 1 (
    call :emit UNKNOWN "%W%" "does not reference %WT% anymore - mapping is stale"
    exit /b 0
)
set "TS="
for /f "usebackq tokens=1-4 delims=|" %%a in ("%TMPREQ%") do if /I "%%a"=="%WT%" call :target_status "%%b" "%%c"
if not defined TS set "TS=UNKNOWN"
call :emit %TS% "%W%" "wrapper - %WT%"
exit /b 0

:target_status
set "TS=UNKNOWN"
if "%~1"=="-" (
    set "TS=OK"
    exit /b 0
)
call :hasenc_set "%~1"
if not defined ENCOK (
    set "TS=NO-ENCODER"
    exit /b 0
)
if "%~2"=="none" (
    set "TS=OK"
    exit /b 0
)
if "%~2"=="qsv" (
    if defined HASINTEL (
        set "TS=UNKNOWN"
    ) else (
        set "TS=NO-DEVICE"
    )
    exit /b 0
)
if "%~2"=="nvidia" (
    if defined HASNVIDIA (
        set "TS=OK"
    ) else (
        set "TS=NO-DEVICE"
    )
    exit /b 0
)
exit /b 0

rem :emit <status> <entry> <note> - print one padded row and count it
:emit
call :pad "%~1"
echo %PAD% %~2 %~3
if "%~1"=="OK" set /a COUNT_OK+=1
if "%~1"=="UNKNOWN" set /a COUNT_UNK+=1
if not "%~1"=="OK" if not "%~1"=="UNKNOWN" set /a COUNT_NO+=1
exit /b 0

:pad
set "PAD=%~1            "
set "PAD=%PAD:~0,12%"
exit /b 0

:have
if exist "%REPO%\%~1" (
    echo   present  %~1
) else (
    echo   MISSING  %~1
)
exit /b 0

:rows
if not exist "%REPO%\%~1" (
    echo   %~1 MISSING
    exit /b 0
)
set "N="
for /f "tokens=3 delims=:" %%n in ('find /c /v "" "%REPO%\%~1"') do set "N=%%n"
if not defined N (
    echo   %~1 unreadable
    exit /b 0
)
set /a N=N-1
echo   %~1 %N% rows
exit /b 0

rem :probe_entry <entry> - run it with the tiny clip as the file argument
rem :probe_entry <entry> <enc|remux> - run it once on a tiny clip and judge
rem by the real artifact (see :judge_art). enc mode: fixture clip.mp4 in,
rem clip-compressed.mp4 expected out. remux mode: fixture named clip.mkv in
rem (a remux entry refuses mp4-in and -n would collide with the input name),
rem clip.mp4 expected out.
:probe_entry
set "B=%~1"
set "D=%WORK%\entry_%~n1"
if not exist "%D%" mkdir "%D%" >nul 2>&1
set "INFILE=clip.mp4"
set "OUTFILE=clip-compressed.mp4"
if /I "%~2"=="remux" (
    copy /y "%TINY%" "%D%\clip.mkv" >nul 2>&1
    del /q "%D%\clip.mp4" >nul 2>&1
    set "INFILE=clip.mkv"
    set "OUTFILE=clip.mp4"
) else (
    copy /y "%TINY%" "%D%\clip.mp4" >nul 2>&1
    del /q "%D%\clip-compressed.mp4" >nul 2>&1
)
pushd "%D%"
call "%REPO%\%B%" "%INFILE%" < nul > "%D%\run.log" 2>&1
set "RC=%errorlevel%"
popd
call :judge_art "%B%" "%RC%" "%D%\%OUTFILE%"
exit /b 0

rem :probe_list <entry> <enc|remux> - same, but the entry receives a one-line
rem list file. The list holds an ABSOLUTE path (same rule as the .sh twin): a
rem relative name depends on the child's cwd, an absolute one does not.
rem Spaces are fine - the list helper reads the whole line and quotes it
rem when calling the encoder.
:probe_list
set "B=%~1"
if not exist "%REPO%\%B%" exit /b 0
set "D=%WORK%\list_%~n1"
if not exist "%D%" mkdir "%D%" >nul 2>&1
set "INFILE=clip.mp4"
set "OUTFILE=clip-compressed.mp4"
if /I "%~2"=="remux" (
    copy /y "%TINY%" "%D%\clip.mkv" >nul 2>&1
    del /q "%D%\clip.mp4" >nul 2>&1
    set "INFILE=clip.mkv"
    set "OUTFILE=clip.mp4"
) else (
    copy /y "%TINY%" "%D%\clip.mp4" >nul 2>&1
    del /q "%D%\clip-compressed.mp4" >nul 2>&1
)
> "%D%\list.txt" echo %D%\%INFILE%
pushd "%D%"
call "%REPO%\%B%" "%D%\list.txt" < nul > "%D%\run.log" 2>&1
set "RC=%errorlevel%"
popd
call :judge_art "%B%" "%RC%" "%D%\%OUTFILE%"
exit /b 0

rem :judge_art <entry> <rc> <artifact> - PROBE-OK needs rc=0 AND a real
rem output artifact (>4096 bytes). The entry .bat wrappers always exit 0,
rem so rc alone cannot separate "encoded" from "ffmpeg died, window said
rem 转换已出错或完成 anyway"; the artifact size can. A 3s 320x240 encode at
rem the table bitrate is tens of KB, so 4096 is a safe floor.
:judge_art
set "OUTSZ=0"
if exist "%~3" for %%A in ("%~3") do set "OUTSZ=%%~zA"
if not "%~2"=="0" (
    call :pfail "%~1" "rc=%~2"
    exit /b 0
)
if %OUTSZ% GTR 4096 (
    call :pok "%~1" "rc=0 out=%OUTSZ%B"
) else (
    call :pfailnote "%~1" "rc=0 but no real output (%OUTSZ%B) - see run.log"
)
exit /b 0

:pok
call :pad PROBE-OK
echo %PAD% %~1 %~2
set /a P_OK+=1
exit /b 0

:pfail
call :pad PROBE-FAIL
echo %PAD% %~1 rc=%~2
set /a P_FAIL+=1
exit /b 0

:pfailnote
call :pad PROBE-FAIL
echo %PAD% %~1 %~2
set /a P_FAIL+=1
exit /b 0

:NO_REPO
echo FATAL: repo not found at "%REPO%" - expected ffmpeg_avc_qsv.bat there
echo usage: check_env.bat [/probe] [repo_path]
exit /b 2

:NO_FF
echo FATAL: ffmpeg not found - lib\common.bat find_ffmpeg returned "%FFBIN%"
exit /b 2

:NO_FIXTURE
echo FATAL: cannot build the probe clip in %WORK%
exit /b 2
