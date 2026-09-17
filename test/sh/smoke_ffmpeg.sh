#!/bin/bash
# ============================================================
# smoke_ffmpeg.sh (v2) - sh-family smoke harness
#
#   PARITY NOTE: this harness is the 1:1 twin of
#   test/bat/smoke_ffmpeg.bat. Cases that exist in both
#   families share the same T-id, the same 1080p60 fixture and
#   the same expected TARGET_BITRATE, so a T-number difference
#   between the two families is a real cross-family divergence.
#   sh-only cases are T8 / T18 / T19 / T20 / T21 / T22 / T23 /
#   T24 / T25 (see test/README.md for the full table).
#
#   Location: <repo>/test/sh/  - the repo root is derived from
#   this script's own path (two levels up), so a clone anywhere
#   works. ASCII only, LF.
#
# Usage:  bash test/sh/smoke_ffmpeg.sh [part]
#         part = all (default) | parity | list | guard
#
# Env knobs:
#   REPO=<path>          repo root; default = two levels up from this script
#   WORK=<dir>           scratch dir; default = ${TMPDIR:-/tmp}/ffmpeg_bat_smoke_sh
#   WIPE=0               keep the scratch dir (post-mortem); default 1 = wipe first
#   FIXTURE=<path>       source clip; auto-generated with lavfi when absent
#   EXPECT_AV1_QSV=auto|ok|fail|skip
#                        auto (default) = probe the hardware with a 1-frame
#                        clip first: unprobeable entries are reported as SKIP,
#                        never FAIL. ok/fail = assert it, skip = never run.
#
# Exit code: 0 = all cases passed (SKIP is not a failure)
#            1 = at least one FAIL
#            2 = setup error (repo / ffmpeg / ffprobe / fixture generation)
# ============================================================
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
W="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_smoke_sh}"
# A Windows-form TEMP value ("C:////Users////...") mixes separators once joined with
# "/ffmpeg_bat_smoke_sh"; native tools and some safe-delete wrappers cannot
# canonicalise that. Normalise to a pure forward-slash absolute path.
case "$W" in
    *[\\]*) W="$(cygpath -m "$W" 2>/dev/null || printf '%s' "$W" | tr '\\' '/')" ;;
esac
LOG="$W/logs"
SUM="$W/summary.txt"
PART="${1:-all}"
EXPECT_AV1_QSV="${EXPECT_AV1_QSV:-auto}"
WIPE="${WIPE:-1}"

FF="$(command -v ffmpeg || true)"
FP="$(command -v ffprobe || true)"

# ---------- setup guards (exit 2 = setup error, not a test failure) ----------
if [ ! -f "$REPO/lib/common.sh" ]; then
    echo "FATAL: repo not found at $REPO (expected $REPO/lib/common.sh)" >&2
    exit 2
fi
if [ -z "$FF" ] || [ -z "$FP" ]; then
    echo "FATAL: ffmpeg/ffprobe not on PATH" >&2
    exit 2
fi
[ "$WIPE" = "1" ] && rm -rf "$W"
mkdir -p "$W" "$W/tiny" "$W/cases" "$W/probe" "$LOG"

PASS=0; FAIL=0; SKIPN=0; RC=0; TB=""; HYG=""
FIXTURE="${FIXTURE:-$W/fixture.mp4}"

say()   { echo "$@" | tee -a "$SUM"; }
head1() { say ""; say "==== $* ===="; }
part_in() { [ "$PART" = "all" ] || [ "$PART" = "$1" ]; }

# ---------- metadata header (same spirit as the .bat summary) ----------
{
    echo "==== ffmpeg_bat_git sh smoke harness v2 ===="
    echo "date    : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "host    : $(hostname 2>/dev/null) ($(uname -srm))"
    echo "repo    : $REPO"
    echo "ffmpeg  : $("$FF" -hide_banner -version | head -1)"
    echo "which   : ffmpeg=$FF ffprobe=$FP"
    echo "shell   : $BASH_VERSION"
    echo "av1_qsv : $EXPECT_AV1_QSV   (auto = probe hardware, SKIP when absent)"
    echo
} > "$SUM"

