@echo off
::setlocal enabledelayedexpansion
::setlocal EnableExtensions

echo %1 
echo %2 
echo %3 
if %1%==1 (echo "The value is 1") else (echo "Unknown value") 
if %2%==2 (echo "The value is 2") else (echo "Unknown value") 
if %3%==3 (echo "The value is 3") else (echo "Unknown value")

call :return_value_function %1 %2 tmp1
echo tmp1=%tmp1%

::call :numOK %4 %2 tmp2
::echo tmp2=%tmp2%

set "TARGET_BITRATE=%4"
::set "TARGET_BITRATE=" rem 这个变量就相当于不存在了不能用%TARGET_BITRATE%表达式了
echo cmp1
::if defined TARGET_BITRATE (echo 1) else (echo 0)
if defined TARGET_BITRATE (
    echo %TARGET_BITRATE%
    echo %2%
    set "percentage="
    set /a percentage=(%TARGET_BITRATE%*100^)     /     %2%
    echo percentage0=%percentage%%%
    set /a percentage=(%TARGET_BITRATE%*100^)     /     %2%
    echo percentage0=%percentage%%%
)
set /a tmp3=%TARGET_BITRATE%*100
echo tmp3=%tmp3%
call :numOK "%tmp3%" "%2" "tmp2"
echo tmp2=%tmp2%

exit /b 0


echo cmp2
if not %TARGET_BITRATE%=="" (echo 1) else (echo 0)
echo cmp3
if %TARGET_BITRATE% neq "" (echo 1) else (echo 0)
echo cmp4
if %TARGET_BITRATE% neq [] (echo 1) else (echo 0)



:numOK
setlocal EnableDelayedExpansion
set numA=%~1
echo numA=%numA%
set numB=%~2
echo numB=%numB%

set decimals=2
set /A one=1, decimalsP1=decimals+1
for /L %%i in (1,1,%decimals%) do set "one=!one!0"

set "fpA=%numA:.=%"
set "fpB=%numB:.=%"
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one, div=fpA*one/fpB

::echo %numA% + %numB% = !add:~0,-%decimals%!.!add:~-%decimals%!
::echo %numA% - %numB% = !sub:~0,-%decimals%!.!sub:~-%decimals%!
::echo %numA% * %numB% = !mul:~0,-%decimals%!.!mul:~-%decimals%!
echo %numA% / %numB% = !div:~0,-%decimals%!.!div:~-%decimals%!
set /a ret = !div:~0,-%decimals%!
echo ret=%ret%
endlocal & set /a %~3=%ret%
exit /b 0


:return_value_function
SET /A %~3=%~1+%~2
EXIT /B 0
