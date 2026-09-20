#!/usr/bin/env python3
# ============================================================
# selftest.py - regression tests FOR the linter itself
#
# A checker that is only ever observed reporting "all clean" is worthless: it
# may be blind. Every case below is a small synthetic repo whose expected
# verdict is known, so this file pins down BOTH directions:
#
#   * recall    -- a known-bad construct must be flagged, and
#   * precision -- a known-good construct must NOT be flagged.
#
# The precision cases are the ones that actually matter here: every one of them
# is a false positive the real repository produced at some point during
# development (see the comments in lint.py for the concrete history).
#
# Usage: python3 test/lint/selftest.py
# Exit code: 0 = all cases behave as documented, 1 = at least one case is wrong
# ============================================================
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

_spec = importlib.util.spec_from_file_location("lint_under_test",
                                               os.path.join(HERE, "lint.py"))
lint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lint)

# A lib/common.bat good enough for the helper-dispatch checks.
COMMON_BAT = "\n".join([
    "@echo off",
    "setlocal",
    'if /I "%~1"=="extract" goto extract',
    'if /I "%~1"=="lookup_bitrate" goto lookup_bitrate',
    "exit /b 1",
    ":extract",
    "exit /b 0",
    ":lookup_bitrate",
    "exit /b 0",
])

