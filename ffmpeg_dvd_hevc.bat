@echo off
rem =========================================================================
rem cp65001 relaunch guard (ASCII only - do NOT add non-ASCII here)
rem cmd.exe reads a .bat with the codepage of the process that reads it;
rem an in-file chcp can misalign that reader, and the split line fragment
rem is then executed as a command (garbled banner line). So: switch the
rem console to UTF-8 and restart ourselves in a FRESH cmd process, which
rem reads this whole file from byte 0 under UTF-8.
rem Do NOT use a marker ARGUMENT + SHIFT here: SHIFT overwrites %0 as well
rem (documented), so every path derived from the script directory would
rem resolve against the marker instead of this script. An environment
rem variable keeps %0 and all arguments untouched.
rem SETLOCAL first: the marker must stay inside THIS invocation. Without it
rem the marker leaks into the CALLER environment, so a caller that uses
rem CALL, or a second run in the same cmd session, skips the guard.
setlocal
set "SELF_DIR=%~dp0"
if defined FB_UTF8_GUARD goto main
set "FB_UTF8_GUARD=1"
chcp 65001 >nul
cmd /c call "%~f0" %*
exit /b %errorlevel%

:main

rem =========================================================================
rem  ffmpeg_dvd_hevc.bat  -  DVD-Video(ISO / VIDEO_TS 目录 / 光驱) -> HEVC
rem
rem  用法:
rem    ffmpeg_dvd_hevc.bat <源> [输出目录] [title号]
rem      源       ISO 镜像、含 VIDEO_TS 的目录、或光驱盘符(如 E:)
rem      输出目录 默认 <源所在目录>\HEVC_OUT
rem      title号  给了这个就切到 MODE=TITLE 只处理这一条
rem
rem  为什么不能直接拿 ffmpeg_hevc_nvenc.bat 用:
rem    1) 它用 -i 直接喂文件, ffmpeg 不认 UDF 镜像/IFO。裸 -i 喂 ISO **不会报错**,
rem       而是把镜像当 MPEG-PS 糊乱解开, 实测得到 ~130s / 110504 帧的废品
rem       (正片其实是 55 分钟)。必须走 -f dvdvideo
rem    2) 它的 -c:s mov_text 遇到 DVD 位图字幕会直接报
rem       "Subtitle encoding currently only possible from text to text or bitmap
rem        to bitmap" 然后失败
rem    3) 就算把 mov_text 换成 copy, mov(mp4) 封装也会静默丢掉第 2 条字幕轨
rem       (实测: 300s 片段 -> mkv 保留 2 条, mp4 只剩 1 条)
rem    4) 它不做 IVTC: DVD 里大量内容是 3:2 pulldown 的 23.976p, 按 29.97 编码
rem       白扔 20% 码率还留梳状波纹
rem
rem  本脚本相对现有脚本新增的三件事:
rem    A. -f dvdvideo 直接读整张镜像 / VIDEO_TS 目录 / 光驱, 不用先解 VOB
rem    B. 默认按源制式选滤镜(FILT=AUTO): NTSC 29.97i -> IVTC 到 23.976p,
rem      PAL 25i -> BWDIF 去交错保留 25p(PAL 硬套 IVTC 会掉到 20fps, 实测踩过);
rem      要手动指定就 FILT=IVTC / BWDIF / NONE
rem    C. 默认 MKV + AC3 remux + 位图字幕无损保留全部轨
rem
rem  通用化设计(刻意不改的两件事):
rem    * 不动 SAR, 不裁边。DVD 的宽高比要同时看 IFO 与 MPEG-2 序列头, 同一张盘
rem      两者都可能不一致, 没有放之四海皆准的写法 —— 交给 ffmpeg 从容器里带来
rem      的原始 SAR 透传最稳。确实要修就填 VFILT_EXTRA(追加到滤镜链末尾):
rem         set VFILT_EXTRA=setsar=32:27
rem         set VFILT_EXTRA=crop=704:480:8:0,setsar=40:33
rem    * 不猜测该切哪一章。前編/後編的分界章号每张盘都不一样, 由调用方填
rem      SPLIT_CHAPTER; 默认 0 = 不切。
rem
rem  编码器(开关 VENC, 与 .sh 侧同名同义):
rem    空 / auto = 依次真跑探测 hevc_nvenc -> hevc_qsv -> libx265, 取第一个能编的
rem    显式     = ffmpeg 原生名(hevc_nvenc / hevc_qsv / h264_nvenc / h264_qsv /
rem               av1_nvenc / av1_qsv / libx265 / libx264 / libsvtav1), 探测通不过
rem               就报错退出并列出本机可用的, 不静默降级。名字用原生名, 不另起别名
rem               连字符写法(hevc-nvenc)也认; avc_nvenc / avc_qsv 翻成 h264_*。
rem
rem  码率仍复用仓库现有的 power-law 模型(三张表都 /2, 用哪张由编码器定):
rem    bitrate_table_hevc.csv / _avc.csv / _av1.csv + lib\common.bat 的 lookup_bitrate
rem    例: 720x480 = 345600 px -> 表值 1272042 -> 再 /2 = 636021 bit/s
rem  注意: VBITRATE 单位是 bit/s(裸数字), 与 ffmpeg_hevc_nvenc.bat 同口径;
rem        别写成 636k, 那会被当成 636 Mbps 把 NVENC 顶回去。
rem
rem  路径/命令行拼接规则「沿用第六轮实测结论, 勿改回 set 包装写法」:
rem    RUN_COM 里存的是整条已拼好的命令行(含自带引号的路径), 值里有字面量
rem    双引号, 因此必须用非包装的 set RUN_COM=... 形式。
rem
rem  注意: 本文件务必保持 UTF-8 编码 + CRLF 行尾
rem =========================================================================

