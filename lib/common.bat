
rem ============================================================
rem lib\common.bat - 公共子程序库 (P1 重构)
rem 用法: call "%~dp0lib\common.bat" <函数名> [参数...]
rem   函数的实际参数从 %2 开始 ( %1 为函数名)
rem   find_ffmpeg: 四级回退定位 ffmpeg/ffprobe (FFMPEG_BIN > 仓库内 > PATH > 默认目录)
rem                 本函数**不做能力筛选**(2026-09-20 同日回退, 原因见下方 :find_ffmpeg 注释)
rem   check_isvideo: 校验输入含视频流, 无则打印错误并返回 1
rem   on_exist:      产物已存在时的策略(FF_ON_EXIST=skip 默认 / overwrite / fail),
rem                  导出 FF_OUT_FLAG / FF_EXIST_SKIP / FF_EXIST_FAIL, 见 :on_exist
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
if /I "%~1"=="probe_source"          goto probe_source
if /I "%~1"=="probe_field"           goto probe_field
if /I "%~1"=="cover_map"            goto cover_map
if /I "%~1"=="check_isvideo"          goto check_isvideo
if /I "%~1"=="on_exist"               goto on_exist
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
set "fpB=%numB:~0%"
set /A add=fpA+fpB, sub=fpA-fpB, mul=fpA*fpB/one, div=fpA/fpB

set /a ret = 8*!div!
endlocal & set /a %~4=%ret%
exit /b 0

:extract
rem 拆分文件路径: call ... extract <文件> <输出路径变量> <输出文件名变量>
rem   输出形如 "D:\dir\" 与 "name-compressed.mp4"
rem 获取到文件路径
set %~3="%~dp2"
rem 获取到文件盘符
rem 获取到文件名称
rem 获取到文件后缀
set %~4="%~n2-compressed.mp4"
exit /b 0

:get_suffix
rem 获取文件后缀: call ... get_suffix <文件> <输出变量名>
set %~3=%~x2
exit /b 0

:extract_mp4
rem 拆分文件路径(remux 用, 输出名不加后缀): call ... extract_mp4 <文件> <输出路径变量> <输出文件名变量>
rem   输出形如 "D:\dir\" 与 "name.mp4"
rem 获取到文件路径
set %~3="%~dp2"
rem 获取到文件名称
set %~4="%~n2.mp4"
exit /b 0