# ---------------------------------------------------------------- the cases
# ("id", "file", crlf, content, {check ids that MUST fire}, {ids that must NOT})
CASES = [
    (
        "clean file is silent",
        "clean.bat", True,
        "@echo off\n"
        "set SRC_FILE=\"C:\\clips\\a.mp4\"\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -i %SRC_FILE% -c:v libx264\n"
        "exit /b 0\n",
        set(), {"L01", "L02", "L04", "L05", "L06", "L07", "L08", "L09", "L13"},
    ),
    (
        "L01: CRLF in a .sh is caught",
        "bad_eol.sh", True,
        "#!/bin/bash\necho hi\n",
        {"L01"}, set(),
    ),
    (
        "L04: non-ASCII inside the cp65001 guard is caught",
        "guard.bat", True,
        "@echo off\nrem 守卫区不该有中文\n:main\nsetlocal\nexit /b 0\n",
        {"L04"}, set(),
    ),
    (
        "L06: unbalanced literal quote is caught",
        "quote.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\n"
        "exit /b 0\n",
        {"L06"}, set(),
    ),
    (
        "L06 precision: %VAR:\"=% must not look like an odd quote count",
        "qsubst.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set SRC_FILE=\"%~1\"\n"
        "set SRC_FILE=\"%SRC_FILE:\"=%\"\n"
        "exit /b 0\n",
        set(), {"L06"},
    ),
    (
        "L07: unresolved label is caught",
        "label.bat", True,
        "@echo off\n:main\nsetlocal\ncall :nope\nexit /b 0\n",
        {"L07"}, set(),
    ),
    (
        "L08: wrapped set referencing a quoted variable is caught",
        "wrapped.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set \"CMD=%RUN_COM% -i input.mp4\"\n"
        "exit /b 0\n",
        {"L08"}, set(),
    ),
    (
        "L09: a value re-wrapped in extra quotes leaks its separator",
        "leak.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set SRC_FILE=\"C:\\clips\\a & b.mp4\"\n"
        "echo \"%SRC_FILE%\"\n"
        "exit /b 0\n",
        {"L09"}, {"L08"},
    ),
    (
        "L09 precision: the safe `set VAR=%QVAR%` idiom is clean",
        "safe.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set SRC_FILE=\"C:\\clips\\a & b.mp4\"\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -i %SRC_FILE%\n"
        "exit /b 0\n",
        set(), {"L09"},
    ),
    (
        "L09 precision: a literal `endlocal & set` is script syntax, not a leak",
        "literal_amp.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set SRC_FILE=\"C:\\clips\\a & b.mp4\"\n"
        "endlocal & set OUT=%SRC_FILE%\n"
        "exit /b 0\n",
        set(), {"L09"},
    ),
    (
        "L09 precision: a FOR-variable modifier is not a metachar carrier",
        "forvar.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set SRC_FILE=\"C:\\clips\\a & b.mp4\"\n"
        "for %%A in (%SRC_FILE%) do set SRC_SIZE=%%~zA\n"
        "exit /b 0\n",
        set(), {"L09"},
    ),
    (
        "L09 precision: set /p turns a probe-command variable into a number",
        "flow.bat", True,
        "@echo off\n:main\nsetlocal\n"
        "set FB_TMP=%TEMP%\\x.tmp\n"
        "set SRC_BITRATE=\"C:\\ffmpeg\\ffprobe.exe\" -v error\n"
        "set /p SRC_BITRATE=<\"%FB_TMP%\"\n"
        "echo \"%SRC_BITRATE%\"\n"
        "exit /b 0\n",
        set(), {"L09"},
    ),
    (
        "L13: an undocumented exit code is caught",
        "exitcode.bat", True,
        "@echo off\n:main\nsetlocal\nexit /b 7\n",
        {"L13"}, set(),
    ),
    (
        "L15: an entry .bat that swallows ffmpeg failure is caught",
        "ffmpeg_probe.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0\n"
        "echo RUN_COM4:%RUN_COM%\n"
        "%RUN_COM%\n"
        "echo ERRORLEVEL:%ERRORLEVEL%\n"
        "exit /b 0\n",
        {"L15"}, {"L01", "L02", "L04", "L05", "L06", "L07", "L13"},
    ),
    (
        "L15 precision: an entry that propagates the failure stays silent",
        "ffmpeg_probe.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0\n"
        "%RUN_COM%\n"
        "set \"FB_RC=%ERRORLEVEL%\"\n"
        "if not \"%FB_RC%\"==\"0\" (\n"
        "    echo Convert failed! rc=%FB_RC%\n"
        "    exit /b 1\n"
        ")\n"
        "exit /b 0\n",
        set(), {"L15", "L01", "L02", "L04", "L05", "L06", "L07", "L13"},
    ),
    (
        "L15: `if errorlevel 1` cannot see the NEGATIVE exit code ffmpeg returns",
        "ffmpeg_probe.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0\n"
        "%RUN_COM%\n"
        "if errorlevel 1 (\n"
        "    echo Convert failed! rc=%ERRORLEVEL%\n"
        "    exit /b 1\n"
        ")\n"
        "exit /b 0\n",
        {"L15"}, {"L01", "L02", "L04", "L05", "L06", "L07", "L13"},
    ),
    (
        "L15: a numeric NEQ 0 guard on %ERRORLEVEL% is accepted as negative-safe",
        "ffmpeg_probe.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0\n"
        "%RUN_COM%\n"
        "if %ERRORLEVEL% NEQ 0 (\n"
        "    echo Convert failed! rc=%ERRORLEVEL%\n"
        "    exit /b 1\n"
        ")\n"
        "exit /b 0\n",
        set(), {"L15", "L01", "L02", "L04", "L05", "L06", "L07", "L13"},
    ),
    (
        "L15: a list wrapper that ignores a failed child is caught",
        "convert_from_list_probe.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "for /f \"usebackq delims=\" %%i in (\"%SRC_FILE%\") do "
        "call \"%~dp0ffmpeg_probe.bat\" \"%%i\"\n",
        {"L15"}, {"L01", "L02", "L04", "L05", "L06", "L07", "L13"},
    ),
    (
        "L16: an mp4 entry without a stream map is caught",
        "ffmpeg_probe.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -i %SRC_FILE% -c:v libx264\n"
        "%RUN_COM%\n"
        "set \"FB_RC=%ERRORLEVEL%\"\n"
        "if not \"%FB_RC%\"==\"0\" (\n"
        "    echo Convert failed! rc=%FB_RC%\n"
        "    exit /b 1\n"
        ")\n"
        "exit /b 0\n",
        {"L16"}, {"L01", "L02", "L04", "L05", "L06", "L07", "L13", "L15"},
    ),
    (
        "L16 precision: a fully mapped .sh entry stays silent",
        "ffmpeg_probe.sh", False,
        "#!/bin/bash\n"
        "CMD=(ffmpeg -hide_banner)\n"
        "CMD+=(-i \"$ABS_NAME\")\n"
        "CMD+=(-map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 "
        "-map_chapters 0)\n"
        "CMD+=(-c:v libx264 \"$TARGET_FILE\")\n"
        "\"${CMD[@]}\"\n"
        "if [ $? -ne 0 ]; then\n"
        "    echo -e \"Convert failed\"\n"
        "    exit 1\n"
        "fi\n"
        "exit 0\n",
        set(), {"L03", "L15", "L16"},
    ),
    (
        "L17: a remux entry that leaves moov behind mdat is caught",
        "ffmpeg_copy_to_mp4.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set RUN_COM=\"C:\\ffmpeg\\ffmpeg.exe\" -hide_banner\n"
        "set RUN_COM=%RUN_COM% -i %SRC_FILE% -c:v copy -c:a copy "
        "-map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0\n"
        "%RUN_COM%\n"
        "set \"FB_RC=%ERRORLEVEL%\"\n"
        "if not \"%FB_RC%\"==\"0\" (\n"
        "    echo Convert failed! rc=%FB_RC%\n"
        "    exit /b 1\n"
        ")\n"
        "exit /b 0\n",
        {"L17"}, {"L01", "L02", "L04", "L05", "L06", "L07", "L13", "L15", "L16"},
    ),
    (
        "L17 precision: a .sh remux entry with +faststart stays silent",
        "ffmpeg_copy_to_mp4.sh", False,
        "#!/bin/bash\n"
        "CMD=(ffmpeg -hide_banner)\n"
        "CMD+=(-i \"$ABS_NAME\")\n"
        "CMD+=(-c:v copy -c:a copy)\n"
        "CMD+=(-map 0:v -map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 "
        "-map_chapters 0)\n"
        "CMD+=(-movflags +faststart)\n"
        "CMD+=(-n \"$TARGET_FILE\")\n"
        "\"${CMD[@]}\"\n"
        "if [ $? -ne 0 ]; then\n"
        "    echo -e \"Convert failed\"\n"
        "    exit 1\n"
        "fi\n"
        "exit 0\n",
        set(), {"L03", "L15", "L16", "L17"},
    ),
    (
        "L18: a test\\bat tool reading %REPO% without ever assigning it is caught",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "call \"%REPO%\\lib\\common.bat\" extract %SRC_FILE% OUT_PATH OUT_NAME\n"
        "pause\n"
        "exit /b 0\n",
        {"L18"}, set(),
    ),
    (
        "L18: an anchor assigned AFTER its first use is caught",
        "probe_tool.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "call \"%REPO%\\lib\\common.bat\" extract %SRC_FILE% OUT_PATH OUT_NAME\n"
        "set \"REPO=%~dp0\"\n"
        "exit /b 0\n",
        {"L18"}, set(),
    ),
    (
        "L18: a test\\bat tool that never self-anchors on %~dp0..\\.. is caught",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~1\"\n"
        "call \"%REPO%\\lib\\common.bat\" extract %SRC_FILE% OUT_PATH OUT_NAME\n"
        "exit /b 0\n",
        {"L18"}, set(),
    ),
    (
        "L18 precision: a properly self-anchored test\\bat tool stays silent",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "for %%I in (\"%REPO%\") do set \"REPO=%%~fI\"\n"
        "if not exist \"%REPO%\\lib\\common.bat\" goto NO_REPO\n"
        "call \"%REPO%\\lib\\common.bat\" extract %SRC_FILE% OUT_PATH OUT_NAME\n"
        "exit /b 0\n"
        ":NO_REPO\n"
        "exit /b 2\n",
        set(), {"L18"},
    ),
    (
        "L19: a for-backtick running a variable-expanded program path is caught",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "set \"FFPROBE_PATH=%FF_BIN%\\ffprobe.exe\"\n"
        "for /f \"usebackq delims=\" %%W in (`%FFPROBE_PATH% -v error "
        "-select_streams v:0 -show_entries stream=width -of csv=p=0 "
        "\"%SRC%\"`) do set \"SW=%%W\"\n"
        "exit /b 0\n",
        {"L19"}, set(),
    ),
    (
        "L19: the quoted `\"%FFPROBE_PATH%\" ...` form is caught too",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "set \"FFPROBE_PATH=%FF_BIN%\\ffprobe.exe\"\n"
        "for /f \"usebackq delims=\" %%R in (`\"%FFPROBE_PATH%\" -v error "
        "-select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "
        "\"%OUT%\"`) do set \"DEL=%%R\"\n"
        "exit /b 0\n",
        {"L19"}, set(),
    ),
    (
        "L19 precision: PATH-resolved tools (bare ffprobe / powershell) are legal",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "for /f \"usebackq delims=\" %%W in (`ffprobe -v error -select_streams "
        "v:0 -show_entries stream=width -of csv=p=0 \"%SRC%\"`) do set \"SW=%%W\"\n"
        "for /f \"usebackq delims=\" %%V in (`powershell -NoProfile -Command "
        "\"(Get-Content -Raw '%JS%' | ConvertFrom-Json).pooled_metrics.vmaf.mean\"`) "
        "do set \"VM=%%V\"\n"
        "exit /b 0\n",
        set(), {"L19"},
    ),
    (
        "L20: a .sh needing libvmaf but trusting PATH is caught",
        "test/sh/probe_calib.sh", False,
        "#!/bin/bash\n"
        "ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf \\\n"
        "    || { echo \"ERROR: this ffmpeg build has no libvmaf filter\"; exit 2; }\n"
        "ffmpeg -y -i \"$1\" -c:v libx265 -preset fast -b:v 1M out.mp4\n",
        {"L20"}, set(),
    ),
    (
        "L21: an argument expansion nested inside quotes is caught "
        "(the :ff_satisfies shape)",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "call \"%REPO%\\lib\\common.bat\" find_ffmpeg FF_BIN\n"
        "if errorlevel 1 goto NO_FFMPEG\n"
        "call :ff_satisfies \"%FF_BIN%\"\n"
        "if not errorlevel 1 exit /b 0\n"
        "exit /b 1\n"
        ":ff_satisfies\n"
        "\"%1\\ffmpeg.exe\" -hide_banner -filters 2>nul | "
        "findstr /c:\"libvmaf\" >nul\n"
        "exit /b 0\n",
        {"L21"}, set(),
    ),
    (
        "L20 precision: a capability-aware .sh lookup is legal",
        "test/sh/probe_calib.sh", False,
        "#!/bin/bash\n"
        "FF=\"$(find_ffmpeg --need-filter libvmaf)\" || exit 2\n"
        "FP=\"$(find_ffprobe \"$FF\")\" || exit 2\n"
        "\"$FF\" -y -i \"$1\" -c:v libx265 -preset fast -b:v 1M out.mp4\n",
        set(), {"L20"},
    ),
    (
        "L21 precision: a quoted path built from a %VAR% is legal",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "call \"%REPO%\\lib\\common.bat\" find_ffmpeg FF_BIN\n"
        "if errorlevel 1 goto NO_FFMPEG\n"
        "\"%FF_BIN%\\ffmpeg.exe\" -hide_banner -filters 2>nul | "
        "findstr /c:\"libvmaf\" >nul || goto NO_VMAF\n"
        "exit /b 0\n",
        set(), {"L21", "L20"},
    ),
    (
        "L21 precision: \"%~1\" (quote-stripping) and a verbatim \"%1\" are legal",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "call :probe \"%1\"\n"
        "exit /b 0\n"
        ":probe\n"
        "\"%~1\\ffmpeg.exe\" -hide_banner -filters 2>nul | "
        "findstr /c:\"libvmaf\" >nul\n"
        "exit /b 0\n",
        set(), set(),
    ),
    (
        "L20 precision: check_env is an inventory tool, not a libvmaf consumer",
        "test/sh/check_env.sh", False,
        "#!/bin/bash\n"
        "# reports whether the ffmpeg on PATH has libvmaf\n"
        "if command -v ffmpeg >/dev/null 2>&1; then\n"
        "    ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf "
        "&& echo \"filt libvmaf : yes\"\n"
        "fi\n",
        set(), {"L20"},
    ),
    (
        "L22: a bare '=' in a call argument list is caught "
        "(the :probe_field shape that printed delivered=0)",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "set \"OUT=C:\\Temp\\x.mp4\"\n"
        "call \"%REPO%\\lib\\common.bat\" probe_field \"%OUT%\" stream=bit_rate DEL\n"
        "if not defined DEL set \"DEL=0\"\n"
        "exit /b 0\n",
        {"L22"}, set(),
    ),
    (
        "L22 precision: a keyword argument is safe",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "set \"REPO=%~dp0..\\..\"\n"
        "set \"OUT=C:\\Temp\\x.mp4\"\n"
        "call \"%REPO%\\lib\\common.bat\" probe_field \"%OUT%\" vbr DEL\n"
        "if not defined DEL set \"DEL=0\"\n"
        "exit /b 0\n",
        set(), {"L22", "L21", "L20", "L19"},
    ),
    (
        "L22 precision: a quoted '=' is split-safe and legal",
        "test/bat/probe_calib.bat", True,
        "@echo off\n"
        ":main\n"
        "setlocal\n"
        "call :probe \"opt=1\"\n"
        "exit /b 0\n"
        ":probe\n"
        "echo %~1\n"
        "exit /b 0\n",
        set(), {"L22"},
    ),
]