# ---------- fixtures ----------
# 1080p60 2s at ~18 Mbps: bitrate high enough that the table value always
# wins the "source bitrate lower than table" clamp, so TARGET_BITRATE can be
# asserted as an exact number - identical to what the .bat harness expects.
mk_fixture() {
    local out="$1" size="$2" rate="$3" secs="$4" br="$5" audio="$6"
    local vopt=(-hide_banner -loglevel error -f lavfi -i "testsrc2=size=${size}:rate=${rate}")
    if [ "$audio" = "1" ]; then
        vopt+=(-f lavfi -i "sine=frequency=440:sample_rate=44100")
    fi
    vopt+=(-t "$secs" -c:v libx264 -preset ultrafast -b:v "$br" -pix_fmt yuv420p)
    [ "$audio" = "1" ] && vopt+=(-c:a aac -b:a 128k -shortest)
    "$FF" "${vopt[@]}" -y "$out" || return 1
    return 0
}

mkdir -p "$W"
if [ ! -f "$FIXTURE" ]; then
    echo "fixture absent -> generating $FIXTURE (1080p60 2s ~18 Mbps)"
    mk_fixture "$FIXTURE" 1920x1080 60 2 18M 1 || { echo "FATAL: fixture generation failed" >&2; exit 2; }
fi
IN="$FIXTURE"
INMOV="$W/smoke mov input 1080p60.mov"
QUIET="$W/smoke silent 1080p60.mp4"
AONLY="$W/smoke audio only.m4a"
LOW="$W/smoke lowbitrate 1080p30.mp4"
TINY="$W/tiny/tiny.mp4"

[ -f "$QUIET" ] || mk_fixture "$QUIET" 1920x1080 60 2 18M 0 || { echo "FATAL: silent fixture failed" >&2; exit 2; }
[ -f "$INMOV" ] || mk_fixture "$INMOV" 1920x1080 60 1 18M 1 || { echo "FATAL: mov fixture failed" >&2; exit 2; }
[ -f "$AONLY" ] || "$FF" -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:sample_rate=44100" -t 2 -c:a aac -b:a 128k -y "$AONLY" || { echo "FATAL: audio fixture failed" >&2; exit 2; }
# low-bitrate source: 400k < table(1080p AVC)/2 = 3836249 -> the documented
# "keep the source bitrate" clamp must fire in ARG mode too (T17).
[ -f "$LOW" ] || mk_fixture "$LOW" 1920x1080 30 2 400k 1 || { echo "FATAL: low-bitrate fixture failed" >&2; exit 2; }
# tiny clip for availability probing (T15/T19 style hardware gates)
# NOTE: 320x240, NOT 128x128. NVENC refuses to initialise an encoder below a
# minimum size ("InitializeEncoder failed: invalid argument"), so a 128x128 probe
# clip made the gate report SKIP on boxes whose GPU works perfectly well --
# measured 2026-09-16 on the RTX box: 128x128 fails for hevc_nvenc AND av1_nvenc,
# 160x120 and above succeed. QSV accepts any of them, but one probe clip is used
# for both families, and the probe must never be the reason a box looks
# unsupported.
[ -f "$TINY" ] || mk_fixture "$TINY" 320x240 30 1 200k 1 || { echo "FATAL: tiny fixture failed" >&2; exit 2; }

say "probe mp4  : $IN   [1080p60, audio+video]"
say "probe mov  : $INMOV   [audio+video]"
say "probe mute : $QUIET   [video only, -map 0:a? regression]"
say "probe audio: $AONLY   [audio only, non-video guard]"
say "probe low  : $LOW   [400k source -> clamp regression]"
say "probe tiny : $TINY   [hardware availability probe]"
# UTF-8 file names for T11, built from byte escapes so this file stays ASCII-only:
# "ep1"/"ep2 space" written with CJK ideographs.
UTF8_1="$(printf '\xE7\xAC\xAC\xE4\xB8\x80\xE9\x9B\x86')"
UTF8_2="$(printf '\xE7\xAC\xAC\xE4\xBA\x8C\xE9\x9B\x86 \xE7\xA9\xBA\xE6\xA0\xBC')"
say ""
say "---- verdicts ----"