:find_ffmpeg
rem 定位 ffmpeg/ffprobe 所在 bin 目录: call ... find_ffmpeg <输出变量名>
rem 优先级: 环境变量 FFMPEG_BIN(指向bin目录) > 仓库内 ffmpeg\bin > gyan 默认安装目录 > PATH(where) > 其余常见目录
rem   gyan 那一档刻意排在 PATH **之前**(2026-09-30): 只要是 Windows, 就强制用 gyan
rem   full —— PATH 里第一个常常是别的打包版本(choco / scoop / 某软件的私有副本),
rem   能力不全。显式 FFMPEG_BIN 仍是最高优先级, 不会被这一档顶掉; gyan 目录不存在
rem   时照旧回落到 PATH 与其余兜底目录(那时行为与改动前一致)。
rem 命中: 输出变量=bin目录(无尾部反斜杠), 返回 0; 未找到: 返回 1
rem 本函数刻意不做"能力筛选"(2026-09-20 回退, 曾加过第 3 参数 + :ff_satisfies):
rem   那里的 "%1\ffmpeg.exe" 是双引号叠加 —— 调用方传进来的是**带引号**的 %FFBIN%,
rem   展开成 ""C:\Program Files\ffmpeg\bin"\ffmpeg.exe", 程序名被解析成空串, 错误又被
rem   2>nul 吞掉 → 对任何候选都判"缺少能力"。而本机 ffmpeg 根本不在 PATH 上, 走的是
rem   下面的兜底目录, 那段筛选对这台机器毫无作用。将来要重做必须写 "%~1\ffmpeg.exe"
rem   (lint L21 已能拦住这种写法), 且必须有真机双击验证的余地。
set "FF_OUT=%~2"
if not defined FF_OUT exit /b 1
set "FFBIN="
if defined FFMPEG_BIN if exist "%FFMPEG_BIN%\ffmpeg.exe" set "FFBIN=%FFMPEG_BIN%"
if not defined FFBIN if exist "%~dp0..\ffmpeg\bin\ffmpeg.exe" for %%I in ("%~dp0..\ffmpeg\bin") do set "FFBIN=%%~fI"
rem gyan full 的默认安装位置优先于 PATH(见上方优先级说明)
if not defined FFBIN if exist "C:\Program Files\ffmpeg\bin\ffmpeg.exe" set "FFBIN=C:\Program Files\ffmpeg\bin"
if not defined FFBIN (
    for /f "delims=" %%p in ('where ffmpeg.exe 2^>nul') do (
        if not defined FFBIN for %%I in ("%%p") do set "FFBIN=%%~dpI"
    )
)
if not defined FFBIN if exist "C:\ffmpeg\bin\ffmpeg.exe" set "FFBIN=C:\ffmpeg\bin"
if not defined FFBIN if exist "C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe" set "FFBIN=C:\Program Files (x86)\ffmpeg\bin"
if not defined FFBIN (
    echo [find_ffmpeg] 未找到 ffmpeg.exe: 请安装 ffmpeg 或设置环境变量 FFMPEG_BIN 指向其 bin 目录
    set "%FF_OUT%="
    exit /b 1
)
if "%FFBIN:~-1%"=="\" set "FFBIN=%FFBIN:~0,-1%"
set "%FF_OUT%=%FFBIN%"
rem 醒目回显最终选定的 ffmpeg(与 .sh 侧 ff_report 同义): 定位过程一堆诊断很容易盖过
rem 真正被采用的那个, 用户问"到底用的哪个 ffmpeg"时看的就是这块牌子。
rem 版本串走"先写临时文件再 for /f usebackq 回读" —— 本机真机验证过的读法; 不写成
rem for /f 反引号直接跑 %FFBIN%\ffmpeg.exe(那样是变量展开的程序路径, lint L21 会拦)
set "FF_SHOW=%FFBIN%\ffmpeg.exe"
set "FF_VER="
if defined TEMP "%FF_SHOW%" -hide_banner -version > "%TEMP%\ffmpeg_bat_ffver.tmp" 2>nul
if defined TEMP if exist "%TEMP%\ffmpeg_bat_ffver.tmp" for /f "usebackq tokens=3" %%v in ("%TEMP%\ffmpeg_bat_ffver.tmp") do if not defined FF_VER set "FF_VER=%%v"
if defined TEMP del "%TEMP%\ffmpeg_bat_ffver.tmp" 2>nul
echo ============================================================
echo  使用 ffmpeg : %FF_SHOW%
if defined FF_VER echo  版本       : %FF_VER%
echo ============================================================
exit /b 0

:check_isvideo
rem 校验输入是否含视频流: call ... check_isvideo <文件>
rem   返回 0 = 含视频流; 返回 1 = 无视频流/参数缺失/FFPROBE_PATH 未设(均已打印错误)
rem   依赖调用方已设置 FFPROBE_PATH; 参数直接传带引号的 %SRC_FILE% 即可
rem   (路径在双引号内无需转义, 加 ^& 反而会把字面量脱字符带进路径)
set "CV_FILE=%~2"
if not defined CV_FILE (
    echo [check_isvideo] missing file argument
    exit /b 1
)
if not defined FFPROBE_PATH (
    echo [check_isvideo] FFPROBE_PATH not set by caller
    exit /b 1
)
rem 2026-09-17: 探测统一走 probe_source(一次 ffprobe); 入口随后用同文件再调
rem probe_source 时命中缓存, 不再起第二个 ffprobe 进程。
call "%~f0" probe_source "%CV_FILE%"
rem 注意: 下面这行刻意不进括号块、且给路径加引号 —— 路径含 ) 或 & 时才不会被解析坏
if defined P_streams.stream.0.codec_type exit /b 0
echo [check_isvideo] "%CV_FILE%" 不是视频文件, 未检测到视频流
exit /b 1

