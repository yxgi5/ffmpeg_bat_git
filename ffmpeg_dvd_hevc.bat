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
rem    B. 可选 IVTC 到 23.976p(FILT=IVTC/BWDIF/NONE)
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
rem  码率仍复用仓库现有的 power-law 模型:
rem    lib\bitrate_table_hevc.csv + lib\common.bat 的 lookup_bitrate
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
set "PREFIX=%~n1"
if not defined PREFIX set "PREFIX=dvd"

rem EXT=mkv  推荐: 能同时装 HEVC + 多条原生 AC3 + 多条 DVD 位图字幕
rem EXT=mp4  只能 HEVC + AAC + 1 条字幕，且 AC3 必须重编码
set EXT=mkv

rem IVTC    3:2 pulldown -> 23.976p，动画/电影 DVD 多数是这种，默认用它
rem BWDIF   去交错但保留 29.97p，只有确认是真隔行(摄像机/现场录像)时才用
rem NONE    原样 29.97 直接编码
set FILT=IVTC

rem 追加到滤镜链末尾的可选处理（通用化：默认空，不改 SAR 也不裁边）
rem   例: setsar=32:27            16:9 变形宽银幕
rem       setsar=8:9              4:3
rem       crop=704:480:8:0,setsar=40:33   裁掉左右过扫边后再修 SAR
set VFILT_EXTRA=

rem AUDIO=copy  MKV 下保留原始 AC3，零重损失，最快
rem AUDIO=aac   必须重编码(MP4 下强制用这个)
set AUDIO=copy

rem MODE=AUTO   自动扫描所有 title，挑时长最长的那条当正片(默认，最通用)
rem MODE=TITLE  只处理 DVD_TITLE 指定的一条
rem MODE=ALL    每个 title 各出一个文件
set MODE=AUTO
set "DVD_TITLE=%~3"
if defined DVD_TITLE set MODE=TITLE

rem SPLIT_CHAPTER=N  按第 N 章把正片切成两段(例如前編/後編)，0 = 不切
rem   第 1 段 = 第 1 章到第 N-1 章，第 2 段 = 第 N 章到结尾
rem   查章节点: ffprobe -f dvdvideo -preindex 1 -title 3 -show_chapters <源>
set SPLIT_CHAPTER=0

rem 额外要导出的 title 号，空格分隔；留空则跳过。例: set EXTRA_TITLES=1 4 5
set EXTRA_TITLES=

rem 空 = 用 lib\bitrate_table_hevc.csv 查表再 /2（推荐）；填数字则直接覆盖(bit/s)
set VBITRATE=
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
set BESTD=0
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

rem ---------------------------- 算目标码率 ----------------------------
if defined VBITRATE goto HAVE_BIT
set "BIT="
if not exist "%SELF_DIR%lib\common.bat" (
    echo [错误] 找不到 lib\common.bat，查不了码率表。
    echo        要么把仓库放完整，要么手工给码率: set VBITRATE=636021
    exit /b 2
)
call "%SELF_DIR%lib\common.bat" lookup_bitrate %SRC_PIX% BIT bitrate_table_hevc.csv
if not defined BIT (
    echo [错误] %SRC_PIX% 不在码率表范围内
    exit /b 2
)
set /a VBITRATE=%BIT% / 2
:HAVE_BIT
echo 目标视频码率: %VBITRATE% bit/s

rem ---------------------------- 组滤镜链 ----------------------------
set VFILT=
if "%FILT%"=="IVTC" set VFILT=fieldmatch=mode=pc:combmatch=full,yadif=deint=interlaced,decimate
if "%FILT%"=="BWDIF" set VFILT=bwdif=mode=1
if defined VFILT_EXTRA if defined VFILT set VFILT=%VFILT%,%VFILT_EXTRA%
if defined VFILT_EXTRA if not defined VFILT set VFILT=%VFILT_EXTRA%
set VFOPT=
if defined VFILT set VFOPT=-vf "%VFILT%"

rem ---------------------------- 容器相关选项 ----------------------------
if "%EXT%"=="mkv" goto CFG_MKV
if "%EXT%"=="mp4" goto CFG_MP4
echo [错误] EXT 只能是 mkv 或 mp4
exit /b 3

:CFG_MKV
set VENC=hevc_nvenc -profile:v main -preset p4 -tune:v hq -rc cbr -b:v %VBITRATE%
if "%AUDIO%"=="aac" (set AENC=-c:a aac -b:a 192k) else (set AENC=-c:a copy)
set SENC=-c:s copy
set SMAP=-map 0:s?
goto RUN_ALL

:CFG_MP4
echo 注意: MP4 只能保留 1 条 DVD 位图字幕，其余会丢；要全留请用 EXT=mkv
set VENC=hevc_nvenc -profile:v main -preset p4 -tune:v hq -rc cbr -b:v %VBITRATE%
set AENC=-c:a aac -b:a 192k
set SENC=-c:s dvdsub
set SMAP=-map 0:s:0?
goto RUN_ALL

:RUN_ALL
rem 一个 title 失败不立刻退出: 后面的分段/特典还要跑完, 但退出码必须真的传出去
set FAILED=
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
set "CHOP="
if not "%CS%"=="0" set CHOP=-chapter_start %CS%
if not "%CE%"=="0" set CHOP=%CHOP% -chapter_end %CE%
echo ------------------------------------------------------------
echo ^> title %T% ^-^> "%OUTN%.%EXT%"  %CHOP%
set RUN_COM="%FF%" -y -hide_banner -v error -stats -f dvdvideo -title %T% %CHOP% -i "%SRC%" -map 0:V -map 0:a? %SMAP% %VFOPT% -c:v %VENC% %AENC% %SENC% -map_chapters 0 -map_metadata 0 -rtbufsize 120m -max_muxing_queue_size 1024 "%OUTDIR%\%OUTN%.%EXT%"
echo RUN_COM:%RUN_COM%
%RUN_COM%
rem 负退出码陷阱: Windows ffmpeg 失败时返回负的 AVERROR 值, 而 cmd 的
rem `if errorlevel N` 是带符号比较, 负值 >= 1 不成立 -> 守卫不触发,
rem 真失败一路落到 exit /b 0。改成"不等于 0"的字符串比较兜住负数与正数。
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" (
    echo Convert failed! rc=%FB_RC%
    echo 常见原因: [1] -c:s 处理不了位图字幕  [2] MP4 下 AC3 没转成 AAC
    echo            [3] NVIDIA 驱动过旧 / hevc_nvenc 不可用
    exit /b 1
)
exit /b 0

:ENC_EXTRA
set "T=%~1"
set "OUTN=%~2"
echo ^> 附加 title %T% ^-^> "%OUTN%.%EXT%"
set RUN_COM="%FF%" -y -hide_banner -v error -stats -f dvdvideo -title %T% -i "%SRC%" -map 0:V -map 0:a? %VFOPT% -c:v %VENC% %AENC% "%OUTDIR%\%OUTN%.%EXT%"
%RUN_COM%
set "FB_RC=%ERRORLEVEL%"
if not "%FB_RC%"=="0" (
    echo Convert failed! rc=%FB_RC%
    exit /b 1
)
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
if not defined SRC_DUR goto DONE_END
if not defined VBITRATE goto DONE_END
for /f "tokens=1 delims=." %%A in ("%SRC_DUR%") do set DI=%%A
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
echo  体积估算: 视频 ~%EST_KB%kbps x %DI%s ≈ %EST_MB% MB（另加音频）
:DONE_END
echo ============================================================
if defined FAILED (
    echo [失败] 至少一个 title 编码失败
    exit /b 1
)
exit /b 0
