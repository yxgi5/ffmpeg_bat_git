@echo off
setlocal EnableDelayedExpansion


set decimals=2


set /A one=1, decimalsP1=decimals+1
for /L %%i in (1,1,%decimals%) do set "one=!one!0"


:getNumber
set /P "numA=Enter a number with %decimals% decimals: "
if "!numA:~-%decimalsP1%,1!" equ "." goto numOK
echo The number must have a point and %decimals% decimals
goto getNumber


:numOK
set numA=3.01
set numB=2.54


set "fpA=%numA:.=%"
set "fpB=%numB:.=%"


set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one, div=fpA*one/fpB


echo %numA% + %numB% = !add:~0,-%decimals%!.!add:~-%decimals%!
echo %numA% - %numB% = !sub:~0,-%decimals%!.!sub:~-%decimals%!
echo %numA% * %numB% = !mul:~0,-%decimals%!.!mul:~-%decimals%!
echo %numA% / %numB% = !div:~0,-%decimals%!.!div:~-%decimals%!