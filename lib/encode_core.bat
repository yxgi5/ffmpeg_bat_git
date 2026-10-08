@echo off
rem ============================================================
rem lib/encode_core.bat - 编码入口的公共内核 (TODO.md 阶段 0)
rem
rem 由 7 个编码入口共用: libx264 / libx265、avc_qsv / hevc_qsv / av1_qsv、
rem hevc_nvenc / av1_nvenc。抽这块之前它们是 7 份 ~300 行副本(彼此只差 65~85 行)。
rem
rem 本文件只做 "RUN_COM 拼装器", 结果留在共享环境里交回入口:
rem   call "%SELF_DIR%lib\encode_core.bat" enc_build <enc>
rem 入口自己留着三样搬不走的东西:
rem   1) cp65001 重入守卫 + :HWACCEL_FALLBACK —— 守卫区必须纯 ASCII(L04), 那个标签
rem      要被入口的执行段 call, 而 goto 不能跨文件;
rem   2) 执行段(auto 才拦 stderr 做 D3D 回退)与失败守卫 —— 与运行期语义绑在一起;
rem   3) 自己的 usage 文案与头部说明。
rem
rem 编码器之间的差异压成两��表 + 两个钩子:
rem   表  ENC_TABLE   编码器 -> 码率表 csv
rem   表  ENC_ARGS    编码器 -> -c:v:0 系列 + 音视频/字幕/封面/元数据段
rem   钩子 DEC_ARGS    解码/设备初始化(软编 / QSV / NVENC 三种拓扑)
rem   钩子 ENC_GATE   硬件能力门(目前只有 av1_qsv, exit 4)
rem 另有 FF_HWACCEL 归一: 硬件入口的 -hwaccel 由编码器族写死, 用户设的值一律归空
rem (与 ffmpeg_libx264.sh 的 enc_dec_args 同口径)。
rem
rem 依赖 lib\common.bat 提供的: parse_switches 的产物 PARSE_POS / init_ext /
rem EXT / SENC / find_ffmpeg / probe_source / lookup_bitrate / bitrate_from_table /
rem extract / on_exist / cover_map / src_hw_decode_hostile / src_is_10bit /
rem qsv_encoder_ready / dry_run。
rem 本文件不 setlocal —— call 跨文件共享环境, 内核 set 的变量要对调用方可见
rem (与 lib\common.bat 同一约定)。注意: 本文件必须保持 CRLF 行尾。
rem ============================================================

if "%~1"=="" exit /b 1
if /I "%~1"=="enc_build" goto enc_build
echo 未知函数: %~1
exit /b 1

:enc_build
set "ENC=%~2"
set "FB_NO_PATH="
if "%ENC%"=="" (
    echo enc_build: 缺编码器参数
    exit /b 1
)
echo ============================================================
echo 欢迎使用ffmpeg视频压缩批处理工具
echo 您有两种使用方式:
echo 1) 直接将待压缩的视频拖放到批处理上
echo 2) 在下面输入待压缩视频地址
echo.
echo 由 andreas 编写
echo ============================================================

