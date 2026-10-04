#!/bin/bash
# ============================================================
# smoke_dvd_tools.sh (v1) - tools/ 下五个 DVD 脚本的端到端冒烟
#
#   为什么单独一套: tools/ 那五个脚本吃的是"DVD 结构"(ISO / VIDEO_TS),
#   smoke_ffmpeg.sh 那套吃的是"视频文件", 两边输入形态都不一样,
#   硬塞进 T1-T25 只会让编号含义打架。
#
#   被测链路(每一步的依赖都是上一步的产物, 所以顺序固定):
#     D01 dvd_make_sample  造一张**已知规格**的盘(2 title x 30s x 3 章节)
#         —— 拿真盘测的话, 读出来 1682s 你也不确定对不对; 合成盘的期望值是自己定的
#     D03-D08 dvd_repair   体检门三档退出码 0/1/2 + APPLY=1 真修 + 复检 + 逐字节比对
#     D09    dvd_restore   目录 -> 可刻录 ISO(-dvd-video 排序 + UDF)
#     D10    dvd_shrink    真重编码瘦身
#     D11/D12 dvd_to_data_iso  数据盘(不压) / DVD 源(先压 HEVC 再打包)
#     D13/D14 体检门        断号盘必须被 shrink / data_iso 拦下
#     D15/D16 无参调用      给用法、不崩; make_sample 无参的默认目录行为
#
#   刻意没有 .bat 孪生: 这套依赖 dvdauthor + genisoimage/mkisofs,
#   Windows 上基本没有, 孪生过去只会整片 SKIP。等 tools/ 那五个有了
#   .bat 版本再一起补(到时按 test/README 的一一对应约定命名)。
#
# Usage:  bash test/sh/smoke_dvd_tools.sh
#
# Env knobs:
#   REPO=<path>   repo root; default = two levels up from this script
#   WORK=<dir>    scratch dir; default = ${TMPDIR:-/tmp}/ffmpeg_bat_dvd_sh
#   WIPE=0        keep the scratch dir (post-mortem); default 1 = wipe first
#   DUR / TITLES_N / SCENE   样例盘的时长 / title 数 / 场景间隔秒
#
# Exit code: 0 = all cases passed (SKIP is not a failure)
#            1 = at least one FAIL
#            2 = setup error (repo / ffmpeg / ffprobe)
# ============================================================
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
W="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_dvd_sh}"
LOG="$W/logs"
SUM="$W/summary.txt"
WIPE="${WIPE:-1}"
DUR="${DUR:-30}"
TITLES_N="${TITLES_N:-2}"
SCENE="${SCENE:-10}"

FF="$(command -v ffmpeg || true)"
FP="$(command -v ffprobe || true)"
# 能力探针要和脚本同口径: 脚本走 find_ffmpeg(挑得出带 dvdvideo 的那份), 这里若只看
# PATH 第一个就会低估本机能力 —— 2026-09-30 实测 Cygwin PATH 首份 7.1.1 没有 libx265,
# D12 因此被误判成 SKIP, 而脚本真跑时用的是 gyan 那份(有 libx265)。
if [ -f "$REPO/lib/common.sh" ]; then
    . "$REPO/lib/common.sh" >/dev/null 2>&1
    # 带 --need-demuxer dvdvideo: 与 dvd_to_data_iso / dvd_shrink 的挑选口径一致
    # (裸 find_ffmpeg 会挑回 PATH 首份, Cygwin 下那是 7.1.1, 没有 libx265, D12 会误 SKIP)
    _ff="$(find_ffmpeg --need-demuxer dvdvideo 2>/dev/null)"; [ -n "${_ff:-}" ] && FF="$_ff"
    _fp="$(find_ffprobe "$FF" 2>/dev/null)"; [ -n "${_fp:-}" ] && FP="$_fp"
fi

# 统一 --help / -help / -h: 与 .bat 孪生同一套版式(见 lib/common.sh 的 ff_usage_block)
# 放在这段 if 之后: common.sh 只在 if 里被 source, 守卫必须排在它后面。
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" -- \
    "smoke_dvd_tools.sh  -  tools/ 那几个 DVD 脚本的端到端冒烟" \
    "用法: bash test/sh/smoke_dvd_tools.sh [仓库路径]" \
    "造一张已知规格的样例盘, 走体检门 -> 修复 -> restore / shrink / data_iso 出盘, 并断言断号盘一定被体检门拦下; 需要 dvdauthor + genisoimage, 缺工具链时整段 SKIP" || :

# ---------- setup guards ----------
if [ ! -f "$REPO/lib/common.sh" ]; then
    echo "FATAL: repo not found at $REPO (expected $REPO/lib/common.sh)" >&2
    exit 2
fi
if [ -z "$FF" ] || [ -z "$FP" ]; then
    echo "FATAL: ffmpeg/ffprobe not on PATH" >&2
    exit 2
fi
# 与另两个套件同口径: 开跑前在屏幕上报出 ffmpeg / ffprobe 路径与版本。
ff_report "$FF" "$FP"
[ "$WIPE" = "1" ] && rm -rf "$W"
mkdir -p "$W" "$LOG"