def build(root, files):
    for rel, text, crlf in files:
        p = os.path.join(root, rel)
        d = os.path.dirname(p)
        if d and not os.path.isdir(d):
            os.makedirs(d)
        data = text.replace("\n", "\r\n" if crlf else "\n")
        with open(p, "wb") as fh:
            fh.write(data.encode("utf-8"))


def listing(root, *parts):
    d = os.path.join(root, *parts)
    if not os.path.isdir(d):
        return []
    return [os.path.join(*parts, f) for f in sorted(os.listdir(d)) if os.path.isfile(os.path.join(d, f))]


def make_inv(root):
    """Same shape as lint.inventory(). The test/bat and test/sh trees are only
    populated for the cases that need them (an L18 case lives two levels down),
    every other case still gets the flat root-only inventory."""
    bat = [f for f in listing(root) if f.endswith(".bat")]
    sh = [f for f in listing(root) if f.endswith(".sh")]
    test_bat = [f for f in listing(root, "test", "bat") if f.endswith(".bat")]
    test_sh = [f for f in listing(root, "test", "sh") if f.endswith(".sh")]
    lib = listing(root, "lib")
    return {
        "bat": bat, "root_bat": bat, "root_sh": sh, "lib": lib,
        "test_bat": test_bat, "test_sh": test_sh, "md": [],
        "all_bat": bat + lib + test_bat, "all_sh": sh + test_sh + ["lib/common.sh"],
    }