:probe_source
rem 取回全部源字段: call ... probe_source <文件>
rem   一次 ffprobe -of flat(字段集与 .sh 侧 lib/common.sh 的 probe_source 逐字对齐),
rem   结果存入 P_* 变量(值已由 %%~b 剥引号):
rem     P_streams.stream.0.{codec_type,codec_name,width,height,r_frame_rate,bit_rate}
rem     P_format.{size,duration,bit_rate}
rem   -select_streams v:0 会把选中流重新编号为 stream.0; 无视频流时 stream.* 整体缺失
rem   (format.* 仍在)而 rc 仍为 0 -- 与原逐字段 v:0 探测的表现一致。
rem   返回 ffprobe 的退出码。同一文件在同一进程内重复调用命中缓存(PS_LAST/PS_RC):
rem   check_isvideo 先探一次, 入口紧接的 probe_source 调用是零进程的。
rem   P_* 不清理: 每个入口进程只探一个源文件, 重复调用按同键覆盖。
rem   注意: 本函数不 setlocal -- P_*/PS_* 必须对调用方可见(本文件函数约定)。
set "PS_FILE=%~2"
if not defined PS_FILE (
    echo [probe_source] missing file argument
    exit /b 1
)
if not defined FFPROBE_PATH (
    echo [probe_source] FFPROBE_PATH not set by caller
    exit /b 1
)
if "%PS_LAST%"=="%PS_FILE%" exit /b %PS_RC%
set "PS_LAST=%PS_FILE%"
set "PS_TMP=%TEMP%\ffmpeg_bat_probe_%RANDOM%%RANDOM%.tmp"
"%FFPROBE_PATH%" -v error -hide_banner -select_streams v:0 -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,bit_rate:format=size,duration,bit_rate -of flat "%PS_FILE%" > "%PS_TMP%" 2>nul
set "PS_RC=%ERRORLEVEL%"
for /f "usebackq tokens=1,* delims==" %%a in ("%PS_TMP%") do set "P_%%a=%%~b"
del "%PS_TMP%" 2>nul
exit /b %PS_RC%

