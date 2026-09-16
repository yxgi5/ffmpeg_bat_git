#!/bin/bash
# ============================================================
# smoke_special_chars.sh (v1) - sh-family metacharacter matrix
#
#   1:1 twin of test/bat/smoke_special_chars.bat: same part
#   letters (A / C / B / D / Z) and the same 20 filenames in
#   part A, so a case number means the same thing in both
#   families. ASCII only, LF.
#
#   The movie library contains names like "A & B (2020).mp4"
#   and "Tora! Tora! Tora!.mov". cmd treats & ^ ! % ( ) as
#   syntax; bash does not, but it has its own pitfalls around
#   unquoted expansion and word splitting - which is exactly
#   what part Z pins down.
#
#   Deliberate divergences from the .bat twin, all documented:
#   - part C uses ffmpeg_libx264.sh and part B uses
#     convert_from_list_libx265.sh: the software entries, so
#     this suite needs NO hardware anywhere (the .bat twin
#     uses the QSV entries because on Windows that is the
#     always-present encoder on the test boxes).
#   - A07 (caret in the name) is TESTED here, not SKIPped: in
#     sh a caret is just a character. The .bat twin must skip
#     it because CALL re-parses its arguments and doubles the
#     caret before the script ever sees it.
#   - part D is a real PASS here: a redirected file reaches
#     the no-arg branch fine (the .bat twin can only report
#     SKIP for it because of the cp65001 relaunch probe
#     limitation - documented there, not a user-facing bug).
#   - part Z has no cp65001 replicas (Windows-only construct);
#     it instead pins the shell constructs run_list and the
#     suffix logic depend on, so a red result points straight
#     at the construct that broke.
#
# Usage:  bash test/sh/smoke_special_chars.sh
#
# Env knobs:
#   REPO=<path>   repo root; default = two levels up from this script
#   WORK=<dir>    scratch dir; default = ${TMPDIR:-/tmp}/ffmpeg_bat_chars_sh
#   WIPE=0        keep the scratch dir (post-mortem); default 1 = wipe first
#
# Exit code: 0 = all cases passed (SKIP is not a failure)
#            1 = at least one FAIL
#            2 = setup error (repo / ffmpeg / ffprobe / fixture)
# ============================================================
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
W="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_chars_sh}"
# A Windows-form TEMP value ("C:////Users////...") mixes separators once joined with
# "/ffmpeg_bat_chars_sh"; native tools and some safe-delete wrappers cannot
# canonicalise that. Normalise to a pure forward-slash absolute path.
case "$W" in
    *[\\]*) W="$(cygpath -m "$W" 2>/dev/null || printf '%s' "$W" | tr '\\' '/')" ;;
esac
LOG="$W/logs"
SUM="$W/summary.txt"
WIPE="${WIPE:-1}"

FF="$(command -v ffmpeg || true)"
FP="$(command -v ffprobe || true)"

# ---------- setup guards ----------
if [ ! -f "$REPO/lib/common.sh" ]; then
    echo "FATAL: repo not found at $REPO (expected $REPO/lib/common.sh)" >&2
    exit 2
fi
if [ -z "$FF" ] || [ -z "$FP" ]; then
    echo "FATAL: ffmpeg/ffprobe not on PATH" >&2
    exit 2
fi
[ "$WIPE" = "1" ] && rm -rf "$W"
mkdir -p "$W" "$W/chars" "$W/chars/sub & dir (x)" "$W/chars/lst" "$LOG"

PASS=0; FAIL=0; SKIPN=0

say() { echo "$@" | tee -a "$SUM"; }

{
    echo "==== ffmpeg_bat_git sh special-character smoke v1 ===="
    echo "date    : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "host    : $(hostname 2>/dev/null) ($(uname -srm))"
    echo "repo    : $REPO"
    echo "ffmpeg  : $("$FF" -hide_banner -version | head -1)"
    echo "shell   : $BASH_VERSION"
    echo
} > "$SUM"