# ---------- helpers ----------
probe_codec() {   # probe_codec <file> -> codec_name or NOFILE
    [ -f "$1" ] || { echo "NOFILE"; return; }
    local c
    c=$("$FP" -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | tr -d '\r')
    echo "${c:-none}"
}

probe_sidecar() {  # probe_sidecar <file> <out.txt>
    [ -f "$1" ] || return 0
    "$FP" -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate \
        -of default=noprint_wrappers=1 "$1" > "$2" 2>&1
}

tb_of() {   # last TARGET_BITRATE value printed in a log
    grep -aoE 'TARGET_BITRATE *[=:] *[0-9]+k?' "$1" 2>/dev/null | tail -1 | sed -E 's/.*[=:] *//'
}

check_hygiene() {  # check_hygiene <log> -> sets HYG to ";"-joined findings
    local f="$1" hits=""
    grep -aq "is not recognized" "$f" && hits="$hits bannerParseErr;"
    grep -aq "bitrate abnormal" "$f" && hits="$hits bitrateAbnormal;"
    grep -aq "command not found" "$f" && hits="$hits commandNotFound;"
    grep -aqE "^bash: line|syntax error" "$f" && hits="$hits shellSyntaxErr;"
    HYG="$hits"
}

judge() {   # judge <tid> <name> <want:ok|fail> <expTARGET> <expCODEC> <note>
    # expTARGET: exact number | LT:<n> | INFO | 0 | "" (=assert nothing)
    # expCODEC : exact codec_name | INFO | "" (=assert nothing)
    local tid="$1" name="$2" want="$3" expt="$4" expc="$5" note="$6"
    local got="ok" why="" CODEC="none" tbn=""

    [ "$RC" -ne 0 ] && got="fail"
    if [ "$got" = "ok" ] && [ ! -f "$OUT" ]; then got="ok-no-output"; fi

    TB="$(tb_of "$LOGF")"
    if [ "$got" = "ok" ]; then
        check_hygiene "$LOGF"; why="$HYG"
        tbn="${TB%k}"
        case "$expt" in
            ""|0|INFO) ;;
            LT:*) if [ -n "$tbn" ] && [ "$tbn" -lt "${expt#LT:}" ]; then :; else why="$why targetNotLt${expt#LT:}(got=${TB:-none});"; fi ;;
            *)    if [ "$TB" = "$expt" ]; then :; else why="$why targetBitrate=${TB:-none} expected=$expt;"; fi ;;
        esac
        CODEC="$(probe_codec "$OUT")"
        case "$expc" in
            ""|INFO) ;;
            *) if [ "$CODEC" = "$expc" ]; then :; else why="$why codec=$CODEC expected=$expc;"; fi ;;
        esac
        probe_sidecar "$OUT" "$LOG/${tid}_${name}_probe.txt"
    fi

    if [ "$got" = "$want" ] && [ -z "$why" ]; then
        PASS=$((PASS+1))
        say "[PASS] $tid $name rc=$RC target=${TB:-none} codec=$CODEC  ($note)"
        [ "$want" = "fail" ] && say "       (expected failure; log kept at $LOG/${tid}_${name}.log)"
    else
        FAIL=$((FAIL+1))
        say "[FAIL] $tid $name rc=$RC want=$want got=$got target=${TB:-none} codec=$CODEC"
        say "       note: $note"
        [ -n "$why" ] && say "       why : $why"
        say "       log : $LOGF"
        sed 's/^/       | /' "$LOGF" | tail -8 >> "$SUM"
    fi
}

skipcase() {   # skipcase <tid> <name> <note>
    SKIPN=$((SKIPN+1))
    say "[SKIP] $1 $2  ($3)"
}

