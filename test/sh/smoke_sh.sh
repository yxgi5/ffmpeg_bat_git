#!/bin/bash
# smoke_sh.sh - sh-family smoke harness (machine-parameterized)
# Location: <repo>/test/sh/  (the repo root is derived from this script's path,
# two levels up, so a clone anywhere works). ASCII only, LF.
# Origin: written on A machine (i7-9700T / UHD630 / Ubuntu 22.04, distro 4.4.2
# + /opt master-gpl); re-run on C machine (Ultra 7 265K / Arrow Lake).
#
# Usage: bash smoke_sh.sh [part]        part = all|arg|stdin|list|guard|stdinleak
#
# Env knobs:
#   REPO=<path>          repo root; default = two levels up from this script
#   WORK=<dir>           scratch dir; default = ${TMPDIR:-/tmp}/ffmpeg_bat_smoke_sh
#   FIXTURE=<path>       source clip. Auto-generated with lavfi when absent
#                        (the repo media fixtures are untracked, so a fresh
#                        clone/box has none).
#   EXPECT_AV1_QSV=ok|fail
#                        "fail" (default) = Gen9.5-class iGPU: no AV1 encoder.
#                        "ok"  = C machine: Arrow Lake hardware AV1 + /opt master-gpl,
#                        and ffmpeg_av1_qsv.sh prepends /opt by itself.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
W="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_smoke_sh}"
CASES="$W/cases"
LOG="$W/logs"
SUM="$W/summary.txt"
PART="${1:-all}"
FIXTURE="${FIXTURE:-$W/fixture.mp4}"
EXPECT_AV1_QSV="${EXPECT_AV1_QSV:-fail}"

rm -rf "$W"
mkdir -p "$CASES" "$LOG"
: > "$SUM"

PASS=0; FAIL=0; SKIP=0

# ---- fixture: 720p30 5s H.264 + AAC, made by whatever ffmpeg is first on PATH ----
if [ ! -f "$FIXTURE" ]; then
  echo "fixture absent -> generating $FIXTURE"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "testsrc2=size=1280x720:rate=30" \
    -f lavfi -i "sine=frequency=440:sample_rate=44100" \
    -t 5 -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -c:a aac -b:a 128k -shortest "$FIXTURE" || { echo "FIXTURE GENERATION FAILED"; exit 9; }
fi
echo "fixture: $FIXTURE ($(stat -c %s "$FIXTURE") bytes)"
echo "av1_qsv expectation on this box: $EXPECT_AV1_QSV"

say()  { echo "$@" | tee -a "$SUM"; }
head1() { say ""; say "==== $* ===="; }

# probe_vout <file> -> "codec/audio" summary, or NOFILE
probe_vout() {
  [ -f "$1" ] || { echo "NOFILE"; return; }
  local v a
  v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null)
  a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null)
  echo "v=${v:-none} a=${a:-none}"
}

