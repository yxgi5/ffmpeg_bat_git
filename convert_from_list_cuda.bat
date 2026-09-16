@echo off
setlocal EnableDelayedExpansion
chcp 65001

SET "SRC_FILE="

if [%1] neq [] (
    SET SRC_FILE=%1
) else (
    SET SRC_FILE=list.txt
)
echo SRC_FILE=%SRC_FILE%

rem NOTE: usebackq + quotes makes the list path a FILE, not a literal
rem string; CALL is required or cmd never returns from the encoder and
rem only the first list entry gets processed; %~dp0 anchors the encoder
rem so this also works when the repo is not the current directory.
for /f "usebackq delims=" %%i in ("%SRC_FILE%") do call "%~dp0ffmpeg_hevc_nvenc.bat" "%%i"