:probe_field
rem 取单个标量并回填变量: call ... probe_field <文件> <条目关键词> <输出变量名>
rem   **参数里绝不含 "="** —— cmd 切分批处理参数 %1..%9 时把**等号也当分隔符**,
rem   所以 `probe_field "%OUT%" stream=bit_rate DEL` 实际被切成
rem     %2=<文件>  %3=stream  %4=bit_rate  %5=DEL
rem   于是"输出变量名"成了 bit_rate, 而调用方读的 DEL 从未被赋值 -> 静默 delivered=0
rem   (用户 2026-09-20 真机报障: 五点全跑完、vmaf 正常, 唯独 delivered 恒为 0;
rem    开发沙箱跑不了 cmd.exe, 静态审查查不出来 —— 只能靠这条规则挡住).
rem   因此 show_entries 串改在本函数内部按**关键词**展开, 外部只传一个不含 "=" 的单词;
rem   lint L22 拦截任何"call 的参数里出现裸等号"的写法. 关键词:
rem     vbr = 视频流码率   (stream=bit_rate)
rem     fbr = 容器平均码率 (format=bit_rate)
rem   新关键词按需在这里加, **不要**改成让调用方传 show_entries 串.
rem   返回 ffprobe 的退出码; 取不到值时输出变量被清空.
rem   **绝不**用 for /f 反引号去跑 ffprobe: 程序路径多为
rem   "C:\Program Files\ffmpeg\bin\ffprobe.exe", 而反引号里的命令由子 cmd /c 执行,
rem   变量展开的程序路径两种写法都不安全:
rem     裸写   `%FFPROBE_PATH% -v error ...` -> 空格截断 -> cmd 报
rem            'C:\Program' 不是内部或外部命令 (用户 2026-09-20 报障)
rem     加引号 `"%FFPROBE_PATH%" -v error ...` -> cmd /c 的引号剥离规则
rem            ("首字符是引号时, 剥掉首个引号与命令行最后一个引号") 会吃掉
rem            末尾参数的收尾引号, 只要路径里有空格就同样散架
rem   改成常规命令行重定向到临时文件(此处无引号剥离问题), 再用
rem   for /f "usebackq" 读文件 —— 本仓库 2026-09-17 重构前一直在用、经真机验证的写法.
rem   注意: 同 probe_source, 本函数不 setlocal -- 输出变量必须对调用方可见.
set "PF_FILE=%~2"
set "PF_KEY=%~3"
set "PF_OUT=%~4"
if not defined PF_OUT exit /b 1
if not defined PF_FILE exit /b 1
if not defined PF_KEY exit /b 1
if not defined FFPROBE_PATH (
    echo [probe_field] FFPROBE_PATH not set by caller
    exit /b 1
)
set "PF_ENT="
if /I "%PF_KEY%"=="vbr" set "PF_ENT=stream=bit_rate"
if /I "%PF_KEY%"=="fbr" set "PF_ENT=format=bit_rate"
if not defined PF_ENT (
    echo [probe_field] unknown key "%PF_KEY%" ^(vbr^|fbr^)
    exit /b 1
)
set "%PF_OUT%="
set "PF_TMP=%TEMP%\ffmpeg_bat_pfield_%RANDOM%%RANDOM%.tmp"
"%FFPROBE_PATH%" -v error -hide_banner -select_streams v:0 -show_entries %PF_ENT% -of csv=p=0 "%PF_FILE%" > "%PF_TMP%" 2>nul
set "PF_RC=%ERRORLEVEL%"
rem 累加用固定名 PF_VAL: do 子句里出现 %变量% 会在**解析时**冻结, 固定名最省心
set "PF_VAL="
for /f "usebackq delims=" %%a in ("%PF_TMP%") do if not defined PF_VAL set "PF_VAL=%%a"
rem 取不到值又不吭声最害人: rc 非 0 时至少把 rc 与文件回显一行
if not defined PF_VAL if not "%PF_RC%"=="0" echo [probe_field] ffprobe rc=%PF_RC% on "%PF_FILE%" ^(%PF_KEY%^)
del "%PF_TMP%" 2>nul
set "%PF_OUT%=%PF_VAL%"
exit /b %PF_RC%

