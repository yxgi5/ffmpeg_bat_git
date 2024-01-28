@echo off
setlocal EnableDelayedExpansion

for /f "delims=" %%i in (list.txt) do ffmpeg_bat_git.bat "%%i"