# judge <name> <want:ok|fail> <expect_note> <outfile...>
judge() {
  local name="$1" want="$2" note="$3"; shift 3
  local got f
  if [ "$RC" -ne 0 ]; then
    got="fail"
  else
    got="ok"
    for f in "$@"; do
      [ -f "$f" ] || got="ok-no-output"
    done
  fi
  local mark
  if [ "$got" = "$want" ]; then
    mark="PASS"; PASS=$((PASS+1))
  else
    mark="FAIL"; FAIL=$((FAIL+1))
  fi
  local extra=""
  if [ $# -gt 0 ]; then extra=" | out: $(probe_vout "$1")"; fi
  say "[$mark] $name  rc=$RC want=$want got=$got$extra  ($note)"
  if [ "$mark" = "FAIL" ]; then
    sed 's/^/        | /' "$LOG/$name.log" | tail -6 >> "$SUM"
  fi
}

# newdir <name> -> path with clip.mp4 inside
newdir() {
  local d="$CASES/$1"
  mkdir -p "$d"
  cp -f "$FIXTURE" "$d/clip.mp4"
  echo "$d"
}

# ---------- part 1: arg mode ----------
if [ "$PART" = "all" ] || [ "$PART" = "arg" ]; then
head1 "part 1: arg mode (single file, path as \$1)"
for spec in "ffmpeg_h264_vaapi.sh:ok:VAAPI AVC" \
            "ffmpeg_hevc_vaapi.sh:ok:VAAPI HEVC" \
            "ffmpeg_libx264.sh:ok:soft AVC" \
            "ffmpeg_libx265.sh:ok:soft HEVC" \
            "ffmpeg_avc_qsv.sh:ok:QSV AVC" \
            "ffmpeg_hevc_qsv.sh:ok:QSV HEVC" \
            "ffmpeg_av1_qsv.sh:$EXPECT_AV1_QSV:AV1 HW encoder availability is box-dependent (want=$EXPECT_AV1_QSV)" \
            "ffmpeg_hevc_nvenc.sh:fail:no NVIDIA GPU" \
            "ffmpeg_av1_nvenc.sh:fail:no NVIDIA GPU" \
            "ffmpeg_hevc_nvenc_cygwin.sh:fail:Cygwin-only entry" ; do
  s="${spec%%:*}"; rest="${spec#*:}"; want="${rest%%:*}"; note="${rest#*:}"
  n="${s%.sh}"
  d=$(newdir "$n")
  bash "$REPO/$s" "$d/clip.mp4" > "$LOG/$n.log" 2>&1
  RC=$?
  judge "$n" "$want" "$note" "$d/clip-compressed.mp4"
done

# copy_to_mp4: removes the suffix-free name -> clip.mp4 collides with the source,
# so use a differently named source inside its own dir.
d=$(newdir "copy_to_mp4_arg")
mv "$d/clip.mp4" "$d/remux_me.mkv"
bash "$REPO/ffmpeg_copy_to_mp4.sh" "$d/remux_me.mkv" > "$LOG/copy_to_mp4_arg.log" 2>&1
RC=$?
judge "copy_to_mp4_arg" "ok" "remux, no re-encode" "$d/remux_me.mp4"
fi

# ---------- part 2: interactive mode (stdin) ----------
if [ "$PART" = "all" ] || [ "$PART" = "stdin" ]; then
head1 "part 2: interactive mode (no args, path via stdin)"
d=$(newdir "h264_vaapi_stdin")
printf '%s\n\n' "$d/clip.mp4" | bash "$REPO/ffmpeg_h264_vaapi.sh" > "$LOG/h264_vaapi_stdin.log" 2>&1
RC=$?
judge "h264_vaapi_stdin" "ok" "interactive: path + default bitrate" "$d/clip-compressed.mp4"

# interactive with an explicit bitrate override
d=$(newdir "libx264_stdin_br")
printf '%s\n900k\n' "$d/clip.mp4" | bash "$REPO/ffmpeg_libx264.sh" > "$LOG/libx264_stdin_br.log" 2>&1
RC=$?
judge "libx264_stdin_br" "ok" "interactive: path + bitrate override 900k" "$d/clip-compressed.mp4"
grep -a "real TARGET_BITRATE" "$LOG/libx264_stdin_br.log" | tail -1 | sed 's/^/        | /' >> "$SUM"
fi

# ---------- part 3: list mode (the </dev/null fix) ----------
if [ "$PART" = "all" ] || [ "$PART" = "list" ]; then
head1 "part 3: list mode (3 entries incl. a name with a space)"

mklist() {   # mklist <dir> <listfile> <eol:lf|crlf> <bom:0|1>
  local d="$1" lf="$2" eol="$3" bom="$4" f
  : > "$lf"
  [ "$bom" = "1" ] && printf '\xEF\xBB\xBF' >> "$lf"
  for f in "ep1.mkv" "ep 2.mkv" "ep3.mkv"; do
    cp -f "$FIXTURE" "$d/$f"
    if [ "$eol" = "crlf" ]; then printf '%s\r\n' "$d/$f" >> "$lf"
    else printf '%s\n' "$d/$f" >> "$lf"; fi
  done
}

for spec in "convert_from_list_libx265.sh:ok:list -> libx265" \
            "convert_from_list_qsv.sh:ok:list -> hevc_qsv" \
            "convert_from_list_cuda.sh:fail:list -> nvenc, no NVIDIA GPU" ; do
  s="${spec%%:*}"; rest="${spec#*:}"; want="${rest%%:*}"; note="${rest#*:}"
  n="${s%.sh}"
  d="$CASES/$n"; mkdir -p "$d"
  mklist "$d" "$d/list_lf.txt" lf 0
  bash "$REPO/$s" "$d/list_lf.txt" > "$LOG/$n.log" 2>&1
  RC=$?
  judge "$n" "$want" "$note" "$d/ep1-compressed.mp4" "$d/ep 2-compressed.mp4" "$d/ep3-compressed.mp4"
done

# repack_from_list writes <name>.mp4 (no -compressed suffix)
d="$CASES/repack_from_list"; mkdir -p "$d"
mklist "$d" "$d/list_lf.txt" lf 0
bash "$REPO/repack_from_list.sh" "$d/list_lf.txt" > "$LOG/repack_from_list.log" 2>&1
RC=$?
judge "repack_from_list" "ok" "list -> remux" "$d/ep1.mp4" "$d/ep 2.mp4" "$d/ep3.mp4"

head1 "part 3b: CRLF + BOM list (Notepad-style) - run_list tolerance"
d="$CASES/convert_from_list_libx265_crlf"; mkdir -p "$d"
mklist "$d" "$d/list_crlf.txt" crlf 1
bash "$REPO/convert_from_list_libx265.sh" "$d/list_crlf.txt" > "$LOG/list_crlf_bom.log" 2>&1
RC=$?
judge "list_crlf_bom" "ok" "CRLF + UTF-8 BOM must still parse" "$d/ep1-compressed.mp4" "$d/ep 2-compressed.mp4" "$d/ep3-compressed.mp4"
fi

# ---------- part 4: guard rails ----------
if [ "$PART" = "all" ] || [ "$PART" = "guard" ]; then
head1 "part 4: guard rails"
d="$CASES/guard_nonvideo"; mkdir -p "$d"
echo "this is not a video" > "$d/notes.txt"
bash "$REPO/ffmpeg_h264_vaapi.sh" "$d/notes.txt" > "$LOG/guard_nonvideo.log" 2>&1
RC=$?
judge "guard_nonvideo" "fail" "non-video input rejected before ffmpeg"

d="$CASES/guard_missing"; mkdir -p "$d"
bash "$REPO/ffmpeg_h264_vaapi.sh" "$d/does_not_exist.mp4" > "$LOG/guard_missing.log" 2>&1
RC=$?
judge "guard_missing" "fail" "missing input rejected"
rc_on=$(grep -c "Convert failed" "$LOG/guard_nonvideo.log")
say "        | (non-video log: 'Convert failed' x$rc_on)"

d="$CASES/guard_badlist"; mkdir -p "$d"
printf '%s\n' "$d/nope.mp4" > "$d/badlist.txt"
bash "$REPO/convert_from_list_libx265.sh" "$d/badlist.txt" > "$LOG/guard_badlist.log" 2>&1
RC=$?
judge "guard_badlist" "fail" "list entry missing -> abort at that entry"
fi

# ---------- part 5: </dev/null regression, isolated ----------
if [ "$PART" = "all" ] || [ "$PART" = "stdinleak" ]; then
head1 "part 5: run_list stdin isolation (the </dev/null fix)"
say "  3-entry list, entry #2/#3 would lose their first char if ffmpeg ate stdin."
d="$CASES/stdinleak"; mkdir -p "$d"
: > "$d/list.txt"
for i in 1 2 3 4 5; do
  cp -f "$FIXTURE" "$d/e${i}.mkv"
  printf '%s\n' "$d/e${i}.mkv" >> "$d/list.txt"
done
bash "$REPO/convert_from_list_libx265.sh" "$d/list.txt" > "$LOG/stdinleak.log" 2>&1
RC=$?
n=0
for i in 1 2 3 4 5; do [ -f "$d/e${i}-compressed.mp4" ] && n=$((n+1)); done
say "[$([ "$RC" -eq 0 ] && [ "$n" -eq 5 ] && echo PASS || echo FAIL)] stdinleak  5-entry list rc=$RC outputs=$n/5"
[ "$RC" -eq 0 ] && [ "$n" -eq 5 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
grep -a "file not exists\|No such file" "$LOG/stdinleak.log" | head -2 | sed 's/^/        | /' >> "$SUM"
fi

say ""
say "============================================================"
say "sh-family smoke:  PASS=$PASS  FAIL=$FAIL  (ffmpeg: $(ffmpeg -hide_banner -version | head -1 | awk '{print $3}'))"
say "logs: $LOG"
say "============================================================"