# ---------- fixtures (320x240: NVENC-class entries refuse smaller, and the
# min-size rule must hold for every fixture in this repo, not just the
# hardware ones - see test/README.md) ----------
mk_base() {
    "$FF" -hide_banner -loglevel error \
        -f lavfi -i "testsrc2=size=320x240:rate=10" \
        -f lavfi -i "sine=frequency=440:sample_rate=44100" \
        -t 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -y "$1"
}
BASE_MP4="$W/base.mp4"
BASE_MOV="$W/base.mov"
[ -f "$BASE_MP4" ] || mk_base "$BASE_MP4" || { echo "FATAL: fixture generation failed" >&2; exit 2; }
[ -f "$BASE_MOV" ] || cp -f "$BASE_MP4" "$BASE_MOV"

CDIR="$W/chars"

# ---------- helpers ----------
probe_codec() {   # probe_codec <file> -> codec_name or none
    [ -f "$1" ] || { echo "NOFILE"; return; }
    local c
    c=$("$FP" -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | tr -d '\r')
    echo "${c:-none}"
}

check_hyg() {   # check_hyg <log> -> "findings;" or empty
    local f="$1" hits=""
    grep -aq "command not found" "$f" && hits="$hits commandNotFound;"
    grep -aqE "syntax error|^bash: line" "$f" && hits="$hits shellSyntaxErr;"
    echo "$hits"
}

# runA <idx> <name>   : part A - remux through ffmpeg_copy_to_mp4.sh
runA() {
    local idx="$1" name="$2"
    local src="$CDIR/$name"
    local expect="$CDIR/${name%.*}.mp4"
    cp -f "$BASE_MOV" "$src" 2>/dev/null
    if [ ! -f "$src" ]; then
        say "[SETUP-FAIL] A$idx \"$name\"  could not create test file"
        FAIL=$((FAIL+1)); return
    fi
    rm -f "$expect"
    local logf="$LOG/A$idx.log" rc
    bash "$REPO/ffmpeg_copy_to_mp4.sh" "$src" > "$logf" 2>&1
    rc=$?
    local v="FAIL" why
    [ -f "$expect" ] && v="PASS"
    if [ "$v" = "PASS" ]; then
        why="$(check_hyg "$logf")"
        [ -n "$why" ] && { v="FAIL"; }
    fi
    if [ "$v" = "PASS" ]; then
        PASS=$((PASS+1)); say "[PASS] A$idx rc=$rc \"$name\""
    else
        FAIL=$((FAIL+1)); say "[FAIL] A$idx rc=$rc \"$name\""
        sed 's/^/       | /' "$logf" | tail -5 >> "$SUM"
    fi
}

# runC <idx> <name>   : part C - full encode through ffmpeg_libx264.sh
runC() {
    local idx="$1" name="$2"
    local src="$CDIR/$name"
    local expect="$CDIR/${name%.*}-compressed.mp4"
    cp -f "$BASE_MP4" "$src" 2>/dev/null
    if [ ! -f "$src" ]; then
        say "[SETUP-FAIL] C$idx \"$name\"  could not create test file"
        FAIL=$((FAIL+1)); return
    fi
    rm -f "$expect"
    local logf="$LOG/C$idx.log" rc codec why
    bash "$REPO/ffmpeg_libx264.sh" "$src" > "$logf" 2>&1
    rc=$?
    local v="FAIL"
    if [ -f "$expect" ]; then
        codec="$(probe_codec "$expect")"
        why="$(check_hyg "$logf")"
        if [ "$codec" = "h264" ] && [ -z "$why" ]; then v="PASS"; fi
    fi
    if [ "$v" = "PASS" ]; then
        PASS=$((PASS+1)); say "[PASS] C$idx rc=$rc codec=$codec \"$name\""
    else
        FAIL=$((FAIL+1)); say "[FAIL] C$idx rc=$rc codec=${codec:-none} \"$name\""
        sed 's/^/       | /' "$logf" | tail -5 >> "$SUM"
    fi
}