# can_run <script> <extra args...> : run the entry against the tiny clip.
# Used to gate hardware-dependent entries so a box without the hardware
# reports SKIP instead of FAIL (same policy as T15 in the .bat harness).
can_run() {
    local script="$1"; shift
    local d="$W/probe/$(basename "$script" .sh)"
    # fresh dir every call: a leftover clip-compressed.mp4 makes the entry's
    # ffmpeg -n refuse to run ("already exists. Exiting."), which then reads
    # as "hardware absent" -- observed as T6/T10 wrongly SKIPping on box A
    # right after T1's probe had succeeded.
    rm -rf "$d"; mkdir -p "$d"; cp -f "$TINY" "$d/clip.mp4"
    # < /dev/null: ffmpeg consumes whatever stdin it inherits. Inside the
    # gate_arg heredoc loop that stdin IS the remaining spec lines -- box A
    # ate "T3|f" from the next line, so the loop then tried
    # `bash .../2548951` and mangled the SKIP ("fmpeg_hevc_qsv.sh 2548951").
    bash "$REPO/$script" "$d/clip.mp4" "$@" < /dev/null > "$LOG/probe_$(basename "$script" .sh).log" 2>&1
    [ $? -eq 0 ] && [ -f "$d/clip-compressed.mp4" ]
}

# run_arg <tid> <script> <want> <expTARGET> <expCODEC> <note> [input file]
run_arg() {
    local tid="$1" script="$2" name="${2%.sh}"
    local d="$W/cases/${tid}_${name}"
    mkdir -p "$d"; cp -f "${7:-$IN}" "$d/clip.mp4"
    LOGF="$LOG/${tid}_${name}.log"; OUT="$d/clip-compressed.mp4"
    rm -f "$OUT"
    # < /dev/null for the same reason as can_run: gate_arg calls run_arg from
    # inside the heredoc loop, so an unredirected ffmpeg would eat spec lines.
    bash "$REPO/$script" "$d/clip.mp4" < /dev/null > "$LOGF" 2>&1
    RC=$?
    judge "$tid" "$name" "$3" "$4" "$5" "$6"
}

# gate_arg <tid> <script> <expTARGET> <expCODEC> <note>
# Hardware-dependent entries: probe the box with the tiny clip first and
# report SKIP when this machine cannot run the encoder at all, so the suite
# stays green (and honest) on boxes without that hardware.
gate_arg() {
    local tid="$1" script="$2" expt="$3" expc="$4" note="$5"
    if can_run "$script"; then
        run_arg "$tid" "$script" ok "$expt" "$expc" "$note (hardware probe passed)"
    else
        skipcase "$tid" "${script%.sh}" "not runnable here: $note (probe log: $LOG/probe_$(basename "$script" .sh).log)"
    fi
}

# ============================================================
# part: parity  (T-ids shared with test/bat/smoke_ffmpeg.bat)
# ============================================================
if part_in parity; then
head1 "part parity: 1080p60 fixture, arg mode (same T-ids as the .bat harness)"

# --- software paths: asserted unconditionally (no hardware involved) ---
run_arg T4  ffmpeg_libx265.sh ok 2548951 hevc "arg: soft HEVC"
run_arg T16 ffmpeg_libx264.sh ok 3836249 h264 "arg: soft AVC (bat twin added 2026-09-16)"
# T17: 400k source vs table(1080p AVC)/2 = 3836249 -> the documented clamp
# ("keep the source bitrate") must fire in ARG mode, not only interactively.
run_arg T17 ffmpeg_libx264.sh ok LT:3836249 h264 "arg: low-bitrate source keeps source bitrate" "$LOW"
say "       | $(grep -a 'real TARGET_BITRATE\|percentage' "$LOG/T17_ffmpeg_libx264.log" | tr '\n' ' ')"

# --- hardware paths: probe first, SKIP when this box cannot run the encoder ---
# format: tid|script|expTARGET|expCODEC|note
while IFS='|' read -r tid script expt expc note; do
    [ -z "$tid" ] && continue
    gate_arg "$tid" "$script" "$expt" "$expc" "$note"
