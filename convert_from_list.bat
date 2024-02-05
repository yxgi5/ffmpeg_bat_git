@echo off
setlocal EnableDelayedExpansion
chcp 65001
for /f "delims=" %%i in (list.txt) do ffmpeg_bat_git.bat "%%i"