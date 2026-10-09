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
rem SELF_DIR is captured first and used for every sub-call below.
rem SETLOCAL first: the marker must stay inside THIS invocation.
rem Without it the marker leaks into the CALLER environment, so a
rem caller that uses CALL (convert_from_list_*.bat) or a second run
rem in the same cmd session skips the guard and the garbled banner
rem line comes back. The child cmd /c below still inherits it.
setlocal
set "SELF_DIR=%~dp0"
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

rem ---- HWACCEL_FALLBACK: D3D fallback for -hwaccel auto (measured 2026-09-30) ----
rem When the Windows session is disconnected or locked, D3D device creation is
rem refused and ffmpeg does NOT degrade gracefully - it crashes (0xC0000005).
rem On failure with a D3D signature in stderr, rerun once without -hwaccel auto.
rem Kept between "exit /b" and ":main" so it is never reached by fallthrough, and
rem ASCII-only on purpose: everything above :main is the cp65001 guard region and
rem is read under an unknown codepage (lint L04 rejects non-ASCII bytes there).
:HWACCEL_FALLBACK
findstr /c:"Failed to create Direct3D device" /c:"Device creation failed" "%FF_HWERR%" >nul 2>&1
if errorlevel 1 exit /b 0
echo.
echo [fallback] -hwaccel auto init failed (D3D unavailable), retry without hwaccel
set RUN_COM=%RUN_COM: -hwaccel %FF_HWACCEL%=%
%RUN_COM%
set "FB_RC=%ERRORLEVEL%"
exit /b 0

:main

rem ============================================================
rem 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.bat 的 :parse_switches)
rem   优先级 参数 > 环境变量 > defaults.cfg; 没给的回退 env / cfg(老 set 写法仍兼容)
rem   位置参数(文件名)记在 PARSE_POS, 下面取它取代 %~1
call "%SELF_DIR%lib\common.bat" parse_switches %*
if errorlevel 2 exit /b 2

rem 统一 --help / -help / -h: 打印用法后退出, 不干活(见 lib\common.bat 的 :want_help / :usage)
rem 刻意用两条独立的 if 而不是 ( ) 块: usage 的参数里不许出现半角右括号(会提前闭块)。
call "%SELF_DIR%lib\common.bat" want_help %*
if defined FB_WANT_HELP call "%SELF_DIR%lib\common.bat" usage "ffmpeg_libx264.bat  -  AVC libx264 软件编码压缩（无硬件要求）" "用法: ffmpeg_libx264.bat 视频文件    也可直接把文件拖到本 bat 上"
if defined FB_WANT_HELP exit /b 0

rem ffmpeg_libx264.bat - AVC libx264 软件编码压缩 (P1 重构版)
rem 无硬件要求, 作为 H.264 软编保底入口; 编码参数与 ffmpeg_libx264.sh 对齐
rem (-profile:v:0 high -preset fast -pix_fmt yuv420p)
rem 用法: 拖放视频文件到本 bat 上, 或双击后输入视频地址
rem 码率查表: lib\bitrate_table_avc.csv | 公共函数: lib\common.bat
rem ------------------------------------------------------------
rem 路径/命令行拼接规则「第六轮实测, 勿改回 set 包装写法」:
rem   本脚本的 RUN_COM / SRC_CODEC / SRC_FILE / TARGET_FILE 里存的是
rem   「已用双引号包好的路径, 或整条已拼好的命令行」。
rem   set 的包装写法 set "VAR=值" 要求「值里不能出现字面量双引号」;
rem   一旦出现, 例如值以 %FFMPEG_PATH% 的带引号形式开头, 或值里又嵌了带引号的
rem   %SRC_FILE%, 包装引号就会与值里第一个引号配对闭合,
rem   后面的路径段落落进「未加引号区」, 路径里的与号和小括号立刻被 cmd
rem   当成语法字符, 命令行当场被截断。
rem   日志实证: 给 SRC_FILE 赋值那行用的是非包装写法, 路径含「A 与 B 2020」,
rem             结果完整正确; 而拼接 RUN_COM 那行用包装写法加同一路径,
rem             结果 RUN_COM 在 -i 处就被截断, 并报 B is not recognized。
rem   结论: 值里会出现引号的 set 一律用非包装写法 set VAR=值, 这样整行引号
rem   配对是平衡的, 路径里的与号 / 小括号 / 脱字符全落在引号内被保护;
rem   只有值内确定没有引号的常量赋值, 才可以用包装写法。
rem   原版曾用「把与号替换成 脱字符 再跟与号」来补偿包装写法造成的不配对,
rem   在非包装写法下必须去掉, 否则脱字符会进到真实路径里, 勿恢复。
rem ------------------------------------------------------------
rem 注意: 本文件必须保持 CRLF 行尾
rem ============================================================