rem ============================ 配置区 ============================
rem 源: 命令行第 1 参；没给就交互问一次
set "SRC=%~1"
if not defined SRC set /p "SRC=请输入 DVD 源(ISO / VIDEO_TS 目录 / 光驱盘符): "
if not defined SRC (
    echo [错误] 没给源
    exit /b 1
)

rem 输出目录: 命令行第 2 参；没给就用源所在目录下的 HEVC_OUT
set "OUTDIR=%~2"
if not defined OUTDIR set "OUTDIR=%~dp1HEVC_OUT"

rem 输出名前缀: 默认取源文件名(去扩展名)
rem 不覆盖调用方预设(与 .sh 侧 ${PREFIX:-...} 及 EXT/MODE/VENC 的守卫同口径)
if not defined PREFIX set "PREFIX=%~n1"
if not defined PREFIX set "PREFIX=dvd"

rem EXT=mkv  推荐: 能同时装 HEVC + 多条原生 AC3 + 多条 DVD 位图字幕
rem EXT=mp4  只能 HEVC + AAC + 1 条字幕，且 AC3 必须重编码
rem 同上: 不覆盖调用方预设的值(与 .sh 侧 ${EXT:-mkv} 同义)
if not defined EXT set EXT=mkv

rem AUTO(默认) 按源制式选: NTSC 29.97i -> IVTC 还原 23.976p; PAL 25i -> BWDIF 去交错
rem           保留 25p; 源已是 23.976p -> 不加滤镜。读不到帧率就按高度猜(576/288=PAL,
rem           480/240=NTSC)。PAL 盘没有 3:2 pulldown, 硬套 IVTC 会掉到 20fps(实测: 本机
rem           两张 720x576 PAL 盘跑 IVTC 出来 r_frame_rate=20/1, 白扔 20% 帧)
rem IVTC    3:2 pulldown -> 23.976p，NTSC 动画/电影 DVD 多数是这种
rem BWDIF   去交错但保留原帧率(PAL 25i -> 25p)。注意 bwdif=mode=1 是 send_field,
rem         帧率直接翻倍(实测 25i -> 50p), 帧数翻倍会把码率摊薄, 故这里用 mode=0
rem NONE    原样编码，不做去交错
if not defined FILT set FILT=AUTO

rem 追加到滤镜链末尾的可选处理（通用化：默认空，不改 SAR 也不裁边）
rem   例: setsar=32:27            16:9 变形宽银幕
rem       setsar=8:9              4:3
rem       crop=704:480:8:0,setsar=40:33   裁掉左右过扫边后再修 SAR
rem 不覆盖调用方预设(与 .sh 侧 ${VFILT_EXTRA:-} 同义)
if not defined VFILT_EXTRA set VFILT_EXTRA=

rem AUDIO=copy  MKV 下保留原始 AC3 / DTS / MP2，零重损失，最快。
rem             唯一例外: 源音轨是 LPCM(pcm_dvd) 时 Matroska 装不下(实测报
rem             "No wav codec tag found for codec pcm_dvd")，会自动转成 AAC
rem             按**每条 title 各自**探测: 一张盘的 title 1 与 title 2 音轨可以不同
rem AUDIO=aac   强制重编码成 AAC 192k(MP4 下强制用这个)
rem AUDIO=flac  强制重编码成 FLAC，无损，体积约为 LPCM 的一半
if not defined AUDIO set AUDIO=copy

rem MODE=ALL    每个 title 各出一个文件(默认)
rem MODE=AUTO   自动扫描所有 title，挑时长最长的那条当正片
rem MODE=TITLE  只处理 DVD_TITLE 指定的一条
rem 不覆盖调用方预设的值: setlocal 挡不住继承来的环境变量, 写成 set MODE=ALL 会把
rem "set MODE=AUTO && ffmpeg_dvd_hevc.bat ..." 里的 AUTO 悄悄冲掉
if not defined MODE set MODE=ALL
set "DVD_TITLE=%~3"
if defined DVD_TITLE set MODE=TITLE

rem SPLIT_CHAPTER=N  按第 N 章把正片切成两段(例如前編/後編)，0 = 不切
rem   第 1 段 = 第 1 章到第 N-1 章，第 2 段 = 第 N 章到结尾
rem   查章节点: ffprobe -f dvdvideo -preindex 1 -title 3 -show_chapters <源>
rem 不覆盖调用方预设(与 .sh 侧 ${SPLIT_CHAPTER:-0} 同义)
if not defined SPLIT_CHAPTER set SPLIT_CHAPTER=0

rem 额外要导出的 title 号，空格分隔；留空则跳过。例: set EXTRA_TITLES=1 4 5
rem 不覆盖调用方预设(与 .sh 侧 ${EXTRA_TITLES:-} 同义)
if not defined EXTRA_TITLES set EXTRA_TITLES=

rem 空 = 查表再 /2（推荐）；填数字则直接覆盖(bit/s)
rem   用哪张表由编码器定: hevc_* -> hevc 表, h264_* / libx264 -> avc 表,
rem   av1_* / libsvtav1 -> av1 表(三张表都 /2, 与仓库其余入口同口径)
rem 不覆盖调用方预设(与 .sh 侧 ${VBITRATE:-} 同义)
if not defined VBITRATE set VBITRATE=

rem VENC 空 / auto = 依次探测 hevc_nvenc -> hevc_qsv -> libx265, 用第一个真能编的
rem VENC 显式     = 直接填 ffmpeg 原生名: hevc_nvenc / hevc_qsv / h264_nvenc /
rem                 h264_qsv / av1_nvenc / av1_qsv / libx265 / libx264 / libsvtav1
rem                 (连字符写法 hevc-nvenc 也认; avc_nvenc / avc_qsv 会自动翻成
rem                  h264_nvenc / h264_qsv —— ffmpeg 里没有 avc_* 这个编码器名)
rem 显式指定的那个探测通不过 -> 报错退出并列出本机可用的，不静默降级
rem 同上: 不覆盖调用方预设的 VENC
if not defined VENC set "VENC=auto"
rem ==================================================================

