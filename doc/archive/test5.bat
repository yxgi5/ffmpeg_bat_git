@echo off
::SETLOCAL ENABLEEXTENSIONS
::SETLOCAL ENABLEDELAYEDEXPANSION

set SRC_BITRATE=11122
set "BIT="
call :calc_bitrate25
::echo. SRC_BITRATE1=%SRC_BITRATE%
echo SRC_BITRATE1=%SRC_BITRATE%
set BIT=%BIT%
echo BIT1=%BIT%
ENDLOCAL
exit /B

:calc_bitrate25
set /a BIT=%SRC_BITRATE%*100/25
echo function25
echo BIT=%BIT%
exit /b 0