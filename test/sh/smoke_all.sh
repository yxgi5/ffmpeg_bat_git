#!/bin/bash
# ============================================================
# smoke_all.sh (v1) - sh-family combined smoke runner
#
#   1:1 twin of test/bat/smoke_all.bat: one command runs both
#   sh smoke layers against the repo.
#
#   [1/2] smoke_ffmpeg.sh          regression suite T1-T25
#         every encoder entry in arg mode with exact table
#         assertions, list mode, stdin mode, audio-only
#         rejection, the exit-code contract, and hardware
#         gates (a box without the hardware gets SKIP, never
#         FAIL).
#         -> $W/summary.txt   (default /tmp/ffmpeg_bat_smoke_sh)
#
#   [2/3] smoke_special_chars.sh   metacharacter matrix
#         filenames carrying & ( ) ! % ' ^ and friends,
#         list-driven runs, no-arg stdin mode, and construct
#         micro-tests (part Z).
#         -> $W/summary.txt   (default /tmp/ffmpeg_bat_chars_sh)
#
#   [3/3] smoke_dvd_tools.sh        DVD toolchain chain
#         tools/ 那五个脚本: 造一张已知规格的样例盘, 再走
#         体检门(0/1/2) -> 修复 -> restore/shrink/data_iso 出盘,
#         最后断言断号盘一定被体检门拦下。需要 dvdauthor +
#         genisoimage/mkisofs, 缺工具链时整段 SKIP(不算失败)。
#         -> $W/summary.txt   (default /tmp/ffmpeg_bat_dvd_sh)
#
#   Unlike the .bat twin this runner needs no stdin tricks
#   (the .bat one feeds its children from NUL so their final
#   pause does not stall the chain).
#
# Usage:  bash test/sh/smoke_all.sh
#
# Env knobs: REPO / WORK, passed through to both children.
#
# Exit code: 0 = both suites green (SKIP is not a failure)
#            1 = at least one suite failed
#            2 = a suite could not even start (setup error)
# ============================================================
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 统一 --help / -help / -h: 与 .bat 孪生同一套版式。common.sh 是条件加载的
# (这套脚本本来可以脱离仓库单跑), 所以加载失败时守卫静默跳过, 下面的兄弟文件
# 检查照旧报错。
if [ -r "$SELF_DIR/../../lib/common.sh" ]; then
    . "$SELF_DIR/../../lib/common.sh"
fi
declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" -- \
    "smoke_all.sh  -  一条命令跑完 sh 族各层冒烟" \
    "用法: bash test/sh/smoke_all.sh" \
    "依次跑: 回归套件 → 元字符矩阵 → DVD 工具链; 任一层失败整体返回 1, 启动不了返回 2" || :

R1=""; R2=""; R3=""
if [ ! -f "$SELF_DIR/smoke_ffmpeg.sh" ]; then
    echo "[FATAL] smoke_ffmpeg.sh not found next to this file" >&2
    exit 2
fi
if [ ! -f "$SELF_DIR/smoke_special_chars.sh" ]; then
    echo "[FATAL] smoke_special_chars.sh not found next to this file" >&2
    exit 2
fi
if [ ! -f "$SELF_DIR/smoke_dvd_tools.sh" ]; then
    echo "[FATAL] smoke_dvd_tools.sh not found next to this file" >&2
    exit 2
fi

echo "============================================================"
echo " combined smoke: regression suite + special character matrix"
echo "============================================================"
echo

echo "[1/3] regression suite T1-T25 ..."
bash "$SELF_DIR/smoke_ffmpeg.sh" all
R1=$?

echo
echo "[2/3] special character matrix ..."
bash "$SELF_DIR/smoke_special_chars.sh"
R2=$?

echo
echo "[3/3] dvd toolchain chain ..."
bash "$SELF_DIR/smoke_dvd_tools.sh"
R3=$?

echo
echo "============================================================"
echo " all runs finished"
echo " regression suite rc = $R1"
echo " char matrix    rc = $R2"
echo " dvd tools      rc = $R3"
echo "============================================================"
if [ "$R1" -ne 0 ] || [ "$R2" -ne 0 ] || [ "$R3" -ne 0 ]; then exit 1; fi
exit 0
