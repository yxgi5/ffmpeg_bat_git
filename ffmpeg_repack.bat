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
rem When the harness feeds stdin via a redirected file, skip chcp: the chcp
rem command itself breaks SET /P reads from a redirected file. The harness
rem console already runs under UTF-8 (cp65001), so this no-BOM file still
rem reads correctly here; interactive double-click is unaffected.
if defined FB_NO_CHCP goto main
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main

rem ============================================================
rem ffmpeg_repack.bat - 无损转封装(remux, 不重编码); 薄壳, 公共流程在 lib\encode_core.bat
rem 用法: 拖放视频文件到本 bat 上, 或双击后输入视频地址(交互模式还会再问一次输出文件名)
rem 默认出口 mp4; EXT=mkv 可切; --repair / REPAIR=1 强制 mkv 并注入修复选项
rem 与 7 个编码入口同内核(encode_core.bat 的 :copy_run); 本文件只留三样搬不走的东西:
rem   cp65001 守卫 + rc 传播(由 :copy_run 内部完成执行) + 自己的 usage 文案与头部说明。
rem 输出文件名: 拖放/命令行传了源文件则自动命名 <名>-repacked.<ext>, 绝不询问; 仅交互模式
rem   (无参双击)会再问一次输出文件名, 留空则沿用自动名, --repair 时归一成 .mkv。
rem   (旧版独立脚本曾单独有手填输出文件名且与全家族不一致; 现已统一进 :copy_run 同口径)
rem 注意: 本文件必须保持 CRLF 行尾
rem ============================================================

rem 命令行开关解析: --key value / --key=value -> 同名大写环境变量(见 lib\common.bat 的 :parse_switches)
rem   优先级 参数 > 环境变量 > defaults.cfg; 没给的回退 env / cfg(老 set 写法仍兼容)
rem   位置参数(文件名)记在 PARSE_POS, 下面取它取代 %~1
call "%SELF_DIR%lib\common.bat" parse_switches %*
if errorlevel 2 exit /b 2

rem 统一 --help / -help / -h: 打印用法后退出, 不干活(见 lib\common.bat 的 :want_help / :usage)
rem 刻意用两条独立的 if 而不是 ( ) 块: usage 的参数里不许出现半角右括号(会提前闭块)。
call "%SELF_DIR%lib\common.bat" want_help %*
if defined FB_WANT_HELP call "%SELF_DIR%lib\common.bat" usage "ffmpeg_repack.bat  -  无损转封装（不重编码，默认 mp4；EXT=mkv 可切）" "用法: ffmpeg_repack.bat [源文件]  也可直接把源文件拖到本 bat 上" "本入口没有码率表；源已是目标容器也会重命名为 -repacked" "无参双击会询问 源文件 与 输出文件名（留空则自动 名-repacked.mp4）"
if defined FB_WANT_HELP exit /b 0

rem ---------- 公共流程(命令拼装 + 执行 + 退出码)在 lib\encode_core.bat :copy_run ----------
call "%SELF_DIR%lib\encode_core.bat" copy_run
set "FB_RC=%ERRORLEVEL%"
rem 找不到 ffmpeg 时内核只置 FB_NO_PATH(goto 不能跨文件), 由这里跳过去 —— 那边的
rem 提示与 pause 是入口的交互, 不该搬进内核。
if defined FB_NO_PATH goto NO_PATH_ERR
rem 其余退出码(1 转码失败 / 3 输入无视频流)原样传回, 契约见 test\README.md §5.2。
if not "%FB_RC%"=="0" exit /b %FB_RC%
exit /b 0

:NO_PATH_ERR
echo 找不到 ffmpeg.exe: 请安装 ffmpeg(默认查找 C:\Program Files\ffmpeg\bin)
echo 或设置环境变量 FFMPEG 指向 ffmpeg 可执行文件后重试
pause
exit /b 1
