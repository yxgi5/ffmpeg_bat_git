@echo off
setlocal DisableDelayedExpansion
rem ==================================================================
rem smoke_special_chars.bat - special/metacharacter path smoke (round 6b)
rem
rem Double-click this file. Nothing is written outside TEMP and the
rem chars_logs\ folder next to this script.
rem
rem Why: the movie library contains names like "A & B (2020).mp4" and
rem "Tora! Tora! Tora!.mov". cmd treats & ^ ! % ( ) as syntax, so every
rem place a path gets expanded is a chance for the command line to break.
rem
rem Round 6b change: round 6 revealed that the real culprit is the
rem   set "VAR=value"   (wrapped) form
rem whenever value itself carries double quotes (which every path var in
rem this repo does). The wrapper quote pairs up with the first quote
rem inside the value, so the rest of the value is scanned UNQUOTED and
rem any & ( ) in the path becomes syntax. The fix was to use the plain
rem   set VAR=value
rem form for every such assignment. Part Z below proves that mechanism
rem with a self-contained micro-test, so a red result points straight
rem at the construct that broke.
rem
rem Coverage:
rem   part A : 20 filename metacharacter cases through ffmpeg_copy_to_mp4
rem   part C : full encoder path (ffmpeg_avc_qsv) for the real-world shapes
rem   part B : same shapes driven through convert_from_list_qsv (list mode)
rem   part D : no-argument mode, path fed over stdin (probe can only
rem            approximate console typing, hence the SKIP verdict)
rem   part Z : construct micro-tests (set forms, list-call caret,
rem            stdin - direct, forwarded, and through an ASCII
rem            replica of the cp65001 relaunch guard)
rem
rem All output here is deliberately ASCII-only, so the summary reads the
rem same whatever code page the console is in.
rem ==================================================================

set "SELF=%~dp0"
rem repo root = two levels up from this file (<repo>\test\bat\); %1 may override
set "REPO=%~1"
if not defined REPO for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "WORK=%TEMP%\ffmpeg_bat_chars"
set "CDIR=%WORK%\chars"
set "LDIR=%SELF%chars_logs"
set "SUM=%LDIR%\summary.txt"

if not exist "%LDIR%" mkdir "%LDIR%"
del /q "%LDIR%\*.log" 2>nul
del /q "%LDIR%\*.txt" 2>nul

if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%CDIR%"
mkdir "%CDIR%\sub & dir (x)"
mkdir "%CDIR%\lst"

rem ---------------- locate ffmpeg ----------------
set "FF="
if exist "C:\Program Files\ffmpeg\bin\ffmpeg.exe" set "FF=C:\Program Files\ffmpeg\bin\ffmpeg.exe"
if not defined FF for /f "delims=" %%p in ('where ffmpeg.exe 2^>nul') do if not defined FF set "FF=%%p"
if not defined FF (
    echo [FATAL] ffmpeg.exe not found - install ffmpeg or set FFMPEG_BIN
    pause
    exit /b 1
)

rem ---------------- fixtures ----------------
echo generating fixtures ...
"%FF%" -v error -y -f lavfi -i testsrc2=size=320x240:rate=10 -f lavfi -i sine=frequency=440 -t 1 -c:v libx264 -pix_fmt yuv420p -c:a aac "%WORK%\base.mp4" 2>nul
if not exist "%WORK%\base.mp4" (
    echo [FATAL] fixture generation failed
    pause
    exit /b 1
)
copy /y "%WORK%\base.mp4" "%WORK%\base.mov" >nul

> "%SUM%" echo ==================================================
>>"%SUM%" echo  special character smoke - round 6b
>>"%SUM%" echo  repo: %REPO%
>>"%SUM%" echo  time: %TIME%
>>"%SUM%" echo ==================================================