done <<'SPECS'
T1|ffmpeg_avc_qsv.sh|3836249|h264|QSV AVC
T3|ffmpeg_hevc_qsv.sh|2548951|hevc|QSV HEVC
T8|ffmpeg_h264_vaapi.sh|3836249|h264|VAAPI AVC (Linux-only entry: VAAPI is a Linux kernel API)
T19|ffmpeg_hevc_vaapi.sh|2548951|hevc|VAAPI HEVC
T2|ffmpeg_hevc_nvenc.sh|2548951|hevc|NVENC HEVC
T14|ffmpeg_av1_nvenc.sh|1707157|av1|AV1 NVENC (needs Ada or newer)
T20|ffmpeg_hevc_nvenc_cygwin.sh|2548951|hevc|Cygwin variant (cuvid + hwdownload)
SPECS

# AV1 QSV: keep the explicit override knob (auto = probe, see the header)
if [ "$EXPECT_AV1_QSV" = "skip" ]; then
    skipcase T15 ffmpeg_av1_qsv.sh "EXPECT_AV1_QSV=skip"
elif [ "$EXPECT_AV1_QSV" = "ok" ] || [ "$EXPECT_AV1_QSV" = "fail" ]; then
    run_arg T15 ffmpeg_av1_qsv.sh "$EXPECT_AV1_QSV" 1707157 av1 "arg: AV1 QSV (forced by EXPECT_AV1_QSV)"
else
    gate_arg T15 ffmpeg_av1_qsv.sh 1707157 av1 "AV1 QSV (needs Arrow Lake or newer iGPU)"
fi

# T5: copy_to_mp4 remux, no bitrate table; output keeps the source name
d="$W/cases/T5_copy_to_mp4"; mkdir -p "$d"; cp -f "$INMOV" "$d/remux_me.mkv"
LOGF="$LOG/T5_copy_to_mp4.log"; OUT="$d/remux_me.mp4"; rm -f "$OUT"
bash "$REPO/ffmpeg_copy_to_mp4.sh" "$d/remux_me.mkv" > "$LOGF" 2>&1
RC=$?
judge T5 copy_to_mp4 ok INFO h264 "arg: remux mov -> mp4, no re-encode"

# T6: interactive mode, path via stdin, no bitrate override (src = QSV AVC)
if can_run ffmpeg_avc_qsv.sh; then
    d="$W/cases/T6_avc_qsv_stdin"; mkdir -p "$d"; cp -f "$IN" "$d/clip.mp4"
    LOGF="$LOG/T6_avc_qsv_stdin.log"; OUT="$d/clip-compressed.mp4"; rm -f "$OUT"
    printf '%s\n\n' "$d/clip.mp4" | bash "$REPO/ffmpeg_avc_qsv.sh" > "$LOGF" 2>&1
    RC=$?
    judge T6 avc_qsv_stdin ok 3836249 h264 "stdin: path then blank (keeps computed bitrate)"
else
    skipcase T6 avc_qsv_stdin "QSV AVC not runnable here (probe log: $LOG/probe_ffmpeg_avc_qsv.log)"
fi

# T7: the .bat harness has a "usage C" case (fresh cmd process already in
# UTF-8 / cp65001 guard). There is no console-codepage concept on Linux.
skipcase T7 cp65001_guard "no analogue: the cp65001 guard is a Windows console feature"

# T10: silent input (-map 0:a? regression)
if can_run ffmpeg_avc_qsv.sh; then
    d="$W/cases/T10_avc_qsv_silent"; mkdir -p "$d"; cp -f "$QUIET" "$d/clip.mp4"
    LOGF="$LOG/T10_avc_qsv_silent.log"; OUT="$d/clip-compressed.mp4"; rm -f "$OUT"
    bash "$REPO/ffmpeg_avc_qsv.sh" "$d/clip.mp4" > "$LOGF" 2>&1
    RC=$?
    judge T10 avc_qsv_silent ok 3836249 h264 "arg: video-only source (-map 0:a? regression)"
else
    skipcase T10 avc_qsv_silent "QSV AVC not runnable here (probe log: $LOG/probe_ffmpeg_avc_qsv.log)"
fi

