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
#   [2/2] smoke_special_chars.sh   metacharacter matrix
#         filenames carrying & ( ) ! % ' ^ and friends,
#         list-driven runs, no-arg stdin mode, and construct
#         micro-tests (part Z).
#         -> $W/summary.txt   (default /tmp/ffmpeg_bat_chars_sh)
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

R1=""; R2=""
if [ ! -f "$SELF_DIR/smoke_ffmpeg.sh" ]; then
    echo "[FATAL] smoke_ffmpeg.sh not found next to this file" >&2
    exit 2
fi
if [ ! -f "$SELF_DIR/smoke_special_chars.sh" ]; then
    echo "[FATAL] smoke_special_chars.sh not found next to this file" >&2
    exit 2
fi

echo "============================================================"
echo " combined smoke: regression suite + special character matrix"
echo "============================================================"
echo

echo "[1/2] regression suite T1-T25 ..."
bash "$SELF_DIR/smoke_ffmpeg.sh" all
R1=$?

echo
echo "[2/2] special character matrix ..."
bash "$SELF_DIR/smoke_special_chars.sh"
R2=$?

echo
echo "============================================================"
echo " both runs finished"
echo " regression suite rc = $R1"
echo " char matrix    rc = $R2"
echo "============================================================"
if [ "$R1" -ne 0 ] || [ "$R2" -ne 0 ]; then exit 1; fi
exit 0
