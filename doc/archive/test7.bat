@echo OFF
CALL :return_value_function ret_val1,ret_val2
ECHO The square root of %ret_val1% is %ret_val2%
PAUSE
EXIT /B %ERRORLEVEL% 
:return_value_function
SET %~1=100
SET %~2=10
EXIT /B 0