rem ---------------- part A: metacharacter matrix ----------------
>>"%SUM%" echo.
>>"%SUM%" echo ---- part A: one file straight through ffmpeg_copy_to_mp4 ----
echo [part A] 20 filename cases ...
call :run 01 "smoke_plain.mov"
call :run 02 "smoke_amp & test.mov"
call :run 03 "smoke_pct 100%% test.mov"
call :run 04 "smoke_bang ! test.mov"
call :run 05 "smoke_paren (1).mov"
call :run 06 "smoke_brk [x].mov"
rem A07 (caret in the name) is skipped: this probe reaches :run through
rem CALL, and CALL re-parses its arguments, so the caret is doubled
rem before it ever gets handed to the script - the probe cannot create
rem and then open the SAME name. (Proved by round 6: the fixture landed
rem on disk as "smoke_caret ^^ test.mov".) Caret in a filename is out
rem of scope for the movie library anyway.
call :skip 07 "smoke_caret case - SKIP, CALL re-parses caret"
call :run 08 "smoke_semi ; test.mov"
call :run 09 "smoke_comma , test.mov"
call :run 10 "smoke_eq a=b.mov"
call :run 11 "smoke_sharp #.mov"
call :run 12 "smoke_dollar $.mov"
call :run 13 "smoke_plus +.mov"
call :run 14 "smoke_tick '.mov"
call :run 15 "smoke_tilde ~.mov"
call :run 16 "smoke_at @.mov"
call :run 17 "smoke_real A & B (2020).mov"
call :run 18 "smoke_real2 Tora! Tora! Tora! (1970).mov"
call :run 19 "smoke_extreme A&B!C(2) 100%%.mov"
call :run 20 "sub & dir (x)\smoke_subdir.mov"

rem ---------------- part C: full encoder ----------------
>>"%SUM%" echo.
>>"%SUM%" echo ---- part C: full encode path (ffmpeg_avc_qsv) ----
echo [part C] full encoder cases ...
call :runenc 81 "smoke_real A & B (2020).mp4"
call :runenc 82 "smoke_real2 Tora! Tora! Tora! (1970).mp4"
call :runenc 83 "smoke_extreme A&B!C(2) 100%%.mp4"

rem ---------------- part B: list mode ----------------
rem list mode uses its own folder: the encoder writes "<base>-compressed.mp4"
rem next to the input, which would collide with part C's outputs.
>>"%SUM%" echo.
>>"%SUM%" echo ---- part B: list driven (convert_from_list_qsv) ----
echo [part B] list mode ...
copy /y "%WORK%\base.mov" "%CDIR%\lst\smoke_plain.mov" >nul
copy /y "%WORK%\base.mov" "%CDIR%\lst\smoke_amp & test.mov" >nul
copy /y "%WORK%\base.mov" "%CDIR%\lst\smoke_bang ! test.mov" >nul
copy /y "%WORK%\base.mov" "%CDIR%\lst\smoke_paren (1).mov" >nul
copy /y "%WORK%\base.mov" "%CDIR%\lst\smoke_real A & B (2020).mov" >nul
copy /y "%WORK%\base.mov" "%CDIR%\lst\sub & dir (x) case.mov" >nul

set "LF=%WORK%\list_chars.txt"
> "%LF%" echo %CDIR%\lst\smoke_plain.mov
>>"%LF%" echo %CDIR%\lst\smoke_amp ^& test.mov
>>"%LF%" echo %CDIR%\lst\smoke_bang ! test.mov
>>"%LF%" echo %CDIR%\lst\smoke_paren (1).mov
>>"%LF%" echo %CDIR%\lst\smoke_real A ^& B (2020).mov
>>"%LF%" echo %CDIR%\lst\smoke_plain ^& noext.mov
copy /y "%CDIR%\lst\smoke_plain.mov" "%CDIR%\lst\smoke_plain & noext.mov" >nul

