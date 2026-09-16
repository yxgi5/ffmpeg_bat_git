@echo off
rem ============================================================
rem smoke_all.bat   *** ASCII ONLY / CRLF ***
rem
rem One double-click runs both smoke layers against the repo:
rem
rem   [1/2] smoke_ffmpeg.bat          regression suite T1-T17
rem         - every encoder entry, three usage modes (drag-drop,
rem           interactive, fresh-UTF-8 console), list mode,
rem           silent-input test, audio-only rejection, AV1 NVENC
rem           (T14) and AV1 QSV (T15, self-SKIPping when the iGPU
rem           has no AV1 encoder), plus the global banner and
rem           debug-echo hygiene lines.
rem         -> smoke_logs\summary.txt
rem
rem   [2/2] smoke_special_chars.bat   metacharacter matrix
rem         - filenames carrying & ( ) ! % [ ] and friends, list
rem           driven runs, construct micro-tests (part Z).
rem         -> chars_logs\summary.txt
rem
rem Both children are called with stdin from NUL so their own
rem trailing pause does not stop the chain; this script pauses once
rem at the very end instead.
rem ============================================================
setlocal EnableExtensions
set "SELF=%~dp0"

echo ============================================================
echo  combined smoke: regression suite + special character matrix
echo ============================================================
echo.

if not exist "%SELF%smoke_ffmpeg.bat" (
    echo [FATAL] smoke_ffmpeg.bat not found next to this file
    pause
    exit /b 1
)
if not exist "%SELF%smoke_special_chars.bat" (
    echo [FATAL] smoke_special_chars.bat not found next to this file
    pause
    exit /b 1
)

echo [1/2] regression suite T1-T17 ...
call "%SELF%smoke_ffmpeg.bat" < nul
set "RC1=%ERRORLEVEL%"

echo.
echo [2/2] special character matrix ...
call "%SELF%smoke_special_chars.bat" < nul
set "RC2=%ERRORLEVEL%"

echo.
echo ============================================================
echo  both runs finished
echo  regression suite rc = %RC1%   summary: %SELF%smoke_logs\summary.txt
echo  char matrix    rc = %RC2%   summary: %SELF%chars_logs\summary.txt
echo ============================================================
echo.
pause
exit /b 0