# ============================================================
# part A: metacharacter matrix (same 20 names as the .bat twin)
# ============================================================
say ""
say "---- part A: one file straight through ffmpeg_copy_to_mp4 ----"
echo "[part A] 20 filename cases ..."
runA 01 "smoke_plain.mov"
runA 02 "smoke_amp & test.mov"
runA 03 "smoke_pct 100% test.mov"
runA 04 "smoke_bang ! test.mov"
runA 05 "smoke_paren (1).mov"
runA 06 "smoke_brk [x].mov"
# A07: the .bat twin SKIPs this (CALL re-parses its arguments and doubles
# the caret); in sh a caret is an ordinary filename character -> real case.
runA 07 "smoke_caret ^^ test.mov"
runA 08 "smoke_semi ; test.mov"
runA 09 "smoke_comma , test.mov"
runA 10 "smoke_eq a=b.mov"
runA 11 "smoke_sharp #.mov"
runA 12 "smoke_dollar $.mov"
runA 13 "smoke_plus +.mov"
runA 14 "smoke_tick '.mov"
runA 15 "smoke_tilde ~.mov"
runA 16 "smoke_at @.mov"
runA 17 "smoke_real A & B (2020).mov"
runA 18 "smoke_real2 Tora! Tora! Tora! (1970).mov"
runA 19 "smoke_extreme A&B!C(2) 100%.mov"
runA 20 "sub & dir (x)/smoke_subdir.mov"

# ============================================================
# part C: full encoder (libx264, hardware-free by design)
# ============================================================
say ""
say "---- part C: full encode path (ffmpeg_libx264) ----"
echo "[part C] full encoder cases ..."
runC 81 "smoke_real A & B (2020).mp4"
runC 82 "smoke_real2 Tora! Tora! Tora! (1970).mp4"
runC 83 "smoke_extreme A&B!C(2) 100%.mp4"

# ============================================================
# part B: list driven (convert_from_list_libx265, hardware-free)
# ============================================================
say ""
say "---- part B: list driven (convert_from_list_libx265) ----"
echo "[part B] list mode ..."
LDST="$CDIR/lst"
for n in "smoke_plain.mov" "smoke_amp & test.mov" "smoke_bang ! test.mov" \
         "smoke_paren (1).mov" "smoke_real A & B (2020).mov" "smoke_plain & noext.mov"; do
    cp -f "$BASE_MOV" "$LDST/$n"
done
LF="$W/list_chars.txt"
: > "$LF"
printf '%s\n' "$LDST/smoke_plain.mov"               >> "$LF"
printf '%s\n' "$LDST/smoke_amp & test.mov"          >> "$LF"
printf '%s\n' "$LDST/smoke_bang ! test.mov"         >> "$LF"
printf '%s\n' "$LDST/smoke_paren (1).mov"           >> "$LF"
printf '%s\n' "$LDST/smoke_real A & B (2020).mov"   >> "$LF"
printf '%s\n' "$LDST/smoke_plain & noext.mov"       >> "$LF"
BLOG="$LOG/B0_list.log"
rm -f "$LDST"/*-compressed.mp4
bash "$REPO/convert_from_list_libx265.sh" "$LF" > "$BLOG" 2>&1
BRC=$?
BOK=0
for n in "smoke_plain" "smoke_amp & test" "smoke_bang ! test" "smoke_paren (1)" \
         "smoke_real A & B (2020)" "smoke_plain & noext"; do
    [ -f "$LDST/$n-compressed.mp4" ] && BOK=$((BOK+1))
done
if [ "$BRC" -eq 0 ] && [ "$BOK" -eq 6 ]; then
    PASS=$((PASS+1)); say "[PASS] B0 list mode 6 metachar entries  (outputs=$BOK/6)"
else
    FAIL=$((FAIL+1)); say "[FAIL] B0 list mode  outputs=$BOK/6 rc=$BRC"
    sed 's/^/       | /' "$BLOG" | tail -6 >> "$SUM"
fi

# ============================================================
# part D: no-argument mode, path from stdin
# (the .bat twin can only SKIP this - file-redirected stdin
#  plus its cp65001 relaunch is a probe limitation there; on
#  sh the redirect genuinely reaches the read, so this is a
#  real assertion, not an observation)
# ============================================================
say ""
say "---- part D: no-argument mode, path from stdin ----"
echo "[part D] no-argument mode ..."
DLOG="$LOG/D0_noarg.log"
DNAME="smoke_amp & test stdin.mov"   # own name: the expected output must not collide with part A02's
DEXPECT="$CDIR/${DNAME%.*}.mp4"
cp -f "$BASE_MOV" "$CDIR/$DNAME"   # part D builds its own input (its name differs from part A's)
rm -f "$DEXPECT"
printf '%s\n' "$CDIR/$DNAME" | bash "$REPO/ffmpeg_copy_to_mp4.sh" > "$DLOG" 2>&1
DRC=$?
if [ -f "$DEXPECT" ] && [ "$DRC" -eq 0 ]; then
    PASS=$((PASS+1)); say "[PASS] D0 no-argument rc=$DRC  (metachar path fed over stdin)"
else
    FAIL=$((FAIL+1)); say "[FAIL] D0 no-argument rc=$DRC"
    sed 's/^/       | /' "$DLOG" | tail -5 >> "$SUM"
fi

# ============================================================
# part Z: construct micro-tests
# If part A/C/B still shows red, these pin the failure on one
# shell construct instead of leaving you to guess. They assert
# the constructs run_list and the suffix logic depend on - the
# sh analogue of the .bat twin's set-form replicas (cp65001
# guard replicas have no sh counterpart: Windows-only).
# ============================================================
say ""
say "---- part Z: construct micro-tests ----"
echo "[part Z] construct micro-tests ..."

# Z1: the "${name%.*}" suffix strip and "${name##*/}" basename split must
#     survive a value carrying & ( ) ! % ' spaces - every entry derives its
#     output name this way. (sh analogue of the .bat twin's Z1 set-form test.)
ZN="A & B (c) 100%!' x.mov"
Z1V="FAIL"
if [ "${ZN%.*}" = "A & B (c) 100%!' x" ] && [ "${ZN##*/}" = "$ZN" ]; then
    Z1V="PASS"