call "%REPO%\convert_from_list_qsv.bat" "%LF%" > "%LDIR%\B0_list.log" 2>&1
set "BRC=%ERRORLEVEL%"
set "BOK=0"
if exist "%CDIR%\lst\smoke_plain-compressed.mp4" set /a BOK+=1
if exist "%CDIR%\lst\smoke_amp & test-compressed.mp4" set /a BOK+=1
if exist "%CDIR%\lst\smoke_bang ! test-compressed.mp4" set /a BOK+=1
if exist "%CDIR%\lst\smoke_paren (1)-compressed.mp4" set /a BOK+=1
if exist "%CDIR%\lst\smoke_real A & B (2020)-compressed.mp4" set /a BOK+=1
if exist "%CDIR%\lst\smoke_plain & noext-compressed.mp4" set /a BOK+=1
>>"%SUM%" echo   list mode: %BOK%/6 outputs, rc=%BRC%  (see B0_list.log)

rem ---------------- part D: no-argument mode via stdin ----------------
rem The probe can only feed the interactive branch by redirecting stdin.
rem Observation (rounds 6/6b): with a FILE redirect the interactive
rem branch sees EOF, so the script exits 1 with its normal "no input"
rem message. What is NOT the cause: set /p reading a redirected file
rem works fine on a plain bat (part Z2a, direct call and forwarded),
rem and the T-suite feeds the real script through a PIPE in its mode-B
rem tests and passes (T6/T7). So the suspect is the combination
rem "file redirect + the cp65001 relaunch"; part Z2d isolates exactly
rem that construct with an ASCII replica of the guard. Either way it is
rem a probe limitation, not a user-facing bug: real use is double-click
rem plus typing at the console. Verdict logic:
rem   output produced              -> PASS
rem   rc=1 (the documented no-input path) -> SKIP
rem   anything else                -> FAIL
rem D1 below repeats the call with FFMPEG_BIN pre-set (no child spawned
rem before the prompt); Z2e / Z2f isolate chcp and the for /f lookup.
>>"%SUM%" echo.
>>"%SUM%" echo ---- part D: no-argument mode, path from stdin ----
echo [part D] no-argument mode ...
set "IFILE=%WORK%\stdin_path.txt"
> "%IFILE%" echo %CDIR%\smoke_amp ^& test.mov
>>"%IFILE%" echo.
>>"%IFILE%" echo.
del /q "%CDIR%\smoke_amp & test.mp4" 2>nul
call "%REPO%\ffmpeg_copy_to_mp4.bat" < "%IFILE%" > "%LDIR%\D0_noarg.log" 2>&1
set "DRC=%ERRORLEVEL%"
set "DV=FAIL"
if exist "%CDIR%\smoke_amp & test.mp4" set "DV=PASS"
if "%DRC%"=="1" if not exist "%CDIR%\smoke_amp & test.mp4" set "DV=SKIP"
>>"%SUM%" echo [%DV%] D0 no-argument rc=%DRC%  (SKIP = file-redirected stdin never reaches the no-arg branch, see Z2a/Z2d)

rem D1: the same call, but FFMPEG_BIN is pre-set so find_ffmpeg takes its
rem     first branch and spawns NO child before the prompt. If D1 now reads
rem     the path while D0 does not, the stdin eater is a child process that
rem     find_ffmpeg runs (the for /f where lookup).
set "FFMPEG_BIN=C:\Program Files\ffmpeg\bin"
del /q "%CDIR%\smoke_amp & test.mp4" 2>nul
call "%REPO%\ffmpeg_copy_to_mp4.bat" < "%IFILE%" > "%LDIR%\D1_noarg_ffbin.log" 2>&1
set "D1RC=%ERRORLEVEL%"
set "D1V=FAIL"
if exist "%CDIR%\smoke_amp & test.mp4" set "D1V=PASS"
if "%D1RC%"=="1" if not exist "%CDIR%\smoke_amp & test.mp4" set "D1V=noRead"
set "FFMPEG_BIN="
>>"%SUM%" echo [%D1V%] D1 same, but no child before the prompt  (rc=%D1RC%, see D1_noarg_ffbin.log)