# T18 (sh-only): interactive bitrate override. The .bat side asks for a raw
# ffmpeg value at that point, so there is no equivalent assertion there.
d="$W/cases/T18_libx264_stdin_br"; mkdir -p "$d"; cp -f "$IN" "$d/clip.mp4"
LOGF="$LOG/T18_libx264_stdin_br.log"; OUT="$d/clip-compressed.mp4"; rm -f "$OUT"
printf '%s\n900k\n' "$d/clip.mp4" | bash "$REPO/ffmpeg_libx264.sh" > "$LOGF" 2>&1
RC=$?
judge T18 libx264_stdin_br ok 900k h264 "stdin: path + bitrate override 900k"
fi

# ============================================================
# part: list
# ============================================================
mklist() {   # mklist <dir> <listfile> <eol:lf|crlf> <bom:0|1> <names...>
    local d="$1" lf="$2" eol="$3" bom="$4"; shift 4
    : > "$lf"
    [ "$bom" = "1" ] && printf '\xEF\xBB\xBF' >> "$lf"
    local f
    for f in "$@"; do
        cp -f "$IN" "$d/$f"
        if [ "$eol" = "crlf" ]; then printf '%s\r\n' "$d/$f" >> "$lf"
        else printf '%s\n' "$d/$f" >> "$lf"; fi
    done
}

if part_in list; then
head1 "part list: T9/T11/T12 mirror the .bat harness, T21-T23 are sh-only extensions"

# convert_from_list_qsv.sh needs QSV AVC hardware. Probe ONCE for the whole
# part: on a box without QSV (e.g. the Raspberry Pi test box) the three list
# cases used to fail rc=1 -- "hardware absent" reported as a repo defect
# (found on D-box, 2026-09-16). Same policy as the gate_arg parity cases.
if can_run ffmpeg_avc_qsv.sh; then LISTGATE=1; else LISTGATE=0; fi