rem ---------------------------- 找 ffmpeg ----------------------------
set "FF="
if exist "%SELF_DIR%lib\common.bat" call "%SELF_DIR%lib\common.bat" find_ffmpeg FF_BIN
if defined FF_BIN set "FF=%FF_BIN%\ffmpeg.exe"
if not defined FF if exist "C:\Program Files\ffmpeg\bin\ffmpeg.exe" set "FF=C:\Program Files\ffmpeg\bin\ffmpeg.exe"
if not defined FF for /f "delims=" %%A in ('where ffmpeg 2^>nul') do if not defined FF set "FF=%%A"
if not defined FF (
    echo [错误] 找不到 ffmpeg.exe
    exit /b 1
)
set FP=%FF:ffmpeg.exe=ffprobe.exe%
echo ffmpeg    : %FF%
echo 源        : "%SRC%"
rem 探针结果先落到 %WORK% 下的临时文件, 再用 for /f "usebackq" 回读。
rem **不要**把回读写成 set /p 配脱字符小于号: 脱字符会把小于号转成字面量参数,
rem set /p 随即退化成"从键盘读一行", 整个脚本静默卡住等人按键
rem (2026-09-22 用户报障: 打印完"源"就再无输出)。本仓库真机验证过的读法是
rem for /f "usebackq" 读文件, 见 lib\common.bat 的 probe_source / probe_field。
if not defined WORK set "WORK=%TEMP%"
if not defined WORK set "WORK=%SELF_DIR%"

rem dvdvideo 解复用器依赖 libdvdread/libdvdnav，精简构建没有
"%FF%" -hide_banner -demuxers 2>nul | findstr /i "dvdvideo" >nul
if errorlevel 1 (
    echo [错误] 这份 ffmpeg 没有 dvdvideo 解复用器
    echo        需要带 libdvdread + libdvdnav 的构建（gyan.dev full build 有）
    echo        实测命令: ffmpeg -demuxers ^| findstr /i dvdvideo
    exit /b 1
)

if not exist "%OUTDIR%" md "%OUTDIR%"

rem -------------------------- 选定要处理的 title --------------------------
if "%MODE%"=="TITLE" goto HAVE_TITLE
if "%MODE%"=="ALL" goto ALL_TIER

rem MODE=AUTO: 扫所有 title，挑时长最长的
rem 不能"读不到就收尾": DVD 的 title 编号**不连续**(本盘实测缺 title 2，
rem 一收尾就只看到 84s 的 title 1，而 55 分钟正片是 title 3)。
rem 改成连续缺失 5 次才收尾。
echo 正在扫描所有 title（逐条开镜像探测，请稍等；读不到的会自动跳过）...
rem BESTD 从 -1 起(与 .sh 侧对齐): 时长全读不出来(N/A -> 0)时也要能选中第一条,
rem 否则 0 gtr 0 恒假 -> DVD_TITLE 一直没定义 -> "一个 title 都没读到" 把整盘拦下
set BESTD=-1
set DVD_TITLE=
set MISS=0
set N=1
:AUTO_LOOP
call :PROBE %N% TW TH TD
if not defined TW goto AUTO_MISS
set MISS=0
for /f "tokens=1 delims=." %%A in ("%TD%") do set TDI=%%A
if not defined TDI set TDI=0
rem 时长读不到时 ffprobe 会给 "N/A" —— 非纯数字一律当 0, 否则下面
rem 的 if gtr 会因 "N/A was unexpected at this time." 当场打断批处理
for /f "delims=0123456789" %%B in ("%TDI%") do set TDI=0
if %TDI% gtr %BESTD% (
    set BESTD=%TDI%
    set DVD_TITLE=%N%
    set SRC_W=%TW%
    set SRC_H=%TH%
    set SRC_DUR=%TD%
)
echo   title %N%: %TW%x%TH%  %TDI%s
goto AUTO_NEXT
:AUTO_MISS
set /a MISS=%MISS%+1
if %MISS% geq 5 goto AUTO_DONE
:AUTO_NEXT
set /a N=%N%+1
if %N% gtr 99 goto AUTO_DONE
goto AUTO_LOOP
:AUTO_DONE
if %BESTD% lss 0 set BESTD=0
if not defined DVD_TITLE (
    echo [错误] 一个 title 都没读到，检查源路径 / 是否受 CSS 保护
    exit /b 1
)
echo 自动选定: title %DVD_TITLE%（共 %BESTD%s，最长）
goto HAVE_TITLE

:ALL_TIER
rem MODE=ALL: 同一张 DVD 上各 title 分辨率一致, 用 title 1 定码率档位即可。
rem 原实现直接 goto DO_ALL 会整段跳过码率计算, VBITRATE 为空 -> -b:v 是空值
rem -> 每个 title 都在 ffmpeg 处失败(2026-09-22 静态审查发现, 与 .sh 侧对齐)。
call :PROBE 1 SRC_W SRC_H SRC_DUR
if not defined SRC_W (
    echo [错误] 读不到 title 1，检查源路径 / 是否受 CSS 保护
    exit /b 1
)
goto HAVE_TITLE