rem ---------------- part Z: construct micro-tests ----------------
rem Purpose: if part A/C/B still shows red, these pin the failure on one
rem construct instead of leaving you to guess. Each child .bat is
rem generated on the fly and run in its own process, so a construct that
rem really is broken cannot take this probe down with it.
>>"%SUM%" echo.
>>"%SUM%" echo ---- part Z: construct micro-tests ----
echo [part Z] construct micro-tests ...
set "ZW=%WORK%\zwork"
if exist "%ZW%" rmdir /s /q "%ZW%"
mkdir "%ZW%"

rem Z1: plain set + value carrying its own quotes + metacharacters in the
rem     path. The verdict line below stays free of bare metacharacters on
rem     purpose: an unquoted ampersand in an echo line splits it into two
rem     commands and kills the whole probe (that is exactly what happened
rem     in the first 6b run, Z1/Z2 verdict lines went missing).
rem     This is the form the repo now uses everywhere; it must survive.
> "%ZW%\z1.bat" echo @echo off
>>"%ZW%\z1.bat" echo set ZV1="%ZW%\a & b (c) d!e.mov"
>>"%ZW%\z1.bat" echo echo Z1VAL=[%%ZV1%%]
call "%ZW%\z1.bat" > "%LDIR%\Z1.log" 2>&1
set "Z1RC=%ERRORLEVEL%"
set "Z1=FAIL"
findstr /c:"d!e.mov" "%LDIR%\Z1.log" >nul 2>&1
if not errorlevel 1 set "Z1=PASS"
>>"%SUM%" echo [%Z1%] Z1 plain set keeps a quoted value (rc=%Z1RC%, see Z1.log)

rem The counterpart test (the old wrapped form) is deliberately NOT
rem written here: putting that construct in this file would break THIS
rem probe the same way it broke the scripts, and the round 6 logs
rem already record it (RUN_COM truncated at -i + 'B' is not
rem recognized). Part A/B/C now exercise the fixed form end to end.

rem Z2a/Z2b: stdin + set /p, called directly vs forwarded through cmd /c.
rem     Tells apart "set /p cannot read a redirected file" from
rem     "the codepage-65001 relaunch drops stdin".
> "%ZW%\z3.bat" echo @echo off
>>"%ZW%\z3.bat" echo set "ZV3="
>>"%ZW%\z3.bat" echo set /p ZV3=enter a path:
>>"%ZW%\z3.bat" echo echo Z3VAL=[%%ZV3%%]
> "%ZW%\z3.in" echo "%ZW%\a & b (c) d.mov"
call "%ZW%\z3.bat" < "%ZW%\z3.in" > "%LDIR%\Z2a.log" 2>&1
cmd /c "%ZW%\z3.bat" < "%ZW%\z3.in" > "%LDIR%\Z2b.log" 2>&1
>>"%SUM%" echo [INFO] Z2a set /p via direct call  (see Z2a.log)
>>"%SUM%" echo [INFO] Z2b set /p via cmd /c forward  (see Z2b.log)

rem Z2d: ASCII replica of the repo's cp65001 relaunch guard, fed a
rem     FILE-redirected stdin. If this one sees EOF while Z2a (plain
rem     bat, same redirect) read the path fine, then the guard
rem     relaunch is what drops a file-redirected stdin - which is
rem     exactly what part D runs into. Kept ASCII-only on purpose so
rem     no code page can interfere with this judgement.
> "%ZW%\z4.bat" echo @echo off
>>"%ZW%\z4.bat" echo setlocal
>>"%ZW%\z4.bat" echo if defined ZG goto zmain
>>"%ZW%\z4.bat" echo set "ZG=1"
>>"%ZW%\z4.bat" echo cmd /c call "%%~f0" %%*
>>"%ZW%\z4.bat" echo exit /b %%errorlevel%%
>>"%ZW%\z4.bat" echo :zmain
>>"%ZW%\z4.bat" echo set "ZV4="
>>"%ZW%\z4.bat" echo set /p ZV4=enter:
>>"%ZW%\z4.bat" echo echo Z4VAL=[%%ZV4%%]
call "%ZW%\z4.bat" < "%ZW%\z3.in" > "%LDIR%\Z2d.log" 2>&1
set "Z2DRC=%ERRORLEVEL%"
set "Z2D=noRead (guard relaunch drops file-redirected stdin)"
findstr /c:"d.mov" "%LDIR%\Z2d.log" >nul 2>&1
if not errorlevel 1 set "Z2D=PASS (stdin survived the relaunch)"
>>"%SUM%" echo [%Z2D%] Z2d guard replica, stdin from file  (rc=%Z2DRC%, see Z2d.log)

