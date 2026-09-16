#!/bin/bash
# ============================================================
# check_env.sh - "what can I actually run on THIS box?"
#
#   This is a REPORT, not a regression test. It answers the question
#   "which entries of this repo are usable in the current environment"
#   without pretending that an unusable entry is a bug.
#
#   Two levels:
#     (default)   QUICK  - static capability inventory: ffmpeg build
#                          features, hwaccels, devices, GPU, tables.
#                          Takes well under a second.
#     --probe     DEEP   - additionally runs every candidate entry on a
#                          tiny 3s clip and reports its real exit code.
#                          Needs a scratch dir and a few seconds per entry.
#
#   Status vocabulary (identical in check_env.bat, so the two reports can be
#   diffed against each other):
#     OK           usable here (static evidence, or rc=0 from --probe)
#     NO-ENCODER   the ffmpeg build has no such encoder
#     NO-DEVICE    encoder exists but this machine has no usable device/GPU
#     NO-FFMPEG    ffmpeg not found at all
#     N/A-OS       entry is meaningless on this OS (e.g. VAAPI on Windows)
#     UNKNOWN      static check cannot decide -> run with --probe
#     PROBE-OK     --probe ran it and it worked
#     PROBE-FAIL   --probe ran it and it returned non-zero
#
#   Location: <repo>/test/sh/  - the repo root is derived from this script's own
#   path (two levels up), so a clone anywhere works. ASCII only, LF.
#
#   Scope: the .sh family. The .bat family has its own twin at
#   test/bat/check_env.bat, which must be run from Windows.
#
# Usage:  bash test/sh/check_env.sh [--probe] [--help]
#
# Env knobs:
#   REPO=<path>       repo root; default = two levels up from this script
#   WORK=<dir>        scratch dir for --probe; default ${TMPDIR:-/tmp}/ffmpeg_bat_check_env
#   FFMPEG=<path>     ffmpeg binary; default = search (see find_ffmpeg)
#   FFPROBE=<path>    ffprobe binary; default = sibling of $FFMPEG, then PATH
#
# Exit code: 0 = report produced (statuses are data, not failures)
#            2 = setup error (repo missing / ffmpeg missing)
# ============================================================
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
W="${WORK:-${TMPDIR:-/tmp}/ffmpeg_bat_check_env}"
PROBE=0

for arg in "$@"; do
    case "$arg" in
        --probe) PROBE=1 ;;
        -h|--help)
            # print the leading comment block, minus the shebang line
            awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
            exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ---------- ffmpeg discovery ----------
