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
if defined FB_WANT_HELP call "%SELF_DIR%lib\common.bat" usage "ffmpeg_encode.bat  -  统一压缩入口（软件 / QSV / NVENC + 转封装）" "用法: ffmpeg_encode.bat --venc <编码器> [--dec <解码器>] 视频文件    也可直接把文件拖到本 bat 上" "  --venc libx264 libx265 libsvtav1" "        avc_qsv hevc_qsv av1_qsv" "        avc_nvenc hevc_nvenc av1_nvenc" "        copy                  (无损转封装, 不重编码)" "  --dec  auto | cpu | none | qsv | cuda   可省, 默认用编码器族的固定解码" "老入口仍然可用: ffmpeg_libx264.bat / ffmpeg_hevc_qsv.bat / ffmpeg_copy_to_mp4.bat …"
rem ffmpeg_encode.bat - 统一压缩入口 (.bat 侧, TODO.md 阶段 1)
rem   用法: ffmpeg_encode.bat --venc <编码器> [--dec <解码器>] 视频文件
rem   也可以把视频文件直接拖到本 bat 上(位置参数走 PARSE_POS)
rem
rem --venc 取值与 ffmpeg_dvd_hevc.bat 的 VENC 同义(avc_* 是 h264_* 的别名), 但**不含
rem   VAAPI** —— 那是 Linux 内核 API, Windows 侧没有对应入口。
rem --dec  取值 auto | cpu(=none) | none | qsv | cuda, 可省 —— 省了用编码器族的固定解码;
rem   与族不一致时只警告不拦(混合硬解有人用), 但会说明 10bit 降位滤镜不跟过来。
rem
rem 公共流程(banner / ffmpeg 定位 / 源探测 / 码率查表 / 命令拼装 / 输出路径)全在
rem lib\encode_core.bat 里; 编码器之间的差异压成 ENC_TABLE / ENC_ARGS 两张表与
rem DEC / GATE 两个钩子。本文件只留三样搬不走的东西: cp65001 守卫 +
rem :HWACCEL_FALLBACK(上面)、执行段与失败守卫(下面)、以及自己的 usage 文案。
rem ------------------------------------------------------------
rem ---------- 校验 --venc ----------
rem parse_switches 只认键名不认语义, 取值是否合法由本脚本自己判。
rem 这里**不做**别名归一: 内核的表(ENC_TABLE / ENC_ARGS)以 avc_* 为主键,
rem enc_ffenc 那一层"键 -> ffmpeg 编码器名"的翻译只在核心里做。
if not defined VENC (
    echo [错误] 要指定编码器: --venc 编码器
    call "%SELF_DIR%lib\encode_core.bat" enc_known
    exit /b 1
)
set "ENC=%VENC%"
set "ENC_OK="
if /I "%ENC%"=="libx264" set "ENC_OK=1"
if /I "%ENC%"=="libx265" set "ENC_OK=1"
if /I "%ENC%"=="libsvtav1" set "ENC_OK=1"
if /I "%ENC%"=="avc_qsv" set "ENC_OK=1"
if /I "%ENC%"=="hevc_qsv" set "ENC_OK=1"
if /I "%ENC%"=="av1_qsv" set "ENC_OK=1"
if /I "%ENC%"=="avc_nvenc" set "ENC_OK=1"
if /I "%ENC%"=="hevc_nvenc" set "ENC_OK=1"
if /I "%ENC%"=="av1_nvenc" set "ENC_OK=1"
if /I "%ENC%"=="copy" set "ENC_OK=1"
if not defined ENC_OK (
    echo [错误] 不认识的编码器: %ENC%
    call "%SELF_DIR%lib\encode_core.bat" enc_known
    exit /b 1
)
rem copy 不解码也不重编码, 给了 --dec 就说清楚, 而不是默默忽略
if /I "%ENC%"=="copy" if defined DEC echo 注意: --venc copy 是转封装, 不解码也不重编码, --dec 对它无效(已忽略)。

rem ---------- 公共流程 ----------
if /I "%ENC%"=="copy" call "%SELF_DIR%lib\encode_core.bat" copy_run
if /I not "%ENC%"=="copy" call "%SELF_DIR%lib\encode_core.bat" enc_build %ENC%
set "FB_RC=%ERRORLEVEL%"
rem 找不到 ffmpeg 时内核只置 FB_NO_PATH(goto 不能跨文件), 由这里跳过去 —— 那边的
rem 提示与 pause 是入口的交互, 不该搬进内核。
if defined FB_NO_PATH goto NO_PATH_ERR
rem 其余退出码(2 码率表未命中 / 3 输入无视频流 / 4 硬件缺失 / 5 码率异常 / 6 产物已存在
rem 失败 / 1 转码失败)原样传回, 契约见 test\README.md 5.2。
if not "%FB_RC%"=="0" exit /b %FB_RC%
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