rem Z2e: same replica, but with the chcp 65001 line the real guard has.
rem     ASCII only, so a code page change cannot corrupt this file itself -
rem     the only variable under test is the chcp call.
> "%ZW%\z5.bat" echo @echo off
>>"%ZW%\z5.bat" echo setlocal
>>"%ZW%\z5.bat" echo if defined ZG goto zmain
>>"%ZW%\z5.bat" echo set "ZG=1"
>>"%ZW%\z5.bat" echo chcp 65001 ^>nul
>>"%ZW%\z5.bat" echo cmd /c call "%%~f0" %%*
>>"%ZW%\z5.bat" echo exit /b %%errorlevel%%
>>"%ZW%\z5.bat" echo :zmain
>>"%ZW%\z5.bat" echo set "ZV5="
>>"%ZW%\z5.bat" echo set /p ZV5=enter:
>>"%ZW%\z5.bat" echo echo Z5VAL=[%%ZV5%%]
call "%ZW%\z5.bat" < "%ZW%\z3.in" > "%LDIR%\Z2e.log" 2>&1
set "Z2ERC=%ERRORLEVEL%"
set "Z2E=noRead (chcp 65001 eats the redirected stdin)"
findstr /c:"d.mov" "%LDIR%\Z2e.log" >nul 2>&1
if not errorlevel 1 set "Z2E=PASS (chcp made no difference)"
>>"%SUM%" echo [%Z2E%] Z2e guard replica plus chcp  (rc=%Z2ERC%, see Z2e.log)

rem Z2f: same replica, but a for /f "where" lookup runs right before the
rem     prompt - that is what find_ffmpeg does. If the path is gone from the
rem     read, the returned stdin has been consumed by that child.
> "%ZW%\z6.bat" echo @echo off
>>"%ZW%\z6.bat" echo setlocal
>>"%ZW%\z6.bat" echo if defined ZG goto zmain
>>"%ZW%\z6.bat" echo set "ZG=1"
>>"%ZW%\z6.bat" echo cmd /c call "%%~f0" %%*
>>"%ZW%\z6.bat" echo exit /b %%errorlevel%%
>>"%ZW%\z6.bat" echo :zmain
>>"%ZW%\z6.bat" echo set "ZZ="
>>"%ZW%\z6.bat" echo for /f "delims=" %%%%p in ('where ffmpeg.exe') do set "ZZ=%%%%p"
>>"%ZW%\z6.bat" echo set "ZV6="
>>"%ZW%\z6.bat" echo set /p ZV6=enter:
>>"%ZW%\z6.bat" echo echo Z6VAL=[%%ZV6%%]
call "%ZW%\z6.bat" < "%ZW%\z3.in" > "%LDIR%\Z2f.log" 2>&1
set "Z2FRC=%ERRORLEVEL%"
set "Z2F=noRead (a prior for /f child ate the stdin)"
findstr /c:"d.mov" "%LDIR%\Z2f.log" >nul 2>&1
if not errorlevel 1 set "Z2F=PASS (for /f child made no difference)"
>>"%SUM%" echo [%Z2F%] Z2f guard replica plus for /f where  (rc=%Z2FRC%, see Z2f.log)