PASS=0; FAIL=0; SKIPN=0

say() { printf '%s\n' "$*" | tee -a "$SUM"; }

ok_case()   { PASS=$((PASS+1));  printf '[PASS] %-4s %s\n' "$1" "$2" | tee -a "$SUM"; }
bad_case()  { FAIL=$((FAIL+1));  printf '[FAIL] %-4s %s\n' "$1" "$2" | tee -a "$SUM"; }
skip_case() { SKIPN=$((SKIPN+1)); printf '[SKIP] %-4s %s\n' "$1" "$2" | tee -a "$SUM"; }

# 跑一条命令, 比退出码。期望值写 nonzero 表示"只要非 0 就算对"
# 命令输出全部落到 $LOG/<id>.log, FAIL 时回打最后几行
expect_rc() {
    local id="$1" desc="$2" want="$3"; shift 3
    local logf="$LOG/$id.log" rc
    "$@" > "$logf" 2>&1
    rc=$?
    if { [ "$want" = "nonzero" ] && [ "$rc" -ne 0 ]; } || [ "$rc" = "$want" ]; then
        ok_case "$id" "$desc (rc=$rc)"
    else
        bad_case "$id" "$desc — 期望 rc=$want, 实得 $rc"
        tail -6 "$logf" 2>/dev/null | sed 's/^/         | /' | tee -a "$SUM"
    fi
}

# 断言这些文件都存在且非空
expect_file() {
    local id="$1" desc="$2"; shift 2
    local f miss=""
    for f in "$@"; do [ -s "$f" ] || miss="$miss $f"; done
    if [ -z "$miss" ]; then ok_case "$id" "$desc"
    else bad_case "$id" "$desc — 缺:$miss"; fi
}


say "============================================================"
say " sh dvd-tools smoke v1: tools/ 五个 DVD 脚本端到端"
say "============================================================"
say "ffmpeg : $FF"
say "ffprobe: $FP"
say "版本   : $("$FF" -hide_banner -version 2>/dev/null | awk 'NR==1{print $3; exit}')"
say "repo   : $REPO"
say "work   : $W"
say

# ---------- 依赖盘点: 缺工具链就整段 SKIP(与"无硬件 -> SKIP"同口径) ----------
MISS=""
add_miss() { MISS="${MISS:+$MISS, }$1"; }
command -v dvdauthor >/dev/null 2>&1 || add_miss dvdauthor
if ! command -v genisoimage >/dev/null 2>&1 && ! command -v mkisofs >/dev/null 2>&1; then
    add_miss "genisoimage/mkisofs"
fi
if ! "$FF" -hide_banner -encoders 2>/dev/null | grep -q " mpeg2video "; then
    add_miss "encoder:mpeg2video"
fi
if ! "$FF" -hide_banner -encoders 2>/dev/null | grep -q " ac3 "; then
    add_miss "encoder:ac3"
fi

if [ -n "$MISS" ]; then
    say "[SKIP] 整段跳过: 本机缺 $MISS"
    say "       装法(Debian/Ubuntu): sudo apt install dvdauthor genisoimage"
    say
    say "sh dvd-tools smoke v1: PASS=0  FAIL=0  SKIP=1"
    say "logs: $LOG"
    exit 0
fi

# ============================================================
say "---- D01: 造一张已知规格的样例盘 ----"
expect_rc D01 "dvd_make_sample 造盘(${TITLES_N} title x ${DUR}s, 场景间隔 ${SCENE}s)" 0 \
    env DURATION="$DUR" TITLES="$TITLES_N" SCENE_LEN="$SCENE" LABEL=0 \
    bash "$REPO/tools/dvd_make_sample.sh" "$W/sample"
expect_file D02 "产物齐全(VIDEO_TS.IFO / VTS_01_1.VOB / sample.iso)" \
    "$W/sample/VIDEO_TS/VIDEO_TS.IFO" "$W/sample/VIDEO_TS/VTS_01_1.VOB" "$W/sample.iso"

# ============================================================
say
say "---- D03-D08: dvd_repair 体检门(0 完好 / 1 可修 / 2 补不出来) ----"
expect_rc D03 "完好盘体检 -> 0" 0 \
    env CHECK_ONLY=1 bash "$REPO/tools/dvd_repair.sh" "$W/sample"

cp -r "$W/sample" "$W/broke1" 2>/dev/null
rm -f "$W/broke1/VIDEO_TS/VTS_01_0.BUP"
expect_rc D04 "缺一个 BUP -> 1(可修)" 1 \
    env CHECK_ONLY=1 bash "$REPO/tools/dvd_repair.sh" "$W/broke1"

cp -r "$W/sample" "$W/gap" 2>/dev/null
cp "$W/gap/VIDEO_TS/VTS_01_1.VOB" "$W/gap/VIDEO_TS/VTS_01_3.VOB"
expect_rc D05 "VOB 断号(1、3 在, 2 缺) -> 2(补不出来)" 2 \
    env CHECK_ONLY=1 bash "$REPO/tools/dvd_repair.sh" "$W/gap"