fi
say "[$Z1V] Z1 suffix-strip construct keeps a metachar value (\"$ZN\")"

# Z2: "while IFS= read -r" must hand run_list the entry byte-for-byte -
#     unquoted/IFS-mangled reads are the classic way these paths break.
Z2V="FAIL"
Z2GOT="$(printf '%s\n' "$ZN" | while IFS= read -r line; do printf '%s' "$line"; done)"
if [ "$Z2GOT" = "$ZN" ]; then Z2V="PASS"; fi
say "[$Z2V] Z2 while IFS= read -r round-trips a metachar list entry"

# Z3: backslash is a legal filename character on Linux but forbidden by the
#     Windows filesystem, so the .bat twin can never test it. Create it when
#     the filesystem allows; SKIP where it does not (Windows, always).
Z3SRC="$CDIR/smoke_back \\ slash.mov"
Z3V="SKIP"
cp -f "$BASE_MOV" "$Z3SRC" 2>/dev/null && Z3V="SETUP-OK"
if [ "$Z3V" = "SETUP-OK" ]; then
    Z3EXP="$CDIR/smoke_back \\ slash.mp4"
    rm -f "$Z3EXP"
    Z3LOG="$LOG/Z3_backslash.log"
    bash "$REPO/ffmpeg_copy_to_mp4.sh" "$Z3SRC" > "$Z3LOG" 2>&1
    Z3RC=$?
    if [ -f "$Z3EXP" ] && [ "$Z3RC" -eq 0 ]; then Z3V="PASS"; else Z3V="FAIL"; fi
    if [ "$Z3V" = "PASS" ]; then
        say "[PASS] Z3 backslash in filename (legal on Linux, impossible on Windows)"
    else
        FAIL=$((FAIL+1)); say "[FAIL] Z3 backslash in filename rc=$Z3RC"
        sed 's/^/       | /' "$Z3LOG" | tail -5 >> "$SUM"
    fi
else
    SKIPN=$((SKIPN+1))
    say "[SKIP] Z3 backslash in filename - this filesystem refuses to create it (Windows/MSYS2)"
fi
if [ "$Z1V" = "PASS" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
if [ "$Z2V" = "PASS" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---------- global hygiene: no log may carry a shell error ----------
BADN=0
for f in "$LOG"/*.log; do
    [ -f "$f" ] || continue
    H="$(check_hyg "$f")"
    if [ -n "$H" ]; then say "[FAIL] hygiene ($H) in $(basename "$f")"; BADN=$((BADN+1)); fi
done
if [ "$BADN" -eq 0 ]; then
    PASS=$((PASS+1)); say "[PASS] hygiene check: no 'command not found' / 'syntax error' in any log"
else
    FAIL=$((FAIL+1))
fi

# ---------- summary + exit code ----------
say ""
say "============================================================"
say "sh special-character smoke v1: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIPN   ffmpeg=$("$FF" -hide_banner -version | head -1 | awk '{print $3}')"
say "logs: $LOG"
say "============================================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