call "%~dp0common.bat" find_ffmpeg FF_BIN
rem goto 不能跨文件, 所以这里只置标志, 由入口跳 NO_PATH_ERR(提示与 pause 在那边)
if errorlevel 1 set "FB_NO_PATH=1"
if defined FB_NO_PATH exit /b 1
set "FFMPEG_PATH=%FF_BIN%\ffmpeg.exe"
rem ---------- 输出容器开关 EXT: mp4(默认) / mkv ----------
rem 默认值写在 lib\defaults.cfg(两族共用一份), 校验 / 去空格 / -c:s 的选法统统在
rem lib\common.bat 的 :init_ext 里 —— 加容器、改默认都只动那一处, 入口不再各写一遍。
rem 命令行 set EXT=mkv 优先于配置文件(:load_defaults 只补没设过的键)。
call "%~dp0common.bat" init_ext
if errorlevel 1 exit /b 1
echo 已找到ffmpeg于:%FFMPEG_PATH%
rem 解码加速器可配置: FF_HWACCEL=none(默认, 2026-10-05 改: 软编实时显示进度, 不再吞 stderr) / cuda /
rem qsv / vaapi / d3d11va / dxva2 / none。原先写死 -hwaccel auto —— 由 ffmpeg 挑第一个
rem 能初始化的(核显与 N 卡并存时选谁不可控), 且锁屏/断开会话下 D3D 会直接崩; 上面
rem :HWACCEL_FALLBACK 的回退按 FF_HWACCEL 的实际值删参数, 显式指定时同样会回退一次。
rem 纯 N 卡机器可钉成 cuda; 想彻底不碰硬件设 none(一次 -hwaccel 都不加)。只影响解码,
rem 编码器仍是本入口的 libx264/libx265。
if not defined FF_HWACCEL set "FF_HWACCEL=none"
set "FF_HW_ARG= -hwaccel %FF_HWACCEL%"
if /i "%FF_HWACCEL%"=="none" set "FF_HW_ARG="
rem FF_HWACCEL 归一: 硬件入口(QSV/NVENC)的 -hwaccel 由编码器族写死,
rem 用户设的值一律清空 —— 与 ffmpeg_libx264.sh 的 enc_dec_args 同口径
rem (--ff_hwaccel 对硬件入口无效, 入口 --help 里也这么写)。归一后执行段的
rem auto 分支永不命中, RUN_COM 里一个 hwaccel 参数都不多。
if not "%ENC%"=="libx264" if not "%ENC%"=="libx265" (
    set "FF_HWACCEL=none"
    set "FF_HW_ARG="
)
set RUN_COM="%FFMPEG_PATH%" -hide_banner -threads 0
if /I "%ENC%"=="libx264" set RUN_COM=%RUN_COM% -v verbose%FF_HW_ARG%
if /I "%ENC%"=="libx265" set RUN_COM=%RUN_COM% -v verbose%FF_HW_ARG%
if /I "%ENC%"=="avc_qsv" set RUN_COM=%RUN_COM%%FF_HW_ARG% -init_hw_device qsv=hw -filter_hw_device hw
if /I "%ENC%"=="hevc_qsv" set RUN_COM=%RUN_COM%%FF_HW_ARG% -init_hw_device qsv=hw -filter_hw_device hw
if /I "%ENC%"=="av1_qsv" set RUN_COM=%RUN_COM%%FF_HW_ARG% -init_hw_device qsv=hw -filter_hw_device hw
if /I "%ENC%"=="hevc_nvenc" set RUN_COM=%RUN_COM%%FF_HW_ARG% -hwaccel cuda -hwaccel_output_format cuda
if /I "%ENC%"=="av1_nvenc" set RUN_COM=%RUN_COM%%FF_HW_ARG% -hwaccel cuda -hwaccel_output_format cuda

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
call "%~dp0common.bat" check_isvideo %SRC_FILE%
if errorlevel 1 exit /b 3
rem 统一源探测: 一次 ffprobe 取回全部字段(同文件对 check_isvideo 的探测命中缓存);
rem 失败时传回 1, 与 .sh 侧探测失败报错对齐(2026-09-17 用户裁定修"假判据")。
call "%~dp0common.bat" probe_source %SRC_FILE%
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" exit /b 1
rem ---------- 硬件能力门(仅 av1_qsv): "编码器在 ffmpeg 里" != "硬件支持" ----------
rem UHD 770 实测: ffmpeg -encoders 里就有 av1_qsv, 一开却是
rem   [av1_qsv @ ...] Current codec type is unsupported
rem   some encoding parameters are not supported by the QSV runtime. rc=-40
rem 跑到底只能留下 0 字节产物, 比"明确说不支持"更糟。所以在动源文件之前拿 1 帧
rem lavfi 源先试一次; AV1 QSV 需要 Arrow Lake 或更新的核显。
if /I "%ENC%"=="av1_qsv" call "%~dp0common.bat" qsv_encoder_ready av1_qsv
if /I "%ENC%"=="av1_qsv" if "%QSV_ENC_OK%"=="1" goto AV1_ENC_READY
rem 刻意用两条独立 if 而不是 ( ) 块: 上面那句 echo 的参数里有半角小括号
rem (需 Arrow Lake 或更新的核显), 放进块里会提前闭块(与入口 usage 同一个坑)。
if /I "%ENC%"=="av1_qsv" echo 本机没有可用的 AV1 QSV 编码器(需 Arrow Lake 或更新的核显) —— 未生成产物
rem 退出码 4 = 硬件缺失(契约见 test\README.md 5.2), 与"这一个文件转失败"(1)分开:
rem   4 对清单里每一个文件都成立, convert_from_list_* 因此直接中止整份清单,
rem   而不是把同一堵墙再撞一遍; 1 只是当前文件的问题。
if /I "%ENC%"=="av1_qsv" exit /b 4
:AV1_ENC_READY
rem ---------- 解码拓扑: 软编可选 -hwaccel; QSV 要 -init_hw_device; NVENC 只用 cuda ----------
rem ---------- QSV 三入口: 10bit 源的两种症状, 两种修法 (2026-09-30 实测) ----------
rem ① H.264 High 10(profile 110): 卡在**解码**侧 —— QSV 的 H.264 解码器不吃 High 10,
rem    硬解一挂帧退回系统内存, 编码器要硬件表面 -> auto_scale 接不上 -> rc=1 / 0 字节。
rem    修法: 这种源不要 -hwaccel(它是输入选项, 必须排在 -i 之前), 改软解后 hwupload。
rem ② HEVC Main10 等: 硬解正常(帧已在 QSV 表面), 但 -profile main(8bit) 吃不下 10bit
rem    输入 -> 编码器报错 / 产物异常。修法: scale_qsv=format=nv12 在 QSV 硬件内降到
rem    8bit。不能用软滤镜 format=nv12(帧在硬件表面, auto_scale 照样接不上)。
rem 判据见 lib\common.bat 的 src_hw_decode_hostile / src_is_10bit。
rem -vf 是输出滤镜, 不能排在 -i 之前 —— 它的位置在下方编码器段的 %QSV_VF% 上。
if /I "%ENC%"=="avc_qsv" goto QSV_DEC
if /I "%ENC%"=="hevc_qsv" goto QSV_DEC
if /I "%ENC%"=="av1_qsv" goto QSV_DEC
goto AFTER_QSV
:QSV_DEC
call "%~dp0common.bat" src_hw_decode_hostile
set "QSV_HWDEC=1"
set "QSV_VF="
if "%HW_HOSTILE%"=="1" set "QSV_HWDEC=0"
if "%HW_HOSTILE%"=="1" echo H.264 High 10 source: QSV hwdec unsupported, use soft-dec + hwupload
if "%HW_HOSTILE%"=="1" set "QSV_VF= -vf format=nv12,hwupload=extra_hw_frames=64"
set "SRC_PIXFMT=%P_streams.stream.0.pix_fmt%"
if defined SRC_PIXFMT echo SRC_PIXFMT=%SRC_PIXFMT%
call "%~dp0common.bat" src_is_10bit
if "%HW_HOSTILE%"=="0" if "%SRC_IS10%"=="1" set "QSV_VF= -vf scale_qsv=format=nv12"
if "%HW_HOSTILE%"=="0" if "%SRC_IS10%"=="1" echo 10bit source: scale_qsv=format=nv12 (QSV hw 内降 8bit)
if "%QSV_HWDEC%"=="1" set RUN_COM=%RUN_COM% -hwaccel qsv -hwaccel_output_format qsv
:AFTER_QSV
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
call "%~dp0common.bat" is_pos_num "%SRC_BITRATE%" SRC_BITRATE_OK
rem 块内 %VAR% 为解析期展开: 变量在块内被重赋值后, 块内再引用会拿到旧值, 故拆到块外
if %SRC_BITRATE_OK% == 0 set "SRC_BITRATE=%P_streams.stream.0.bit_rate%"
call "%~dp0common.bat" is_pos_num "%SRC_BITRATE%" SRC_BITRATE_OK
call "%~dp0common.bat" is_pos_num "%P_format.duration%" SRC_DUR_OK
if %SRC_BITRATE_OK% == 0 if %SRC_DUR_OK% == 1 (
    call "%~dp0common.bat" calc_bitrate_fromsize %SRC_SIZE% %P_format.duration% SRC_BITRATE
)
call "%~dp0common.bat" is_pos_num "%SRC_BITRATE%" SRC_BITRATE_OK
if %SRC_BITRATE_OK% == 0 set "SRC_BITRATE=0"
echo SRC_BITRATE=%SRC_BITRATE%
rem 时长兜底: format.duration -> size*8/bitrate(需有效码率)
call "%~dp0common.bat" is_pos_num "%SRC_DURATION%" SRC_DUR_OK
if %SRC_DUR_OK% == 0 if %SRC_BITRATE_OK% == 1 (
    call "%~dp0common.bat" calc_duration_fromsize %SRC_SIZE% %SRC_BITRATE% SRC_DURATION
)
call "%~dp0common.bat" is_pos_num "%SRC_DURATION%" SRC_DUR_OK
if %SRC_DUR_OK% == 0 set "SRC_DURATION=0"
echo SRC_DURATION=%SRC_DURATION%
rem ---------- 码率查表: lib\bitrate_table_avc.csv (替代原 190 行 if-elif) ----------
set "BIT="
set "ENC_TABLE=bitrate_table_hevc.csv"
if /I "%ENC%"=="libx264" set "ENC_TABLE=bitrate_table_avc.csv"
if /I "%ENC%"=="avc_qsv" set "ENC_TABLE=bitrate_table_avc.csv"
if /I "%ENC%"=="av1_qsv" set "ENC_TABLE=bitrate_table_av1.csv"
if /I "%ENC%"=="av1_nvenc" set "ENC_TABLE=bitrate_table_av1.csv"
call "%~dp0common.bat" lookup_bitrate %SRC_PIX% BIT %ENC_TABLE%
if not defined BIT (
    echo SRC_PIX=%SRC_PIX% 超出码率表范围, Manual handle it
    exit /b 2
)
call "%~dp0common.bat" bitrate_from_table BIT
if errorlevel 1 exit /b 1
set TARGET_BITRATE=%BIT%
echo TARGET_BITRATE=%TARGET_BITRATE%
set "percentage=0"
if %SRC_BITRATE% gtr 0 (
    set /a percentage=(%TARGET_BITRATE%*100^)/%SRC_BITRATE%
    call "%~dp0common.bat" numOK "%TARGET_BITRATE%" %SRC_BITRATE% percentage
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
call "%~dp0common.bat" cover_map
rem EXT=mkv 时字幕默认原样复制(-c:s copy): mkv 装得下位图字幕, 比 mp4 少丢东西。
rem 唯一例外是源里带 mov_text —— mp4 的软字幕格式, matroska 装不下, 实测
rem -c:s copy 在这里直接 rc=-40 / 0 字节 —— 所以这种源把文本字幕转成 ass。
rem CM_MOV 由上面的封面闸门顺路数出来, 没有额外起 ffprobe。
if "%EXT%"=="mkv" if "%CM_MOV%"=="1" set "SENC=-c:s ass"
set "ENC_ARGS=-c:v:0 libx264 -profile:v:0 high -preset fast -b:v %BIT% -pix_fmt yuv420p -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
if /I "%ENC%"=="libx265" set "ENC_ARGS=-c:v:0 libx265 -profile:v:0 main -preset fast -b:v %BIT% -pix_fmt nv12 -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -g 250 -keyint_min 25 -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
if /I "%ENC%"=="avc_qsv" set "ENC_ARGS=-c:v:0 h264_qsv -profile:v:0 main -preset veryfast -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
if /I "%ENC%"=="hevc_qsv" set "ENC_ARGS=-c:v:0 hevc_qsv -profile:v:0 main -preset veryfast -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
if /I "%ENC%"=="av1_qsv" set "ENC_ARGS=-c:v:0 av1_qsv -profile:v:0 main -preset fast -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
if /I "%ENC%"=="hevc_nvenc" set "ENC_ARGS=-c:v:0 hevc_nvenc -profile:v:0 main -preset p4 -tune:v hq -rc cbr -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
rem av1_nvenc 不接受 -profile:v:0(实测报未知参数), 所以这行比 hevc_nvenc 少一段
if /I "%ENC%"=="av1_nvenc" set "ENC_ARGS=-c:v:0 av1_nvenc -preset p4 -tune:v hq -rc cbr -b:v %BIT% -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map 0:V -map 0:a? -map 0:s? %COVERMAP% %SENC% -map_metadata 0 -map_chapters 0 -rtbufsize 120m -max_muxing_queue_size 1024"
if defined BIT set RUN_COM=%RUN_COM%%QSV_VF% %ENC_ARGS%
echo RUN_COM2:%RUN_COM%

echo.
echo SRC_FILE:%SRC_FILE%
if defined SRC_FILE call "%~dp0common.bat" extract %SRC_FILE% TARGET_PATH TARGET_NAME %EXT%
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
if defined PARSE_POS call "%~dp0common.bat" on_exist %TARGET_FILE%
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

exit /b 0
