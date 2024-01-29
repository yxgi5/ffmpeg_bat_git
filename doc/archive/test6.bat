@echo off
SETLOCAL

CALL :SetValue value1,value2
echo value1=%value1%
echo value2=%value2%
EXIT /B %ERRORLEVEL%

:SetValue
set "%~1=5"
set "%~2=10"
EXIT /B 0