def run_checks(inv):
    lint.PASS[:] = []
    lint.FAIL[:] = []
    lint.WARN[:] = []
    lint.SKIP[:] = []
    lint.check_eol_and_bom(inv)
    lint.check_shebang(inv)
    lint.check_bat_guard_ascii(inv)
    lint.check_bat_syntax_shape(inv)
    lint.check_bat_labels(inv)
    qbf = lint.quoted_vars_by_line(inv)
    lint.check_wrapped_set(inv, qbf)
    lint.check_metachars(inv, qbf, lint.calibrate_scanner())
    lint.check_sh_invariants(inv)
    lint.check_exit_codes(inv)
    lint.check_fail_propagation(inv)
    lint.check_stream_map(inv)
    lint.check_moov_front(inv)
    lint.check_repo_anchor(inv)
    lint.check_backtick_program(inv)
    lint.check_ffmpeg_requirement(inv)
    lint.check_quoted_arg_expansion(inv)
    lint.check_call_arg_equals(inv)
    return {cid for cid, _ in lint.FAIL}


def main():
    real_root = lint.ROOT
    failures = 0
    print("lint selftest: %d cases" % len(CASES))
    print("")
    try:
        for name, fname, crlf, content, must, must_not in CASES:
            root = tempfile.mkdtemp(prefix="lint_selftest_")
            try:
                build(root, [("lib/common.bat", COMMON_BAT, True),
                             (fname, content, crlf)])
                lint.ROOT = root
                fired = run_checks(make_inv(root))
            finally:
                lint.ROOT = real_root
                shutil.rmtree(root, ignore_errors=True)
            missed = must - fired
            extra = fired & must_not
            if missed or extra:
                failures += 1
                print("[FAIL] %s" % name)
                if missed:
                    print("         expected to fire but did not: %s"
                          % ", ".join(sorted(missed)))
                if extra:
                    print("         fired although it must not:  %s"
                          % ", ".join(sorted(extra)))
            else:
                detail = ("fired %s" % ",".join(sorted(must))) if must else "stayed silent"
                print("[PASS] %s (%s)" % (name, detail))
    finally:
        lint.ROOT = real_root
    print("")
    print("---- %d cases, %d FAIL ----" % (len(CASES), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
