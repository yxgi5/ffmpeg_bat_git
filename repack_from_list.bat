@echo off
rem ============================================================
rem cp65001 relaunch guard (ASCII only - do NOT add non-ASCII here)
rem cmd.exe reads a .bat with the codepage of the process that reads
rem it; an in-file chcp can misalign that reader, and the split line
rem fragment is then executed as a command (garbled banner line). So:
rem switch the console to UTF-8 and restart ourselves in a FRESH cmd
rem process, which reads this whole file from byte 0 under UTF-8.
rem Do NOT use a marker ARGUMENT + SHIFT here: SHIFT overwrites %0 as
rem well (documented), so every path derived from the script directory
rem would then resolve against the marker instead of this script. An
rem environment variable keeps %0 and all arguments untouched.
rem SETLOCAL first: the marker must stay inside THIS invocation.
rem Without it the marker leaks into the CALLER environment, so a
rem caller that uses CALL or a second run in the same cmd session
rem skips the guard and the garbled banner line comes back. The
rem child cmd /c below still inherits it.
setlocal
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main
setlocal DisableDelayedExpansion
rem 本脚本不需要延迟展开: 一旦开启, for 变量 %%i 里的感叹号会被成对吃掉,
rem 片名 Tora! Tora! Tora!.mp4 这类条目会变成残缺路径

rem 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.bat 的 :parse_switches)
call "%~dp0lib\common.bat" parse_switches %*
if errorlevel 2 exit /b 2

rem 统一 --help / -help / -h: 打印用法后退出, 不干活(见 lib\common.bat 的 :want_help / :usage)
rem 刻意用两条独立的 if 而不是 ( ) 块: usage 的参数里不许出现半角右括号(会提前闭块)。
call "%~dp0lib\common.bat" want_help %*
if defined FB_WANT_HELP call "%~dp0lib\common.bat" usage "repack_from_list.bat  -  按清单逐条无损转封装为 mp4" "用法: repack_from_list.bat 清单文件    不带参数默认 list.txt" "清单每行一个视频路径；逐条调用 ffmpeg_copy_to_mp4.bat"
if defined FB_WANT_HELP exit /b 0

SET "SRC_FILE="

rem %~1 (not %1) strips the surrounding quotes: keeping them made the
rem quoted expansion below turned into a doubly quoted path, and cmd then
rem looked for a file whose name literally contains quote characters.
if not "%PARSE_POS%"=="" (
    SET "SRC_FILE=%PARSE_POS%"
) else (
    SET "SRC_FILE=list.txt"
)
echo SRC_FILE="%SRC_FILE%"
rem ---------- 开关透传(无人值守留痕) ----------
rem 本脚本经 parse_switches 接受标准 --key value 开关(EXT / BITRATE_NO_HALF /
rem   FF_HWACCEL / FF_ON_EXIST 等, 见 readme.md 的开关表), 设成环境变量后原样透传给下游入口
rem   ffmpeg_copy_to_mp4.bat; 老的环境变量写法仍兼容。
rem 默认值统一写在 lib\defaults.cfg —— 无人值守前改那个文件即可, 命令行
rem   set XXX=... 的临时覆盖优先。 load_defaults 把默认值装进本进程环境(子进程
rem   继承), 再回显一行: 跑一整晚的日志里能一眼看出这份清单是按什么设置转的。
call "%~dp0lib\common.bat" load_defaults
echo SWITCHES: EXT=%EXT% BITRATE_NO_HALF=%BITRATE_NO_HALF% FF_ON_EXIST=%FF_ON_EXIST%

rem NOTE: usebackq + quotes makes the list path a FILE, not a literal
rem string; CALL is required or cmd never returns from the encoder and
rem only the first list entry gets processed; %~dp0 anchors the encoder
rem so this also works when the repo is not the current directory.
rem fail-fast: 与 .sh 孪生(run_list)对齐 —— 任一文件失败立即中止并传回 1,
rem 不再默默跑完整份清单还报 0。goto 是 cmd 里跳出 for 块的可靠写法。
rem 退出码 4(硬件缺失)单独判: 它不是"这个文件转坏了", 而是"这台机器跑不了这个
rem   入口" —— 清单剩下的条目会一条接一条撞同一堵墙, 所以按用户裁定不跳过、
rem   直接中止并把 4 传回, 让调用方一眼看出是硬件而不是片子的问题。
rem 判定只能用 if errorlevel: for 块里 %VAR% 在块解析时就冻结了, %ERRORLEVEL%
rem   读不到子调用的返回值; 且 "if errorlevel 4" + "if not errorlevel 5" 才是
rem   "正好等于 4"(不会把 5/6 截走), ffmpeg 的负 AVERROR(如 av1_qsv 的 -40)
rem   也进不来 —— 带符号比较下 -40 < 4。
rem ---------- UTF-8 BOM(记事本存出来的清单) ----------
rem 清单第一条若带 BOM, cmd 的 for /f 会把它一并吃进路径 —— check_isvideo 于是
rem   判"不是视频"并把整份清单打成 rc=3(sh 侧 run_list 早就剥了, 实测 T21 在 sh 侧
rem   PASS / bat 侧 FAIL)。剥除放在子程序里做: for 块内不能展开 %LINE:~1%(块解析时
rem   就冻结), 而开延迟展开又会吃掉片名里的 '!'(Tora! Tora! Tora!.mp4 那一类),
rem   所以这里 call 到 :RUN_ONE, 在子程序里按普通展开处理。
rem   只处理第一行 —— BOM 只可能出现在文件开头。

for /f "usebackq delims=" %%i in ("%SRC_FILE%") do (
    call :RUN_ONE "%%i"
    if errorlevel 4 if not errorlevel 5 goto LIST_HWFAIL
    if errorlevel 1 goto LIST_FAIL
)
exit /b 0

:RUN_ONE
set "LINE=%~1"
rem 第一个字符是 UTF-8 BOM(U+FEFF, 下面那个引号里就是它, 不可见)时才剁;
rem   for /f 在 cp65001 下会把 EF BB BF 解成这一个字符。
if "%LINE:~0,1%"=="﻿" set "LINE=%LINE:~1%"
call "%~dp0ffmpeg_copy_to_mp4.bat" "%LINE%"
set "RC=%errorlevel%"
exit /b %RC%

:LIST_HWFAIL
echo 硬件缺失(rc=4): 这台机器跑不了这个入口, 后续条目同样跑不了 —— 中止整份清单
exit /b 4

:LIST_FAIL
echo Convert failed! rc=%ERRORLEVEL%
exit /b 1
