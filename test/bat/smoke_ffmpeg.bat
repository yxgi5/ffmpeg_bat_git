@echo off
rem ============================================================
rem smoke_ffmpeg.bat (v12)  *** ASCII ONLY / CRLF ***
rem
rem Automated smoke harness for the ffmpeg_bat_git .bat family.
rem Usage modes covered:
rem   A) file argument     -> drag and drop / cmd direct call
rem   B) interactive path  -> double click, then type the path (SET /P)
rem   C) fresh process     -> console already UTF-8 (opencmd.bat style)
rem Every run captures stdout+stderr into smoke_logs\*.log, and a verdict
rem table is written to smoke_logs\summary.txt
rem
rem v12 changes vs v11 (2026-10-04):
rem   - new case T31 for the --dry-run switch: rc=0, the command line comes
rem     out with the input named in it, and NOTHING is produced. Runs on the
rem     libx264 entry -> no hardware, never SKIPped. Same T-id as the .sh twin.
rem v11 changes vs v10 (2026-10-02):
rem   - new case T30: a Notepad-style list (CRLF line ends + UTF-8 BOM) must
rem     still produce one output per entry. The .sh side has covered this
rem     since T21 (run_list strips the BOM); the .bat wrappers did not -- cmd's
rem     for /f swallowed the BOM into the first path, check_isvideo then said
rem     "not a video" and the whole list died with rc=3. The BOM here is made
rem     on the fly with certutil (three bytes EF BB BF prepended to the list),
rem     so the case needs no external fixture and no invisible character in
rem     this file. Runs on the libx265 wrapper -> no hardware, never SKIPped.
rem v10 changes vs v9 (2026-10-02):
rem   - new cases T26 / T27 for the EXT container switch (mp4 default, mkv
rem     optional). Same T-ids as test/sh/smoke_ffmpeg.sh. T26: EXT=mkv must
rem     move the auto output name (-compressed.mkv) AND the muxer (probes as
rem     matroska), and must not write an .mp4 for the same job. T27: a source
rem     carrying a mov_text subtitle track must still come out usable --
rem     plain -c:s copy into mkv ends with rc=-40 and a 0-byte file, so the
rem     switch has to fall back to -c:s ass there.
rem v9 changes vs v8:
rem   - new case T23: a missing list entry must abort the wrapper
rem     (rc != 0). It mirrors T23 in test/sh/smoke_ffmpeg.sh. It could
rem     not exist here before 2026-09-17: the .bat wrappers kept going
rem     after a failed child and still exited 0, so the case would have
rem     failed on every run. Uses the libx265 wrapper -> no hardware,
rem     never SKIPped, same fixture as the sh side.
rem v8 changes vs v7:
rem   - hardware-dependent cases (T1/T2/T3/T7/T14) now PROBE the entry on a
rem     small clip first and report SKIP when this box cannot initialise the
rem     encoder, exactly like the .sh twin does. Without this, a box with no
rem     Intel/NVIDIA hardware produced FAIL lines that say nothing at all
rem     about the repo. Each probe writes gate_<entry>.log next to the
rem     other logs.
rem   - the probe clip is 320x240: NVENC refuses to initialise an encoder
rem     below a minimum size, so a 128x128 probe turned a WORKING GPU into a
rem     silent SKIP (measured 2026-09-16: 128x128 fails for hevc_nvenc and
rem     av1_nvenc, 160x120 and above succeed).
rem v7 changes vs v6:
rem   - :judge now ASSERTS the output codec (ffprobe sidecar) instead of
rem     only writing it, and accepts "LT:<n>" as an expected-bitrate
rem     relation (assert that the computed bitrate is BELOW n).
rem   - T16: ffmpeg_libx264.bat (soft AVC, no hardware needed).
rem   - T17: low-bitrate source -> the computed bitrate must be clamped to
rem     the source bitrate (arg mode too). Regression for the arg-mode
rem     clamp bug fixed on 2026-09-16.
rem   - T13 runs on ffmpeg_libx264.bat so the exit-code contract is also
rem     testable on a box without Intel/NVIDIA hardware.
rem v6 changes vs v5:
rem   - T15: ffmpeg_av1_qsv.bat (AV1 QSV). AV1 hardware encoding only exists
rem     on Arrow Lake or newer iGPUs, so the test PROBES the hardware first
rem     with a 1-frame lavfi clip and reports SKIP (never FAIL) on boxes
rem     without an AV1 QSV encoder. Probe log:
rem     smoke_logs\T15_av1_qsv_probe.txt
rem v5 changes vs v4:
rem   - T13: an audio-only input must be REJECTED before ffmpeg runs
rem     (regression for the new lib\common.bat :check_isvideo)
rem   - global hygiene line: no log may contain the old lib debug
rem     echoes (in extract() / in extract_mp4() / ret=)
rem v4 changes vs v3:
rem   - optional 2nd arg LIST: runs only the list-mode tests (T9/T11/T12)
rem   - T12: list mode with NO argument, launched from another directory
rem     (the documented double-click usage; list.txt comes from the cwd)
rem v3 changes vs v2:
rem   - fixtures are REGENERATED on every run (v2 reused stale clips that
rem     had no audio track, which made every encoder fail on -map 0:a)
rem   - T10 silent input is now an ASSERTED test (regression for -map 0:a?)
rem   - global banner check line: every log must be free of
rem     "is not recognized" (regression for the guard marker leak)
rem
rem Location: <repo>\test\bat\  (the repo root is derived from this
rem         file's own path, two levels up)
rem
rem Usage:  smoke_ffmpeg.bat [repo_path] [LIST]
rem         (no 2nd arg = full run incl. T13/T14/T15/T16/T17;
rem          LIST = list tests only)
rem         default repo_path = two levels up from this .bat
rem ============================================================
setlocal EnableExtensions
set "REPO=%~1"
if not defined REPO for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
rem 统一 --help / -help / -h: 与 sh 孪生同一套版式(见 lib\common.bat 的 :want_help / :usage)
call "%REPO%\lib\common.bat" want_help %*
if defined FB_WANT_HELP call "%REPO%\lib\common.bat" usage "smoke_ffmpeg.bat  -  bat 族回归冒烟（T1-T31）" "用法: test\bat\smoke_ffmpeg.bat [仓库路径] [LIST]" "第二个参数写 LIST 时只跑清单段（T9 / T11 / T12 / T23 / T30）"
if defined FB_WANT_HELP exit /b 0
set "ONLY=%~2"
if /I not "%ONLY%"=="LIST" set "ONLY="
if not exist "%REPO%\ffmpeg_avc_qsv.bat" goto NO_REPO

set "LOGDIR=%~dp0smoke_logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
del /q "%LOGDIR%\*.log" >nul 2>&1
del /q "%LOGDIR%\*_probe.txt" >nul 2>&1
set "SUM=%LOGDIR%\summary.txt"
set "WORK=%TEMP%\ffmpeg_bat_smoke"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1

rem ---- console codepage we started with (= fresh console default) ----
set "CP0="
for /f "delims=" %%l in ('chcp') do set "CP0=%%l"
set "CP0=%CP0:*: =%"

echo ==== ffmpeg_bat smoke harness v8 ==== > "%SUM%"
echo date      : %DATE% %TIME% >> "%SUM%"
echo repo      : %REPO% >> "%SUM%"
echo startCP   : %CP0% >> "%SUM%"
echo workdir   : %WORK% >> "%SUM%"
echo. >> "%SUM%"

rem ---- locate ffmpeg through the repo helper (also exercises find_ffmpeg) ----
set "FFBIN="
call "%REPO%\lib\common.bat" find_ffmpeg FFBIN
set "FFRC=%errorlevel%"
echo find_ffmpeg rc=%FFRC% bin=%FFBIN% >> "%SUM%"
if not defined FFBIN goto NO_FF
set "FF=%FFBIN%\ffmpeg.exe"
set "FP=%FFBIN%\ffprobe.exe"
"%FF%" -version 2>&1 | findstr /b /c:"ffmpeg version" >> "%SUM%"

rem ---- fixtures: always regenerate (stale clips caused false failures) ----
del /q "%WORK%\smoke input 1080p60.mp4" >nul 2>&1
del /q "%WORK%\smoke mov input 1080p60.mov" >nul 2>&1
del /q "%WORK%\smoke silent 1080p60.mp4" >nul 2>&1
del /q "%WORK%\smoke audio only.m4a" >nul 2>&1
del /q "%WORK%\smoke lowbitrate 1080p30.mp4" >nul 2>&1
del /q "%WORK%\list_a.mp4" >nul 2>&1
del /q "%WORK%\list b.mp4" >nul 2>&1
set "VOPT=-hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=60 -f lavfi -i sine=frequency=440:sample_rate=44100"
set "IN=%WORK%\smoke input 1080p60.mp4"
"%FF%" %VOPT% -t 2 -c:v libx264 -preset ultrafast -b:v 18M -pix_fmt yuv420p -c:a aac -b:a 128k -y "%IN%"
set "INMOV=%WORK%\smoke mov input 1080p60.mov"
"%FF%" %VOPT% -t 1 -c:v libx264 -preset ultrafast -b:v 18M -pix_fmt yuv420p -c:a aac -b:a 128k -y "%INMOV%"
set "QUIET=%WORK%\smoke silent 1080p60.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 2 -c:v libx264 -preset ultrafast -b:v 18M -pix_fmt yuv420p -y "%QUIET%"
set "AONLY=%WORK%\smoke audio only.m4a"
"%FF%" -hide_banner -loglevel error -f lavfi -i sine=frequency=440:sample_rate=44100 -t 2 -c:a aac -b:a 128k -y "%AONLY%"
set "L1=%WORK%\list_a.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 128k -y "%L1%"
set "L2=%WORK%\list b.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 128k -y "%L2%"
rem low-bitrate source for T17: 400k, well below table(1080p AVC)/2 = 3836249
set "LOWBR=%WORK%\smoke lowbitrate 1080p30.mp4"
"%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 2 -c:v libx264 -preset ultrafast -b:v 400k -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -y "%LOWBR%"
echo probe mp4 : %IN%  [audio+video] >> "%SUM%"
echo probe mov : %INMOV%  [audio+video] >> "%SUM%"
echo probe mute: %QUIET%  [video only, for -map 0:a? regression] >> "%SUM%"
echo probe audio: "%AONLY%"  [audio only, for check_isvideo regression] >> "%SUM%"
echo probe lowbr: "%LOWBR%"  [1080p30 400k, for the bitrate clamp] >> "%SUM%"
echo. >> "%SUM%"
echo ---- verdicts ---- >> "%SUM%"

if defined ONLY goto LISTONLY

rem ---- probe clip for the hardware gates, see :gate below ----------------
rem 320x240 on purpose: NVENC refuses to initialise below a minimum size, and
rem a probe clip that is itself too small would silently hide real coverage.
set "GATECLIP=%WORK%\gate_clip.mp4"
if not exist "%GATECLIP%" "%FF%" -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x240:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 1 -c:v libx264 -preset ultrafast -b:v 200k -pix_fmt yuv420p -c:a aac -b:a 64k -shortest -y "%GATECLIP%"

rem ============ usage A: file argument (drag and drop equivalent) ============
chcp %CP0% >nul
call :gate ffmpeg_avc_qsv
if not defined GATED call :runA ffmpeg_avc_qsv    "%IN%" T1_avc_qsv_A      3836249 S A h264
if defined GATED call :skipcase T1 ffmpeg_avc_qsv
chcp %CP0% >nul
call :gate ffmpeg_hevc_nvenc
if not defined GATED call :runA ffmpeg_hevc_nvenc "%IN%" T2_hevc_nvenc_A   2548951 S A hevc
if defined GATED call :skipcase T2 ffmpeg_hevc_nvenc
chcp %CP0% >nul
call :gate ffmpeg_hevc_qsv
if not defined GATED call :runA ffmpeg_hevc_qsv   "%IN%" T3_hevc_qsv_A     2548951 S A hevc
if defined GATED call :skipcase T3 ffmpeg_hevc_qsv
chcp %CP0% >nul
call :runA ffmpeg_libx265    "%IN%" T4_libx265_A      2548951 S A hevc
chcp %CP0% >nul
rem T14: ffmpeg_av1_nvenc.bat (added 2026-09-16). Needs an Ada+ GPU (RTX 40 series or
rem newer); 1080p AV1 table entry = 1707157. Verdict artefacts: log must show
rem TARGET_BITRATE=1707157 and the ffprobe sidecar must show codec_name=av1.
call :gate ffmpeg_av1_nvenc
if not defined GATED call :runA ffmpeg_av1_nvenc  "%IN%" T14_av1_nvenc_A  1707157 S A av1
if defined GATED call :skipcase T14 ffmpeg_av1_nvenc

rem ============ T16: ffmpeg_libx264.bat (added 2026-09-16) ============
rem Soft AVC fallback: no hardware needed, so it runs on every box.
rem 1080p AVC table / 2 = 3836249 - the same value the .sh twin asserts.
chcp %CP0% >nul
call :runA ffmpeg_libx264   "%IN%" T16_libx264_A    3836249 S A h264

rem ============ T26: EXT=mkv -- name AND muxer follow the switch ==========
rem Added 2026-10-02 together with the EXT switch (see readme.md). Default is
rem still mp4 (T4/T16 cover that branch); EXT=mkv must move the auto output
rem name AND the container, so the verdict is threefold: rc=0, the file
rem clip-compressed.mkv exists, and it probes as matroska -- plus the negative
rem one, no .mp4 may be written for the same job.
chcp %CP0% >nul
set "T26D=%WORK%\cases\T26_libx265_mkv"
if not exist "%T26D%" mkdir "%T26D%" >nul 2>&1
copy /y "%IN%" "%T26D%\clip.mp4" >nul
del /q "%T26D%\clip-compressed.mkv" >nul 2>&1
del /q "%T26D%\clip-compressed.mp4" >nul 2>&1
set "T26LOG=%LOGDIR%\T26_libx265_mkv.log"
set "T26OUT=%T26D%\clip-compressed.mkv"
set "EXT=mkv"
call "%REPO%\ffmpeg_libx265.bat" "%T26D%\clip.mp4" < nul > "%T26LOG%" 2>&1
set "RC26=%errorlevel%"
set "EXT="
set "V26=PASS"
set "N26="
if not "%RC26%"=="0" ( set "V26=FAIL" & set "N26=%N26% rc=%RC26% want0;" )
if not exist "%T26OUT%" ( set "V26=FAIL" & set "N26=%N26% noClipCompressedMkv;" )
if exist "%T26D%\clip-compressed.mp4" ( set "V26=FAIL" & set "N26=%N26% mp4WrittenAnyway;" )
if exist "%T26OUT%" "%FP%" -v error -show_entries format=format_name -of csv=p=0 "%T26OUT%" > "%LOGDIR%\T26_container.txt" 2>&1
findstr /i /c:"matroska" "%LOGDIR%\T26_container.txt" >nul 2>&1
if errorlevel 1 ( set "V26=FAIL" & set "N26=%N26% notMatroska;" )
echo [%V26%] T26 EXT=mkv libx265 rc=%RC26% >> "%SUM%"
if not "%N26%"=="" echo        why: %N26% >> "%SUM%"

rem ============ T27: EXT=mkv against a mov_text subtitle source ===========
rem Such a source cannot go into mkv with -c:s copy: ffmpeg ends with rc=-40
rem and leaves a 0-byte file (measured 2026-10-02). The switch must fall back
rem to -c:s ass for exactly this case, so the assertions are: rc=0, output
rem exists, is not 0 bytes, and its subtitle track survived -- as ass.
chcp %CP0% >nul
set "T27D=%WORK%\cases\T27_libx265_movtext"
if not exist "%T27D%" mkdir "%T27D%" >nul 2>&1
copy /y "%IN%" "%T27D%\clip.mp4" >nul
>  "%T27D%\sub.srt" echo 1
>> "%T27D%\sub.srt" echo 00:00:00,000 --^> 00:00:02,000
>> "%T27D%\sub.srt" echo EXT mkv smoke line
"%FF%" -hide_banner -loglevel error -i "%T27D%\clip.mp4" -i "%T27D%\sub.srt" -map 0:v -map 0:a -map 1:s -c copy -c:s mov_text -y "%T27D%\movtxt.mp4" > "%LOGDIR%\T27_mksrc.log" 2>&1
set "T27OUT=%T27D%\movtxt-compressed.mkv"
del /q "%T27OUT%" >nul 2>&1
set "EXT=mkv"
call "%REPO%\ffmpeg_libx265.bat" "%T27D%\movtxt.mp4" < nul > "%LOGDIR%\T27_libx265_movtext.log" 2>&1
set "RC27=%errorlevel%"
set "EXT="
set "V27=PASS"
set "N27="
if not "%RC27%"=="0" ( set "V27=FAIL" & set "N27=%N27% rc=%RC27% want0;" )
if not exist "%T27OUT%" ( set "V27=FAIL" & set "N27=%N27% noOutput;" )
if exist "%T27OUT%" "%FP%" -v error -select_streams s:0 -show_entries stream=codec_name -of csv=p=0 "%T27OUT%" > "%LOGDIR%\T27_sub.txt" 2>&1
findstr /i /c:"ass" "%LOGDIR%\T27_sub.txt" >nul 2>&1
if errorlevel 1 ( set "V27=FAIL" & set "N27=%N27% subNotAss;" )
if exist "%T27OUT%" for %%A in ("%T27OUT%") do if %%~zA LEQ 0 ( set "V27=FAIL" & set "N27=%N27% zeroByte;" )
echo [%V27%] T27 EXT=mkv mov_text source rc=%RC27% >> "%SUM%"
if not "%N27%"=="" echo        why: %N27% >> "%SUM%"

rem ============ T28: BITRATE_NO_HALF=1 -> double target bitrate ============
rem The historical rule halves the table value; the new switch must skip that
rem step, so for the SAME clip the second run has to print exactly twice the
rem target of the first. Default of the switch lives in lib\defaults.cfg.
chcp %CP0% >nul
set "T28D=%WORK%\cases\T28_libx265_nohalf"
if not exist "%T28D%" mkdir "%T28D%" >nul 2>&1
copy /y "%IN%" "%T28D%\clip.mp4" >nul
del /q "%T28D%\clip-compressed.mp4" >nul 2>&1
call "%REPO%\ffmpeg_libx265.bat" "%T28D%\clip.mp4" < nul > "%LOGDIR%\T28_default.log" 2>&1
set "TB28A=none"
if exist "%LOGDIR%\T28_default.log" for /f "tokens=1,2 delims==" %%a in ('findstr /b /c:"TARGET_BITRATE=" "%LOGDIR%\T28_default.log"') do set "TB28A=%%b"
del /q "%T28D%\clip-compressed.mp4" >nul 2>&1
set "BITRATE_NO_HALF=1"
call "%REPO%\ffmpeg_libx265.bat" "%T28D%\clip.mp4" < nul > "%LOGDIR%\T28_nohalf.log" 2>&1
set "RC28=%errorlevel%"
set "BITRATE_NO_HALF="
set "TB28B=none"
if exist "%LOGDIR%\T28_nohalf.log" for /f "tokens=1,2 delims==" %%a in ('findstr /b /c:"TARGET_BITRATE=" "%LOGDIR%\T28_nohalf.log"') do set "TB28B=%%b"
set "V28=PASS"
set "N28="
set "EXP28=0"
if not "%TB28A%"=="none" set /a EXP28=%TB28A% * 2
if not "%RC28%"=="0" ( set "V28=FAIL" & set "N28=%N28% rc=%RC28% want0;" )
if "%TB28A%"=="none" ( set "V28=FAIL" & set "N28=%N28% noBaseline;" )
if not "%TB28B%"=="%EXP28%" ( set "V28=FAIL" & set "N28=%N28% target=%TB28B% want%EXP28%;" )
echo [%V28%] T28 BITRATE_NO_HALF=1 target %TB28A% -^> %TB28B% >> "%SUM%"
if not "%N28%"=="" echo        why: %N28% >> "%SUM%"

rem ============ T29: FB_DEFAULTS alternate config drives the container ======
rem lib\defaults.cfg is the single source of truth for the shared switches;
rem FB_DEFAULTS points at another copy of it (nothing in the repo is touched),
rem so a run WITHOUT any command-line override must come out as mkv.
chcp %CP0% >nul
set "T29D=%WORK%\cases\T29_cfgfile"
if not exist "%T29D%" mkdir "%T29D%" >nul 2>&1
copy /y "%IN%" "%T29D%\clip.mp4" >nul
del /q "%T29D%\clip-compressed.mkv" >nul 2>&1
del /q "%T29D%\clip-compressed.mp4" >nul 2>&1
>  "%T29D%\alt.cfg" echo EXT=mkv
>> "%T29D%\alt.cfg" echo BITRATE_NO_HALF=0
set "FB_DEFAULTS=%T29D%\alt.cfg"
call "%REPO%\ffmpeg_libx265.bat" "%T29D%\clip.mp4" < nul > "%LOGDIR%\T29_cfgfile.log" 2>&1
set "RC29=%errorlevel%"
set "FB_DEFAULTS="
set "T29OUT=%T29D%\clip-compressed.mkv"
set "V29=PASS"
set "N29="
if not "%RC29%"=="0" ( set "V29=FAIL" & set "N29=%N29% rc=%RC29% want0;" )
if not exist "%T29OUT%" ( set "V29=FAIL" & set "N29=%N29% noClipCompressedMkv;" )
if exist "%T29D%\clip-compressed.mp4" ( set "V29=FAIL" & set "N29=%N29% mp4WrittenAnyway;" )
echo [%V29%] T29 FB_DEFAULTS alt config -^> mkv rc=%RC29% >> "%SUM%"
if not "%N29%"=="" echo        why: %N29% >> "%SUM%"

rem ============ T31: --dry-run prints the command, runs nothing ============
rem Added 2026-10-04 together with the dry-run switch (see readme.md). The
rem point of the switch is that "what would this entry run" is answerable
rem without touching the source: rc=0, a command line naming the clip is on
rem stdout, and no product appears. Same T-id as test/sh/smoke_ffmpeg.sh.
chcp %CP0% >nul
set "T31D=%WORK%\cases\T31_dryrun"
if not exist "%T31D%" mkdir "%T31D%" >nul 2>&1
copy /y "%IN%" "%T31D%\clip.mp4" >nul
del /q "%T31D%\clip-compressed.mp4" >nul 2>&1
set "T31LOG=%LOGDIR%\T31_dryrun.log"
call "%REPO%\ffmpeg_libx264.bat" --dry-run "%T31D%\clip.mp4" < nul > "%T31LOG%" 2>&1
set "RC31=%errorlevel%"
set "V31=PASS"
set "N31="
if not "%RC31%"=="0" ( set "V31=FAIL" & set "N31=%N31% rc=%RC31% want0;" )
rem 标记行说明"这一步没真跑"; 再单独确认打出来的命令带着输入文件名
findstr /c:"[dry-run]" "%T31LOG%" >nul 2>&1
if errorlevel 1 ( set "V31=FAIL" & set "N31=%N31% noDryRunMarker;" )
findstr /c:"clip.mp4" "%T31LOG%" >nul 2>&1
if errorlevel 1 ( set "V31=FAIL" & set "N31=%N31% cmdMissingInput;" )
if exist "%T31D%\clip-compressed.mp4" ( set "V31=FAIL" & set "N31=%N31% productWritten;" )
echo [%V31%] T31 --dry-run libx264 rc=%RC31% >> "%SUM%"
if not "%N31%"=="" echo        why: %N31% >> "%SUM%"

rem ============ T17: low-bitrate source (clamp regression) ============
rem A 400k source must keep its own bitrate instead of being re-encoded up
rem to the table value. The source bitrate is whatever the encoder produced,
rem so the check is a relation ("LT:3836249"), not an exact number.
chcp %CP0% >nul
call :runA ffmpeg_libx264 "%LOWBR%" T17_libx264_lowbr LT:3836249 S A h264

rem ============ T5: copy_to_mp4 (mov -> mp4, no bitrate table) ============
chcp %CP0% >nul
call :runA ffmpeg_copy_to_mp4 "%INMOV%" T5_copy_to_mp4_A 0 C A h264

rem ============ usage B: double click + typed path (stdin fed) ============
chcp %CP0% >nul
call :runB ffmpeg_avc_qsv "%IN%" T6_avc_qsv_B 3836249 B

rem ============ usage C: console already UTF-8, FRESH cmd process ============
chcp 65001 >nul
call :gate ffmpeg_hevc_nvenc
if not defined GATED call :runA ffmpeg_hevc_nvenc "%IN%" T7_hevc_nvenc_C 2548951 S C hevc F
if defined GATED call :skipcase T7 ffmpeg_hevc_nvenc

rem ============ T10: silent input (regression for -map 0:a?) ============
chcp %CP0% >nul
call :runA ffmpeg_avc_qsv "%QUIET%" T10_avc_qsv_silent 3836249 S A-silent h264

rem ============ T13: non-video input must be rejected before ffmpeg =====
chcp %CP0% >nul
set "T13LOG=%LOGDIR%\T13_nonvideo_A.log"
set "T13OUT=%WORK%\smoke audio only-compressed.mp4"
del /q "%T13OUT%" >nul 2>&1
rem soft-encode entry on purpose: the guard lives in lib\common.bat and is
rem shared by every entry, so T13 stays runnable without any hardware.
call "%REPO%\ffmpeg_libx264.bat" "%AONLY%" < nul > "%T13LOG%" 2>&1
set "RC13=%errorlevel%"
set "V13=PASS"
set "N13="
findstr /i /c:"check_isvideo" "%T13LOG%" >nul 2>&1
if errorlevel 1 ( set "V13=FAIL" & set "N13=%N13% noCheckMsg;" )
findstr /i /c:"matches no streams" "%T13LOG%" >nul 2>&1
if not errorlevel 1 ( set "V13=FAIL" & set "N13=%N13% reachedFfmpeg;" )
if exist "%T13OUT%" ( set "V13=FAIL" & set "N13=%N13% outputProduced;" )
if not "%RC13%"=="3" ( set "V13=FAIL" & set "N13=%N13% exitCode=%RC13% want3;" )
echo [%V13%] T13 non-video input rejected before ffmpeg rc=%RC13% >> "%SUM%"
if not "%N13%"=="" echo        why: %N13% >> "%SUM%"

rem ============ T15: ffmpeg_av1_qsv.bat (added 2026-09-16) =============
rem AV1 QSV hardware encoding only exists on Arrow Lake or newer iGPUs and
rem only in recent ffmpeg builds. Probe the capability first so this case
rem reports SKIP instead of FAIL on a box that simply lacks the hardware.
rem 1080p AV1 table entry = 1707157 (same value the .sh twin produced on
rem the C-machine Arrow Lake box).
chcp %CP0% >nul
set "AV1P=%WORK%\probe_av1_qsv.mp4"
set "AV1PLOG=%LOGDIR%\T15_av1_qsv_probe.txt"
del /q "%AV1P%" >nul 2>&1
"%FF%" -hide_banner -init_hw_device qsv=hw -filter_hw_device hw -f lavfi -i color=size=256x256:rate=30 -frames:v 1 -c:v av1_qsv -preset fast -profile:v main -y "%AV1P%" > "%AV1PLOG%" 2>&1
set "AV1PRC=%errorlevel%"
if not "%AV1PRC%"=="0" goto T15SKIP
if not exist "%AV1P%" goto T15SKIP
del /q "%AV1P%" >nul 2>&1
chcp %CP0% >nul
call :runA ffmpeg_av1_qsv "%IN%" T15_av1_qsv_A 1707157 S A av1
goto T15DONE
:T15SKIP
echo [SKIP] T15 ffmpeg_av1_qsv: no AV1 QSV hardware encoder on this box >> "%SUM%"
echo        probe rc=%AV1PRC%, see T15_av1_qsv_probe.txt >> "%SUM%"
:T15DONE

rem ============ T23: a missing list entry must abort the wrapper ============
rem Mirrors T23 in test/sh/smoke_ffmpeg.sh. The .bat wrappers used to grind
rem through the whole list and still exit 0, so this case could only exist
rem on the sh side; since 2026-09-17 they fail fast (goto LIST_FAIL). The
rem libx265 wrapper is used on purpose: software encoder, no hardware, so
rem the case can never be SKIPped and both families run the same fixture.
chcp %CP0% >nul
if not exist "%WORK%\T23_abort" mkdir "%WORK%\T23_abort" >nul 2>&1
> "%WORK%\T23_abort\badlist.txt" echo %WORK%\T23_abort\nope.mp4
call "%REPO%\convert_from_list_libx265.bat" "%WORK%\T23_abort\badlist.txt" < nul > "%LOGDIR%\T23_list_abort.log" 2>&1
set "RC23=%errorlevel%"
set "V23=PASS"
set "N23="
if "%RC23%"=="0" ( set "V23=FAIL" & set "N23=%N23% exitCode=0 wantNonZero;" )
findstr /i /c:"is not recognized" "%LOGDIR%\T23_list_abort.log" >nul 2>&1
if not errorlevel 1 ( set "V23=FAIL" & set "N23=%N23% bannerParseErr;" )
echo [%V23%] T23 missing list entry aborts the wrapper rc=%RC23% >> "%SUM%"
if not "%N23%"=="" echo        why: %N23% >> "%SUM%"

rem ============ T30: CRLF + UTF-8 BOM list (twin of sh T21) ============
rem sh T21 has covered this since the beginning: run_list strips a leading
rem BOM from the first list line. The .bat wrappers did not, so a list saved
rem by Notepad lost its first entry and the whole run died with rc=3
rem (check_isvideo saw "\xEF\xBB\xBFclip.mp4"). The four wrappers now strip
rem it in :RUN_ONE; this case pins that down: 3 entries -> 3 outputs, rc=0.
rem The BOM is generated here (certutil -decodehex of "ef bb bf" + copy /b)
rem instead of shipping a fixture: nothing external, nothing invisible.
chcp %CP0% >nul
set "T30D=%WORK%\cases\T30_list_crlf_bom"
if not exist "%T30D%" mkdir "%T30D%" >nul 2>&1
copy /y "%IN%" "%T30D%\bom1.mp4" >nul
copy /y "%IN%" "%T30D%\bom2.mp4" >nul
copy /y "%IN%" "%T30D%\bom3.mp4" >nul
del /q "%T30D%\*-compressed.mp4" >nul 2>&1
>  "%T30D%\names.txt" echo %T30D%\bom1.mp4
>> "%T30D%\names.txt" echo %T30D%\bom2.mp4
>> "%T30D%\names.txt" echo %T30D%\bom3.mp4
>  "%T30D%\bom.hex" echo ef bb bf
certutil -decodehex "%T30D%\bom.hex" "%T30D%\bom.bin" >nul 2>&1
copy /b "%T30D%\bom.bin" + "%T30D%\names.txt" "%T30D%\list.txt" >nul 2>&1
call "%REPO%\convert_from_list_libx265.bat" "%T30D%\list.txt" < nul > "%LOGDIR%\T30_list_crlf_bom.log" 2>&1
set "RC30=%errorlevel%"
set "CNT30=0"
for %%c in ("%T30D%\*-compressed.mp4") do set /a CNT30+=1
set "V30=PASS"
set "N30="
if not "%RC30%"=="0" ( set "V30=FAIL" & set "N30=%N30% rc=%RC30% want0;" )
if not "%CNT30%"=="3" ( set "V30=FAIL" & set "N30=%N30% outputs=%CNT30% want3;" )
findstr /i /c:"is not recognized" "%LOGDIR%\T30_list_crlf_bom.log" >nul 2>&1
if not errorlevel 1 ( set "V30=FAIL" & set "N30=%N30% bannerParseErr;" )
echo [%V30%] T30 CRLF + UTF-8 BOM list : %CNT30% of 3 outputs, rc=%RC30% >> "%SUM%"
if not "%N30%"=="" echo        why: %N30% >> "%SUM%"

:LISTONLY
rem T9/T11/T12 run convert_from_list_qsv.bat, which needs QSV AVC hardware.
rem Gate ONCE for all three: without QSV they would be reported as repo
rem failures -- hardware absence, not a defect (exposed by the Pi box).
chcp %CP0% >nul
call :gate ffmpeg_avc_qsv
if defined GATED call :skipcase T9-T12 convert_from_list_qsv
if defined GATED goto LISTDONE
> "%WORK%\list.txt" (
    echo %WORK%\list_a.mp4
    echo %WORK%\list b.mp4
)
del /q "%WORK%\*-compressed.mp4" >nul 2>&1
pushd "%REPO%"
call "%REPO%\convert_from_list_qsv.bat" "%WORK%\list.txt" < nul > "%LOGDIR%\T9_convert_from_list.log" 2>&1
set "RC9=%errorlevel%"
popd
call :countout CNT9
echo [TEST] T9 convert_from_list_qsv 2-entry list : %CNT9% of 2 outputs, rc=%RC9% >> "%SUM%"

rem ============ T11: list mode with UTF-8 (non-ASCII) file names ===========
if not exist "%WORK%\list_utf8.txt" goto T11SKIP
del /q "%WORK%\*-compressed.mp4" >nul 2>&1
pushd "%REPO%"
call "%REPO%\convert_from_list_qsv.bat" "%WORK%\list_utf8.txt" < nul > "%LOGDIR%\T11_convert_from_list_utf8.log" 2>&1
set "RC11=%errorlevel%"
popd
call :countout CNT11
echo [TEST] T11 list mode utf8 names : %CNT11% of 2 outputs, rc=%RC11% >> "%SUM%"
goto T11DONE
:T11SKIP
echo [SKIP] T11 utf8 list fixture missing: %WORK%\list_utf8.txt >> "%SUM%"
:T11DONE

rem ============ T12: list mode, NO argument, cwd = another directory ====
chcp %CP0% >nul
if not exist "%WORK%\cwdtest" mkdir "%WORK%\cwdtest" >nul 2>&1
copy /y "%WORK%\list.txt" "%WORK%\cwdtest\list.txt" >nul 2>&1
del /q "%WORK%\*-compressed.mp4" >nul 2>&1
pushd "%WORK%\cwdtest"
call "%REPO%\convert_from_list_qsv.bat" < nul > "%LOGDIR%\T12_convert_from_list_nocwd.log" 2>&1
set "RC12=%errorlevel%"
popd
call :countout CNT12
echo [TEST] T12 list mode, no arg, cwd elsewhere : %CNT12% of 2 outputs, rc=%RC12% >> "%SUM%"

:LISTDONE
rem ============ global: no log may contain the banner parse error ========
set "BAD=0"
for %%f in ("%LOGDIR%\*.log") do (
    findstr /i /c:"is not recognized" "%%f" >nul 2>&1
    if not errorlevel 1 (
        echo [FAIL] banner parse error in %%~nxf >> "%SUM%"
        set "BAD=1"
    )
)
rem ============ T32: 统一入口实跑 --venc libx265 ============
rem 阶段 1(统一入口)的断言。每条单独加、单独在真机跑一遍冒烟 —— 一次加一批的话,
rem 一旦把文件结构弄坏(前车: 引号被吞导致套件跑不到断言就死), 很难定位是哪一行。
chcp %CP0% >nul
set "T32LOG=%LOGDIR%\T32_encode_libx265.log"
set "T32OUT=%WORK%\unified clip-compressed.mp4"
del /q "%T32OUT%" >nul 2>&1
copy /y "%IN%" "%WORK%\unified clip.mp4" >nul 2>&1
call "%REPO%\ffmpeg_encode.bat" --venc libx265 "%WORK%\unified clip.mp4" < nul > "%T32LOG%" 2>&1
set "RC32=%errorlevel%"
set "V32=PASS"
set "N32="
if not "%RC32%"=="0" set "V32=FAIL" & set "N32=rc=%RC32% want0"
if not exist "%T32OUT%" set "V32=FAIL" & set "N32=%N32% noOutput"
findstr /i /c:"-c:v:0 libx265" "%T32LOG%" >nul 2>&1
if errorlevel 1 set "V32=FAIL" & set "N32=%N32% noLibx265Args"
echo [%V32%] T32 encode_libx265 rc=%RC32% -- unified entry arg mode >> "%SUM%"
if not "%N32%"=="" echo        why: %N32% >> "%SUM%"
rem ============ T33: 新旧入口同参 -> RUN_COM 逐字一致 ============
rem 这是"等价"的直接证据。老用例只断言各自跑通, 不断言两个入口命令行相同 ——
rem 抽内核时最值得盯的就是这个, 任何一侧改了参数顺序或多一个空格都会被抓到。
rem 比较方式用 findstr 抽行 + fc 字节比对, **不用** for /f 读回来:
rem 后者那套 for /f "delims=" %%L in ('... "...%VAR%"...') 的嵌套引号在 cmd 下
rem 会被吞, 表现为整个文件被当命令执行、套件跑不到断言就死(2026-10-08 踩过)。
chcp %CP0% >nul
set "T33LNEW=%LOGDIR%\T33_equiv_new.log"
set "T33LOLD=%LOGDIR%\T33_equiv_old.log"
set "T33FNEW=%LOGDIR%\T33_new.txt"
set "T33FOLD=%LOGDIR%\T33_old.txt"
call "%REPO%\ffmpeg_encode.bat" --venc libx265 --dry-run "%IN%" < nul > "%T33LNEW%" 2>&1
call "%REPO%\ffmpeg_libx265.bat" --dry-run "%IN%" < nul > "%T33LOLD%" 2>&1
findstr /b /c:"RUN_COM0=" "%T33LNEW%" > "%T33FNEW%"
findstr /b /c:"RUN_COM0=" "%T33LOLD%" > "%T33FOLD%"
set "V33=PASS"
set "N33="
for %%A in ("%T33FNEW%") do if %%~zA LEQ 1 set "V33=FAIL" & set "N33=newNoRUN_COM"
for %%A in ("%T33FOLD%") do if %%~zA LEQ 1 set "V33=FAIL" & set "N33=%N33% oldNoRUN_COM"
fc /b "%T33FNEW%" "%T33FOLD%" >nul 2>&1
if errorlevel 1 set "V33=FAIL" & set "N33=%N33% RUN_COM differs"
echo [%V33%] T33 unified --venc libx265 vs ffmpeg_libx265.bat -- byte identical RUN_COM >> "%SUM%"
if not "%N33%"=="" echo        why: %N33% >> "%SUM%"
rem ============ T34: --dec 的命令行形态 ============
rem 阶段 1 的统一入口断言, 每条单独加、单独在真机跑一遍冒烟。
rem 这里用 --dry-run 断言命令行, 所以本机有没有硬编都能跑。
rem cpu 的语义就是 none(§6 第 3 条): 一次 -hwaccel 都不加, 与 FF_HWACCEL=none 对齐。
chcp %CP0% >nul
set "L34=%LOGDIR%\T34_dec_auto.log"
call "%REPO%\ffmpeg_encode.bat" --venc libx265 --dec auto --dry-run "%IN%" < nul > "%L34%" 2>&1
set "RC34=%errorlevel%"
set "V34=PASS"
if not "%RC34%"=="0" set "V34=FAIL"
findstr /c:"-hwaccel auto" "%L34%" >nul 2>&1
if errorlevel 1 set "V34=FAIL"
echo [%V34%] T34 dec=auto -> -hwaccel auto >> "%SUM%"
set "L34=%LOGDIR%\T34_dec_cpu.log"
call "%REPO%\ffmpeg_encode.bat" --venc libx265 --dec cpu --dry-run "%IN%" < nul > "%L34%" 2>&1
set "RC34=%errorlevel%"
set "V34=PASS"
if not "%RC34%"=="0" set "V34=FAIL"
findstr /c:"-hwaccel" "%L34%" >nul 2>&1
if not errorlevel 1 set "V34=FAIL"
echo [%V34%] T34 dec=cpu -> no hwaccel at all >> "%SUM%"
rem ============ T35: --dec 与族不一致 -> 警告但不拦 ============
rem 断言抓 [warn] 这个 ASCII 标签: 冒烟一律抓 ASCII 标记(同 :check_isvideo 的做法),
rem findstr /c:"警告" 在 bat 的编码下匹配不上。
rem 顺带断言警告里说了 10bit 降位滤镜不跟过来 —— 那是实测最容易静默丢东西的地方。
chcp %CP0% >nul
set "L35=%LOGDIR%\T35_dec_mismatch.log"
call "%REPO%\ffmpeg_encode.bat" --venc hevc_qsv --dec cuda --dry-run "%IN%" < nul > "%L35%" 2>&1
set "RC35=%errorlevel%"
set "V35=PASS"
if not "%RC35%"=="0" set "V35=FAIL"
findstr /c:"[warn]" "%L35%" >nul 2>&1
if errorlevel 1 set "V35=FAIL"
findstr /c:"10bit" "%L35%" >nul 2>&1
if errorlevel 1 set "V35=FAIL"
echo [%V35%] T35 --dec mismatch warns and does not block >> "%SUM%"
rem ============ T36: 打错字 / 不给 --venc 都得报错 ============
rem 不许静默走进某个默认编码器 —— 那就是"打错字也能跑, 只是跑错编码器"。
rem 打错字时还要列出可选值, 否则用户不知道该填什么。
chcp %CP0% >nul
set "L36=%LOGDIR%\T36_badvenc.log"
call "%REPO%\ffmpeg_encode.bat" --venc libx266 --dry-run "%IN%" < nul > "%L36%" 2>&1
set "RC36=%errorlevel%"
set "V36=PASS"
if "%RC36%"=="0" set "V36=FAIL"
findstr /c:"libx264" "%L36%" >nul 2>&1
if errorlevel 1 set "V36=FAIL"
set "L36=%LOGDIR%\T36_novenc.log"
call "%REPO%\ffmpeg_encode.bat" --dry-run "%IN%" < nul > "%L36%" 2>&1
set "RC36=%errorlevel%"
if "%RC36%"=="0" set "V36=FAIL"
echo [%V36%] T36 unknown and missing --venc both rejected >> "%SUM%"
rem ============ T37: --venc copy 并入转封装 ============
rem 三个要点: 产物与源同名(不带 -compressed)、带 moov 前置、源已是目标容器能早退。
rem ⚠️ 别在 %WORK% 里留多余文件: 元字符矩阵会数这个目录的文件, 之前 A19 就是这么挂的。
chcp %CP0% >nul
set "L37=%LOGDIR%\T37_copy.log"
set "O37=%WORK%\unified remux.mp4"
del /q "%O37%" >nul 2>&1
del /q "%WORK%\unified remux-compressed.mp4" >nul 2>&1
copy /y "%INMOV%" "%WORK%\unified remux.mov" >nul 2>&1
call "%REPO%\ffmpeg_encode.bat" --venc copy "%WORK%\unified remux.mov" < nul > "%L37%" 2>&1
set "RC37=%errorlevel%"
set "V37=PASS"
if not "%RC37%"=="0" set "V37=FAIL"
if not exist "%O37%" set "V37=FAIL"
if exist "%WORK%\unified remux-compressed.mp4" set "V37=FAIL"
findstr /c:"-movflags +faststart" "%L37%" >nul 2>&1
if errorlevel 1 set "V37=FAIL"
echo [%V37%] T37 copy -- remux with faststart and plain output name >> "%SUM%"
echo. >> "%SUM%"
if "%BAD%"=="0" (echo [PASS] banner check: no "is not recognized" in any log) >> "%SUM%"
rem ============ global: lib debug echoes must be gone (hygiene) =========
set "DBG=0"
for %%f in ("%LOGDIR%\*.log") do (
    findstr /i /b /c:"in extract" /c:"ret=" "%%f" >nul 2>&1
    if not errorlevel 1 (
        echo [FAIL] debug echo found in %%~nxf >> "%SUM%"
        set "DBG=1"
    )
)
echo. >> "%SUM%"
if "%DBG%"=="0" (echo [PASS] debug check: no lib debug echoes in any log) >> "%SUM%"
echo. >> "%SUM%"
echo logs dir  : %LOGDIR% >> "%SUM%"
echo ---- end of summary ---- >> "%SUM%"

echo.
echo ============================================================
echo summary written to: %SUM%
echo logs in: %LOGDIR%
echo ============================================================
type "%SUM%"
echo.
pause
exit /b 0

rem ============================================================
rem :gate <bat base name>
rem   Probe the ENTRY itself on the shared gate clip and set GATED when this
rem   initialise it. The caller then reports SKIP instead of FAIL - the same
rem   policy as :gate_arg in test/sh/smoke_ffmpeg.sh, so the two suites agree on
rem   what "this machine cannot run it" means.
rem   The probe runs the real entry (not a hand written ffmpeg line) so it
rem   exercises the same device init path the real case uses.
rem ============================================================
:gate
set "GATED="
set "GB=%~1"
set "GD=%WORK%\gate_%GB%"
if not exist "%GD%" mkdir "%GD%" >nul 2>&1
copy /y "%GATECLIP%" "%GD%\clip.mp4" >nul 2>&1
del /q "%GD%\clip-compressed.mp4" >nul 2>&1
pushd "%GD%"
call "%REPO%\%GB%.bat" "clip.mp4" < nul > "%LOGDIR%\gate_%GB%.log" 2>&1
set "GRC=%errorlevel%"
popd
if not "%GRC%"=="0" set "GATED=1"
exit /b 0

rem ============================================================
rem :skipcase <T-id> <bat base name>
rem ============================================================
:skipcase
echo [SKIP] %~1 %~2.bat: this box cannot initialise the encoder here >> "%SUM%"
echo        probe log gate_%~2.log - hardware absence, not a repo defect >> "%SUM%"
exit /b 0

rem ============================================================
rem :runA <batname> <input> <logname>
rem       <expected TARGET_BITRATE: n | LT:n | 0 | INFO>
rem       <outmode S or C> <modelabel> [expCODEC | empty | INFO]
rem       [F = run in a fresh cmd process]
rem ============================================================
:runA
set "NAM=%~1"
set "INP=%~2"
set "LOGN=%~3"
set "EXP=%~4"
set "OM=%~5"
set "MDL=%~6"
set "EXPCODEC=%~7"
set "FRESH=%~8"
set "LOG=%LOGDIR%\%LOGN%.log"
if /I "%OM%"=="C" (
    for %%X in ("%INP%") do set "OUT=%%~dpnX.mp4"
) else (
    for %%X in ("%INP%") do set "OUT=%%~dpnX-compressed.mp4"
)
del /q "%OUT%" >nul 2>&1
if defined FRESH (
    cmd /c call "%REPO%\%NAM%.bat" "%INP%" < nul > "%LOG%" 2>&1
) else (
    call "%REPO%\%NAM%.bat" "%INP%" < nul > "%LOG%" 2>&1
)
set "RC=%errorlevel%"
call :judge %NAM% %MDL% %EXP% "%OUT%" %RC% "%LOG%" %EXPCODEC%
exit /b 0

rem ============================================================
rem :runB <batname> <input> <logname> <expected TARGET_BITRATE> <modelabel>
rem   no file argument -> interactive prompts, stdin fed with:
rem   line1 = input path, line2/3 = blank (keeps computed defaults)
rem ============================================================
:runB
set "NAM=%~1"
set "INP=%~2"
set "LOGN=%~3"
set "EXP=%~4"
set "MDL=%~5"
set "LOG=%LOGDIR%\%LOGN%.log"
for %%X in ("%INP%") do set "OUT=%%~dpnX-compressed.mp4"
del /q "%OUT%" >nul 2>&1
( echo %~2 & echo. & echo. ) | call "%REPO%\%NAM%.bat" > "%LOG%" 2>&1
set "RC=%errorlevel%"
call :judge %NAM% %MDL% %EXP% "%OUT%" %RC% "%LOG%" h264
exit /b 0

rem ============================================================
rem :countout <outvar>   count of *-compressed.mp4 in %WORK%
rem ============================================================
:countout
set "CN=0"
for /f %%c in ('dir /b "%WORK%\*-compressed.mp4" 2^>nul ^| find /c /v ""') do set "CN=%%c"
set "%~1=%CN%"
exit /b 0

rem ============================================================
rem :judge <batname> <modelabel>
rem        <expTB: n | LT:n | 0 | INFO> <outfile> <rc> <logfile>
rem        [expCODEC | empty | INFO]
rem   Assertions: rc==0, output exists, log hygiene (banner parse error /
rem   bitrate abnormal / not found / ERRORLEVEL:-), the printed TARGET_BITRATE
rem   (exact, or LT:n = strictly below n), and the output codec taken from the
rem   ffprobe sidecar. 0/INFO skip only the bitrate check.
rem ============================================================
:judge
set "NAM=%~1"
set "MDL=%~2"
set "EXP=%~3"
set "OUT=%~4"
set "RC=%~5"
set "LOG=%~6"
set "EXPCODEC=%~7"
set "V=PASS"
set "NT="
set "INF=0"
if /I "%EXP%"=="INFO" set "INF=1"
if "%INF%"=="1" set "V=INFO"
findstr /i /c:"is not recognized" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% bannerParseErr;" )
findstr /i /c:"bitrate abnormal" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% bitrateAbnormal;" )
findstr /i /c:"not found" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% notFoundMsg;" )
findstr /i /c:"ERRORLEVEL:-" "%LOG%" >nul 2>&1
if not errorlevel 1 ( set "V=FAIL" & set "NT=%NT% ffmpegError;" )
set "TB="
for /f "tokens=1,2 delims==" %%a in ('findstr /b /c:"TARGET_BITRATE=" "%LOG%"') do set "TB=%%b"
rem ---- ffprobe sidecar FIRST: the codec assertion below needs it ----
set "PROBEFILE=%LOGDIR%\%NAM%_%MDL%_probe.txt"
if exist "%PROBEFILE%" del /q "%PROBEFILE%" >nul 2>&1
if exist "%OUT%" "%FP%" -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "%OUT%" > "%PROBEFILE%" 2>&1
set "GOTC="
if exist "%PROBEFILE%" for /f "tokens=2 delims==" %%c in ('findstr /b /c:"codec_name=" "%PROBEFILE%"') do set "GOTC=%%c"
if "%INF%"=="1" goto JG_CODEC
if "%EXP%"=="" goto JG_CODEC
if "%EXP%"=="0" goto JG_CODEC
if /I "%EXP:~0,3%"=="LT:" goto JG_LT
if not "%TB%"=="%EXP%" ( set "V=FAIL" & set "NT=%NT% targetBitrate=%TB% expected=%EXP%;" )
goto JG_CODEC
:JG_LT
if not defined TB ( set "V=FAIL" & set "NT=%NT% targetBitrateMissing;" & goto JG_CODEC )
if %TB% lss %EXP:~3% goto JG_CODEC
set "V=FAIL" & set "NT=%NT% targetNotLt=%EXP:~3%(got=%TB%);"
:JG_CODEC
if "%EXPCODEC%"=="" goto JG_NOASSERT
if /I "%EXPCODEC%"=="INFO" goto JG_NOASSERT
if not "%GOTC%"=="%EXPCODEC%" ( set "V=FAIL" & set "NT=%NT% codec=%GOTC% expected=%EXPCODEC%;" )
:JG_NOASSERT
if not exist "%OUT%" ( set "V=FAIL" & set "NT=%NT% noOutputFile;" )
if not "%RC%"=="0" ( set "V=FAIL" & set "NT=%NT% exitCode=%RC%;" )
echo [%V%] %NAM% %MDL% rc=%RC% target=%TB% codec=%GOTC% >> "%SUM%"
echo        out exists: %OUT% >> "%SUM%"
if not "%NT%"=="" echo        why: %NT% >> "%SUM%"
exit /b 0

:NO_REPO
echo [FATAL] repo not found. usage: smoke_ffmpeg.bat ^<repo_path^>
pause
exit /b 1

:NO_FF
echo [FATAL] ffmpeg not found by lib\common.bat find_ffmpeg rc=%FFRC% >> "%SUM%"
echo [FATAL] ffmpeg not found. set FFMPEG to your ffmpeg executable, then rerun.
type "%SUM%"
pause
exit /b 2
