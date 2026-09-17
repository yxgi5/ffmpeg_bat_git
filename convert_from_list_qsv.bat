@echo off
rem ============================================================
rem cp65001 relaunch guard (ASCII only - do NOT add non-ASCII here)
rem cmd.exe reads a .bat with the codepage of the process that reads
rem it; an in-file chcp can misalign that reader, and the split line
rem fragment is then executed as a command (garbled banner line). So:
rem switch the console to UTF-8 and restart ourselves in a FRESH cmd
rem process, which reads this whole file from byte 0 under UTF-8.
rem Do NOT use a marker ARGUMENT + SHIFT here: SHIFT overwrites %0 as
rem well (documented), so every path derived from the script directory
rem would then resolve against the marker instead of this script. An
rem environment variable keeps %0 and all arguments untouched.
rem SETLOCAL first: the marker must stay inside THIS invocation.
rem Without it the marker leaks into the CALLER environment, so a
rem caller that uses CALL or a second run in the same cmd session
rem skips the guard and the garbled banner line comes back. The
rem child cmd /c below still inherits it.
setlocal
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main
setlocal DisableDelayedExpansion
rem 本脚本不需要延迟展开: 一旦开启, for 变量 %%i 里的感叹号会被成对吃掉,
rem 片名 Tora! Tora! Tora!.mp4 这类条目会变成残缺路径

SET "SRC_FILE="

rem %~1 (not %1) strips the surrounding quotes: keeping them made the
rem quoted expansion below turned into a doubly quoted path, and cmd then
rem looked for a file whose name literally contains quote characters.
if not "%~1"=="" (
    SET "SRC_FILE=%~1"
) else (
    SET "SRC_FILE=list.txt"
)
echo SRC_FILE="%SRC_FILE%"

rem NOTE: usebackq + quotes makes the list path a FILE, not a literal
rem string; CALL is required or cmd never returns from the encoder and
rem only the first list entry gets processed; %~dp0 anchors the encoder
rem so this also works when the repo is not the current directory.
rem fail-fast: 与 .sh 孪生(run_list)对齐 —— 任一文件失败立即中止并传回 1,
rem 不再默默跑完整份清单还报 0。goto 是 cmd 里跳出 for 块的可靠写法。
for /f "usebackq delims=" %%i in ("%SRC_FILE%") do (
    call "%~dp0ffmpeg_hevc_qsv.bat" "%%i"
    if errorlevel 1 goto LIST_FAIL
)
exit /b 0

:LIST_FAIL
echo Convert failed! rc=%ERRORLEVEL%
exit /b 1
