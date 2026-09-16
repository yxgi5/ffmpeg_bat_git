
rem ============================================================
rem lib\common.bat - 公共子程序库 (P1 重构)
rem 用法: call "%~dp0lib\common.bat" <函数名> [参数...]
rem   函数的实际参数从 %2 开始 ( %1 为函数名)
rem   find_ffmpeg: 四级回退定位 ffmpeg/ffprobe (FFMPEG_BIN > 仓库内 > PATH > 默认目录)
rem   call 跨文件共享环境: 函数内 set 的变量(非 setlocal 内)对调用方可见
rem 注意: 本文件必须保持 CRLF 行尾, 勿用会剥 CR 的编辑器保存
rem ============================================================

if "%~1"=="" exit /b 1
if /I "%~1"=="lookup_bitrate"        goto lookup_bitrate
if /I "%~1"=="find_ffmpeg"           goto find_ffmpeg
if /I "%~1"=="numOK"                 goto numOK
if /I "%~1"=="calc_bitrate_fromsize" goto calc_bitrate_fromsize
if /I "%~1"=="extract"               goto extract
if /I "%~1"=="extract_mp4"           goto extract_mp4
if /I "%~1"=="get_suffix"            goto get_suffix
echo 未知函数: %~1
exit /b 1

:lookup_bitrate
rem 按像素总数查目标码率: call ... lookup_bitrate <像素数> <输出变量名> [csv文件名]
rem   csv 文件名可选, 位于本目录: bitrate_table_hevc.csv(默认) / bitrate_table_avc.csv / bitrate_table_av1.csv
rem   命中: 返回 0 并设置输出变量; 超出表范围或参数缺失: 返回 2 且输出变量被清空
set "LB_VAR=%~3"
set "LB_CSV=%~4"
if not defined LB_VAR exit /b 2
if "%~2"=="" exit /b 2
set "%LB_VAR%="
if not defined LB_CSV set "LB_CSV=bitrate_table_hevc.csv"
set "LB_FILE=%~dp0%LB_CSV%"
if not exist "%LB_FILE%" (
    echo %LB_CSV% not found: %LB_FILE%
    exit /b 2
)
setlocal EnableDelayedExpansion
set "LB_VAL="
rem 方向与 common.sh 一致: 取第一个 max_pixels >= 像素数的档位 (向上取档)
for /f "usebackq skip=1 tokens=1,2 delims=," %%a in ("%LB_FILE%") do (
    if not defined LB_VAL if %~2 leq %%a set "LB_VAL=%%b"
)
endlocal & set "%LB_VAR%=%LB_VAL%"
if not defined %LB_VAR% exit /b 2
exit /b 0

:numOK
rem 整数除法取整: call ... numOK <被除数> <除数> <输出变量名>
rem (参数偏移: 原 %~1/%~2/%~3 变为 %~2/%~3/%~4, 因 %1 为函数名)
setlocal EnableDelayedExpansion
set numA=%~2
set numB=%~3

set decimals=4
set /A one=1, decimalsP1=decimals+1
for /L %%i in (1,1,2) do set "one=!one!0"

set "fpA=%numA:.=%"
set "fpB=%numB:.=%"
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one

set /a check=fpA*one
if !check! lss 0 (
    set /a fpA=fpA/10
    set /a fpB=fpB/10
)
if !fpB! neq 0 (
    set /A div=fpA*one/fpB
) else (
    echo fpB is 0, Divide by zero error.
    exit /b 1
)

set /a ret = !div!
endlocal & set /a %~4=%ret%
exit /b 0

:calc_bitrate_fromsize
rem 由文件大小与时长估算码率: call ... calc_bitrate_fromsize <字节数> <秒数> <输出变量名>
setlocal EnableDelayedExpansion
set numA=%~2
set numB=%~3

set decimals=1
set /A one=1, decimalsP1=decimals+1
for /L %%i in (1,1,1) do set "one=!one!0"

set "fpA=%numA:.=%"
echo !fpA!
set "fpB=%numB:~0%"
echo !fpB!
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one, div=fpA/fpB

echo %numA% / %numB% = !div!
set /a ret = 8*!div!
echo ret=%ret%
endlocal & set /a %~4=%ret%
exit /b 0

:extract
rem 拆分文件路径: call ... extract <文件> <输出路径变量> <输出文件名变量>
rem   输出形如 "D:\dir\" 与 "name-compressed.mp4"
rem 获取到文件路径
echo in extract()
echo %~dp2
set %~3="%~dp2"
rem 获取到文件盘符
echo %~d2
rem 获取到文件名称
echo "%~n2"
rem 获取到文件后缀
echo %~x2
set %~4="%~n2-compressed.mp4"
echo "%~n2-compressed.mp4"
exit /b 0

:get_suffix
rem 获取文件后缀: call ... get_suffix <文件> <输出变量名>
set %~3=%~x2
exit /b 0

:extract_mp4
rem 拆分文件路径(remux 用, 输出名不加后缀): call ... extract_mp4 <文件> <输出路径变量> <输出文件名变量>
rem   输出形如 "D:\dir\" 与 "name.mp4"
rem 获取到文件路径
echo in extract_mp4()
echo %~dp2
set %~3="%~dp2"
rem 获取到文件名称
echo "%~n2"
set %~4="%~n2.mp4"
echo "%~n2.mp4"
exit /b 0

:find_ffmpeg
rem 定位 ffmpeg/ffprobe 所在 bin 目录: call ... find_ffmpeg <输出变量名>
rem 优先级: 环境变量 FFMPEG_BIN(指向bin目录) > 仓库内 ffmpeg\bin > PATH(where) > C:\Program Files\ffmpeg\bin
rem 命中: 输出变量=bin目录(无尾部反斜杠), 返回 0; 未找到: 返回 1
set "FF_OUT=%~2"
if not defined FF_OUT exit /b 1
set "FFBIN="
if defined FFMPEG_BIN if exist "%FFMPEG_BIN%\ffmpeg.exe" set "FFBIN=%FFMPEG_BIN%"
if not defined FFBIN if exist "%~dp0..\ffmpeg\bin\ffmpeg.exe" for %%I in ("%~dp0..\ffmpeg\bin") do set "FFBIN=%%~fI"
if not defined FFBIN (
    for /f "delims=" %%p in ('where ffmpeg.exe 2^>nul') do (
        if not defined FFBIN for %%I in ("%%p") do set "FFBIN=%%~dpI"
    )
)
if not defined FFBIN if exist "C:\Program Files\ffmpeg\bin\ffmpeg.exe" set "FFBIN=C:\Program Files\ffmpeg\bin"
if not defined FFBIN (
    echo [find_ffmpeg] 未找到 ffmpeg.exe: 请安装 ffmpeg 或设置环境变量 FFMPEG_BIN 指向其 bin 目录
    set "%FF_OUT%="
    exit /b 1
)
if "%FFBIN:~-1%"=="\" set "FFBIN=%FFBIN:~0,-1%"
set "%FF_OUT%=%FFBIN%"
exit /b 0