# Order: explicit env -> PATH -> well-known install prefixes (the lab boxes keep
# a hand-built ffmpeg under /opt/ffmpeg/<build>/bin, which is not on PATH).
find_ffmpeg() {
    if [ -n "${FFMPEG:-}" ] && [ -x "${FFMPEG}" ]; then echo "${FFMPEG}"; return; fi
    local p
    p="$(command -v ffmpeg 2>/dev/null || true)"
    if [ -n "$p" ]; then echo "$p"; return; fi
    for p in /opt/ffmpeg/*/bin/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg \
             "/c/Program Files/ffmpeg/bin/ffmpeg.exe" ; do
        [ -x "$p" ] && { echo "$p"; return; }
    done
    echo ""
}

FF="$(find_ffmpeg)"
if [ -z "$FF" ]; then
    echo "FATAL: ffmpeg not found (set FFMPEG=/path/to/ffmpeg)" >&2
    exit 2
fi
if [ -z "${FFPROBE:-}" ]; then
    FP="$(command -v ffprobe 2>/dev/null || true)"
    [ -z "$FP" ] && FP="$(dirname "$FF")/ffprobe"
    [ -x "$FP" ] || FP=""
else
    FP="$FFPROBE"
fi
if [ ! -f "$REPO/lib/common.sh" ]; then
    echo "FATAL: repo not found at $REPO (expected $REPO/lib/common.sh)" >&2
    exit 2
fi

# ---------- environment facts ----------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
    Linux)        OSFAMILY="linux" ;;
    CYGWIN_NT-*)  OSFAMILY="cygwin" ;;
    MINGW*|MSYS*) OSFAMILY="msys" ;;
    Darwin)       OSFAMILY="macos" ;;
    *)            OSFAMILY="other" ;;
esac

ENCODERS="$("$FF" -hide_banner -encoders 2>/dev/null | awk 'NF>=2 && $1 ~ /^[A-Z.]{6}$/ {print $2}')"
HWACCELS="$("$FF" -hide_banner -hwaccels 2>/dev/null | tail -n +2 | tr -d '[:space:]' | tr '\n' ' ')"
FILTERS="$("$FF" -hide_banner -filters 2>/dev/null | awk 'NF>=2 {print $2}')"

has_enc()    { printf '%s\n' "$ENCODERS" | grep -qx "$1"; }
has_filter() { printf '%s\n' "$FILTERS"  | grep -qx "$1"; }

RENDER_NODES="$(ls /dev/dri/renderD* 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"

# nvidia-smi is not a reliable oracle on its own: a broken/hybrid driver makes it
# exit 255 while printing "Failed to initialize NVML: Unknown Error" on STDOUT, so
# a naive capture turns that error text into a GPU name and every *nvenc entry
# gets reported OK. Require a zero exit code AND a plausible name.
NVIDIA=""
NVIDIA_NOTE=""
if command -v nvidia-smi >/dev/null 2>&1; then
    nv_out="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)"
    nv_rc=$?
    case "$nv_out" in
        *Failed*|*failed*|*Error*|*error*|*ERROR*) nv_out="" ;;
    esac
    if [ "$nv_rc" -eq 0 ] && [ -n "$nv_out" ]; then
        NVIDIA="$(printf '%s' "$nv_out" | head -1 | tr -d '\r')"
    else
        NVIDIA_NOTE="nvidia-smi present but no usable GPU (rc=$nv_rc)"
    fi
fi

# ---------- report header ----------
echo "==== ffmpeg_bat_git environment capability report ===="
echo "date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "host     : $(hostname 2>/dev/null) ($(uname -srm))"
echo "os family: $OSFAMILY"
echo "repo     : $REPO"
echo "ffmpeg   : $("$FF" -hide_banner -version 2>/dev/null | head -1)"
echo "which    : ffmpeg=$FF ffprobe=${FP:-<missing>}"
echo "shell    : $BASH_VERSION"
echo "scope    : .sh family (the .bat family is covered by test/bat/check_env.bat on Windows)"
echo "mode     : $( [ "$PROBE" = 1 ] && echo 'DEEP (--probe: each candidate is really run)' || echo 'QUICK (static inventory; use --probe to really run them)' )"
echo

echo "---- host capability facts ----"
printf '  render nodes : %s\n' "${RENDER_NODES:-<none>}"
printf '  nvidia gpu   : %s\n' "${NVIDIA:-${NVIDIA_NOTE:-<no nvidia-smi>}}"
printf '  hwaccels     : %s\n' "${HWACCELS:-<none>}"
n_enc=$(printf '%s\n' "$ENCODERS" | grep -c . || true)
printf '  encoders     : %s listed\n' "$n_enc"
for e in libx264 libx265 h264_qsv hevc_qsv av1_qsv h264_vaapi hevc_vaapi h264_nvenc hevc_nvenc av1_nvenc; do
    if has_enc "$e"; then printf '  enc  %-12s: yes\n' "$e"; else printf '  enc  %-12s: NO\n' "$e"; fi
done
echo

# ---------- entry -> requirement map ----------
# Format: <entry>|<encoder-or-dash>|<device kind>|<note>
#   device kind: none | render | nvidia | cygwin
# The list is read line by line: the note field contains spaces, so `for x in $(...)`
# would split a single spec into several words.
entry_requirements() {
    cat <<'EOF'
ffmpeg_libx264.sh|libx264|none|software H.264 (always available with a full build)
ffmpeg_libx265.sh|libx265|none|software HEVC (always available with a full build)
ffmpeg_avc_qsv.sh|h264_qsv|render|Intel Quick Sync (needs an Intel GPU)
ffmpeg_hevc_qsv.sh|hevc_qsv|render|Intel Quick Sync (needs an Intel GPU)
ffmpeg_av1_qsv.sh|av1_qsv|render|AV1 QSV needs Arrow Lake / Lunar Lake or newer iGPU
ffmpeg_hevc_nvenc.sh|hevc_nvenc|nvidia|NVIDIA NVENC HEVC
ffmpeg_av1_nvenc.sh|av1_nvenc|nvidia|AV1 NVENC needs Ada (RTX 40) or newer
ffmpeg_h264_vaapi.sh|h264_vaapi|render|VAAPI is a Linux kernel API
ffmpeg_hevc_vaapi.sh|hevc_vaapi|render|VAAPI is a Linux kernel API
ffmpeg_hevc_nvenc_cygwin.sh|hevc_nvenc|cygwin|Cygwin-only variant (cuvid + hwdownload)
ffmpeg_copy_to_mp4.sh|-|none|remux only, no encoder involved
EOF
}

# Wrapper entries call one of the above; their status is inherited.
wrapper_target() {   # wrapper_target <file> -> the ffmpeg_*.sh it invokes
    grep -o 'ffmpeg_[a-z0-9_]*\.sh' "$REPO/$1" 2>/dev/null | head -1
}

classify() {   # classify <entry> <encoder> <device> -> status
    local e="$1" enc="$2" dev="$3"
    [ "$enc" = "-" ] && { echo "OK"; return; }
    if ! has_enc "$enc"; then echo "NO-ENCODER"; return; fi
    case "$e" in
        *_vaapi.sh)
            # VAAPI talks straight to the Linux DRM subsystem.
            if [ "$OSFAMILY" != "linux" ]; then echo "N/A-OS"; return; fi ;;
        *_nvenc_cygwin.sh)
            if [ "$OSFAMILY" != "cygwin" ]; then echo "N/A-OS"; return; fi
            has_filter hwdownload || { echo "NO-ENCODER"; return; } ;;
    esac
    case "$dev" in
        none)    echo "OK" ;;
        render)
            if [ "$OSFAMILY" = "linux" ]; then
                if [ -n "$RENDER_NODES" ]; then echo "OK"; else echo "NO-DEVICE"; fi
            elif [ "$OSFAMILY" = "cygwin" ] || [ "$OSFAMILY" = "msys" ]; then
                # On Windows the iGPU is reached through the vendor driver, not
                # through /dev/dri -- nothing here can confirm it statically.
                echo "UNKNOWN"
            else
                echo "N/A-OS"
            fi ;;
        nvidia)
            if [ -n "$NVIDIA" ]; then
                case "$enc" in av1_*) echo "UNKNOWN" ;; *) echo "OK" ;; esac
            else echo "NO-DEVICE"; fi ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Extra guards that a static encoder list cannot express.
apply_extra_guards() {   # apply_extra_guards <entry> <current status>
    local e="$1" s="$2"
    [ "$s" = "OK" ] || { echo "$s"; return; }
    case "$e" in
        ffmpeg_av1_qsv.sh)
            # av1_qsv ships in recent builds but only runs on Arrow Lake+ iGPUs,
            # which no version string reports reliably.
            echo "UNKNOWN" ;;
        *) echo "$s" ;;
    esac
}

# ---------- the table ----------
echo "---- entries ----"
printf '%-12s %-30s %s\n' "STATUS" "ENTRY" "NOTE"
printf '%-12s %-30s %s\n' "------------" "------------------------------" "------------------------------------"

STATUS_OF_ENTRY=""
COUNT_OK=0; COUNT_NO=0; COUNT_UNK=0
while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    entry="${spec%%|*}"
    rest="${spec#*|}"
    enc="${rest%%|*}"
    rest="${rest#*|}"
    dev="${rest%%|*}"
    note="${rest#*|}"

    if [ ! -f "$REPO/$entry" ]; then
        st="NO-ENTRY"; why="file missing from the repo"
    else
        st="$(classify "$entry" "$enc" "$dev")"
        st="$(apply_extra_guards "$entry" "$st")"
        why="$note"
        case "$st" in
            NO-ENCODER) why="ffmpeg build has no $enc -- $note" ;;
            NO-DEVICE)  why="no usable device on this host ($enc present) -- $note" ;;
            N/A-OS)     why="not applicable on $OSFAMILY -- $note" ;;
            UNKNOWN)    why="$note; needs --probe to decide" ;;
        esac
    fi

    printf '%-12s %-30s %s\n' "$st" "$entry" "$why"
    STATUS_OF_ENTRY="$STATUS_OF_ENTRY$entry=$st
"
    case "$st" in
        OK) COUNT_OK=$((COUNT_OK+1)) ;;
        UNKNOWN) COUNT_UNK=$((COUNT_UNK+1)) ;;
        *) COUNT_NO=$((COUNT_NO+1)) ;;
    esac
done < <(entry_requirements)

# wrappers inherit the status of the entry they drive
for w in convert_from_list_cuda.sh convert_from_list_libx265.sh convert_from_list_qsv.sh repack_from_list.sh; do
    if [ ! -f "$REPO/$w" ]; then
        printf '%-12s %-30s %s\n' "NO-ENTRY" "$w" "file missing from the repo"
        continue
    fi
    tgt="$(wrapper_target "$w")"
    if [ -z "$tgt" ]; then
        printf '%-12s %-30s %s\n' "OK" "$w" "does not drive a single encoder (remux / copy)"
        COUNT_OK=$((COUNT_OK+1))
        continue
    fi
    st="$(printf '%s' "$STATUS_OF_ENTRY" | grep "^$tgt=" | cut -d= -f2)"
    st="${st:-UNKNOWN}"
    printf '%-12s %-30s %s\n' "$st" "$w" "wrapper -> $tgt"
    case "$st" in
        OK) COUNT_OK=$((COUNT_OK+1)) ;;
        UNKNOWN) COUNT_UNK=$((COUNT_UNK+1)) ;;
        *) COUNT_NO=$((COUNT_NO+1)) ;;
    esac
done
echo

# ---------- tooling + data inventory ----------
echo "---- repo tooling ----"
for t in test/lint/lint.py test/lint/selftest.py test/sh/smoke_sh.sh test/sh/check_env.sh \
         test/bat/smoke_ffmpeg_bat.bat test/bat/check_env.bat test/README.md; do
    if [ -f "$REPO/$t" ]; then printf '  present  %s\n' "$t"; else printf '  MISSING  %s\n' "$t"; fi
done
echo "---- bitrate tables ----"
for c in lib/bitrate_table_avc.csv lib/bitrate_table_hevc.csv lib/bitrate_table_av1.csv; do
    if [ -f "$REPO/$c" ]; then
        n=$(awk 'END{print NR-1}' "$REPO/$c")
        printf '  %-30s %s rows\n' "$c" "$n"
    else
        printf '  %-30s MISSING\n' "$c"
    fi
done
echo

# ---------- deep probe ----------
if [ "$PROBE" = 1 ]; then
    echo "---- deep probe (each entry is really run on a 3s clip) ----"
    [ -z "$FP" ] && { echo "WARNING: ffprobe missing, output verification is skipped" >&2; }
    mkdir -p "$W"
    # Native Windows ffmpeg.exe cannot open an MSYS/Cygwin POSIX path (/c/... or
    # /tmp/...): MSYS does not rewrite a path that arrives as a *value* rather than
    # as a command argument. Normalise the scratch dir to the mixed form (C:/...)
    # once, so every absolute path this script hands out is usable as-is.
    if command -v cygpath >/dev/null 2>&1; then
        W="$(cygpath -m "$W")"
    fi
    TINY="$W/probe_clip.mp4"
    if [ ! -f "$TINY" ]; then
        "$FF" -hide_banner -loglevel error -f lavfi -i "testsrc2=size=320x240:rate=30" \
              -f lavfi -i "sine=frequency=440:sample_rate=44100" -t 3 \
              -c:v libx264 -preset ultrafast -b:v 200k -pix_fmt yuv420p \
              -c:a aac -b:a 64k -shortest -y "$TINY" \
            || { echo "FATAL: cannot build the probe clip" >&2; exit 2; }
    fi
    printf '%-12s %-30s %s\n' "STATUS" "ENTRY" "NOTE"
    printf '%-12s %-30s %s\n' "------------" "------------------------------" "------------------------------------"
    p_ok=0; p_fail=0
    for f in "$REPO"/ffmpeg_*.sh "$REPO"/convert_from_list_*.sh "$REPO"/repack_from_list.sh; do
        [ -f "$f" ] || continue
        b="$(basename "$f")"
        d="$W/$(basename "$b" .sh)"
        mkdir -p "$d"; cp -f "$TINY" "$d/clip.mp4"
        lf="$d/run.log"; rm -f "$d/clip-compressed.mp4"
        case "$b" in
            convert_from_list_*|repack_from_list.sh)
                # These take a LIST FILE, not a clip. The list holds an ABSOLUTE
                # path: with a relative name the entry canonicalises it itself and
                # MSYS turns that into a POSIX path (/c/...), which a native
                # ffmpeg.exe then cannot open ("Error opening input file"). Spaces
                # in the path are fine - run_list reads the whole line and quotes
                # it when calling the encoder.
                printf '%s\n' "$d/clip.mp4" > "$d/list.txt"
                rc=0
                ( cd "$d" && bash "$f" "$d/list.txt" < /dev/null > "$lf" 2>&1 ) || rc=$?
                note="rc=0 - list mode" ;;
            *)
                # `cmd || rc=$?` and not `cmd; rc=$?`: the assignment after the
                # subshell would otherwise overwrite $? with its own status.
                rc=0
                ( cd "$d" && bash "$f" "$d/clip.mp4" < /dev/null > "$lf" 2>&1 ) || rc=$?
                note="rc=0" ;;
        esac
        if [ $rc -eq 0 ]; then
            printf '%-12s %-30s %s\n' "PROBE-OK" "$b" "$note"
            p_ok=$((p_ok+1))
        else
            firsterr="$(grep -m1 -i -e 'error' -e 'not recognized' -e 'Invalid' -e 'No such' "$lf" 2>/dev/null | cut -c1-70)"
            printf '%-12s %-30s %s\n' "PROBE-FAIL" "$b" "rc=$rc ${firsterr:+| $firsterr}"
            p_fail=$((p_fail+1))
        fi
    done
    echo
    echo "probe logs: $W/<entry>/run.log"
    echo
fi

echo "==== summary ===="
echo "entries usable (OK): $COUNT_OK"
echo "entries not usable here: $COUNT_NO   (NO-ENCODER / NO-DEVICE / N/A-OS / NO-ENTRY)"
echo "entries needing --probe: $COUNT_UNK"
[ "$PROBE" = 1 ] && echo "probe results: ok=$p_ok fail=$p_fail"
echo
echo "NOTE: a status here is a statement about THIS machine, not about the"
echo "      entry itself. NO-DEVICE just means the hardware is absent."
exit 0
