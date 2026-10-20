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
rem   优先级 参数 > 环境变量 > defaults.cfg; 没给的回退 env / cfg(老 set 写法仍兼容)
rem   清单路径取第一个非 -- 参数(PARSE_POS), 否则默认 list.txt
call "%~dp0lib\common.bat" parse_switches %*
if errorlevel 2 exit /b 2

rem 统一 --help / -help / -h: 打印用法后退出, 不干活(见 lib\common.bat 的 :want_help / :usage)
rem 刻意用两条独立的 if 而不是 ( ) 块: usage 的参数里不许出现半角右括号(会提前闭块)。
call "%~dp0lib\common.bat" want_help %*
if defined FB_WANT_HELP call "%~dp0lib\common.bat" usage "convert_from_list_qsv.bat  -  按清单逐条调用 hevc_qsv 入口" "用法: convert_from_list_qsv.bat 清单文件    不带参数默认 list.txt" "清单每行一个视频路径；开关以环境变量或参数原样透传给下游入口"
if defined FB_WANT_HELP exit /b 0

SET "SRC_FILE="

if defined PARSE_POS (
    SET "SRC_FILE=%PARSE_POS%"
) else (
    SET "SRC_FILE=list.txt"
)
echo SRC_FILE="%SRC_FILE%"
rem T25 (twin of sh T25): a non-text (binary) list file must be rejected, not
rem fed to ffmpeg as a garbage source. Scan for a NUL byte; lists are small.
set "FF_LIST_CHK=%SRC_FILE%"
powershell -NoProfile -Command "$b=[System.IO.File]::ReadAllBytes($env:FF_LIST_CHK); $n=0; foreach($x in $b){if($x -eq 0){$n=1;break}}; if($n -eq 1){exit 1}else{exit 0}" >nul 2>&1
if errorlevel 1 echo Not a plain text list file! binary content detected & exit /b 1
rem ---------- 开关透传(无人值守留痕) ----------
rem 本脚本不解析任何开关: 它们全部以环境变量的形式原样传给下游入口 ——
rem   EXT(输出容器) / BITRATE_NO_HALF(目标码率不除 2) / FF_HWACCEL(软硬解) /
rem   FF_ON_EXIST(同名产物策略), 以及各入口自己的开关(见 readme.md 的开关表)。
rem 默认值统一写在 lib\defaults.cfg —— 无人值守前改那个文件即可, 命令行
rem   set XXX=... 的临时覆盖优先。 load_defaults 把默认值装进本进程环境(子进程
rem   继承), 再回显一行: 跑一整晚的日志里能一眼看出这份清单是按什么设置转的。
call "%~dp0lib\common.bat" load_defaults
rem 转发参数: 把生效开关收集成 --key value, 显式传给每个入口(透传层去 env)
set "FWD="
for %%K in (ext bitrate_no_half ff_on_exist ff_hwaccel dvd_ext) do call :fwd_one %%K
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

rem 跳过计数(2026-10-20): 目录行/无视频流行只累加不中止, 判定与原因见 :RUN_ONE
set "SKIPPED=0"
for /f "usebackq delims=" %%i in ("%SRC_FILE%") do (
    call :RUN_ONE "%%i"
    if errorlevel 4 if not errorlevel 5 goto LIST_HWFAIL
    if errorlevel 1 goto LIST_FAIL
)
rem 汇总放在循环外: for 块里 %SKIPPED% 在块解析时就冻结, 读不到累加后的值
if %SKIPPED% GTR 0 echo [list] 跳过 %SKIPPED% 条(目录/非视频), 其余条目已处理
exit /b 0

:RUN_ONE
set "LINE=%~1"
rem 第一个字符是 UTF-8 BOM(U+FEFF, 下面那个引号里就是它, 不可见)时才剁;
rem   for /f 在 cp65001 下会把 EF BB BF 解成这一个字符。
if "%LINE:~0,1%"=="﻿" set "LINE=%LINE:~1%"
rem 行不存在 -> 中止整份清单(与 T23 的契约一致): 路径缺失多半是清单本身写错了,
rem   继续跑只会让后面的条目一条条陪葬; 它与"存在但不是可编码输入"是两回事,
rem   后者按用户裁定(2026-10-20)跳过, 见下面两个分支。
if not exist "%LINE%" (
    echo [list] 条目不存在, 中止整份清单: "%LINE%"
    exit /b 1
)
rem 是目录 -> 跳过: if exist "路径\"(带引号 + 尾随反斜杠)才是 cmd 里稳定的
rem   "是目录"判据, 实测对空目录与含 & / 圆括号的目录名都可靠(2026-10-20)。
if exist "%LINE%\" (
    echo [skip-dir] 是目录, 已跳过: "%LINE%"
    set /a SKIPPED+=1
    exit /b 0
)
call "%~dp0ffmpeg_hevc_qsv.bat" %FWD% "%LINE%"
set "RC=%errorlevel%"
rem rc=3 = 下游入口的 check_isvideo 判定"无视频流": 非视频文件(或探测失败的文件)
rem   都会走到这。按用户裁定跳过而非中止 —— 清单里混进一条非视频行, 不该让整份
rem   清单陪葬。硬件缺失(4)与真正的转码失败仍由外层 for 块中止(LIST_HWFAIL/LIST_FAIL)。
if "%RC%"=="3" (
    echo [skip-nonvideo] 不是可编码视频[无视频流], 已跳过: "%LINE%"
    set /a SKIPPED+=1
    exit /b 0
)
exit /b %RC%

:LIST_HWFAIL
echo 硬件缺失(rc=4): 这台机器跑不了这个入口, 后续条目同样跑不了 —— 中止整份清单
exit /b 4

:LIST_FAIL
echo Convert failed! rc=%ERRORLEVEL%
exit /b 1

:fwd_one
rem 把已知开关(已定义时)收集成 --key=value 追加到 FWD(见 :main 的 for 循环)
rem   用 = 形式(而非空格分隔)是关键: 在 for 块内 call 时, 含空格的 %FWD% 展开会把
rem   空格分隔的值 token 吞掉; = 形式把 key=value 绑成单一 token, 规避该 cmd 陷阱
set "FK=%~1"
if /I "%FK%"=="ext" if defined EXT set "FWD=%FWD% --ext=%EXT%" & exit /b 0
if /I "%FK%"=="bitrate_no_half" if defined BITRATE_NO_HALF set "FWD=%FWD% --bitrate_no_half=%BITRATE_NO_HALF%" & exit /b 0
if /I "%FK%"=="ff_on_exist" if defined FF_ON_EXIST set "FWD=%FWD% --ff_on_exist=%FF_ON_EXIST%" & exit /b 0
if /I "%FK%"=="ff_hwaccel" if defined FF_HWACCEL set "FWD=%FWD% --ff_hwaccel=%FF_HWACCEL%" & exit /b 0
if /I "%FK%"=="dvd_ext" if defined DVD_EXT set "FWD=%FWD% --dvd_ext=%DVD_EXT%" & exit /b 0
exit /b 0