:HAVE_TITLE
if not defined SRC_W call :PROBE %DVD_TITLE% SRC_W SRC_H SRC_DUR
if not defined SRC_W (
    echo [错误] 读不到 title %DVD_TITLE%，检查源路径 / 是否受 CSS 保护
    exit /b 1
)
echo 正片: title %DVD_TITLE%  %SRC_W%x%SRC_H%  时长 %SRC_DUR%s
set /a SRC_PIX=%SRC_W%*%SRC_H%
rem 制式 / 音轨探测用哪条 title: ALL 模式上面是用 title 1 定码率档位的, 其余模式是正片那条
if "%MODE%"=="ALL" (set REF_TITLE=1) else (set REF_TITLE=%DVD_TITLE%)
call :PROBE_RATE %REF_TITLE% SRC_RATE
call :PROBE_ACODEC %REF_TITLE% SRC_ACODEC

rem ---------------------------- 选编码器 ----------------------------
rem 探测一律「真跑一次小编码」，不看 ffmpeg -encoders 列表：本机三个 nvenc 都挂在
rem 列表里，真跑却在 cuInit 处失败(没 N 卡) —— 只看列表会把不可用判成可用。
rem 尺寸取 320x240：再小(128x128) NVENC 自己就拒绝初始化，反过来会把可用判成
rem 不可用(仓库 test/README.md 记过这个假 SKIP)。
set "VENC_NAME=%VENC%"
if not defined VENC_NAME set VENC_NAME=auto
set "VENC_NAME=%VENC_NAME:-=_%"
if /i "%VENC_NAME%"=="avc_nvenc" set VENC_NAME=h264_nvenc
if /i "%VENC_NAME%"=="avc_qsv" set VENC_NAME=h264_qsv
set "VCODEC="
if /i not "%VENC_NAME%"=="auto" goto VENC_FIXED
call :VENC_OK hevc_nvenc
if "%VRC%"=="0" set "VCODEC=hevc_nvenc"
if defined VCODEC goto VENC_PICKED
call :VENC_OK hevc_qsv
if "%VRC%"=="0" set "VCODEC=hevc_qsv"
if defined VCODEC goto VENC_PICKED
call :VENC_OK libx265
if "%VRC%"=="0" set "VCODEC=libx265"
if defined VCODEC goto VENC_PICKED
echo [错误] hevc_nvenc / hevc_qsv / libx265 三个候选本机都不可用
exit /b 1
:VENC_FIXED
rem 先认名字再探测：拼错的名字不至于被当成「本机不可用」这种误导性报错
call :VENC_BTAB %VENC_NAME%
if defined BTAB goto VENC_FIXED_OK
echo [错误] 不认识的编码器: %VENC_NAME%
echo        认这些: hevc_nvenc hevc_qsv h264_nvenc h264_qsv av1_nvenc av1_qsv libx265 libx264 libsvtav1
exit /b 1
:VENC_FIXED_OK
set "VCODEC=%VENC_NAME%"
call :VENC_OK %VCODEC%
if "%VRC%"=="0" goto VENC_PICKED
echo [错误] 指定的编码器 %VCODEC% 本机不可用，探测失败
echo        常见原因: 没装对应驱动 / 这份 ffmpeg 没编进该编码器 / 显卡不支持该格式
call :VENC_LIST
echo        本机实测可用: %AVAIL_LIST%
exit /b 1
:VENC_PICKED
call :VENC_BTAB %VCODEC%
echo 编码器  : %VCODEC%

rem ---------------------------- 算目标码率 ----------------------------
if defined VBITRATE goto HAVE_BIT
set "BIT="
if not exist "%SELF_DIR%lib\common.bat" (
    echo [错误] 找不到 lib\common.bat，查不了码率表。
    echo        要么把仓库放完整，要么手工给码率: set VBITRATE=636021
    exit /b 2
)
call "%SELF_DIR%lib\common.bat" lookup_bitrate %SRC_PIX% BIT bitrate_table_%BTAB%.csv
if not defined BIT (
    echo [错误] %SRC_PIX% 不在码率表范围内
    exit /b 2
)
set /a VBITRATE=%BIT% / 2
:HAVE_BIT
echo 目标视频码率: %VBITRATE% bit/s
rem -b:v 要等码率算完才能拼进来，所以参数在这里组装(模板见 :VENC_ARGS)
call :VENC_ARGS %VCODEC%
echo 编码参数: %VENC_ARGS%

rem ---------------------------- 组滤镜链 ----------------------------
set "FILT_IVTC=fieldmatch=mode=pc:combmatch=full,yadif=deint=interlaced,decimate"
set "FILT_BW=bwdif=mode=0"
set VFILT=
if "%FILT%"=="IVTC" set "VFILT=%FILT_IVTC%"
if "%FILT%"=="BWDIF" set "VFILT=%FILT_BW%"
if "%FILT%"=="AUTO" goto FILT_AUTO
goto FILT_JOIN
:FILT_AUTO
set FSYS=
if "%SRC_RATE%"=="30000/1001" set FSYS=NTSC29
if "%SRC_RATE%"=="30/1" set FSYS=NTSC29
if "%SRC_RATE%"=="60000/1001" set FSYS=NTSC29
if "%SRC_RATE%"=="24000/1001" set FSYS=NTSC23
if "%SRC_RATE%"=="24/1" set FSYS=NTSC23
if "%SRC_RATE%"=="25/1" set FSYS=PAL25
if "%SRC_RATE%"=="50/1" set FSYS=PAL25
if defined FSYS goto FILT_PICK
rem 读不到帧率就按高度猜: 576/288 = PAL, 480/240 = NTSC
if "%SRC_H%"=="576" set FSYS=PAL25
if "%SRC_H%"=="288" set FSYS=PAL25
if "%SRC_H%"=="480" set FSYS=NTSC29
if "%SRC_H%"=="240" set FSYS=NTSC29
:FILT_PICK
if "%FSYS%"=="NTSC29" set "VFILT=%FILT_IVTC%"
if "%FSYS%"=="PAL25" set "VFILT=%FILT_BW%"
if defined FSYS echo 源制式  : %FSYS% @ %SRC_RATE%
if not defined FSYS echo 源制式  : 读不到帧率也不认识高度，不加滤镜
:FILT_JOIN
if defined VFILT_EXTRA if defined VFILT set VFILT=%VFILT%,%VFILT_EXTRA%
if defined VFILT_EXTRA if not defined VFILT set VFILT=%VFILT_EXTRA%
set VFOPT=
if defined VFILT set VFOPT=-vf "%VFILT%"

