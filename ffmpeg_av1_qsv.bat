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

:main

rem ============================================================
rem 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.bat 的 :parse_switches)
rem   优先级 参数 > 环境变量 > defaults.cfg; 没给的回退 env / cfg(老 set 写法仍兼容)
rem   位置参数(文件名)记在 PARSE_POS, 下面取它取代 %~1
call "%SELF_DIR%lib\common.bat" parse_switches %*
if errorlevel 2 exit /b 2

rem ffmpeg_av1_qsv.bat - AV1 QSV 硬件加速压缩 (P1 重构版)
rem AV1 QSV 硬编只有 Arrow Lake 及更新的 Intel 核显才支持(Meteor/Arrow/Lunar Lake),
rem 且要求较新的 ffmpeg 构建; find_ffmpeg 找到的 ffmpeg 若未编入 av1_qsv,
rem 会直接报 "Unknown encoder"。编码参数与 ffmpeg_av1_qsv.sh 对齐(preset fast)。
rem 用法: 拖放视频文件到本 bat 上, 或双击后输入视频地址
rem 码率查表: lib\bitrate_table_av1.csv | 公共函数: lib\common.bat
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

echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo 您有两种使用方式:
echo 1) 直接将待压缩的视频拖放到批处理上
echo 2) 在下面输入待压缩视频地址
echo.
echo 由 andreas 编写
echo ============================================================

call "%SELF_DIR%lib\common.bat" find_ffmpeg FF_BIN
if errorlevel 1 goto NO_PATH_ERR
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
set "FFPROBE_PATH=%FF_BIN%\ffprobe.exe"
rem ---------- 输出容器开关 EXT: mp4(默认) / mkv ----------
rem 默认值写在 lib\defaults.cfg(两族共用一份), 校验 / 去空格 / -c:s 的选法统统在
rem lib\common.bat 的 :init_ext 里 —— 加容器、改默认都只动那一处, 入口不再各写一遍。
rem 命令行 set EXT=mkv 优先于配置文件(:load_defaults 只补没设过的键)。
call "%SELF_DIR%lib\common.bat" init_ext
if errorlevel 1 exit /b 1
echo 已找到ffmpeg于:%FFMPEG_PATH%
set RUN_COM="%FFMPEG_PATH%" -hide_banner -threads 0 -init_hw_device qsv=hw -filter_hw_device hw

SET "SRC_FILE="

if defined PARSE_POS (
    set "SRC_FILE=%PARSE_POS%"
)

if not defined SRC_FILE (
    SET /P SRC_FILE=请输入待压缩视频地址:
)

IF not defined SRC_FILE (
    echo 没有输入文件
    exit /b 1
)

set SRC_FILE="%SRC_FILE:"=%"

echo SRC_FILE:%SRC_FILE%

rem 输入必须含视频流: 无视频流的输入产不出有意义的成品, 提前拒绝(与 .sh 的 check_file_isvideo 对齐)
call "%SELF_DIR%lib\common.bat" check_isvideo %SRC_FILE%
if errorlevel 1 exit /b 3
rem 统一源探测: 一次 ffprobe 取回全部字段(同文件对 check_isvideo 的探测命中缓存);
rem 失败时传回 1, 与 .sh 侧探测失败报错对齐(2026-09-17 用户裁定修"假判据")。
call "%SELF_DIR%lib\common.bat" probe_source %SRC_FILE%
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" exit /b 1
rem ---------- 硬件能力门: "编码器在 ffmpeg 里" != "硬件支持" ----------
rem UHD 770 实测: ffmpeg -encoders 里就有 av1_qsv, 一开却是
rem   [av1_qsv @ ...] Current codec type is unsupported
rem   some encoding parameters are not supported by the QSV runtime.
rem   Error while opening encoder ... rc=-40
rem 跑到底只能留下 0 字节产物, 比"明确说不支持"更糟。所以在动源文件之前拿
rem 1 帧 lavfi 源先试一次; AV1 QSV 需要 Arrow Lake 或更新的核显。
call "%SELF_DIR%lib\common.bat" qsv_encoder_ready av1_qsv
if "%QSV_ENC_OK%"=="1" goto AV1_ENC_READY
echo 本机没有可用的 AV1 QSV 编码器(需 Arrow Lake 或更新的核显) —— 未生成产物
rem 退出码 4 = 硬件缺失(契约见 test\README.md 5.2), 与"这一个文件转失败"(1)分开:
rem   4 对清单里每一个文件都成立, convert_from_list_* 因此直接中止整份清单,
rem   而不是把同一堵墙再撞一遍; 1 只是当前文件的问题。
exit /b 4
:AV1_ENC_READY