rem ---------- 公共流程在 lib\encode_core.bat (TODO.md 阶段 0) ----------
rem banner / ffmpeg 定位 / 源探测 / 码率查表 / 命令拼装 / 输出路径 全在里面; 编码器
rem 之间的差异压成 ENC_TABLE / ENC_ARGS 两张表与 DEC / GATE 两个钩子。本文件只留
rem 三样搬不走的东西: cp65001 守卫 + :HWACCEL_FALLBACK(上面)、执行段与失败守卫
rem (下面)、以及自己的 usage 文案与头部说明。
call "%SELF_DIR%lib\encode_core.bat" enc_build libx264
set "FB_RC=%ERRORLEVEL%"
rem 找不到 ffmpeg 时内核只置 FB_NO_PATH(goto 不能跨文件), 由这里跳过去 —— 那边的
rem 提示与 pause 是入口的交互, 不该搬进内核。
if defined FB_NO_PATH goto NO_PATH_ERR
rem 其余退出码(2 码率表未命中 / 3 输入无视频流 / 4 硬件缺失 / 5 码率异常 / 1 转码失败)
rem 原样传回, 契约见 test\README.md 5.2。
if not "%FB_RC%"=="0" exit /b %FB_RC%
set "FF_HWERR=%TEMP%\ff_hwaccel_%RANDOM%.err"
rem dry-run: DRY_RUN 为真时只打印这条命令, 不执行(见 lib\common.bat 的 :dry_run)
call "%SELF_DIR%lib\common.bat" dry_run
if defined DRY_HIT exit /b 0
rem 仅 -hwaccel auto 时需要捕获 stderr 做 D3D 回退(锁屏/断会话下 auto 会崩);
rem 其余情况(含默认 none / 显式 cuda 等)直接把 stderr 打到控制台 -> 进度实时可见。
if /i "%FF_HWACCEL%"=="auto" (
    %RUN_COM% 2>"%FF_HWERR%"
    set "FB_RC=%ERRORLEVEL%"
    type "%FF_HWERR%" 2>nul
    if not "%FB_RC%"=="0" call :HWACCEL_FALLBACK
) else (
    %RUN_COM%
    set "FB_RC=%ERRORLEVEL%"
)
rem 负退出码陷阱 (2026-09-17 实测根因): Windows 版 ffmpeg 失败时常常
rem 返回「负」的 AVERROR 值 —— 本机 av1_qsv 拿不到编码器时 ffmpeg.exe
rem 退出码是 -40 (Function not implemented), 而 cmd 的 `if errorlevel N`
rem 是「带符号」比较, -40 >= 1 不成立 → 守卫不会触发,
rem 真失败一路落到文件末尾的 exit /b 0 (探针因此报 rc=0 假 OK).
rem 改成「不等于 0」判定: 它同时兜住负数与正数, 且赋值到变量后
rem 走字符串相等比较, 不依赖 cmd 对负数的数值解析;
rem 值空时也会判成失败(安全侧), 而 if errorlevel 写法在值为空时
rem 只会报语法错误并继续往下跑.
if not "%FB_RC%"=="0" (
    echo.
    echo Convert failed! rc=%FB_RC%
    rem 与 .sh 孪生对齐: ffmpeg 失败必须传回 1, 不能吞成 0.
    rem 探针/冒烟/convert_from_list 都依赖这个非零退出码(见 test/README 退出码契约).
    exit /b 1
)


echo ERRORLEVEL:%ERRORLEVEL%
echo 转换已出错或完成, 默认不替换, 请手动确认输出文件完整性

echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
echo SRC_PIX=%SRC_PIX%
echo SRC_BITRATE=%SRC_BITRATE%
echo TARGET_BITRATE=%TARGET_BITRATE%
echo percentage=%percentage%
echo TARGET_FILE:%TARGET_FILE%

exit /b 0

:NO_PATH_ERR
echo 找不到 ffmpeg.exe: 请安装 ffmpeg(默认查找 C:\Program Files\ffmpeg\bin)
echo 或设置环境变量 FFMPEG 指向 ffmpeg 可执行文件后重试
pause
exit /b 1