if [ "$LISTGATE" -eq 1 ]; then
# T9: 2-entry list, cwd = repo (the .bat T9 writes a CRLF list via cmd echo)
d="$W/cases/T9_list"; mkdir -p "$d"
mklist "$d" "$d/list.txt" lf 0 "ep1.mkv" "ep 2.mkv"
LOGF="$LOG/T9_convert_from_list.log"
rm -f "$d"/*-compressed.mp4
( cd "$REPO" && bash "$REPO/convert_from_list_qsv.sh" "$d/list.txt" ) > "$LOGF" 2>&1
RC=$?
n=0; for f in "$d/ep1-compressed.mp4" "$d/ep 2-compressed.mp4"; do [ -f "$f" ] && n=$((n+1)); done
OUT="$d/ep1-compressed.mp4"
if [ "$RC" -eq 0 ] && [ "$n" -eq 2 ]; then PASS=$((PASS+1)); say "[PASS] T9 convert_from_list_qsv 2-entry list, cwd=repo  (outputs=$n/2)"
else FAIL=$((FAIL+1)); say "[FAIL] T9 convert_from_list_qsv 2-entry list, cwd=repo  outputs=$n/2 rc=$RC"; sed 's/^/       | /' "$LOGF" | tail -6 >> "$SUM"; fi
else
skipcase T9 convert_from_list_qsv "QSV AVC not runnable here (probe log: $LOG/probe_ffmpeg_avc_qsv.log)"
fi


if [ "$LISTGATE" -eq 1 ]; then
# T11: UTF-8 (non-ASCII) names in a list (the .bat harness T11 uses a stale
# fixture and SKIPs when it is missing; here the names are made on the fly)
d="$W/cases/T11_list_utf8"; mkdir -p "$d"
mklist "$d" "$d/list_utf8.txt" lf 0 "${UTF8_1}.mkv" "${UTF8_2}.mkv"
LOGF="$LOG/T11_convert_from_list_utf8.log"
rm -f "$d"/*-compressed.mp4
bash "$REPO/convert_from_list_qsv.sh" "$d/list_utf8.txt" > "$LOGF" 2>&1
RC=$?
n=0; for f in "$d/${UTF8_1}-compressed.mp4" "$d/${UTF8_2}-compressed.mp4"; do [ -f "$f" ] && n=$((n+1)); done
if [ "$RC" -eq 0 ] && [ "$n" -eq 2 ]; then PASS=$((PASS+1)); say "[PASS] T11 list mode utf8 names  (outputs=$n/2)"
else FAIL=$((FAIL+1)); say "[FAIL] T11 list mode utf8 names  outputs=$n/2 rc=$RC"; sed 's/^/       | /' "$LOGF" | tail -6 >> "$SUM"; fi
else
skipcase T11 convert_from_list_qsv "QSV AVC not runnable here (probe log: $LOG/probe_ffmpeg_avc_qsv.log)"
fi


if [ "$LISTGATE" -eq 1 ]; then
# T12: list mode with NO argument, cwd elsewhere -> default list.txt in cwd
d="$W/cases/T12_list_nocwd"; mkdir -p "$d"
mklist "$d" "$d/list.txt" lf 0 "ep1.mkv" "ep 2.mkv"
LOGF="$LOG/T12_convert_from_list_nocwd.log"
rm -f "$d"/*-compressed.mp4
( cd "$d" && bash "$REPO/convert_from_list_qsv.sh" ) > "$LOGF" 2>&1
RC=$?
n=0; for f in "$d/ep1-compressed.mp4" "$d/ep 2-compressed.mp4"; do [ -f "$f" ] && n=$((n+1)); done
if [ "$RC" -eq 0 ] && [ "$n" -eq 2 ]; then PASS=$((PASS+1)); say "[PASS] T12 list mode, no arg, cwd elsewhere  (outputs=$n/2)"
else FAIL=$((FAIL+1)); say "[FAIL] T12 list mode, no arg, cwd elsewhere  outputs=$n/2 rc=$RC"; sed 's/^/       | /' "$LOGF" | tail -6 >> "$SUM"; fi
else
skipcase T12 convert_from_list_qsv "QSV AVC not runnable here (probe log: $LOG/probe_ffmpeg_avc_qsv.log)"
fi


# T21 (sh-only): Notepad-style CRLF + UTF-8 BOM list must still parse
d="$W/cases/T21_list_crlf_bom"; mkdir -p "$d"
mklist "$d" "$d/list_crlf.txt" crlf 1 "ep1.mkv" "ep 2.mkv" "ep3.mkv"
LOGF="$LOG/T21_list_crlf_bom.log"
rm -f "$d"/*-compressed.mp4
bash "$REPO/convert_from_list_libx265.sh" "$d/list_crlf.txt" > "$LOGF" 2>&1
RC=$?
n=0; for f in "$d/ep1-compressed.mp4" "$d/ep 2-compressed.mp4" "$d/ep3-compressed.mp4"; do [ -f "$f" ] && n=$((n+1)); done
if [ "$RC" -eq 0 ] && [ "$n" -eq 3 ]; then PASS=$((PASS+1)); say "[PASS] T21 CRLF + UTF-8 BOM list  (outputs=$n/3)"
else FAIL=$((FAIL+1)); say "[FAIL] T21 CRLF + UTF-8 BOM list  outputs=$n/3 rc=$RC"; sed 's/^/       | /' "$LOGF" | tail -6 >> "$SUM"; fi

# T22 (sh-only): 5-entry list -> stdin isolation (the </dev/null fix).
# Without </dev/null, Linux ffmpeg eats 1 byte from the shared fd and entries
# #2..#5 lose their first character.
d="$W/cases/T22_stdinleak"; mkdir -p "$d"
: > "$d/list.txt"
for i in 1 2 3 4 5; do cp -f "$IN" "$d/e${i}.mkv"; printf '%s\n' "$d/e${i}.mkv" >> "$d/list.txt"; done
LOGF="$LOG/T22_stdinleak.log"
bash "$REPO/convert_from_list_libx265.sh" "$d/list.txt" > "$LOGF" 2>&1
RC=$?
n=0; for i in 1 2 3 4 5; do [ -f "$d/e${i}-compressed.mp4" ] && n=$((n+1)); done
if [ "$RC" -eq 0 ] && [ "$n" -eq 5 ]; then PASS=$((PASS+1)); say "[PASS] T22 stdin isolation (</dev/null)  5-entry list, outputs=$n/5"
else FAIL=$((FAIL+1)); say "[FAIL] T22 stdin isolation (</dev/null)  5-entry list, outputs=$n/5 rc=$RC"; sed 's/^/       | /' "$LOGF" | tail -6 >> "$SUM"; fi
fi

# ============================================================
# part: guard
# ============================================================
if part_in guard; then
head1 "part guard: input validation and the exit-code contract"

# T13: audio-only input must be REJECTED before ffmpeg, exit code 3
# (soft-encode entry on purpose: the guard lives in lib/common.sh and is
#  shared by every entry, so this stays runnable without any hardware)
d="$W/cases/T13_nonvideo"; mkdir -p "$d"
LOGF="$LOG/T13_nonvideo.log"; OUT="$d/never.mp4"
bash "$REPO/ffmpeg_libx264.sh" "$AONLY" > "$LOGF" 2>&1
RC=$?
if [ "$RC" -eq 3 ] && [ ! -f "$AONLY-compressed.mp4" ]; then
    PASS=$((PASS+1)); say "[PASS] T13 non-video input rejected before ffmpeg rc=3 (exit-code contract)"
else
    FAIL=$((FAIL+1)); say "[FAIL] T13 non-video input rejected rc=$RC want=3"; sed 's/^/       | /' "$LOGF" | tail -6 >> "$SUM"
fi
rm -f "$AONLY-compressed.mp4"

# T24 (sh-only): missing input file -> non-zero, no output
d="$W/cases/T24_missing"; mkdir -p "$d"
LOGF="$LOG/T24_missing.log"
bash "$REPO/ffmpeg_avc_qsv.sh" "$d/does_not_exist.mp4" > "$LOGF" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then PASS=$((PASS+1)); say "[PASS] T24 missing input rejected rc=$RC"
else FAIL=$((FAIL+1)); say "[FAIL] T24 missing input rc=$RC want non-zero"; fi

# T25 (sh-only): a non-text list file must be rejected
d="$W/cases/T25_badlist"; mkdir -p "$d"
printf '\x00\x01\x02binary' > "$d/blob.bin"
LOGF="$LOG/T25_badlist.log"
bash "$REPO/convert_from_list_qsv.sh" "$d/blob.bin" > "$LOGF" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then PASS=$((PASS+1)); say "[PASS] T25 non-text list file rejected rc=$RC"
else FAIL=$((FAIL+1)); say "[FAIL] T25 non-text list file rc=$RC want non-zero"; fi

# T23 (sh-only): a missing list entry aborts the run at that entry
d="$W/cases/T23_list_abort"; mkdir -p "$d"
printf '%s\n' "$d/nope.mp4" > "$d/badlist.txt"
LOGF="$LOG/T23_list_abort.log"
bash "$REPO/convert_from_list_qsv.sh" "$d/badlist.txt" > "$LOGF" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then PASS=$((PASS+1)); say "[PASS] T23 missing list entry aborts run rc=$RC"
else FAIL=$((FAIL+1)); say "[FAIL] T23 missing list entry rc=$RC want non-zero"; fi

# ---- global hygiene: no log may carry the banner parse error or a shell error ----
BADN=0
for f in "$LOG"/*.log; do
    [ -f "$f" ] || continue
    if grep -aq "is not recognized" "$f"; then say "[FAIL] banner parse error in $(basename "$f")"; BADN=$((BADN+1)); fi
done
if [ "$BADN" -eq 0 ]; then PASS=$((PASS+1)); say "[PASS] banner check: no 'is not recognized' in any log"
else FAIL=$((FAIL+1)); fi
fi

# ---------- summary + exit code ----------
say ""
say "============================================================"
say "sh smoke v2: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIPN   ffmpeg=$("$FF" -hide_banner -version | head -1 | awk '{print $3}')"
say "logs: $LOG"
say "============================================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