rem ---------------------------- 容器相关选项 ----------------------------
rem 大小写不敏感, 并归一成小写: 输出文件后缀直接取 %EXT%, 不归一的话 set EXT=MP4 会
rem 产出 ".MP4"(与 .sh 侧 ${EXT,,} 同义)
if /i "%EXT%"=="mkv" set "EXT=mkv"
if /i "%EXT%"=="mp4" set "EXT=mp4"
if "%EXT%"=="mkv" goto CFG_MKV
if "%EXT%"=="mp4" goto CFG_MP4
echo [错误] EXT 只能是 mkv 或 mp4
exit /b 3

:CFG_MKV
rem 编码器参数(-c:v 的名字与 -b:v)由上面 :VENC_PICKED / :VENC_ARGS 组装
set AENC=-c:a copy
if "%AUDIO%"=="aac" set AENC=-c:a aac -b:a 192k
if "%AUDIO%"=="flac" set AENC=-c:a flac
if not "%AUDIO%"=="copy" goto CFG_MKV_DONE
if not defined SRC_ACODEC goto CFG_MKV_DONE
rem 含 pcm_dvd 就转: cmd 里没有 contains, 用"去掉子串后是否变短"来判断
if "%SRC_ACODEC:pcm_dvd=%"=="%SRC_ACODEC%" goto CFG_MKV_DONE
set AENC=-c:a aac -b:a 192k
echo 注意: 参考 title %REF_TITLE% 的音轨是 LPCM(pcm_dvd)，Matroska 装不下，自动转 AAC 192k（要无损就设 AUDIO=flac；ALL 模式下其余 title 逐条重新探测）
:CFG_MKV_DONE
rem AENC_BASE = 不含任何单条 title 音轨成分的基线 -c:a，每条 title 编码前据此重算
set "AENC_BASE=%AENC%"
set SENC=-c:s copy
set SMAP=-map 0:s?
goto RUN_ALL

:CFG_MP4
echo 注意: MP4 只能保留 1 条 DVD 位图字幕，其余会丢；要全留请用 EXT=mkv
rem 编码器参数(-c:v 的名字与 -b:v)由上面 :VENC_PICKED / :VENC_ARGS 组装
set AENC=-c:a aac -b:a 192k
set "AENC_BASE=%AENC%"
set SENC=-c:s dvdsub
set SMAP=-map 0:s:0?
goto RUN_ALL

:RUN_ALL
rem 一个 title 失败不立刻退出: 后面的分段/特典还要跑完, 但退出码必须真的传出去
set FAILED=
set /a TOTDUR=0
set /a N_TITLE=0
rem 体积估算的正确口径: MODE=ALL 下是"各 title 时长之和", 不是 title 1 的时长
rem (2026-10-01 实测: 3 title 的盘按 title 1 估成 5MB, 实际产出 845MB)
rem 本次真正写出的产物清单, 结尾据此统计"产物合计"。文件名**必须**带随机后缀:
rem 固定名 %WORK%\_outs.txt 落在全局临时目录, 会跨运行/跨进程互相踩 —— 2026-10-01
rem 实测: 本次合计里混进上一次运行的条目(H:\...\DVD081_title1.mkv), 而本次自己的
rem 两条又被另一个实例的 del 吞掉, 于是报 "4 个文件 466MB"(实为 5 个 267MB)。
if not defined OUTS set "OUTS=%WORK%\_outs_%RANDOM%%RANDOM%.txt"
del "%OUTS%" 2>nul
rem 不用 if(...)else(...) 包住 %VFILT%: 值里一旦出现 ASCII 右括号就会提前关块。
rem 先落进普通变量再 echo, 块外单行 if 不参与括号计数。
set "VF_SHOW=[无]"
if defined VFILT set "VF_SHOW=%VFILT%"
echo 滤镜链: %VF_SHOW%
echo.

if "%MODE%"=="ALL" goto DO_ALL

rem 切分用 goto 而不是 if(...) 块: 块内 %CE% 会在解析时就被展开, 拿不到刚算的值
rem 前缀一律用双引号包住: 源文件名可能含空格与小括号(实测那张盘叫
rem "[DVDISO](18禁アニメ) ...「過ちの夜 」+後編「確かめ合う気持ち」"), 不包的话
rem call :ENC 会按空格把它切成好几个参数, OUTN 与章节号全部错位。
if %SPLIT_CHAPTER% gtr 0 goto DO_SPLIT
call :ENC %DVD_TITLE% "%PREFIX%" 0 0
if errorlevel 1 set FAILED=1
goto AFTER_SPLIT
:DO_SPLIT
set /a CE=%SPLIT_CHAPTER%-1
call :ENC %DVD_TITLE% "%PREFIX%_part1" 1 %CE%
if errorlevel 1 set FAILED=1
call :ENC %DVD_TITLE% "%PREFIX%_part2" %SPLIT_CHAPTER% 0
if errorlevel 1 set FAILED=1
:AFTER_SPLIT
if defined EXTRA_TITLES for %%T in (%EXTRA_TITLES%) do call :ENC_EXTRA %%T "%PREFIX%_title%%T"
if errorlevel 1 set FAILED=1
goto DONE

