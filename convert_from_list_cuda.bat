@echo off
setlocal DisableDelayedExpansion
rem 本脚本不需要延迟展开: 一旦开启, for 变量 %%i 里的感叹号会被成对吃掉,
rem 片名 Tora! Tora! Tora!.mp4 这类条目会变成残缺路径
chcp 65001

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
for /f "usebackq delims=" %%i in ("%SRC_FILE%") do call "%~dp0ffmpeg_hevc_nvenc.bat" "%%i"
