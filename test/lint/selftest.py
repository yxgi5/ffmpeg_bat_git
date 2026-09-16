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


def make_inv(root):
    bat = sorted(f for f in os.listdir(root)
                 if f.endswith(".bat") and os.path.isfile(os.path.join(root, f)))
    sh = sorted(f for f in os.listdir(root)
                if f.endswith(".sh") and os.path.isfile(os.path.join(root, f)))
    lib = [os.path.join("lib", f) for f in sorted(os.listdir(os.path.join(root, "lib")))]
    return {
        "bat": bat, "root_bat": bat, "root_sh": sh, "lib": lib,
        "test_bat": [], "test_sh": [], "md": [],
        "all_bat": bat + lib, "all_sh": sh + ["lib/common.sh"],
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