:DO_ALL
set N=1
set MISS=0
:NEXT_TITLE
call :PROBE %N% TW TH TD
if not defined TW goto NEXT_MISS
set MISS=0
rem 攒该 title 的时长给结尾的体积估算(非数字如 N/A 按 0 处理, 否则 set /a 会报
rem Missing operator —— 与 :DONE 里对 SRC_DUR 的防护同款)
set "TDI=%TD%"
for /f "tokens=1 delims=." %%D in ("%TD%") do set "TDI=%%D"
for /f "delims=0123456789" %%E in ("%TDI%") do set "TDI=0"
set /a TOTDUR+=%TDI%
set /a N_TITLE+=1
call :ENC %N% "%PREFIX%_title%N%" 0 0
if errorlevel 1 set FAILED=1
goto NEXT_STEP
:NEXT_MISS
set /a MISS=%MISS%+1
if %MISS% geq 5 goto DONE
:NEXT_STEP
set /a N=%N%+1
if %N% gtr 99 goto DONE
goto NEXT_TITLE

rem =========================================================================
rem  子过程 ENC  title  outname  chapter_start  chapter_end
rem  注意: 这里刻意不用 -ss。dvdvideo 解复用器 seek 后时间轴不可靠，
rem        实测会让章节整体偏移，靠 -chapter_start/-chapter_end 才是准的。
rem =========================================================================
:ENC
set "T=%~1"
set "OUTN=%~2"
set "CS=%~3"
set "CE=%~4"
rem 逐 title 重算 -c:a: 拿 title 1 的音轨套所有 title 会漏掉 LPCM(见 :ENC_AENC)
call :ENC_AENC %T%
set "CHOP="
if not "%CS%"=="0" set CHOP=-chapter_start %CS%
if not "%CE%"=="0" set CHOP=%CHOP% -chapter_end %CE%
echo ------------------------------------------------------------
echo ^> title %T% ^-^> "%OUTN%.%EXT%"  %CHOP%
set RUN_COM="%FF%" -y -hide_banner -v error -stats -f dvdvideo -title %T% %CHOP% -i "%SRC%" -map 0:V -map 0:a? %SMAP% %VFOPT% -c:v %VCODEC% %VENC_ARGS% %AENC% %SENC% -map_chapters 0 -map_metadata 0 -rtbufsize 120m -max_muxing_queue_size 1024 "%OUTDIR%\%OUTN%.%EXT%"
echo RUN_COM:%RUN_COM%
%RUN_COM%
rem 负退出码陷阱: Windows ffmpeg 失败时返回负的 AVERROR 值, 而 cmd 的
rem `if errorlevel N` 是带符号比较, 负值 >= 1 不成立 -> 守卫不触发,
rem 真失败一路落到 exit /b 0。改成"不等于 0"的字符串比较兜住负数与正数。
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" (
    echo Convert failed! rc=%FB_RC%
    echo 常见原因: [1] -c:s 处理不了位图字幕  [2] MP4 下 AC3 没转成 AAC
    echo            [3] %VCODEC% 的参数不被接受 → 换 VENC=libx265 或 VENC=auto
    exit /b 1
)
>>"%OUTS%" echo "%OUTDIR%\%OUTN%.%EXT%"
exit /b 0

:ENC_EXTRA
set "T=%~1"
set "OUTN=%~2"
rem 同上: 附加 title 的音轨同样可能与正片不同
call :ENC_AENC %T%
echo ^> 附加 title %T% ^-^> "%OUTN%.%EXT%"
set RUN_COM="%FF%" -y -hide_banner -v error -stats -f dvdvideo -title %T% -i "%SRC%" -map 0:V -map 0:a? %VFOPT% -c:v %VCODEC% %VENC_ARGS% %AENC% "%OUTDIR%\%OUTN%.%EXT%"
%RUN_COM%
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" (
    echo Convert failed! rc=%FB_RC%
    exit /b 1
)
>>"%OUTS%" echo "%OUTDIR%\%OUTN%.%EXT%"
exit /b 0

rem =========================================================================
rem  子过程 ENC_AENC  <title>  ->  按该 title 的音轨重设全局 AENC
rem  为什么不能只探一次: ALL 会跑多条 title, 各条音轨可以不一样 —— 拿其中一条的
rem  探测结果套全部, 就会漏掉 LPCM。2026-10-01 实测 FRY001.ISO:
rem    title 1 = AC3(能 copy) / title 2 = LPCM, 于是 title 2 拿着 -c:a copy 去装
rem    pcm_dvd, ffmpeg 写头即失败 rc=-22: "No wav codec tag found for codec pcm_dvd"
rem  只对 AUDIO=copy + MKV 生效: 其余组合的 -c:a 与源音轨无关, 不用逐条重探。
rem =========================================================================
:ENC_AENC
set "AENC=%AENC_BASE%"
set "TAC="
call :PROBE_ACODEC %1 TAC
if not defined TAC exit /b 0
if not "%AUDIO%"=="copy" exit /b 0
if not "%EXT%"=="mkv" exit /b 0
rem 含 pcm_dvd 就转: cmd 里没有 contains, 用"去掉子串后是否变短"来判断
if "%TAC:pcm_dvd=%"=="%TAC%" exit /b 0
set AENC=-c:a aac -b:a 192k
echo   本条音轨是 LPCM(pcm_dvd) -^> 自动转 AAC 192k（要无损就设 AUDIO=flac）
exit /b 0

rem =========================================================================
rem  子过程 VENC_OK  <编码器>  ->  VRC=退出码(0 = 真能编)
rem  真跑一次 320x240 小编码。只看 ffmpeg -encoders 列表会踩「假可用」：本机三个
rem  nvenc 都列在表里，真跑却在 cuInit 处失败(没 N 卡)。320x240 是最小的安全尺寸，
rem  再小(128x128) NVENC 自己拒绝初始化，会把可用判成不可用。
rem =========================================================================
:VENC_OK
"%FF%" -hide_banner -v error -f lavfi -i testsrc2=s=320x240:r=25:d=1 -c:v %~1 -frames:v 2 -f null - >nul 2>&1
set "VRC=%ERRORLEVEL%"
exit /b 0