:cover_map
rem 封面(attached picture)保留能力门: call ... cover_map   (无参数, 用 %FFMPEG_PATH%)
rem   调用后读全局 COVERMAP: "-map 0:v:disp:attached_pic?" 后面跟若干 "-c:v:<n> copy",
rem   n 由源流表算出(见下); 或空串(退回丢封面)。封面复制**按输出流号**下发, 不用
rem   全局 -c:v copy —— 后者会和 `-c:v:0 <编码器>` 撞在同一条流上, ffmpeg 必报
rem   Multiple -codec 警告(详见 lib\common.sh 同名注释)。
rem   与 lib\common.sh 的 cover_map_gate 同义同判据, 完整来龙去脉写在那边的注释里。
rem   要点:
rem     * `disp:` 说明符是 ffmpeg 7.1(2024-09)才加入的; 老构建视为语法错误,
rem       结尾的 `?` 救不了解析错误 -> 先探一次: 不支持只丢封面, 绝不让编码失败。
rem     * 探测走 lavfi 假源 + nul 输出, 不碰用户文件; 每个入口进程只探一次(CM_DONE)。
rem     * rc 判据用 %ERRORLEVEL% 的**字符串**比较: Windows ffmpeg 的失败码是负
rem       AVERROR, `if errorlevel N` 按有符号比较看不见(本仓库硬契约)。
rem     * 复制下标 = [m, m+n): m = `-map 0:V` 命中的路数, n = 封面数。**不能写死** ——
rem       2 路视频 + 2 张封面的实测里写死的 1、2 会整体错位, 第 2 张封面被送进编码器
rem       -> `Could not find tag for codec h264 in stream #4` -> 整条写 0 字节。
rem     * 本变量**不只是封面**: 还兼带位图字幕的排除指令 `-map -0:s:<i>`。入口用的是
rem       `-c:s mov_text`, 而 mp4 装不下位图字幕(hdmv_pgs_subtitle / dvd_subtitle /
rem       xsub / dvb_subtitle), ffmpeg 直接 EINVAL 收尾 -> 整片 0 字节。实测用户
rem       838 条清单里 14 个带 PGS。按 per-type 下标**逐条**排除, 一刀切写 `-map -0:s`
rem       会把同文件里能救的 ass / subrip 一起丢掉。位图名单是黑名单: 没列到的一律
rem       维持原行为, 不会因为漏列而白白丢字幕。
rem     * ffprobe 输出先落临时文件再计数: 本仓库硬契约 —— 绝不用 for /f 反引号直接跑
rem       ffprobe(它的路径常含空格, 子 cmd /c 的引号剥离会把命令拦腰截断)。
rem     * 一律用 goto, 不写括号块。两个坑: ① 块内 set 出来的值在同一块里读不到
rem       (解析期就展开了); ② **块内任何半角右括号都会提前终止块** —— 中文注释或
rem       echo 文本里写"(需 ffmpeg 7.1 或更高)"这种, 那个 ) 会把块拦腰截断,
rem       后面的行全被当成命令执行(实测报一串"不是内部或外部命令")。
rem       块外注释随便写; 一旦进块, 括号一律用全角。
rem     * 本函数不 setlocal —— COVERMAP / CM_DONE 必须对调用方可见。
rem       (计数那几行例外: 用 setlocal + `endlocal & set` 把结果带回来。)
if defined CM_DONE exit /b 0
set "CM_DONE=1"
set "COVERMAP="
set "CM_VT=0"
set "CM_NA=0"
set "CM_SI=0"
set "CM_SUBDROP="
set "CM_DVD=0"
set "CM_TMP=%TEMP%\ffbat_cover_%RANDOM%.tmp"
rem ---- 先数流 ----
if not defined FFPROBE_PATH goto cover_probe_done
if not defined SRC_FILE goto cover_probe_done
rem 计数**纯 bat**, 不用 find/findstr: PATH 里一旦有 Git Bash / MSYS2 的 /usr/bin,
rem `find` 就变成 GNU find —— 实测它把 ",video," 当路径扫全盘, 刷一屏
rem Permission denied 还巨慢。逐行解析 + 延迟扩展递增。
rem csv 行尾带 CR, 所以 attached_pic 只比首字符; 列序固定为 编码,类型,封面位。
"%FFPROBE_PATH%" -v error -show_entries stream=codec_name,codec_type -show_entries stream_disposition=attached_pic -of csv=p=0 %SRC_FILE% > "%CM_TMP%" 2>nul
setlocal enabledelayedexpansion
for /f "usebackq delims=" %%L in ("%CM_TMP%") do (
    for /f "tokens=1,2,3 delims=," %%A in ("%%L") do (
        if "%%B"=="video" (
            set /a CM_VT=!CM_VT!+1
            set "CM_C=%%C"
            if "!CM_C:~0,1!"=="1" set /a CM_NA=!CM_NA!+1
        )
        if "%%A"=="dvd_nav_packet" set "CM_DVD=1"
        if "%%B"=="subtitle" (
            set "CM_IDX=!CM_SI!"
            set /a CM_SI=!CM_SI!+1
            set "CM_BMP="
            if "%%A"=="hdmv_pgs_subtitle" set "CM_BMP=%%A"
            if "%%A"=="dvd_subtitle" set "CM_BMP=%%A"
            if "%%A"=="xsub" set "CM_BMP=%%A"
            if "%%A"=="dvb_subtitle" set "CM_BMP=%%A"
            if defined CM_BMP set "CM_SUBDROP=!CM_SUBDROP! -map -0:s:!CM_IDX!"
        )
    )
)
endlocal & set "CM_VT=%CM_VT%" & set "CM_NA=%CM_NA%" & set "CM_SUBDROP=%CM_SUBDROP%" & set "CM_DVD=%CM_DVD%"
:cover_probe_done
del "%CM_TMP%" 2>nul
rem 导航包只在 DVD-Video 的 ISO / VOB 里有, 实测 192 个 mpg/m2ts 片源 0 命中
if "%CM_DVD%"=="1" echo [dvd] 本源是 DVD-Video —— 不带 -f dvdvideo 会被当 MPEG-PS 胡乱揭开, 内容不对; 请改用 ffmpeg_dvd_hevc.bat
rem ---- 位图字幕排除: 与 disp: 能力无关, 老 ffmpeg 一样会整片写 0 字节 ----
if not defined CM_SUBDROP goto cover_aftersub
set "COVERMAP=%COVERMAP% %CM_SUBDROP%"
echo [sub] 含位图字幕 —— mp4 装不下, 本次不保留; 要保留请出 mkv
:cover_aftersub
rem ---- 封面部分 ----
if not defined FFMPEG_PATH goto cover_noff
"%FFMPEG_PATH%" -hide_banner -v error -f lavfi -i color=c=black:s=16x16:r=1 -t 0.04 -map 0:v:disp:attached_pic? -f null - >nul 2>nul
if not "%ERRORLEVEL%"=="0" goto cover_nodisp
set "COVERMAP=%COVERMAP% -map 0:v:disp:attached_pic?"
if "%CM_VT%"=="" goto cover_fallback
if "%CM_VT%"=="0" goto cover_fallback
if "%CM_NA%"=="0" goto cover_done
set /a CM_M=%CM_VT%-%CM_NA%
if %CM_M% LSS 1 set CM_M=1
set /a CM_I=%CM_M%
:cover_loop
if %CM_I% GEQ %CM_VT% goto cover_done
set "COVERMAP=%COVERMAP% -c:v:%CM_I% copy"
set /a CM_I+=1
goto cover_loop
:cover_noff
echo [cover] FFMPEG_PATH not set by caller
exit /b 0
:cover_nodisp
echo [cover] 本 ffmpeg 不认 disp: 流说明符 —— 需 ffmpeg 7.1 或更高; 本次运行不保留封面
exit /b 0
:cover_fallback
rem 探测不可用 —— 没有 ffprobe 或源探测失败: 退回写死槽位, 至少覆盖 1~2 张封面
set "COVERMAP=%COVERMAP% -c:v:1 copy -c:v:2 copy"
:cover_done
exit /b 0

