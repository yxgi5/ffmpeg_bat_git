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

for /f "delims=" %%i in (%SRC_FILE%) do ffmpeg_copy_to_mp4 "%%i"