rem =========================================================================
rem  子过程 VENC_BTAB  <编码器>  ->  BTAB = hevc / avc / av1(不认识的名字给空)
rem =========================================================================
:VENC_BTAB
set "BTAB="
if /i "%~1"=="hevc_nvenc" set BTAB=hevc
if /i "%~1"=="hevc_qsv" set BTAB=hevc
if /i "%~1"=="libx265" set BTAB=hevc
if /i "%~1"=="h264_nvenc" set BTAB=avc
if /i "%~1"=="h264_qsv" set BTAB=avc
if /i "%~1"=="libx264" set BTAB=avc
if /i "%~1"=="av1_nvenc" set BTAB=av1
if /i "%~1"=="av1_qsv" set BTAB=av1
if /i "%~1"=="libsvtav1" set BTAB=av1
exit /b 0

rem =========================================================================
rem  子过程 VENC_ARGS  <编码器>  ->  VENC_ARGS(含 -b:v, 依赖已算好的 %VBITRATE%)
rem  口径照抄仓库里同名编码器的入口(ffmpeg_hevc_qsv.bat / ffmpeg_av1_qsv.bat ...)
rem =========================================================================
:VENC_ARGS
set "VENC_ARGS=-b:v %VBITRATE%"
if /i "%~1"=="hevc_nvenc" set "VENC_ARGS=-profile:v main -preset p4 -tune:v hq -rc cbr -b:v %VBITRATE%"
if /i "%~1"=="h264_nvenc" set "VENC_ARGS=-profile:v high -preset p4 -tune:v hq -rc cbr -b:v %VBITRATE%"
if /i "%~1"=="av1_nvenc" set "VENC_ARGS=-preset p4 -tune:v hq -rc cbr -b:v %VBITRATE%"
if /i "%~1"=="hevc_qsv" set "VENC_ARGS=-profile:v main -preset veryfast -b:v %VBITRATE%"
if /i "%~1"=="h264_qsv" set "VENC_ARGS=-profile:v main -preset veryfast -b:v %VBITRATE%"
if /i "%~1"=="av1_qsv" set "VENC_ARGS=-profile:v main -preset fast -b:v %VBITRATE%"
if /i "%~1"=="libx265" set "VENC_ARGS=-profile:v main -preset fast -b:v %VBITRATE%"
if /i "%~1"=="libx264" set "VENC_ARGS=-profile:v high -preset fast -b:v %VBITRATE%"
if /i "%~1"=="libsvtav1" set "VENC_ARGS=-preset 8 -b:v %VBITRATE%"
exit /b 0

rem =========================================================================
rem  子过程 VENC_LIST  ->  AVAIL_LIST(本机真能编的编码器, 空格分隔)
rem  只在"显式指定的编码器不可用"这条报错路径上跑, 平时不付这个代价
rem =========================================================================
:VENC_LIST
set "AVAIL_LIST="
call :VENC_OK hevc_nvenc
if "%VRC%"=="0" call :ADD_AVAIL hevc_nvenc
call :VENC_OK h264_nvenc
if "%VRC%"=="0" call :ADD_AVAIL h264_nvenc
call :VENC_OK av1_nvenc
if "%VRC%"=="0" call :ADD_AVAIL av1_nvenc
call :VENC_OK hevc_qsv
if "%VRC%"=="0" call :ADD_AVAIL hevc_qsv
call :VENC_OK h264_qsv
if "%VRC%"=="0" call :ADD_AVAIL h264_qsv
call :VENC_OK av1_qsv
if "%VRC%"=="0" call :ADD_AVAIL av1_qsv
call :VENC_OK libx265
if "%VRC%"=="0" call :ADD_AVAIL libx265
call :VENC_OK libx264
if "%VRC%"=="0" call :ADD_AVAIL libx264
call :VENC_OK libsvtav1
if "%VRC%"=="0" call :ADD_AVAIL libsvtav1
if not defined AVAIL_LIST set "AVAIL_LIST=一个都没有"
exit /b 0

:ADD_AVAIL
if defined AVAIL_LIST (set "AVAIL_LIST=%AVAIL_LIST% %~1") else (set "AVAIL_LIST=%~1")
exit /b 0

rem =========================================================================
rem  子过程 PROBE_RATE  title -> &2=视频流帧率(如 25/1 / 30000/1001), 读不到则空
rem  子过程 PROBE_ACODEC title -> &2=音轨 codec 名(空格分隔, 如 "ac3" / "pcm_dvd")
rem  落盘再回读的理由同 :PROBE; libdvdread 的抱怨是打到标准输出的, 靠 findstr 按
rem  形状过滤(只留纯 "数字/数字" 或纯 codec 名那些行)
rem =========================================================================
:PROBE_RATE
set "%~2="
"%FP%" -v error -f dvdvideo -title %1 -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "%SRC%" 2>nul | findstr /r "^[0-9][0-9]*/[0-9][0-9]*,*$" > "%WORK%\_p3.txt"
rem 只留数值行(libdvdread 的 CHECK_VALUE 抱怨在这类盘上是打到标准输出的, 见下面
rem :PROBE_ACODEC), 但正则必须容忍尾逗号: csv=p=0 对单字段也打 "25/1," 这种形式,
rem 原来的 ^...$ 锚匹配不上 -> SRC_RATE 恒为空, 制式只能退化成按高度猜(日志里
rem "源制式: PAL25 @" 后面是空的)。回读时再按逗号取首列, 与 .sh 侧 tr ',' 同效果。
if exist "%WORK%\_p3.txt" for /f "usebackq tokens=1 delims=," %%A in ("%WORK%\_p3.txt") do set "%~2=%%A"
del "%WORK%\_p3.txt" 2>nul
exit /b 0