::on_exist  <target file, quoted>
rem 2026-09-30: ffmpeg's -n prints "File already exists. Exiting." and then
rem returns 0, so a run that did NOTHING looks like a success (measured). Make
rem it explicit here, chosen by FF_ON_EXIST:
rem   skip      (default) say so and skip; exit code stays 0, so that
rem              convert_from_list_* can resume a batch without failing it
rem   overwrite switch -n to -y and really re-encode
rem   fail      say so and ask the caller to exit 6, so it cannot pass unnoticed
rem Argument is %~2 (not %~1): %1 is the function name in this library.
rem Exports (the caller reads them right after this call):
rem   FF_OUT_FLAG    -n (default) or -y
rem   FF_EXIST_SKIP  1 = output exists and the policy is skip: do not run ffmpeg
rem   FF_EXIST_FAIL  1 = output exists and the policy is fail: the caller exits 6
rem Always returns 0: a `call`ed subroutine cannot terminate the caller, so the
rem decision travels back in variables instead. Echo text stays ASCII so it
rem survives any console codepage.
:on_exist
set "FF_OUT_FLAG=-n"
set "FF_EXIST_SKIP="
set "FF_EXIST_FAIL="
if "%~2"=="" exit /b 0
if not exist %2 exit /b 0
if /i "%FF_ON_EXIST%"=="overwrite" (
    set "FF_OUT_FLAG=-y"
    echo [on_exist] output exists, FF_ON_EXIST=overwrite -^> re-encode: %~2
    exit /b 0
)
if /i "%FF_ON_EXIST%"=="fail" (
    echo [on_exist] output exists, FF_ON_EXIST=fail -^> not overwritten, exit 6: %~2
    set "FF_EXIST_FAIL=1"
    exit /b 0
)
echo [on_exist] output exists -^> SKIPPED, nothing was encoded: %~2
echo [on_exist]   FF_ON_EXIST=overwrite to re-encode, =fail to treat it as an error
set "FF_EXIST_SKIP=1"
exit /b 0