rem ---------- H.264 High 10 源: QSV 硬解不吃 profile 110 ----------
rem 硬解挂掉后 10bit 帧退回系统内存, 编码器要硬件表面 -> auto_scale 接不上 ->
rem rc=1 / 0 字节。这种源不要 -hwaccel(输入选项, 排在 -i 之前), 改软解 + hwupload。
call "%SELF_DIR%lib\common.bat" src_hw_decode_hostile
set "QSV_HWDEC=1"
set "QSV_VF="
if "%HW_HOSTILE%"=="1" set "QSV_HWDEC=0"
if "%HW_HOSTILE%"=="1" echo H.264 High 10 source: QSV hwdec unsupported, use soft-dec + hwupload
if "%HW_HOSTILE%"=="1" set "QSV_VF= -vf format=nv12,hwupload=extra_hw_frames=64"
if "%QSV_HWDEC%"=="1" set RUN_COM=%RUN_COM% -hwaccel qsv -hwaccel_output_format qsv
set RUN_COM=%RUN_COM% -i %SRC_FILE%
echo RUN_COM0=%RUN_COM%

rem 源探测统一走 common.bat 的 probe_source: 一次 ffprobe 取回全部字段,
rem 结果在 P_* 变量里(值已剥引号)。此前这里要起 6 个 ffprobe 进程、每个
rem 配一次临时文件写入+del, 是冒烟套件墙钟的主要成分(见 test/README 6.5 节)。
rem 字段缺失(无视频流等)时 P_ 变量未定义、展开为空 —— 与原实现的空值路径一致。
set "SRC_CODEC=%P_streams.stream.0.codec_name%"
echo SRC_CODEC=%SRC_CODEC%

set "SRC_FRAMERATE=%P_streams.stream.0.r_frame_rate%"
echo SRC_FRAMERATE=%SRC_FRAMERATE%
set /a SRC_FRAMERATE=%SRC_FRAMERATE%

if %SRC_FRAMERATE% gtr 31 (
    set RUN_COM=%RUN_COM% -r 30
    echo TURN DOWN TARGET FRAME RATE TO 30
)

rem 宽高直接读 P_*, 省掉原 resolution 段的 EnableDelayedExpansion 块:
rem 那个块里 %VAR% 展开要再过一遍延迟扫描, 片名带感叹号时会丢字符; 现在整段无路径, 无此风险
set "SRC_W=%P_streams.stream.0.width%"
set "SRC_H=%P_streams.stream.0.height%"
echo SRC_W=%SRC_W%
echo SRC_H=%SRC_H%
set /a SRC_PIX=%SRC_W%*%SRC_H%
echo SRC_PIX=%SRC_PIX%

set "SRC_SIZE=%P_format.size%"
if not defined SRC_SIZE set "SRC_SIZE=0"
if %SRC_SIZE% leq 0 (
   for %%A in (%SRC_FILE%) do set SRC_SIZE=%%~zA
)
echo SRC_SIZE=%SRC_SIZE%

set "SRC_DURATION=%P_format.duration%"
echo SRC_DURATION=%SRC_DURATION%

rem 码率兜底: format.bit_rate -> stream.bit_rate -> size/duration(需有效时长)
set "SRC_BITRATE=%P_format.bit_rate%"
call "%SELF_DIR%lib\common.bat" is_pos_num "%SRC_BITRATE%" SRC_BITRATE_OK
rem 块内 %VAR% 为解析期展开: 变量在块内被重赋值后, 块内再引用会拿到旧值, 故拆到块外
if %SRC_BITRATE_OK% == 0 set "SRC_BITRATE=%P_streams.stream.0.bit_rate%"
call "%SELF_DIR%lib\common.bat" is_pos_num "%SRC_BITRATE%" SRC_BITRATE_OK
call "%SELF_DIR%lib\common.bat" is_pos_num "%P_format.duration%" SRC_DUR_OK
if %SRC_BITRATE_OK% == 0 if %SRC_DUR_OK% == 1 (
    call "%SELF_DIR%lib\common.bat" calc_bitrate_fromsize %SRC_SIZE% %P_format.duration% SRC_BITRATE
)
call "%SELF_DIR%lib\common.bat" is_pos_num "%SRC_BITRATE%" SRC_BITRATE_OK
if %SRC_BITRATE_OK% == 0 set "SRC_BITRATE=0"
echo SRC_BITRATE=%SRC_BITRATE%

rem 时长兜底: format.duration -> size*8/bitrate(需有效码率)
call "%SELF_DIR%lib\common.bat" is_pos_num "%SRC_DURATION%" SRC_DUR_OK
if %SRC_DUR_OK% == 0 if %SRC_BITRATE_OK% == 1 (
    call "%SELF_DIR%lib\common.bat" calc_duration_fromsize %SRC_SIZE% %SRC_BITRATE% SRC_DURATION
)
call "%SELF_DIR%lib\common.bat" is_pos_num "%SRC_DURATION%" SRC_DUR_OK
if %SRC_DUR_OK% == 0 set "SRC_DURATION=0"
echo SRC_DURATION=%SRC_DURATION%