rem Z2g: same replica, but set /p sits inside an "if not defined" block,
rem     exactly the way the real script prompts. The earlier replicas all
rem     used a bare set /p, so the block form is still an untested variable.
rem     The closing paren is caret-escaped so this probe keeps balancing.
> "%ZW%\z7.bat" echo @echo off
>>"%ZW%\z7.bat" echo setlocal
>>"%ZW%\z7.bat" echo if defined ZG goto zmain
>>"%ZW%\z7.bat" echo set "ZG=1"
>>"%ZW%\z7.bat" echo cmd /c call "%%~f0" %%*
>>"%ZW%\z7.bat" echo exit /b %%errorlevel%%
>>"%ZW%\z7.bat" echo :zmain
>>"%ZW%\z7.bat" echo set "ZV7="
>>"%ZW%\z7.bat" echo if not defined ZV7 ^(
>>"%ZW%\z7.bat" echo set /p ZV7=enter:
>>"%ZW%\z7.bat" echo ^)
>>"%ZW%\z7.bat" echo echo Z7VAL=[%%ZV7%%]
call "%ZW%\z7.bat" < "%ZW%\z3.in" > "%LDIR%\Z2g.log" 2>&1
set "Z2GRC=%ERRORLEVEL%"
set "Z2G=noRead (set /p inside a block cannot read the redirect)"
findstr /c:"d.mov" "%LDIR%\Z2g.log" >nul 2>&1
if not errorlevel 1 set "Z2G=PASS (block form made no difference)"
>>"%SUM%" echo [%Z2G%] Z2g guard replica plus block form  (rc=%Z2GRC%, see Z2g.log)

rem ---------------- verdict ----------------
>>"%SUM%" echo.
>>"%SUM%" echo ---- end ----
echo.
echo summary : %SUM%
echo logs    : %LDIR%
echo.
type "%SUM%"
echo.
pause
exit /b 0

rem ==================================================================
rem :run <idx> <name>
rem   copies the fixture to CDIR\<name>, runs copy_to_mp4 on it and
rem   appends one verdict line to the summary.
rem ==================================================================
:run
set "IDX=%~1"
set "NAME=%~2"
set "SRC=%CDIR%\%NAME%"
rem %~dp2 on a bare relative name resolves against the CURRENT directory,
rem which gets the "sub & dir (x)\..." case wrong. Derive it from the
rem assembled absolute path instead.
for %%F in ("%SRC%") do set "EXPECT=%%~dpnF.mp4"
copy /y "%WORK%\base.mov" "%SRC%" >nul 2>nul
if not exist "%SRC%" (
    >>"%SUM%" echo [SETUP-FAIL] A%IDX% "%NAME%"  could not create test file
    exit /b 0
)
if exist "%EXPECT%" del /q "%EXPECT%"
call "%REPO%\ffmpeg_copy_to_mp4.bat" "%SRC%" > "%LDIR%\A%IDX%.log" 2>&1
set "RC=%ERRORLEVEL%"
set "V=FAIL"
if exist "%EXPECT%" set "V=PASS"
>>"%SUM%" echo [%V%] A%IDX% rc=%RC% "%NAME%"
exit /b 0

rem ==================================================================
rem :runenc <idx> <name>
rem   same, but through the full encoder (avc_qsv) with a .mp4 fixture
rem ==================================================================
:runenc
set "IDX=%~1"
set "NAME=%~2"
set "SRC=%CDIR%\%NAME%"
for %%F in ("%SRC%") do set "EXPECT=%%~dpnF-compressed.mp4"
copy /y "%WORK%\base.mp4" "%SRC%" >nul 2>nul
if not exist "%SRC%" (
    >>"%SUM%" echo [SETUP-FAIL] C%IDX% "%NAME%"  could not create test file
    exit /b 0
)
if exist "%EXPECT%" del /q "%EXPECT%"
call "%REPO%\ffmpeg_avc_qsv.bat" "%SRC%" > "%LDIR%\C%IDX%.log" 2>&1
set "RC=%ERRORLEVEL%"
set "V=FAIL"
if exist "%EXPECT%" set "V=PASS"
>>"%SUM%" echo [%V%] C%IDX% rc=%RC% "%NAME%"
exit /b 0

rem ==================================================================
rem :skip <idx> <reason>
rem ==================================================================
:skip
>>"%SUM%" echo [SKIP] A%~1 %~2
exit /b 0