:PROBE_ACODEC
set "%~2="
"%FP%" -v error -f dvdvideo -title %1 -select_streams a -show_entries stream=codec_name -of csv=p=0 "%SRC%" 2>nul | findstr /r "^[a-z][a-z0-9_]*$" > "%WORK%\_p4.txt"
if exist "%WORK%\_p4.txt" for /f "usebackq delims=" %%A in ("%WORK%\_p4.txt") do call set "%~2=%%%~2%% %%A"
del "%WORK%\_p4.txt" 2>nul
exit /b 0

rem =========================================================================
rem  子过程 PROBE  title  ->  &1=宽  &2=高  &3=时长
rem  用临时文件落盘再回读，避开 for /f 反引号对含空格/与号/小括号路径的转义坑
rem  （绝不能用 for /f 反引号直接跑 ffprobe：程序路径含空格，两种写法都会被
rem    cmd 的引号剥离规则吃掉收尾引号，见 lib\common.bat 的长注释）
rem =========================================================================
:PROBE
set "%~2="
set "%~3="
set "%~4="
"%FP%" -v error -f dvdvideo -title %1 -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "%SRC%" > "%WORK%\_p1.txt" 2>nul
"%FP%" -v error -f dvdvideo -title %1 -show_entries format=duration -of csv=p=0 "%SRC%" > "%WORK%\_p2.txt" 2>nul
for /f "usebackq tokens=1,2 delims=," %%A in ("%WORK%\_p1.txt") do (
    set "%~2=%%A"
    set "%~3=%%B"
)
rem 回读时长必须用 for /f "usebackq" —— 本仓库真机验证过的写法。
rem 曾经的写法是 set /p "变量=" 配一个脱字符小于号，以为那是重定向；
rem 实际 cmd 的脱字符只是把小于号转成字面量参数，于是 set /p 变成
rem "从键盘读一行"，脚本在第一次探针处就静默卡死(2026-09-22 用户报障)。
if exist "%WORK%\_p2.txt" for /f "usebackq delims=" %%A in ("%WORK%\_p2.txt") do set "%~4=%%A"
del "%WORK%\_p1.txt" "%WORK%\_p2.txt" 2>nul
exit /b 0

:DONE
echo.
echo ============================================================
echo  输出目录: %OUTDIR%
rem ---- 产物合计: 编码已跑完, 直接统计本次真正写出的文件(比按码率估准) ----
rem 用 KB 累加再折算 MB: cmd 的 set /a 是 32 位有符号, 大文件直接累加字节会溢出
rem 取大小走 call :ACC_OUT 的 %~z1(cmd 对"参数"的标准行为)。注: 实测 %%~zF 在
rem for /f 里同样能取到正确字节数, 换写法只是与其余子过程同风格 —— 真正让合计
rem 算错的坑是上面那份清单的固定文件名(跨运行残留), 已改随机名, 见 :RUN_ALL。
set /a TOTKB=0
set /a N_OUT=0
if exist "%OUTS%" for /f "usebackq delims=" %%F in ("%OUTS%") do if exist %%F call :ACC_OUT %%F
set /a TOTMB=%TOTKB%/1024
if %N_OUT% gtr 0 echo  产物合计: %N_OUT% 个文件, %TOTMB% MB
del "%OUTS%" 2>nul
rem ---- 体积估算: MODE=ALL 下时长口径是"各 title 合计", 不是 title 1 ----
if "%MODE%"=="ALL" (set "DI=%TOTDUR%") else (set "DI=%SRC_DUR%")
if not defined DI goto DONE_END
if not defined VBITRATE goto DONE_END
for /f "tokens=1 delims=." %%A in ("%DI%") do set DI=%%A
if not defined DI set DI=0
rem 同 :AUTO_LOOP: "N/A" 之类的非数字会让 set /a 报 Missing operator
for /f "delims=0123456789" %%B in ("%DI%") do set DI=0
rem VBITRATE 默认来自查表, 是裸 bit/s；被手工覆盖成 "636k" / "2m" 时换算回来
set "VBN=%VBITRATE%"
if /i "%VBITRATE:~-1%"=="k" set /a VBN=%VBITRATE:~0,-1%*1000
if /i "%VBITRATE:~-1%"=="m" set /a VBN=%VBITRATE:~0,-1%*1000000
rem 先 /1024 再乘时长：cmd 的 set /a 是 32 位有符号，直接乘会溢出
set /a EST_MB=%VBN%/1024*%DI%/8192
set /a EST_KB=%VBN%/1000
if "%MODE%"=="ALL" (echo  体积估算: 视频 ~%EST_KB%kbps x %DI%s（%N_TITLE% 个 title 合计） ≈ %EST_MB% MB（另加音频）) else (echo  体积估算: 视频 ~%EST_KB%kbps x %DI%s ≈ %EST_MB% MB（另加音频）)
:DONE_END
echo ============================================================
if defined FAILED (
    echo [失败] 至少一个 title 编码失败
    exit /b 1
)
exit /b 0

rem =========================================================================
rem  子过程 ACC_OUT  <带引号的产物路径>  ->  累加进 TOTKB / N_OUT
rem  %~z1 是 cmd 对"参数"的标准行为(取该文件的字节数), 路径两边的引号由 %~ 自动
rem  剥掉。实测 for /f 变量的 %%~zF 也返回同样的值, 两者都可用。
rem =========================================================================
:ACC_OUT
set /a TOTKB+=%~z1/1024
set /a N_OUT+=1
exit /b 0