rem ---------- 码率查表: lib\bitrate_table_av1.csv (替代原 190 行 if-elif) ----------
set "BIT="
call "%SELF_DIR%lib\common.bat" lookup_bitrate %SRC_PIX% BIT bitrate_table_av1.csv
if not defined BIT (
    echo SRC_PIX=%SRC_PIX% 超出码率表范围, Manual handle it
    exit /b 2
)
call "%SELF_DIR%lib\common.bat" bitrate_from_table BIT
if errorlevel 1 exit /b 1
set TARGET_BITRATE=%BIT%
echo TARGET_BITRATE=%TARGET_BITRATE%
set "percentage=0"
if %SRC_BITRATE% gtr 0 (
    set /a percentage=(%TARGET_BITRATE%*100^)/%SRC_BITRATE%
    call "%SELF_DIR%lib\common.bat" numOK "%TARGET_BITRATE%" %SRC_BITRATE% percentage
)
echo percentage=%percentage%%%

rem 下面两个判定不限于交互模式: arg(拖放/命令行)模式同样生效, 与 .sh 保持一致
rem (原写法多了 if "%~1"=="" 前置, 使低码率源在 arg 模式下被重编码放大)
if %SRC_BITRATE% gtr 0 (
    if %percentage% geq 100 (
        set BIT=%SRC_BITRATE%
        rem keep the summary honest: TARGET_BITRATE must report the bitrate
        rem actually encoded at, not the stale table value (T17 asserts on it)
        set TARGET_BITRATE=%SRC_BITRATE%
    )
)

if %TARGET_BITRATE% leq 0 (
   echo bitrate abnormal, please check
   exit /b 5
)

IF not defined PARSE_POS SET /P BIT=请输入输出码率(如1150k,不输入则保持默认):
echo TARGET_BITRATE=%BIT%
rem ---------- 封面保留能力门: 见 lib\common.bat 的 :cover_map ----------
call "%SELF_DIR%lib\common.bat" cover_map
rem EXT=mkv 时字幕默认原样复制(-c:s copy): mkv 装得下位图字幕, 比 mp4 少丢东西。
rem 唯一例外是源里带 mov_text —— mp4 的软字幕格式, matroska 装不下, 实测
rem -c:s copy 在这里直接 rc=-40 / 0 字节 —— 所以这种源把文本字幕转成 ass。
rem CM_MOV 由上面的封面闸门顺路数出来, 没有额外起 ffprobe。
if "%EXT%"=="mkv" if "%CM_MOV%"=="1" set "SENC=-c:s ass"
if defined BIT set RUN_COM=%RUN_COM%%QSV_VF% -c:v:0 av1_qsv -profile:v:0 main -preset fast -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024
echo RUN_COM2:%RUN_COM%

echo.
echo SRC_FILE:%SRC_FILE%
if defined SRC_FILE call "%SELF_DIR%lib\common.bat" extract %SRC_FILE% TARGET_PATH TARGET_NAME %EXT%
set TARGET_FILE="%TARGET_PATH:"=%%TARGET_NAME:"=%"
echo TARGET_FILE:%TARGET_FILE%

IF not defined PARSE_POS SET /P TARGET_FILE=请输入输出文件(如output.mp4,不输入则输出到相同文件夹并加后缀):
if not defined TARGET_FILE set "TARGET_FILE=output.mp4"
rem 统一给输出路径补引号: 用户手输的可能不带引号, 而不带引号的路径
rem 一旦含 空格/&/( ) 就会被 RUN_COM 的展开拆开
if defined TARGET_FILE set TARGET_FILE="%TARGET_FILE:"=%"
echo SRC_FILE=%SRC_FILE%
echo TARGET_FILE=%TARGET_FILE%

echo RUN_COM3:%RUN_COM%
rem handler name with ) (   call set
rem ---- 产物已存在时的策略: 见 lib\common.bat 的 :on_exist ----
if defined PARSE_POS call "%SELF_DIR%lib\common.bat" on_exist %TARGET_FILE%
if defined FF_EXIST_FAIL exit /b 6
if defined FF_EXIST_SKIP exit /b 0
IF not defined PARSE_POS (
    echo executing 1
    set RUN_COM=%RUN_COM% %TARGET_FILE%
) else (
    echo executing 2
    set RUN_COM=%RUN_COM% %FF_OUT_FLAG% %TARGET_FILE%
)

echo RUN_COM4:%RUN_COM%
echo.
%RUN_COM%
rem 负退出码陷阱 (2026-09-17 实测根因): Windows 版 ffmpeg 失败时常常
rem 返回「负」的 AVERROR 值 —— 本机 av1_qsv 拿不到编码器时 ffmpeg.exe
rem 退出码是 -40 (Function not implemented), 而 cmd 的 `if errorlevel N`
rem 是「带符号」比较, -40 >= 1 不成立 → 守卫不会触发,
rem 真失败一路落到文件末尾的 exit /b 0 (探针因此报 rc=0 假 OK).
rem 改成「不等于 0」判定: 它同时兜住负数与正数, 且赋值到变量后
rem 走字符串相等比较, 不依赖 cmd 对负数的数值解析;
rem 值空时也会判成失败(安全侧), 而 if errorlevel 写法在值为空时
rem 只会报语法错误并继续往下跑.
set "FB_RC=%ERRORLEVEL%"
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
echo 或设置环境变量 FFMPEG_BIN 指向其 bin 目录后重试
pause
exit /b 1
