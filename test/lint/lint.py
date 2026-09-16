#!/usr/bin/env python3
# ============================================================
# lint.py - static + parity checks for ffmpeg_bat_git
#
#   Site: <repo>/test/lint/lint.py   (repo root = two levels up)
#   Deps: python3 stdlib only. Output is ASCII so it survives any console
#         codepage (this repo has a long history of cp936/cp65001 pain).
#
# Usage:
#   python3 test/lint/lint.py                 # everything
#   python3 test/lint/lint.py --lint-only     # static checks only
#   python3 test/lint/lint.py --parity-only   # cross-family parity only
#   python3 test/lint/lint.py --list          # print the check catalogue
#
# Exit code: 0 = clean (warnings allowed), 1 = findings, 2 = scanner self-test
#            failed (treat every other result as unreliable)
# ============================================================
import argparse
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

PASS = []
FAIL = []
WARN = []
SKIP = []


def ok(cid, msg):
    PASS.append((cid, msg))


def bad(cid, msg):
    FAIL.append((cid, msg))


def warn(cid, msg):
    WARN.append((cid, msg))


def skip(cid, msg):
    SKIP.append((cid, msg))


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def read_text(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    return raw, raw.decode("utf-8", "replace")


def lf_lines(text):
    """Logical lines, CRLF-aware, CR stripped."""
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


# ---------------------------------------------------------------- inventory
def inventory():
    root_bat = sorted(f for f in os.listdir(ROOT)
                      if f.endswith(".bat") and os.path.isfile(os.path.join(ROOT, f)))
    root_sh = sorted(f for f in os.listdir(ROOT)
                     if f.endswith(".sh") and os.path.isfile(os.path.join(ROOT, f)))
    lib = [os.path.join("lib", f) for f in sorted(os.listdir(os.path.join(ROOT, "lib")))]
    test_bat = [os.path.join("test/bat", f) for f in sorted(os.listdir(os.path.join(ROOT, "test", "bat")))
                if f.endswith(".bat")]
    test_sh = [os.path.join("test/sh", f) for f in sorted(os.listdir(os.path.join(ROOT, "test", "sh")))
               if f.endswith(".sh")]
    md = [f for f in sorted(os.listdir(ROOT)) if f.endswith(".md")] + ["test/README.md"]
    return {
        "bat": [f for f in root_bat] + [os.path.join("test/bat", os.path.basename(f)) for f in []],
        "root_bat": root_bat,
        "root_sh": root_sh,
        "lib": lib,
        "test_bat": test_bat,
        "test_sh": test_sh,
        "md": md,
        "all_bat": root_bat + ["lib/common.bat"] + test_bat,
        "all_sh": root_sh + ["lib/common.sh"] + test_sh,
    }


# ---------------------------------------------------------------- L01 / L02
def check_eol_and_bom(inv):
    problems = []
    for f in inv["all_sh"] + inv["md"] + ["readme.md"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        raw, _ = read_text(p)
        if raw.count(b"\r\n"):
            problems.append("%s has %d CRLF line(s); .sh/.md must be LF" % (f, raw.count(b"\r\n")))
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        raw, _ = read_text(p)
        bare = raw.count(b"\n") - raw.count(b"\r\n")
        if bare:
            problems.append("%s has %d bare LF line(s); .bat must be CRLF" % (f, bare))
    if problems:
        for m in problems[:12]:
            bad("L01", m)
    else:
        ok("L01", "eol convention: .sh/.md = LF, .bat = CRLF (%d files)"
           % (len(inv["all_sh"]) + len(inv["md"]) + len(inv["all_bat"])))

    boms = []
    for f in inv["all_sh"] + inv["all_bat"] + inv["md"]:
        p = os.path.join(ROOT, f)
        if os.path.isfile(p):
            raw, _ = read_text(p)
            if raw.startswith(b"\xef\xbb\xbf"):
                boms.append(f)
    if boms:
        for m in boms:
            bad("L02", "%s starts with a UTF-8 BOM" % m)
    else:
        ok("L02", "no UTF-8 BOM in any source file")


# ---------------------------------------------------------------- L03
def check_shebang(inv):
    bads = []
    for f in inv["all_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        if not t.startswith("#!/bin/bash"):
            bads.append(f)
    if bads:
        for m in bads:
            bad("L03", "%s does not start with #!/bin/bash" % m)
    else:
        ok("L03", "every .sh starts with #!/bin/bash (%d files)" % len(inv["all_sh"]))


# ---------------------------------------------------------------- L04
def check_bat_guard_ascii(inv):
    """Everything above ':main' is the cp65001 guard: it must stay ASCII-only,
    because a non-ASCII byte there is read under an unknown codepage."""
    bads = []
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        head = []
        for ln in lines:
            if ln.strip() == ":main":
                break
            head.append(ln)
        else:
            continue  # no :main (e.g. lib/common.bat, opencmd.bat) -> not a guard file
        joined = "\n".join(head)
        if any(ord(c) > 127 for c in joined):
            bads.append(f)
    if bads:
        for m in bads:
            bad("L04", "%s has non-ASCII bytes inside the cp65001 guard region" % m)
    else:
        ok("L04", "cp65001 guard region is ASCII-only in every guarded .bat")


# ---------------------------------------------------------------- L05 / L06
# cmd expands `%VAR:"=%` (strip embedded quotes) BEFORE it parses quotes, so the
# quotes inside such a token are not literal and must not be counted by L06.
SUBST_TOKEN_RE = re.compile(r'%[A-Za-z_0-9~.*]+:[^%\r\n]*%')

# `goto :eof` is a cmd builtin, not a label in the file.
BUILTIN_LABELS = {"eof"}


def check_bat_syntax_shape(inv):
    paren_bad, quote_bad = [], []
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        opens = closes = 0
        for i, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if s.startswith("rem") or s.startswith("::"):
                continue
            if s.startswith("echo"):
                continue
            opens += s.count("(")
            closes += s.count(")")
            if SUBST_TOKEN_RE.sub("%SUBST%", s).count('"') % 2:
                quote_bad.append("%s:%d odd quote count: %s" % (f, i, s[:80]))
        if opens != closes:
            paren_bad.append("%s: %d '(' vs %d ')'" % (f, opens, closes))
    if paren_bad:
        for m in paren_bad:
            bad("L05", m)
    else:
        ok("L05", "paren balance ok in every .bat (rem/echo excluded)")
    if quote_bad:
        for m in quote_bad[:8]:
            bad("L06", m)
    else:
        ok("L06", "quote pairing ok on every non-rem .bat line")


# ---------------------------------------------------------------- L07
def check_bat_labels(inv):
    """call :label / goto label must resolve, and every helper call into
    lib/common.bat must name a function that the dispatcher actually knows."""
    missing, helpers, unknown = [], [], []
    common = os.path.join(ROOT, "lib", "common.bat")
    dispatch = set()
    if os.path.isfile(common):
        _, ct = read_text(common)
        for ln in lf_lines(ct):
            m = re.match(r'\s*if\s+/I\s+"%~1"=="([^"]+)"\s+goto\s+(\S+)', ln)
            if m:
                dispatch.add(m.group(1).lower())
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        labels = set()
        for ln in lines:
            m = re.match(r"\s*:([A-Za-z_][A-Za-z0-9_]*)", ln)
            if m:
                labels.add(m.group(1).lower())
        for i, ln in enumerate(lines, 1):
            s = ln.strip()
            if s.lower().startswith("rem"):
                continue
            for m in re.finditer(r"\b(?:call|goto)\s+:([A-Za-z_][A-Za-z0-9_]*)", s):
                tgt = m.group(1).lower()
                if tgt not in labels and tgt not in BUILTIN_LABELS:
                    missing.append("%s:%d -> :%s" % (f, i, m.group(1)))
            for m in re.finditer(r'call\s+"[^"]*common\.bat"\s+([A-Za-z_][A-Za-z0-9_]*)', s):
                helpers.append((f, i, m.group(1)))
    for f, i, h in helpers:
        if h.lower() not in dispatch:
            unknown.append("%s:%d calls unknown helper '%s'" % (f, i, h))
    if missing:
        for m in missing[:8]:
            bad("L07", "unresolved label: " + m)
    else:
        ok("L07", "every call :label / goto label resolves (%d helper call sites checked)"
           % len(helpers))
    if unknown:
        for m in unknown:
            bad("L07b", m)
    else:
        ok("L07b", "every lib/common.bat helper call names a dispatched function "
                   "(%d names in the dispatcher)" % len(dispatch))


# ---------------------------------------------------------------- quoted vars
# Any `%VAR%` or `%VAR:...=%` reference.
REF_RE = re.compile(r'%([A-Za-z_][A-Za-z0-9_]*)(?::[^%\r\n]*)?%')

SET_RE = re.compile(r'^\s*set\s+(?:"([A-Za-z_][A-Za-z0-9_]*)=(.*)"|([A-Za-z_][A-Za-z0-9_]*)=(.*))\s*$',
                    re.IGNORECASE)
# `set /p VAR=<file`  -> VAR gets the FILE CONTENT (a probed number here), the
# quotes belong to the redirect. `set /a VAR=...` always yields a number.
SETP_RE = re.compile(r'^\s*set\s+/p\s+([A-Za-z_][A-Za-z0-9_]*)\s*=', re.IGNORECASE)
SETA_RE = re.compile(r'^\s*set\s+/a\s+([A-Za-z_][A-Za-z0-9_]*)\s*=', re.IGNORECASE)
# `call "...lib\common.bat" extract <in> <VAR1> <VAR2>` -- lib/common.bat assigns
# those two output variables with a quoted value (`set %~4="..."`), so they become
# quote-carrying in the caller even though the caller never writes a quote itself.
HELPER_QUOTED_OUT = {"extract": (1, 2)}   # indices into the argument list

# `%~1` / `%~dp0` style references are bare after cmd strips the quotes.
ARG_REF_RE = re.compile(r"%~[a-z*]*\d+")
# `%%~zA` / `%%~nxA` are FOR-variable modifiers: they yield a size / a name, i.e.
# a plain token with no quotes and no metacharacters. They must NOT be expanded
# with the metachar sample or every `for %%A in (%SRC_FILE%)` line false-fires.
FOR_REF_RE = re.compile(r"%%~[a-z]*[A-Za-z]")
DIR_REF_RE = re.compile(r"%~d[a-z]*\d+")


def collect_set_assignments(inv):
    """name -> list of (file, line, rhs, wrapped)"""
    out = {}
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for i, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if s.lower().startswith("rem") or s.lower().startswith("::"):
                continue
            m = SET_RE.match(ln)
            if not m:
                continue
            if m.group(1) is not None:
                name, rhs, wrapped = m.group(1), m.group(2), True
            else:
                name, rhs, wrapped = m.group(3), m.group(4), False
            out.setdefault(name.upper(), []).append((f, i, rhs, wrapped))
    return out


def rhs_is_quoted(rhs, quoted_now):
    """Does executing `set VAR=<rhs>` put a literal double quote in the value?"""
    if '"' in rhs:
        return True
    for ref in REF_RE.findall(rhs):
        if ref.upper() in quoted_now:
            return True
    return False


def quoted_vars_by_line(inv):
    """f -> {line_no: set of quote-carrying variables AS OF that line}.

    Three properties matter, each learned the hard way on this repo:

    * PER FILE. The same name has different shapes in different families:
      `convert_from_list_*.bat` does `SET "SRC_FILE=%~1"` (bare) while
      `ffmpeg_*.bat` does `set SRC_FILE="%SRC_FILE:"=%"` (carries quotes). A
      repo-wide set leaks the ffmpeg property into the list family and invents
      findings there.
    * ORDER SENSITIVE (last assignment wins). Several variables are a command
      first and a value later: `SRC_BITRATE` is the probe command line, then
      `set /p SRC_BITRATE=<file` and `set /a` turn it into a number. Judging the
      whole file by any single assignment produced two phantom hits at
      ffmpeg_av1_*.bat:182.
    * `set /p` / `set /a` produce plain values: the quotes on the right of
      `set /p X=<"%TMP%"` belong to the redirect, not to X.
    """
    out = {}
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        state = {}
        per_line = {}
        for i, ln in enumerate(lf_lines(t), 1):
            per_line[i] = frozenset(n for n, v in state.items() if v)
            s = ln.strip()
            if s.lower().startswith("rem") or s.lower().startswith("::"):
                continue
            m = SETP_RE.match(ln) or SETA_RE.match(ln)
            if m:
                state[m.group(1).upper()] = False
                continue
            m = re.search(r'call\s+"[^"]*common\.bat"\s+([A-Za-z_][A-Za-z0-9_]*)([^&\r\n]*)', s)
            if m and m.group(1).lower() in HELPER_QUOTED_OUT:
                args = [a for a in re.split(r'\s+', m.group(2).strip()) if a]
                for idx in HELPER_QUOTED_OUT[m.group(1).lower()]:
                    if idx < len(args):
                        state[args[idx].upper()] = True
                continue
            m = SET_RE.match(ln)
            if not m:
                continue
            if m.group(1) is not None:
                name, rhs = m.group(1), m.group(2)
            else:
                name, rhs = m.group(3), m.group(4)
            state[name.upper()] = rhs_is_quoted(rhs, per_line[i])
        out[f] = per_line
    return out


# ---------------------------------------------------------------- L08
def check_wrapped_set(inv, qvars_by_file):
    """set "VAR=value with a quoted variable inside" is the 2026-09 regression:
    the wrapper quotes pair with the value's first quote, everything after it
    falls outside quotes and path metacharacters break the line."""
    hits = []
    total = 0
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        per_line = qvars_by_file.get(f, {})
        total += len(set().union(*per_line.values())) if per_line else 0
        _, t = read_text(p)
        for i, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if s.lower().startswith("rem") or s.lower().startswith("::"):
                continue
            m = SET_RE.match(ln)
            if not m or m.group(1) is None:
                continue
            qvars = per_line.get(i, frozenset())
            rhs = m.group(2)
            for ref in re.findall(r"%([A-Za-z_][A-Za-z0-9_]*)%", rhs):
                if ref.upper() in qvars:
                    hits.append("%s:%d wrapped set references quoted var %%%s%% -> use `set VAR=value`"
                                % (f, i, ref))
    if hits:
        for m in hits[:8]:
            bad("L08", m)
    else:
        ok("L08", "no wrapped set references a quote-carrying variable "
                  "(%d file-local quoted vars tracked)" % total)


# ---------------------------------------------------------------- L09
QUOTED_SAMPLE = '"A & B (2020) ^x !y.mp4"'
BARE_SAMPLE = "A & B (2020) ^x !y.mp4"
# FOR-variable modifiers (`%%~zA` size, `%%~nxA` name) yield plain tokens.
FOR_SAMPLE = "forValue"


def expand_line(line, qvars, neutral=False):
    """Worst-case expansion of a batch line.

    neutral=True replaces every reference with an EMPTY string instead of the
    metachar sample. The neutral text therefore keeps the line's literal
    structure (its own `"`, `&`, `|`, `(`, `)`, `>`) while removing all
    substituted data -- which is exactly what is needed to tell "this `&` is
    script syntax" apart from "this `&` leaked out of a value".

    The two quote-stripping forms are NOT interchangeable and must be expanded
    differently:
      * `"%VAR:"=%"` -- token enclosed by literal quotes -> result `"bare"`
      * `%VAR:"=%`   -- bare token -> result `bare`, no quotes added
    Adding quotes to the second form turns the safe
    `set TARGET_FILE="%TARGET_PATH:"=%%TARGET_NAME:"=%"` into a phantom finding.
    """
    quoted_sample = "" if neutral else QUOTED_SAMPLE
    bare_sample = "" if neutral else BARE_SAMPLE
    out = line
    # "%VAR:"=%"  -> keep the enclosing literal quotes, insert the bare sample
    for v in qvars:
        out = out.replace('"%%%s:"=%%"' % v, '"' + bare_sample + '"')
    # %VAR:"=%  (not enclosed) -> bare sample, no quotes of our own
    for v in sorted(qvars, key=len, reverse=True):
        out = out.replace('%%%s:"=%%' % v, bare_sample)
    for v in sorted(qvars, key=len, reverse=True):
        out = out.replace('%%%s%%' % v, quoted_sample)
    # %~dp0 -> a plain directory (no metacharacters: it is a real path)
    out = DIR_REF_RE.sub(lambda m: "" if neutral else "C:\\repo dir\\", out)
    # %~1 / %~f0 -> quote-stripped argument: the metachar sample is the worst case
    out = ARG_REF_RE.sub(lambda m: bare_sample, out)
    # %%A / %%~zA -> FOR placeholder and modifier: a plain token
    out = FOR_REF_RE.sub(lambda m: "" if neutral else FOR_SAMPLE, out)
    return out


# Only `&` and `|` are scanned. `>`, `<`, `(`, `)` are deliberately excluded:
# they are ordinary batch syntax (`cmd > file`, `if x gtr 1 (`, `for ... in (..)`),
# and a line-level scan cannot tell such syntax apart from data escaping -- it can
# only produce false alarms. The parenthesis/metachar risk carried by filenames is
# covered by L06 (quote pairing), L08 (wrapped set with a quoted var) and by the
# special-character cases in the smoke suites.
HAZARD_CHARS = "&|"


def active_hazards(text):
    """Multiset of `&` / `|` that are outside quotes (i.e. would be executed)."""
    hits = []
    q = False
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "^":
            i += 2          # caret escapes the next character
            continue
        if ch == '"':
            q = not q
        elif ch in HAZARD_CHARS and not q:
            hits.append(ch)
        i += 1
    return sorted(hits)


def quotes_balanced(text):
    q = False
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "^":
            i += 2
            continue
        if ch == '"':
            q = not q
        i += 1
    return not q


def leaked_hazards(expanded, neutral):
    """Hazards present in the expanded line but not in the neutral one.

    Compared as multisets, so a literal `a & b & c` in the script keeps its own
    three separators while only a genuinely new one is reported.
    """
    rest = list(active_hazards(neutral))
    out = []
    for c in active_hazards(expanded):
        if c in rest:
            rest.remove(c)
        else:
            out.append(c)
    return sorted(set(out))


# Any `%VAR%` or `%VAR:...=%` reference -- defined with the quoted-var section.


def references_quoted_var(line, qvars):
    for ref in REF_RE.findall(line):
        if ref.upper() in qvars:
            return True
    return False


def scan_metachars(text, qvars):
    """Differential metacharacter scan of command-assembly lines.

    qvars may be a plain set (uniform state, used by the calibration probes) or a
    {line_no: set} mapping (real files, flow-sensitive).

    For every line that substitutes a quote-carrying variable, compare the
    hazards that are ACTIVE in the neutral line (literal script syntax) with
    those active after the worst-case expansion. Only the difference is a
    finding: it is precisely the case where a value's quotes failed to contain
    the value and a separator leaked out of it -- the 2026-09 `X is not
    recognized` class of failure.
    """
    per_line = isinstance(qvars, dict)
    uniform = None if per_line else frozenset(qvars)
    findings = []
    for i, ln in enumerate(lf_lines(text), 1):
        s = ln.strip()
        if s.lower().startswith("rem") or s.lower().startswith("::"):
            continue
        if "lint:allow" in s:
            continue
        line_qvars = qvars.get(i, frozenset()) if per_line else uniform
        if not references_quoted_var(s, line_qvars):
            continue
        exp = expand_line(ln, line_qvars)
        if not quotes_balanced(exp):
            findings.append((i, "odd number of double quotes after expansion", s))
            continue
        leaked = leaked_hazards(exp, expand_line(ln, line_qvars, neutral=True))
        if leaked:
            findings.append((i, "substituted value leaks %s outside its quotes"
                             % "/".join("'%s'" % c for c in leaked), s))
    return findings


def check_metachars(inv, qvars_by_file, calibrated):
    if not calibrated:
        bad("L09", "scanner self-calibration FAILED - results below are unreliable")
        return
    bads = []
    total = 0
    tracked = sum(len(frozenset().union(*v.values())) if v else 0
                  for v in qvars_by_file.values())
    if tracked == 0:
        bad("L09", "quoted-variable tracking produced an empty set - the scan "
                   "would pass vacuously")
        return
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        qvars = qvars_by_file.get(f, set())
        _, t = read_text(p)
        for i, why, src in scan_metachars(t, qvars):
            total += 1
            if len(bads) < 8:
                bads.append("%s:%d %s | %s" % (f, i, why, src[:90]))
    if bads:
        for m in bads:
            bad("L09", m)
    else:
        ok("L09", "worst-case metacharacter scan clean (self-calibrated, %d .bat "
                  "files, %d file-local quoted vars)" % (len(inv["all_bat"]), tracked))


def calibrate_scanner():
    """Self-test of the worst-case expander, run before trusting L09.

    Three probes, all self-contained (nothing is read from the repo, so the
    verdict cannot be dragged green by whatever the repo happens to contain):

      1. `set X=%QVAR%`            MUST stay clean -- the value carries its own
                                   quotes, which is the repo's safe idiom.
      2. `set "X=%QVAR%"`          MUST be flagged -- the wrapper quote pairs with
                                   the value's first quote and the value's `&`
                                   escapes (the 2026-09 regression).
      3. `endlocal & set X=%QVAR%` MUST stay clean -- the `&` is script syntax and
                                   is active in the neutral line too, so it is not
                                   a leak.

    If (1) or (3) fires, or (2) does not, the scanner cannot be trusted and the
    caller downgrades every L09 result to an explicit failure.
    """
    probe = {"QVAR"}
    safe = 'set X=%QVAR% -i input.mp4'
    wrapped = 'set "X=%QVAR% -i input.mp4"'
    literal_amp = 'endlocal & set X=%QVAR%'
    return (not scan_metachars(safe, probe)
            and bool(scan_metachars(wrapped, probe))
            and not scan_metachars(literal_amp, probe))


# ---------------------------------------------------------------- L10 / L11
def check_sh_invariants(inv):
    bads = []
    for f in inv["all_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        if "run_list" in t and "lib/common.sh" in f:
            if "bash \"$script\" \"$line\" < /dev/null" not in t:
                bads.append("%s: run_list lost its `< /dev/null` stdin isolation" % f)
    if bads:
        for m in bads:
            bad("L10", m)
    else:
        ok("L10", "run_list still redirects the child stdin to /dev/null "
                  "(the 5-entry list regression)")

    bads = []
    for f in inv["all_sh"]:
        if not f.startswith("ffmpeg_") or f == "ffmpeg_copy_to_mp4.sh":
            continue
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        idx_in = [i for i, ln in enumerate(lines) if re.search(r"CMD\+=\(-i\b", ln)]
        idx_enc = [i for i, ln in enumerate(lines) if re.search(r"CMD\+=\(-c:v\b", ln)]
        if not idx_in or not idx_enc:
            bads.append("%s: cannot locate the input/encoder CMD lines" % f)
            continue
        if min(idx_enc) < min(idx_in):
            bads.append("%s: -c:v is added before the input (-i) option" % f)
        for i in idx_in:
            if "-c:v" in lines[i]:
                bads.append("%s:%d has -c:v on the same line as -i" % (f, i + 1))
    if bads:
        for m in bads:
            bad("L11", m)
    else:
        ok("L11", "every encoder adds -i before -c:v (the option-order trap)")


# ---------------------------------------------------------------- L12
def check_bash_syntax(inv):
    bash = shutil_which("bash")
    if not bash:
        skip("L12", "bash not available: skipped `bash -n` syntax check")
        return
    bads = []
    for f in inv["all_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        r = subprocess.run([bash, "-n", p], capture_output=True, text=True)
        if r.returncode != 0:
            bads.append("%s: %s" % (f, (r.stderr or "").strip()[:160]))
    if bads:
        for m in bads:
            bad("L12", m)
    else:
        ok("L12", "`bash -n` clean on every .sh (%d files)" % len(inv["all_sh"]))


def shutil_which(cmd):
    """Locate an executable.

    NOTE: a hand-rolled PATH scan does NOT work on Windows for `bash` -- the
    file on disk is `bash.EXE` and only the PATHEXT rules of shutil.which()
    resolve that. Falling back to a few well-known POSIX shells keeps the
    `bash -n` / live-lookup checks running on the usual Windows setups.
    """
    p = shutil.which(cmd)
    if p:
        return p
    fallbacks = [
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
        r"C:\Program Files (x86)\Git\bin\bash.exe",
        r"D:\cygwin64\bin\bash.exe",
        r"D:\msys64\usr\bin\bash.exe",
        r"D:\Program Files\Git\bin\bash.exe",
    ]
    for p in fallbacks:
        if os.path.isfile(p):
            return p
    return None


# ---------------------------------------------------------------- L13
ALLOWED_BAT_EXITS = {0, 1, 2, 3, 5}
ALLOWED_SH_EXITS = {0, 1, 2, 3, 5, 8, 9}   # 8/9: harness-level setup errors


def check_exit_codes(inv):
    bads = []
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for i, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if s.lower().startswith("rem"):
                continue
            for m in re.finditer(r"exit\s+/b\s+(\d+)", s, re.IGNORECASE):
                if int(m.group(1)) not in ALLOWED_BAT_EXITS:
                    bads.append("%s:%d uses undocumented exit /b %s" % (f, i, m.group(1)))
    for f in inv["all_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for i, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if s.startswith("#"):
                continue
            for m in re.finditer(r"(?<![$\w])exit\s+(\d+)", s):
                if int(m.group(1)) not in ALLOWED_SH_EXITS:
                    bads.append("%s:%d uses undocumented exit %s" % (f, i, m.group(1)))
    if bads:
        for m in bads[:8]:
            bad("L13", m)
    else:
        ok("L13", "exit codes stay inside the documented contract "
                  "(bat %s / sh %s)" % (sorted(ALLOWED_BAT_EXITS), sorted(ALLOWED_SH_EXITS)))


# ---------------------------------------------------------------- tables
def load_table(name):
    rows = []
    with open(os.path.join(ROOT, "lib", name), "r", encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln or ln.startswith("max_pixels"):
                continue
            a, b = ln.split(",")[:2]
            rows.append((int(a), int(b)))
    return rows


def table_value(name, pixels):
    """Reference implementation of the documented lookup: first bucket whose
    max_pixels >= pixels (ceiling match), empty when out of range."""
    for thr, val in load_table(name):
        if pixels <= thr:
            return val
    return None


TABLES = ["bitrate_table_avc.csv", "bitrate_table_hevc.csv", "bitrate_table_av1.csv"]
FAMILY_BY_CODEC = [
    (("h264", "avc", "libx264"), "bitrate_table_avc.csv"),
    (("hevc", "h265", "libx265", "x265"), "bitrate_table_hevc.csv"),
    (("av1",), "bitrate_table_av1.csv"),
]


def family_table(codec):
    c = codec.lower()
    for keys, tbl in FAMILY_BY_CODEC:
        for k in keys:
            if c == k or c.endswith("_" + k) or k in c:
                return tbl
    return None


# ---------------------------------------------------------------- P04
def check_tables():
    """Structural sanity of the three bitrate tables.

    hard (FAIL): max_pixels must never decrease, otherwise `lookup_bitrate`
                 (first threshold >= pixels) stops being well defined; 720p and
                 1080p must stay covered; and one pixel count must not map to two
                 different bitrates (ambiguous row).
    soft (WARN): a bitrate dip, or two rows that are exact duplicates. These
                 tables come from a fitted preset model
                 (bitrate ~ a * pixels^0.775), so a small dip is a data
                 observation, not a code bug -- reported with its row number so
                 it can be reviewed, but not failed.
    """
    bads, warns = [], []
    for name in TABLES:
        rows = load_table(name)
        if not rows:
            bads.append("%s is empty" % name)
            continue
        seen = {}
        for i, (px, br) in enumerate(rows, 2):
            if px in seen:
                if seen[px] != br:
                    bads.append("%s: max_pixels %d maps to two bitrates "
                                "(%d vs %d at row %d) - ambiguous table"
                                % (name, px, seen[px], br, i))
                else:
                    warns.append("%s: row %d is an exact duplicate of an earlier "
                                 "row (px=%d) - redundant, unreachable"
                                 % (name, i, px))
            else:
                seen[px] = br
        for i in range(1, len(rows)):
            if rows[i][0] < rows[i - 1][0]:
                bads.append("%s: max_pixels decreases at row %d (%d -> %d)"
                            % (name, i + 2, rows[i - 1][0], rows[i][0]))
            if rows[i][1] < rows[i - 1][1]:
                drop = 100.0 * (rows[i - 1][1] - rows[i][1]) / rows[i - 1][1]
                warns.append("%s: bitrate dips at row %d (%d -> %d, -%.1f%%)"
                             % (name, i + 2, rows[i - 1][1], rows[i][1], drop))
        for px, label in ((921600, "720p"), (2073600, "1080p")):
            if table_value(name, px) is None:
                bads.append("%s does not cover %s (%d px)" % (name, label, px))
    if bads:
        for m in bads[:8]:
            bad("P04", m)
    else:
        ok("P04", "bitrate tables are structurally sane: max_pixels never "
                  "decreases, one pixel count -> one bitrate, 720p/1080p covered "
                  "(%s)" % ", ".join(TABLES))
    for m in warns[:8]:
        warn("P04", m)


def check_table_expectations(inv):
    """The 1080p expectations hardcoded in both harnesses must equal
    table(2073600) / 2 - this keeps tests and tables from drifting apart."""
    bads = []
    expected = {}
    for name in TABLES:
        v = table_value(name, 2073600)
        expected[name] = v // 2
    p = os.path.join(ROOT, "test", "bat", "smoke_ffmpeg_bat.bat")
    if os.path.isfile(p):
        _, t = read_text(p)
        for m in re.finditer(r"call :runA (\S+)\s+\S+\s+(\S+)\s+(\d+)\s", t):
            script, logname, val = m.group(1), m.group(2), int(m.group(3))
            codec = ("h264" if "avc" in script or "libx264" in script else
                     "av1" if "av1" in script else
                     "hevc" if ("hevc" in script or "libx265" in script) else None)
            if not codec:
                continue
            tbl = family_table(codec)
            if tbl and expected[tbl] != val:
                bads.append("smoke_ffmpeg_bat.bat %s: expected %d but table says %d"
                            % (logname, val, expected[tbl]))
    p = os.path.join(ROOT, "test", "sh", "smoke_sh.sh")
    if os.path.isfile(p):
        _, t = read_text(p)
        for m in re.finditer(r"^(?:run_arg|gate_arg)\s+(T\d+)\s+(\S+)\s+(?:ok|fail)?\s*(\d+)",
                             t, re.MULTILINE):
            tid, script, val = m.group(1), m.group(2), int(m.group(3))
            for codec in ("h264", "hevc", "av1"):
                if codec in script or (codec == "h264" and "libx264" in script):
                    tbl = family_table(codec)
                    if tbl and expected[tbl] != val:
                        bads.append("smoke_sh.sh %s %s: expected %d but table says %d"
                                    % (tid, script, val, expected[tbl]))
                    break
    if bads:
        for m in bads[:8]:
            bad("P06", m)
    else:
        ok("P06", "harness 1080p expectations match table(2073600)/2 "
                  "(avc %d, hevc %d, av1 %d)"
           % (expected["bitrate_table_avc.csv"], expected["bitrate_table_hevc.csv"],
              expected["bitrate_table_av1.csv"]))


# ---------------------------------------------------------------- P05
def sh_lookup(px, csv_name, bash):
    script = 'source "%s/lib/common.sh"; lookup_bitrate %d %s' % (ROOT.replace("\\", "/"), px, csv_name)
    r = subprocess.run([bash, "-c", script], capture_output=True, text=True)
    out = (r.stdout or "").strip()
    return r.returncode, out


def check_lookup_equivalence():
    bash = shutil_which("bash")
    if not bash:
        skip("P05", "bash not available: skipped the live sh lookup comparison")
        return
    bads = []
    samples = [12288, 307200, 921600, 1000000, 2073600, 3000000, 8294400, 132710400, 141557760]
    for name in TABLES:
        for px in samples:
            ref = table_value(name, px)
            rc, got = sh_lookup(px, name, bash)
            if ref is None:
                if rc != 2:
                    bads.append("%s %d px: out of range should return 2, got rc=%d" % (name, px, rc))
            else:
                if rc != 0 or got != str(ref):
                    bads.append("%s %d px: sh lookup rc=%d out=%r reference=%d"
                                % (name, px, rc, got, ref))
    # beyond the last bucket: both implementations must report "out of range"
    for name in TABLES:
        rc, _got = sh_lookup(141557761, name, bash)
        if rc != 2:
            bads.append("%s: pixel count above the last bucket should return 2, got %d" % (name, rc))
    if bads:
        for m in bads[:8]:
            bad("P05", m)
    else:
        ok("P05", "sh lookup_bitrate matches the reference implementation on %d samples "
                  "(incl. out-of-range)" % (len(samples) * len(TABLES)))


# ---------------------------------------------------------------- P01
ENTRY_WHITELIST = {
    "sh_only": {
        "ffmpeg_h264_vaapi.sh": "VAAPI is a Linux kernel API - no Windows twin",
        "ffmpeg_hevc_vaapi.sh": "VAAPI is a Linux kernel API - no Windows twin",
        "ffmpeg_hevc_nvenc_cygwin.sh": "Cygwin-specific variant (cuvid + hwdownload)",
    },
    "bat_only": {
        "opencmd.bat": "Windows helper: open a cmd already switched to UTF-8",
    },
}


def check_entry_inventory(inv):
    def entries(names, suffix):
        out = {}
        for n in names:
            b = os.path.basename(n)
            if b.startswith("ffmpeg_") or b.startswith("convert_from_list_") or b.startswith("repack_from_list"):
                out[b[:-len(suffix)]] = b
        return out
    sh = entries(inv["root_sh"], ".sh")
    bat = entries(inv["root_bat"], ".bat")
    sh_only = sorted(set(sh) - set(bat))
    bat_only = sorted(set(bat) - set(sh))
    bads = []
    for n in sh_only:
        fname = n + ".sh"
        if fname not in ENTRY_WHITELIST["sh_only"]:
            bads.append("sh-only entry with no documented reason: %s" % fname)
    for n in bat_only:
        fname = n + ".bat"
        if fname not in ENTRY_WHITELIST["bat_only"]:
            bads.append("bat-only entry with no documented reason: %s" % fname)
    if bads:
        for m in bads:
            bad("P01", m)
    else:
        ok("P01", "entry inventory: %d shared + %d sh-only (whitelisted) + %d bat-only (whitelisted)"
           % (len(set(sh) & set(bat)), len(sh_only), len(bat_only)))


# ---------------------------------------------------------------- P02
def table_of(text):
    """Which bitrate table a script actually uses.

    Prefer the real `lookup_bitrate ... <table>.csv` call site; fall back to a
    plain scan that IGNORES comment lines, so a stale `rem ... bitrate_table_x`
    comment cannot hide (or fake) the wiring.
    """
    code = "\n".join(ln for ln in lf_lines(text)
                     if not ln.strip().lower().startswith(("rem", "::", "#")))
    m = re.search(r"lookup_bitrate[^\r\n]*?(bitrate_table_[a-z0-9_]+\.csv)", code)
    if m:
        return m.group(1)
    for name in TABLES:
        if name in code:
            return name
    return None


def check_encoder_table_mapping(inv):
    bads = []
    mapping = {}
    for f in inv["root_sh"]:
        p = os.path.join(ROOT, f)
        _, t = read_text(p)
        tbl = table_of(t)
        enc = None
        m = re.search(r"CMD\+=\(-c:v\s+(\S+)", t)
        if m:
            enc = m.group(1)
        else:
            for m in re.finditer(r"-c:v\s+([a-z0-9_]+)", t):
                enc = m.group(1)
        if enc and tbl:
            mapping.setdefault(enc, set()).add(tbl)
    for f in inv["root_bat"]:
        p = os.path.join(ROOT, f)
        _, t = read_text(p)
        tbl = table_of(t)
        enc = None
        m = re.search(r"-c:v\s+([a-z0-9_]+)", t)
        if m:
            enc = m.group(1)
        if enc and tbl:
            mapping.setdefault(enc, set()).add(tbl)
    for enc, tbls in sorted(mapping.items()):
        if len(tbls) > 1:
            bads.append("encoder %s is wired to several tables: %s (families disagree?)"
                        % (enc, sorted(tbls)))
        want = family_table(enc)
        if want and want not in tbls:
            bads.append("encoder %s uses %s but its codec family expects %s"
                        % (enc, sorted(tbls), want))
    if bads:
        for m in bads[:8]:
            bad("P02", m)
    else:
        ok("P02", "encoder -> bitrate table mapping is consistent across families "
                  "(%d encoders)" % len(mapping))


# ---------------------------------------------------------------- P03
def exit_codes_sh(text):
    """nonvideo / bitrate-abnormal / lookup-out-of-range / no-input-file"""
    out = {}
    m = re.search(r"function check_file_isvideo.*?\n}\n", text, re.S)
    if m:
        mm = re.search(r"exit\s+(\d+)", m.group(0))
        out["nonvideo"] = mm.group(1) if mm else None
    m = re.search(r'percentage" -le 0.*?exit\s+(\d+)', text, re.S)
    if m:
        out["bitrateAbnormal"] = m.group(1)
    m = re.search(r"Manual handle it!.*?exit\s+(\d+)", text, re.S)
    if m:
        out["lookupOutOfRange"] = m.group(1)
    if re.search(r"没有输入文件", text):
        out["noInput"] = "1"
    return out


def exit_codes_bat(text):
    out = {}
    m = re.search(r"check_isvideo\s+%SRC_FILE%\s*\r?\n\s*if\s+errorlevel\s+1\s+exit\s+/b\s+(\d+)", text)
    if m:
        out["nonvideo"] = m.group(1)
    m = re.search(r"bitrate abnormal, please check\s*\r?\n\s*exit\s+/b\s+(\d+)", text)
    if m:
        out["bitrateAbnormal"] = m.group(1)
    m = re.search(r"Manual handle it.*?\r?\n\s*exit\s+/b\s+(\d+)", text)
    if m:
        out["lookupOutOfRange"] = m.group(1)
    if re.search(r"没有输入文件", text):
        out["noInput"] = "1"
    return out


def check_exit_contract(inv):
    sh_all = {}
    for f in inv["all_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for k, v in exit_codes_sh(t).items():
            sh_all.setdefault(k, set()).add(v)
    bat_all = {}
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for k, v in exit_codes_bat(t).items():
            bat_all.setdefault(k, set()).add(v)
    bads = []
    for k in sorted(set(sh_all) | set(bat_all)):
        s = sorted(sh_all.get(k, []))
        b = sorted(bat_all.get(k, []))
        if len(s) > 1 or len(b) > 1:
            bads.append("condition '%s' is inconsistent inside a family: sh=%s bat=%s" % (k, s, b))
        elif s and b and s != b:
            bads.append("condition '%s': sh exits %s but bat exits %s" % (k, s[0], b[0]))
    if bads:
        for m in bads:
            bad("P03", m)
    else:
        summary = ", ".join("%s=%s" % (k, sorted(sh_all.get(k, {"?"}))[0]) for k in sorted(sh_all))
        ok("P03", "exit-code contract matches across families: " + summary)


# ---------------------------------------------------------------- P07
PARAM_WHITELIST = {
    ("libx265", "preset"): "known divergence: .sh uses fast, .bat uses veryfast",
}


def check_encoder_params(inv):
    def parse(text, family):
        enc = None
        prof = None
        preset = None
        pix = None
        m = re.search(r"-c:v\s+([a-z0-9_]+)", text)
        if m:
            enc = m.group(1)
        m = re.search(r"-profile:v\s+([a-z0-9]+)", text)
        if m:
            prof = m.group(1)
        m = re.search(r"-preset\s+([a-z0-9]+)", text)
        if m:
            preset = m.group(1)
        m = re.search(r"-pix_fmt\s+([a-z0-9]+)", text)
        if m:
            pix = m.group(1)
        return enc, prof, preset, pix

    sh_map, bat_map = {}, {}
    for f in inv["root_sh"]:
        p = os.path.join(ROOT, f)
        _, t = read_text(p)
        m = re.search(r"CMD\+=\(-c:v\s+([a-z0-9_]+)", t)
        if not m:
            continue
        sh_map[m.group(1)] = parse(t, "sh")[1:]
    for f in inv["root_bat"]:
        p = os.path.join(ROOT, f)
        _, t = read_text(p)
        m = re.search(r"-c:v\s+([a-z0-9_]+)", t)
        if not m:
            continue
        bat_map[m.group(1)] = parse(t, "bat")[1:]
    bads, warned = [], []
    for enc in sorted(set(sh_map) & set(bat_map)):
        s, b = sh_map[enc], bat_map[enc]
        for idx, label in enumerate(("profile", "preset", "pix_fmt")):
            sv, bv = s[idx], b[idx]
            if sv == bv:
                continue
            if (enc, label) in PARAM_WHITELIST:
                warned.append("%s %s: sh=%s bat=%s (%s)" % (enc, label, sv, bv, PARAM_WHITELIST[(enc, label)]))
            else:
                bads.append("%s %s differs: sh=%s bat=%s" % (enc, label, sv, bv))
    if bads:
        for m in bads:
            bad("P07", m)
    else:
        ok("P07", "encoder parameters agree across families where they should "
                  "(%d encoders compared)" % len(set(sh_map) & set(bat_map)))
    for m in warned:
        warn("P07", m)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--lint-only", action="store_true")
    ap.add_argument("--parity-only", action="store_true")
    ap.add_argument("--list", action="store_true", help="print the check catalogue")
    args = ap.parse_args()

    if args.list:
        print("static : L01 eol  L02 bom  L03 shebang  L04 bat guard ascii")
        print("         L05 paren balance  L06 quote pairing  L07 call labels")
        print("         L08 wrapped set with quoted var  L09 metachar scan")
        print("         L10 run_list stdin  L11 option order  L12 bash -n")
        print("         L13 exit-code contract")
        print("parity : P01 entry inventory  P02 encoder->table  P03 exit contract")
        print("         P04 table sanity  P05 lookup equivalence  P06 harness")
        print("         expectations  P07 encoder parameter drift")
        return 0

    inv = inventory()
    print("repo: %s" % ROOT)
    print("")

    if not args.parity_only:
        print("---- static ----")
        check_eol_and_bom(inv)
        check_shebang(inv)
        check_bat_guard_ascii(inv)
        check_bat_syntax_shape(inv)
        check_bat_labels(inv)
        assigns = collect_set_assignments(inv)
        qvars_by_file = quoted_vars_by_line(inv)
        check_wrapped_set(inv, qvars_by_file)
        calibrated = calibrate_scanner()
        check_metachars(inv, qvars_by_file, calibrated)
        check_sh_invariants(inv)
        check_bash_syntax(inv)
        check_exit_codes(inv)

    if not args.lint_only:
        print("---- parity ----")
        check_entry_inventory(inv)
        check_encoder_table_mapping(inv)
        check_exit_contract(inv)
        check_tables()
        check_lookup_equivalence()
        check_table_expectations(inv)
        check_encoder_params(inv)

    print("")
    for cid, msg in PASS:
        print("[PASS] %-5s %s" % (cid, msg))
    for cid, msg in WARN:
        print("[WARN] %-5s %s" % (cid, msg))
    for cid, msg in FAIL:
        print("[FAIL] %-5s %s" % (cid, msg))
    for cid, msg in SKIP:
        print("[SKIP] %-5s %s" % (cid, msg))
    print("")
    print("---- %d PASS  %d FAIL  %d WARN  %d SKIP ----"
          % (len(PASS), len(FAIL), len(WARN), len(SKIP)))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