expect_rc D06 "APPLY=1 真修(补 BUP) -> 0" 0 \
    env APPLY=1 bash "$REPO/tools/dvd_repair.sh" "$W/broke1"
expect_rc D07 "修完复检 -> 0" 0 \
    env CHECK_ONLY=1 bash "$REPO/tools/dvd_repair.sh" "$W/broke1"
expect_rc D08 "补出的 BUP 与源 IFO 逐字节相同" 0 \
    cmp -s "$W/broke1/VIDEO_TS/VTS_01_0.BUP" "$W/sample/VIDEO_TS/VTS_01_0.IFO"

# ============================================================
say
say "---- D09-D12: restore / shrink / data_iso 三条出盘路径 ----"
expect_rc D09 "dvd_restore 目录 -> ISO" 0 \
    bash "$REPO/tools/dvd_restore.sh" "$W/broke1" "$W/restore.iso"
expect_file D09b "restore 出了 ISO" "$W/restore.iso"

expect_rc D10 "dvd_shrink 真瘦身(TARGET_MB=200)" 0 \
    env TARGET_MB=200 bash "$REPO/tools/dvd_shrink.sh" "$W/sample.iso" "$W/shrunk.iso"
expect_file D10b "shrink 出了 ISO" "$W/shrunk.iso"

mkdir -p "$W/plain"
printf 'fake hevc archive payload' > "$W/plain/movie.mkv"
expect_rc D11 "dvd_to_data_iso 普通目录(不压) -> 数据盘 ISO" 0 \
    bash "$REPO/tools/dvd_to_data_iso.sh" "$W/plain" "$W/plain.iso"
expect_file D11b "data_iso 出了 ISO" "$W/plain.iso"

if "$FF" -hide_banner -encoders 2>/dev/null | grep -q " libx265 "; then
    expect_rc D12 "dvd_to_data_iso 走 DVD 源(先压 HEVC 再打包)" 0 \
        env VENC=libx265 bash "$REPO/tools/dvd_to_data_iso.sh" "$W/sample.iso" "$W/hevc.iso"
    expect_file D12b "HEVC 归档盘出了 ISO" "$W/hevc.iso"
else
    skip_case D12 "dvd_to_data_iso 压 HEVC — 本机 ffmpeg 没有 libx265"
    skip_case D12b "同上"
fi

# ============================================================
say
say "---- D13-D14: 断号盘必须被体检门拦下 ----"
expect_rc D13 "dvd_shrink 遇断号 -> 拦下(非 0)" nonzero \
    bash "$REPO/tools/dvd_shrink.sh" "$W/gap" "$W/gap_shrunk.iso"
expect_rc D14 "dvd_to_data_iso 遇断号 -> 拦下(非 0)" nonzero \
    bash "$REPO/tools/dvd_to_data_iso.sh" "$W/gap" "$W/gap_data.iso"

# ============================================================
say
say "---- D15-D16: 无参调用 ----"
# 只在需要参数的四个上验(rc=1 + 打用法); make_sample 无参是合法用法, 单列 D16
noarg_bad=0
for t in dvd_repair.sh dvd_restore.sh dvd_shrink.sh dvd_to_data_iso.sh; do
    out="$(bash "$REPO/tools/$t" </dev/null 2>&1)"
    rc=$?
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "用法"; then
        :
    else
        noarg_bad=1
        printf '         | %s rc=%s\n' "$t" "$rc" | tee -a "$SUM"
    fi
done
if [ "$noarg_bad" -eq 0 ]; then
    ok_case D15 "四个脚本无参 -> rc=1 且打了用法"
else
    bad_case D15 "无参调用不符预期"
fi

# make_sample 无参会在**当前目录**建 dvd_sample/ —— 必须把它关在 WORK 里跑,
# 否则就在仓库根留下一堆未跟踪产物(2026-09-30 实测踩过)
mkdir -p "$W/noarg"
expect_rc D16 "dvd_make_sample 无参 -> 默认目录(在 WORK 里跑, 不脏仓库)" 0 \
    env DURATION=10 TITLES=1 SCENE_LEN=10 LABEL=0 bash -c "cd \"$W/noarg\" && bash \"$REPO/tools/dvd_make_sample.sh\""
expect_file D16b "无参默认落 dvd_sample/" "$W/noarg/dvd_sample/VIDEO_TS/VIDEO_TS.IFO"

# ============================================================
say
say "---- D17: 日志卫生 ----"
if grep -rlE "command not found|syntax error|No such file or directory: .*tools/" "$LOG" >/dev/null 2>&1; then
    bad_case D17 "日志里出现 command not found / syntax error"
    grep -rlE "command not found|syntax error" "$LOG" | head -5 | sed 's/^/         | /' | tee -a "$SUM"
else
    ok_case D17 "日志里没有 command not found / syntax error"
fi

say
say "============================================================"
say " dvd-tools smoke v1: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIPN"
say " logs: $LOG"
say "============================================================"
[ "$FAIL" -ne 0 ] && exit 1
exit 0
