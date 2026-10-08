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
        "all_sh": root_sh + ["lib/common.sh", "lib/encode_core.sh"] + test_sh,
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
def _bat_effective_cmd(line):
    """剥掉行首的重定向前缀后返回剩下的命令头。
    `>>"file" echo if defined ZG goto zmain` 这类行是把 `goto ...` 当**文本**写进
    另一个(生成的)bat 里, 不是本文件执行的跳转; 只看 strip() 后的开头会把它们
    误判成未解析标签(2026-09-22 加固 L07 时实测: smoke_special_chars.bat 的 4 处
    `z4/z5/z6/z7.bat` 生成行全是这种误报)。
    """
    s = line.strip()
    while True:
        m = re.match(r'^\d?(?:>>?|<<?)\s*("[^"]*"|\S+)\s*', s)
        if not m:
            return s
        s = s[m.end():]


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
            s = _bat_effective_cmd(ln)
            if s.lower().startswith(("rem", "echo")):
                continue
            # call 必须带冒号 —— 不带冒号是调脚本文件, 不是标签;
            # goto 的两种写法都合法, 而且 `goto LABEL`(不带冒号)才是最常见的形式。
            # 原正则只认带冒号的那种, 于是 `goto NO_TABLE` 指向不存在的标签能一路
            # 通过 lint(2026-09-22 实测: ffmpeg_dvd_hevc.bat 里就是这么漏过去的,
            # 真机一跑才会打出"找不到批处理标签 - NO_TABLE"然后中断)。
            for m in re.finditer(r"\bcall\s+:([A-Za-z_][A-Za-z0-9_]*)", s):
                tgt = m.group(1).lower()
                if tgt not in labels and tgt not in BUILTIN_LABELS:
                    missing.append("%s:%d -> :%s" % (f, i, m.group(1)))
            for m in re.finditer(r"\bgoto\s+:?([A-Za-z_][A-Za-z0-9_]*)", s):
                tgt = m.group(1).lower()
                if tgt not in labels and tgt not in BUILTIN_LABELS:
                    missing.append("%s:%d -> goto %s" % (f, i, m.group(1)))
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


# ---------------------------------------------------------------- 阶段0: 薄壳入口的命令体
# TODO.md 阶段0 把 9 个编码入口改成了薄壳, 命令拼装搬进了 lib/encode_core.sh。
# 下面两个 helper 把"薄壳入口 + 它在核心里选中的那一个 case 分支"拼回一个可静态
# 检查的命令体, 于是 L11 / L16 的断言对象和抽内核之前**完全一致**:
#   * 共享不变量(-map 0:V / SENC / COVER_MAP / -map_metadata)取 enc_run 的公共段;
#   * 逐入口不变量(-c:v:0 <编码器> / -profile:v:0 / 没有裸 -c:v copy)只取该入口
#     选中的那支, 不会因为"9 个入口共用一份内核"而把逐入口断言放宽成整份内核的断言。
# 不是薄壳的入口(ffmpeg_dvd_hevc)拿不到 enc_run, 返回 None, 调用方回退到"只看自己"。
ENC_CORE_SH = "lib/encode_core.sh"


def core_fn_text(core, fname):
    """取出 lib/encode_core.sh 里 `function <fname>() { ... }` 的整段文本。"""
    m = re.search(r"^function %s\(\) \{" % re.escape(fname), core, re.M)
    if not m:
        return ""
    end = re.search(r"^\}\s*$", core[m.end():], re.M)
    return core[m.start(): m.end() + (end.end() if end else 0)]


def core_branch(core, fname, key):
    """取出 <fname>() 里 key 命中的那个 case 分支的分支体(不含标签行与结尾 ;;)。

    case 标签可能写成 `libx264|libx265)` 这种合并形式, 所以按 `|` 拆开比对。
    """
    out, inside = [], False
    for ln in lf_lines(core_fn_text(core, fname)):
        if inside:
            if re.match(r"^\s*;;\s*$", ln):
                break
            out.append(ln)
            continue
        lab = re.match(r"^\s+([\w|]+)\)\s*$", ln)
        if lab and key in lab.group(1).split("|"):
            inside = True
    return "\n".join(out)


def entry_body_sh(text, core):
    """薄壳入口的有效命令体, 非薄壳返回 None。"""
    m = re.search(r"^enc_run\s+(\S+)\s", text, re.M)
    if not m:
        return None
    key = m.group(1)
    return "\n".join([text,
                      core_fn_text(core, "enc_run"),
                      core_branch(core, "enc_dec_args", key),
                      core_branch(core, "enc_vargs", key)])


def core_text():
    p = os.path.join(ROOT, ENC_CORE_SH)
    if not os.path.isfile(p):
        return ""
    _, t = read_text(p)
    return t


# ---------------------------------------------------------------- L10 / L11
def check_sh_invariants(inv):
    bads = []
    for f in inv["all_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        if "run_list" in t and "lib/common.sh" in f:
            # run_list 现在会把 FWD 开关透传给每个入口, 行形如
            #   bash "$script" "${FWD[@]+"${FWD[@]}"}" "$line" < /dev/null
            # 只要保留 "bash $script" ... "< /dev/null" 的 stdin 隔离即算通过,
            # 不要写死中间那段.
            if not re.search(r'bash "\$script".*"\$line" < /dev/null', t, re.S):
                bads.append("%s: run_list lost its `< /dev/null` stdin isolation" % f)
    if bads:
        for m in bads:
            bad("L10", m)
    else:
        ok("L10", "run_list still redirects the child stdin to /dev/null "
                  "(the 5-entry list regression)")

    bads = []
    core = core_text()
    for f in inv["all_sh"]:
        if not f.startswith("ffmpeg_") or f == "ffmpeg_copy_to_mp4.sh":
            continue
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        body = entry_body_sh(t, core) or t
        lines = lf_lines(body)
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


# ---------------------------------------------------------------- L14
def check_exec_bits(inv):
    """Every tracked .sh must be 100755 in the git index.

    The suites were authored on Windows, where the filesystem does not carry
    the exec bit: without this check a fresh `git clone` on Linux/A/B/C/D gets
    non-executable scripts and every caller needs a manual chmod. Read the
    MODE FROM THE INDEX (`git ls-files -s`), not from the filesystem -- on
    Windows core.fileMode=false makes the worktree mode meaningless, and the
    index is the only thing a clone actually receives.
    """
    if not os.path.isdir(os.path.join(ROOT, ".git")):
        skip("L14", "not a git checkout: skipped exec-bit check")
        return
    git = shutil_which("git")
    if not git:
        skip("L14", "git not available: skipped exec-bit check")
        return
    r = subprocess.run([git, "ls-files", "-s"], cwd=ROOT, capture_output=True,
                       text=True)
    if r.returncode != 0:
        skip("L14", "git ls-files failed: skipped exec-bit check")
        return
    bads = []
    n = 0
    for ln in r.stdout.splitlines():
        parts = ln.split()
        if len(parts) < 4 or not parts[3].endswith(".sh"):
            continue
        n += 1
        if parts[0] != "100755":
            bads.append("%s: index mode is %s (want 100755; "
                        "fix with git update-index --chmod=+x)"
                        % (parts[3], parts[0]))
    if bads:
        for m in bads:
            bad("L14", m)
    else:
        ok("L14", "every tracked .sh carries the exec bit (%d files)" % n)


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
ALLOWED_BAT_EXITS = {0, 1, 2, 3, 4, 5, 6}
ALLOWED_SH_EXITS = {0, 1, 2, 3, 4, 5, 6, 8, 9}  # 4: hardware missing - the encoder is
                                                #    listed by ffmpeg -encoders but the
                                                #    device cannot open it (av1_qsv on
                                                #    UHD 770). List wrappers ABORT the
                                                #    whole run on it (2026-09-30, user
                                                #    call: no point retrying every file).
                                                # 6: output exists and FF_ON_EXIST=fail
                                                #    (2026-09-30; see lib/common.sh
                                                #    ff_run and lib/common.bat :on_exist)
                                                # 8/9: harness-level setup errors


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


# ---------------------------------------------------------------- L15
# Family parity of the FAILURE PATH, not just of the vocabulary (that is L13).
# The .sh twins abort with exit 1 when ffmpeg fails (encoder entries) and
# run_list stops the whole list on the first failed file (wrappers). The .bat
# family was written for double-click use and ended with an unconditional
# `exit /b 0`, so every encode failure looked like success to whoever called
# it: convert_from_list wrappers kept going, check_env --probe reported
# PROBE-OK for encoders that cannot run at all, and the smoke harness could
# not tell a failed case from a passing one. That gap survived L13 because
# L13 only checks which exit codes appear, never whether the failure path is
# reachable. Fixed 2026-09-17 (batch 8 entries + 4 list wrappers); this rule
# keeps it fixed.
#
# 2026-09-17, second pass - the guard has to be NEGATIVE-SAFE. The first fix
# used `if errorlevel 1`, which reads as "errorlevel >= 1" and is compared
# SIGNED: Windows ffmpeg returns NEGATIVE AVERROR values (av1_qsv here exits
# -40, "Function not implemented", when the iGPU has no AV1 encoder), so
# -40 >= 1 is false, the guard never fires and the entry still reached its
# `exit /b 0` - the user's --probe run showed exactly that: `rc=0` while the
# log tail said `ERRORLEVEL:-40`. Accepted forms are the two that really hold:
#   if not "%FB_RC%"=="0"     (string compare; also fails SAFE on an empty value)
#   if %FB_RC% NEQ 0          (numeric, sign-aware)
# where the operand is %ERRORLEVEL% or a variable set from it right after the
# encoder run. A bare `if errorlevel N` is rejected wherever the guard has to
# catch a negative code.
#
# The list wrappers keep `if errorlevel 1` on purpose, and it is correct there:
# their test sits INSIDE a `for /f ... do ( ... )` block, where every `%VAR%`
# is expanded once when the block is parsed, so a `%ERRORLEVEL%` test would be
# frozen at the block's entry value. `if errorlevel` reads the live status
# instead - and the children are constrained by L13 to {0,1,2,3,4,5,6}, all
# non-negative, so the signed compare cannot miss one. (4 is only read through
# `if errorlevel 4 if not errorlevel 5`, i.e. exactly 4, so it cannot swallow 5/6.)
def check_fail_propagation(inv):
    bads = []
    checked = 0

    def tail_has_exit1(lines, idx):
        for ln in lines[idx + 1:]:
            if ln.strip().lower().startswith("exit /b 1"):
                return True
        return False

    def negative_safe_guard(lines, idx):
        """(ok, text) for the conditional that guards the failure exit."""
        window = []
        for ln in lines[idx + 1:]:
            if ln.strip().lower().startswith("exit /b 1"):
                break
            window.append(ln)
        operands = {"%ERRORLEVEL%"}
        for ln in window:
            m = re.match(r'\s*set\s+"?([A-Za-z_]\w*)=%ERRORLEVEL%"?\s*$', ln, re.IGNORECASE)
            if m:
                operands.add("%" + m.group(1) + "%")
        guard = None
        for ln in window:
            s = ln.strip()
            if re.match(r"if\s+(not\s+)?errorlevel\b", s, re.IGNORECASE):
                return False, s          # signed compare: negatives slip through
            if guard is None and s.lower().startswith("if"):
                guard = s
        if guard is None:
            return False, ""
        refs = any(op.upper() in guard.upper() for op in operands)
        nonzero = bool(re.search(r"\bNEQ\s+0\b", guard, re.IGNORECASE)
                       or re.search(r'NOT\s+"[^"]*"\s*==\s*"0"', guard, re.IGNORECASE))
        return (refs and nonzero), guard

    # .bat encoder entries: the bare `%RUN_COM%` line is the one that runs ffmpeg
    for f in inv["root_bat"]:
        if not re.match(r"^ffmpeg_.*\.bat$", f, re.IGNORECASE):
            continue
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        idx = None
        for i, ln in enumerate(lines):
            s = ln.strip()
            # 2026-09-30: the D3D fallback in the two software entries has to
            # capture stderr (that is how it decides whether to retry without
            # -hwaccel), so the run line carries a trailing `2>"file"`. Accept
            # that form, and keep taking the LAST match: the fallback subroutine
            # runs %RUN_COM% as well, and the real entry run is the one inside
            # :main, which comes later in the file. Matching only the exact bare
            # line made lint lock onto the subroutine's copy and then judge the
            # wrong guard -- an L15 false alarm on a guard that is in fact
            # negative-safe (`if not "%FB_RC%"=="0"`).
            if s == "%RUN_COM%" or re.match(r'^%RUN_COM%\s+2>"[^"]*"\s*$', s):
                idx = i
        if idx is None:
            bads.append("%s: no bare %%RUN_COM%% execution line found" % f)
            continue
        checked += 1
        if not tail_has_exit1(lines, idx):
            bads.append("%s: ffmpeg failure is swallowed - no `exit /b 1` after "
                        "`%%RUN_COM%%` (the .sh twin exits 1 on convert failure)" % f)
            continue
        safe, gtext = negative_safe_guard(lines, idx)
        if not safe:
            bads.append("%s: the failure guard cannot see a NEGATIVE exit code (%s) - "
                        "Windows ffmpeg returns negative AVERROR values (av1_qsv here: "
                        "-40) and `if errorlevel N` is a signed compare, so the guard "
                        "never fires and the entry still ends in `exit /b 0`"
                        % (f, gtext or "no conditional found between the encoder run "
                                       "and the exit"))

    # .bat list wrappers: the child is called from inside the for /f block
    for f in inv["root_bat"]:
        if not re.match(r"^(convert_from_list|repack_from_list).*\.bat$", f, re.IGNORECASE):
            continue
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        idx = None
        for i, ln in enumerate(lines):
            if re.search(r"call\s+\"%~dp0ffmpeg_", ln):
                idx = i
        if idx is None:
            bads.append("%s: no `call \"%%~dp0ffmpeg_...bat\"` child call found" % f)
            continue
        checked += 1
        if not tail_has_exit1(lines, idx):
            bads.append("%s: a failed child is ignored - no `exit /b 1` after the list "
                        "loop (the .sh twin run_list exits 1 on the first failure)" % f)

    # .sh encoder entries: already correct, pinned against regressions
    for f in inv["root_sh"]:
        if not re.match(r"^ffmpeg_.*\.sh$", f, re.IGNORECASE):
            continue
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        idx = None
        for i, ln in enumerate(lines):
            if '"${CMD[@]}"' in ln or ln.strip() == "$RUN_COM":
                idx = i
        if idx is None:
            continue
        checked += 1
        if not any(re.match(r"^\s*exit 1\b", ln) for ln in lines[idx + 1:]):
            bads.append("%s: convert failure is swallowed - no `exit 1` after the "
                        "encoder run" % f)

    if bads:
        for m in bads[:8]:
            bad("L15", m)
    else:
        ok("L15", "child failures propagate in both families (%d files checked: "
                  ".bat entries `exit /b 1` behind a negative-safe %%ERRORLEVEL%% test, "
                  ".bat wrappers `exit /b 1`, .sh entries `exit 1`)" % checked)


# ---------------------------------------------------------------- L16
# Stream-mapping uniformity. ffmpeg's DEFAULT stream selection keeps exactly one
# video + one audio stream, so an mp4 entry without an explicit -map silently
# drops every extra audio track and every subtitle - a container conversion
# quietly throwing away the alternate-language tracks is very hard to notice.
# The 12 encoder entries always carried the full set; the two remux entries
# (ffmpeg_copy_to_mp4.{bat,sh}) did not until 2026-09-17, found by the user
# asking what `-map 0:v` was doing there. This rule pins the set for EVERY
# mp4-producing entry in both families.
STREAM_MAP_TOKENS = ("-map 0:a?", "-map 0:s?",
                     "-map_metadata 0", "-map_chapters 0")

# 2026-09-28: the VIDEO token is no longer the same for every exit.
# User report: `./ffmpeg_hevc_nvenc.sh "<mkv>"` died with
#   [mp4 @ ...] Could not find tag for codec hevc in stream #1, codec not
#              currently supported in container
#   [out#0/mp4] Could not write header (incorrect codec parameters ?): Invalid argument
#   Nothing was written into output file, because at least one of its streams
#              received no packets.
# while the same command with the -map options deleted succeeded. Root cause is
# the source, not the encode: that mkv carries an mkvmerge cover as stream #0:3
# (`Video: mjpeg (attached pic)`). `-map 0:v` selects video streams INCLUDING
# attached pictures, so the poster became a SECOND output video stream and was
# re-encoded to hevc - and mp4 can only store an attached picture as
# mjpeg/png/bmp, so the header write failed and zero bytes were written.
# `-map 0:V` (capital V = video streams that are NOT attached pictures) is the
# fix. Verified on the offending file with BOTH ffmpeg builds in use here
# (gyan 8.0-dev / sandbox: rc=0, 119980 B; cygwin 7.1.1: rc=0, 302862 B) and
# the failure reproduced on both (`0:v` -> rc=69 / rc=234). Both builds accept
# the V specifier. The dropped poster is a real but small trade: BEFORE the fix
# such a source produced no output at all.
STREAM_MAP_VIDEO = "-map 0:V"

# Exception: the two remux entries keep `-map 0:v`. They do not re-encode
# (-c:v copy -c:a copy), and mp4 *can* store a copied mjpeg/png poster, so
# there the attached picture survives today - measured on the same cover-art
# mkv: output kept 4 streams (h264 + 2 aac + mjpeg). Rewriting them to 0:V
# would silently drop a poster that the remux keeps right now. The distinction
# is re-encode vs copy, not style - do NOT "unify" it without re-measuring.
STREAM_MAP_VIDEO_KEEP_ATTACHED = {"ffmpeg_copy_to_mp4.bat": "-map 0:v",
                                  "ffmpeg_copy_to_mp4.sh": "-map 0:v"}

# 2026-09-22: ffmpeg_dvd_hevc.{bat,sh} is exempted from the "-c:s mov_text" token
# ONLY. DVD subtitles are run-length **bitmap** streams (dvd_subtitle); ffmpeg
# refuses to convert them, with literally
#   "Subtitle encoding currently only possible from text to text or bitmap to
#    bitmap"
# so mov_text is not a style choice here, it is impossible. The entry keeps
# every other token (-map 0:V / -map 0:a? / -map 0:s? / -map_metadata 0 /
# -map_chapters 0) and carries `-c:s copy` for mkv, which is the lossless
# equivalent. Do NOT extend this exemption to a text-subtitle entry: there
# mov_text really is the right answer.
STREAM_MAP_EXEMPT = {
    "ffmpeg_dvd_hevc.bat": ("-c:s mov_text",),
    "ffmpeg_dvd_hevc.sh": ("-c:s mov_text",),
}

# 2026-09-28: 封面(attached picture)保留。
# 用户要求: "如果有封面的尽可能保留封面"。上一轮把 `-map 0:v` 改成 `-map 0:V`, 片子
# 不再因为海报而写 0 字节, 但封面本身也一并被排除了。这一轮把它**单独映射**回来:
#   -map 0:V                      主视频(排除 attached picture)
#   -map <封面>                    由 lib 的能力门提供(排在主视频之后 -> 输出流号 1/2)
#   -c:v:0 <编码器>                主视频: 只有第 0 路被重编码
#   -c:v:1 copy -c:v:2 copy       封面槽位: 原样复制, 由同一个 lib 变量下发
#
# 2026-09-28 二次修订(用户报): 上一版用**不带流号**的 `-c:v copy` 当"视频默认复制",
# 再靠 `-c:v:0 <编码器>` 把主视频改回编码器。能跑通, 但同一条流被两个 -c 命中,
# ffmpeg 必报
#   [vost#0:0] Multiple -codec/-c/... options specified for stream 0, only the
#              last option '-codec:v:0 ...' will be used.
# 结果全靠"后写的赢": 命令里同时出现 copy 与编码器, 既误导人(用户就是看到那行
# `-c:v copy` 来问"是不是没在编码"), 又埋着"顺序一写反整片变复制"的坑。
# 所以本规则新增第一条断言: **编码出口不许出现未加流号的 `-c:v copy`**。
# 其余断言:
#   * 没有 `-c:v:0`                          -> 主视频不被编码, 或封面被当主视频;
#   * 引用了封面映射却没有封面复制指令        -> 封面被重编码 -> 回到 0 字节事故;
#   * 未限定的 `-profile:v`                  -> 会被套到 copy 流上, ffmpeg 报
#     `Error setting option profile to value main` /
#     `[vost#0:1/copy] Error setting up codec context options` 后失败
#     (实测: 未限定的 -preset/-b:v 打在 copy 流上是安全的, 只有 profile 致命)。
# 映射与复制指令都只定义在两个 lib 里(引用 + 定义分开检查), 入口引用的是变量 ——
# 这样"语法要改"只改一处, 而 lint 仍然能静态钉住两族都没漏。
COVER_MAP_REF = {"bat": "%COVERMAP%", "sh": "COVER_MAP[@]"}
COVER_MAP_LITERAL = "0:v:disp:attached_pic"
COVER_COPY_LITERAL = "-c:v:1 copy"
COVER_MAP_LIB = ("lib/common.sh", "lib/common.bat")

# 字幕出口 -c:s (2026-10-02): 原先每个入口各写一份 `-c:s mov_text`(mp4) 与
# `-c:s copy`(EXT=mkv), 加一个容器要改 20 个文件; 现在两个出口都由 lib 的 SENC
# 下发(默认值与合法值集中在 lib/defaults.cfg), 入口只引用变量 —— 于是这里改成和
# 封面映射同一套"引用 + 定义分开检查": 引用在入口, 定义在 lib, 两边都不能少。
# 为什么必须钉住: mov_text 源配 copy 会 rc=-40 / 0 字节产物, ass 配 mp4 又装不下,
# 容器与字幕出口是配套的 —— 哪个入口漏了变量, 那一族的 EXT 开关就悄悄失效。
# 例外仍是两个 dvd 入口(见 STREAM_MAP_EXEMPT): dvdvideo 是位图字幕, 走自己的 copy。
SUB_ENC_REF = {"bat": "%SENC%", "sh": "SENC[@]"}
SUB_ENC_LITERALS = ("-c:s mov_text", "-c:s copy")
SUB_ENC_LIB = ("lib/common.sh", "lib/common.bat")

# 位图字幕(2026-09-28): mp4 只能装 mov_text, 位图字幕一进 `-c:s mov_text` 就 EINVAL,
# 整片写 0 字节。排除指令 `-map -0:s:<i>` 由 lib 的闸门产出并**随封面变量一起下发**
# (入口零改动), 所以 lib 里那份位图名单是本规则的命根子 —— 名单被删 = 又变 0 字节。
# 判据仍取一个字面量(黑名单里最典型、也是用户片源里实测到的那个: 蓝光 PGS)。
SUB_BITMAP_LITERAL = "hdmv_pgs_subtitle"

# 例外(各有硬理由, 不许扩散):
#   * 两个 remux 入口用 `-map 0:v`: 它们不重编码, mp4 存得下复制来的 jpeg 封面,
#     封面本来就在 —— 再加一条封面映射只会把同一张图映射两次。
#   * 两个 dvd 入口: dvdvideo 源的流表里不存在封面(既没有 attached picture, 也没有
#     附件流), 而且它的 VFILT/VENC_ARGS 拼装方式与通用入口不同 —— 不为一个不存在的
#     场景去改一条已经验证过的路径。
COVER_MAP_SKIP = {
    "ffmpeg_copy_to_mp4.bat": "remux: -map 0:v 已经带上封面, 再加一条会重复映射",
    "ffmpeg_copy_to_mp4.sh": "remux: -map 0:v 已经带上封面, 再加一条会重复映射",
    "ffmpeg_dvd_hevc.bat": "dvdvideo 源没有封面流",
    "ffmpeg_dvd_hevc.sh": "dvdvideo 源没有封面流",
}


def check_stream_map(inv):
    bads = []
    checked = 0
    core = core_text()
    for fam, key in (("bat", "root_bat"), ("sh", "root_sh")):
        for f in inv[key]:
            if not re.match(r"^ffmpeg_.*\.%s$" % fam, f, re.IGNORECASE):
                continue
            p = os.path.join(ROOT, f)
            if not os.path.isfile(p):
                continue
            _, t = read_text(p)
            # 薄壳入口(阶段0): 命令体要看 lib/encode_core.sh 里它选中的那一支,
            # 见 entry_body_sh 的说明; 非薄壳(ffmpeg_dvd_hevc)仍只看自己。
            if fam == "sh":
                t = entry_body_sh(t, core) or t
            body = "\n".join(ln for ln in lf_lines(t)
                             if not ln.strip().lower().startswith(("rem", "#")))
            checked += 1
            exempt = STREAM_MAP_EXEMPT.get(f, ())
            want_video = STREAM_MAP_VIDEO_KEEP_ATTACHED.get(f, STREAM_MAP_VIDEO)
            other_video = (STREAM_MAP_VIDEO if want_video != STREAM_MAP_VIDEO
                           else "-map 0:v")
            missing = [tok for tok in (want_video,) + STREAM_MAP_TOKENS
                       if tok not in body and tok not in exempt]
            if missing:
                bads.append("%s: lacks %s - ffmpeg default selection keeps only 1 video "
                            "+ 1 audio, so extra audio/subtitle tracks are dropped"
                            % (f, ", ".join(missing)))
            # ---- 字幕出口: 引用 lib 的 SENC(定义在 lib 里, 见 SUB_ENC_* 注释) ----
            if f not in STREAM_MAP_EXEMPT and SUB_ENC_REF[fam] not in body:
                bads.append("%s: 没有引用字幕出口变量 %s —— mp4 要 mov_text、EXT=mkv 要 "
                            "copy, 两者都由 lib 按容器下发; 少了它字幕会被 ffmpeg 按容器 "
                            "默认挑, mov_text 源进 mkv 直接 rc=-40 / 0 字节产物"
                            % (f, SUB_ENC_REF[fam]))
            # ---- 封面映射 + 成对约定 (2026-09-28, 见上方 COVER_MAP_* 注释) ----
            if f not in COVER_MAP_SKIP:
                if re.search(r"-c:v\s+copy", body):
                    bads.append("%s: 出现未加流号的 `-c:v copy` —— 它会和 `-c:v:0 "
                                "<编码器>` 撞在同一条流上, ffmpeg 报 Multiple -codec "
                                "警告且语义全靠\"后写的赢\"; 封面请走 lib 变量里的 "
                                "`-c:v:1 copy -c:v:2 copy`" % f)
                elif COVER_MAP_REF[fam] not in body:
                    bads.append("%s: 没有引用封面映射 %s —— 带 mkv 海报的源会静默丢封面"
                                % (f, COVER_MAP_REF[fam]))
                elif "-c:v:0" not in body:
                    bads.append("%s: 编码器没有限定到主视频(缺 `-c:v:0 <编码器>`) —— "
                                "封面会被当成第二路视频重编码, mp4 存不下, 整条转码写 "
                                "0 字节" % f)
                elif re.search(r"-profile:v\s", body):
                    bads.append("%s: `-profile:v` 没有限定到主视频(应写 `-profile:v:0`) —— "
                                "未限定的 profile 会被套到封面那条 copy 流上, ffmpeg 报 "
                                "Error setting up codec context options 后失败" % f)
                else:
                    # 负映射 `-map -0:s:<i>` 是 ffmpeg 里少数**讲究顺序**的指令:
                    # 它只排除"已经映射进来"的流, 必须排在 `-map 0:s?` 之后才生效。
                    # 闸门把它和封面指令一起塞在同一个变量里(入口因此零改动), 于是
                    # 变量的位置就成了硬约束 —— 挪到 -map 0:s? 前面, 位图字幕排除
                    # 直接失效, 又回到整片 0 字节。
                    i_sub = body.find("-map 0:s?")
                    i_ref = body.find(COVER_MAP_REF[fam])
                    if i_sub >= 0 and i_ref >= 0 and i_ref < i_sub:
                        bads.append("%s: %s 排在 `-map 0:s?` 之前 —— 变量里的负映射 "
                                    "`-map -0:s:<i>` 只排除已映射的流, 顺序反了就失效, "
                                    "位图字幕会把整条转码打成 0 字节"
                                    % (f, COVER_MAP_REF[fam]))
            elif other_video in body:
                if want_video == STREAM_MAP_VIDEO:
                    bads.append("%s: uses `%s` - that maps the mkv cover (attached "
                                "picture) as a second output video stream and re-encodes "
                                "it, which mp4 cannot store (`Could not find tag for codec "
                                "... in stream #1`), so the whole run writes 0 bytes; use "
                                "`%s`" % (f, other_video, want_video))
                else:
                    bads.append("%s: uses `%s` - the remux does not re-encode, so `%s` "
                                "would silently drop the cover art it keeps today; remux "
                                "entries must keep `%s`"
                                % (f, other_video, other_video, want_video))
    # 封面映射 + 封面复制指令的**定义**在两个 lib 里各一份; 文件不存在(如 lint
    # 自测的合成仓库)就跳过, 只检查真实存在的那些。
    for rel in COVER_MAP_LIB:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            continue
        _, libtext = read_text(p)
        if COVER_MAP_LITERAL not in libtext:
            bads.append("%s: 没有定义封面映射(%s) —— 入口引用到的变量会是空的, "
                        "封面从此静默丢失" % (rel, COVER_MAP_LITERAL))
        if COVER_COPY_LITERAL not in libtext:
            bads.append("%s: 没有定义封面复制指令(%s) —— 封面映射回来了却没有 copy, "
                        "会被当第二路视频重编码, mp4 存不下, 整条写 0 字节"
                        % (rel, COVER_COPY_LITERAL))
        if SUB_BITMAP_LITERAL not in libtext:
            bads.append("%s: 没有定义位图字幕名单(%s) —— mp4 装不下位图字幕, 排除指令 "
                        "`-map -0:s:<i>` 会跟着消失, 带 PGS / dvd_subtitle 的源一跑就 "
                        "EINVAL 写 0 字节(实测用户清单里 14 个这样的文件)"
                        % (rel, SUB_BITMAP_LITERAL))
    for rel in SUB_ENC_LIB:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            continue
        _, libtext = read_text(p)
        for lit in SUB_ENC_LITERALS:
            if lit not in libtext:
                bads.append("%s: 没有定义字幕出口 %s —— 入口引用的 SENC(%%SENC%% / "
                            "${SENC[@]})会缺一半: mp4 要 mov_text, EXT=mkv 要 copy, "
                            "缺哪个哪个容器就退化成 ffmpeg 默认选择(静默丢字幕 / "
                            "rc=-40 写 0 字节)" % (rel, lit))
    if bads:
        for m in bads[:8]:
            bad("L16", m)
    else:
        ok("L16", "all %d mp4 entries (both families) keep every stream "
                  "(-map 0:V/-map 0:a?/-map 0:s? + %%SENC%%, whose mov_text/copy pair is "
                  "defined in both libs; %d encoder entries also map "
                  "the cover back in and copy it by stream index (-c:v:0 <enc> + "
                  "-c:v:1/-c:v:2 copy, no bare -c:v copy); the 2 remux entries "
                  "keep -map 0:v, which already carries it). the gate variable sits "
                  "after -map 0:s?, so the bitmap-subtitle exclusions it carries "
                  "(-map -0:s:<i>) still take effect"
                  % (checked, checked - len(COVER_MAP_SKIP)))


# ---------------------------------------------------------------- L17
# moov-in-front for the remux exit. A default mp4 keeps the index (moov) AFTER
# the media data, so a player needs the tail of the file before it can start -
# painful for a large file that is copied around or streamed. The user asked
# for front placement on 2026-09-17. Measured on the 320x240/3s probe clip:
# without the flag the atom order is ftyp/free/mdat/moov, with it
# ftyp/moov/free/mdat - and the byte count is IDENTICAL, because ffmpeg moves
# the index in place ("Starting second pass: moving the moov atom to the
# beginning of the file"). Pinned for both remux entries. The 11 encoder
# entries still write the default layout until the user asks for it there too.
MOOV_FRONT = {"ffmpeg_copy_to_mp4.bat": "-movflags +faststart",
              "ffmpeg_copy_to_mp4.sh": "-movflags +faststart"}


def check_moov_front(inv):
    bads = []
    checked = 0
    for f, token in sorted(MOOV_FRONT.items()):
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        body = "\n".join(ln for ln in lf_lines(t)
                         if not ln.strip().lower().startswith(("rem", "#")))
        checked += 1
        if token not in body:
            bads.append("%s: no `%s` - the mp4 index (moov) is written after mdat, "
                        "so playback cannot start before the whole file is fetched"
                        % (f, token))
    if bads:
        for m in bads:
            bad("L17", m)
    else:
        ok("L17", "the %d remux entries put moov in front (-movflags +faststart, "
                  "both families)" % checked)


# ---------------------------------------------------------------- L18
# Self anchoring: an "anchor" variable (REPO / SELF_DIR) holds the path that
# leads back to the repo from a .bat which may be started anywhere. Two ways to
# get it wrong, both of which happened in this repo:
#   * undefined -- "%REPO%\lib\common.bat" degrades to "\lib\common.bat", i.e. a
#     DRIVE-ROOT path, so the call dies from every cwd with "The system cannot
#     find the path specified." and the caller reports it as the misleading
#     "ffmpeg/ffprobe not on PATH". bench_calib.bat did exactly that when it was
#     run from the repo root (user report, 2026-09-20); the commit that was
#     supposed to fix it only swapped one undefined name for another;
#   * "%SELF_DIR%lib\..." with SELF_DIR undefined -- a RELATIVE path that works
#     only while the cwd happens to be the repo root (the bug that swap replaced).
# So: every anchor reference needs an assignment EARLIER in the same file, and a
# tool under test\bat (two levels down) must derive it from %~dp0..\..
ANCHOR_VARS = ("REPO", "SELF_DIR")
ANCHOR_UP2 = "%~dp0..\\.."


def anchor_set_re(var):
    """`set VAR=` at line start, or `... do set VAR=` inside a for/if guard."""
    return (re.compile(r'set\s+"?%s=' % var, re.IGNORECASE),
            re.compile(r'\bdo\s+set\s+"?%s=' % var, re.IGNORECASE))


def check_repo_anchor(inv):
    undef, late, unanchored = [], [], []
    checked = 0
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        lines = lf_lines(t)
        body = "\n".join(ln for ln in lines
                         if not ln.strip().lower().startswith(("rem", "::")))
        used = [v for v in ANCHOR_VARS if re.search(r"%%%s%%" % v, body, re.IGNORECASE)]
        if not used:
            continue
        checked += 1
        for v in used:
            use_re = re.compile(r"%%%s%%" % v, re.IGNORECASE)
            head_re, do_re = anchor_set_re(v)
            first_use = first_set = None
            for i, ln in enumerate(lines, 1):
                s = ln.strip()
                if s.lower().startswith(("rem", "::")):
                    continue
                if first_set is None and (head_re.search(s) or do_re.search(s)):
                    first_set = i
                elif first_use is None and use_re.search(s):
                    first_use = i
                if first_use is not None and first_set is not None:
                    break
            if first_set is None:
                undef.append("%s:%d reads %%%s%% but the file never assigns it "
                             "(the path degrades to a drive-root or relative one)"
                             % (f, first_use or 0, v))
            elif first_use is not None and first_set > first_use:
                late.append("%s:%d reads %%%s%% before it is assigned at line %d"
                            % (f, first_use, v, first_set))
        if f.replace("\\", "/").startswith("test/bat/") and ANCHOR_UP2 not in body:
            unanchored.append("%s: no `%s` anchor - this tool lives two levels below "
                              "the root, so the cwd is wherever the user clicked"
                              % (f, ANCHOR_UP2))
    msgs = undef + late + unanchored
    if msgs:
        for m in msgs[:8]:
            bad("L18", m)
    else:
        ok("L18", "anchor variables are assigned before use in every .bat that reads "
                  "them, and every test\\bat tool self-anchors on %s (%d files)"
           % (ANCHOR_UP2, checked))


# ---------------------------------------------------------------- L19
# `for /f ... in (`cmd`)` is executed by a CHILD cmd /c, and a
# variable-expanded PROGRAM PATH cannot be written safely there:
#   * bare    `%FFPROBE_PATH% -v error ...` -- the space in
#     "C:\Program Files\ffmpeg\bin\ffprobe.exe" splits the command line and cmd
#     answers "'C:\Program' is not recognized as an internal or external
#     command". bench_calib.bat did precisely that on 2026-09-20 (user report):
#     three such lines, then its own guard blamed ffprobe with
#     "ffprobe failed / pixel count overflow on this source";
#   * quoted  `"%FFPROBE_PATH%" -v error ...` -- cmd /c's quote rule ("if the
#     line starts with a quote, strip that one and the LAST quote on the line")
#     removes the closing quote of the final argument, so the line breaks as
#     soon as any path contains a space.
# The repo convention is therefore: run the tool from an ordinary (quoted)
# command line redirected to a temp file, then read that file with
# `for /f "usebackq"` -- exactly what lib\common.bat :probe_source and
# :probe_field do, and how every probe was written before the 2026-09-17
# refactor. Only a path-expanded FIRST token is flagged, so PATH-resolved
# `ffprobe` / `powershell` backtick commands stay legal.
# (Only the backtick form is checked: with usebackq a single-quoted string is a
# literal, not a command.)
BACKTICK_CMD_RE = re.compile(r"`([^`]*)`")
VAR_TOKEN_RE = re.compile(r"^%[A-Za-z_][A-Za-z0-9_]*%$")


def check_backtick_program(inv):
    bads, inspected = [], 0
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for i, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if s.lower().startswith(("rem", "::")):
                continue
            for m in BACKTICK_CMD_RE.finditer(ln):
                cmd = m.group(1).strip()
                if not cmd:
                    continue
                inspected += 1
                prog = cmd.split()[0].strip("\"'")
                if VAR_TOKEN_RE.match(prog):
                    bads.append("%s:%d runs %s from inside a for-backtick - a "
                                "variable-expanded program path cannot carry a "
                                "space there; redirect to a temp file and read "
                                "it with for /f \"usebackq\" (lib\\common.bat "
                                ":probe_field)" % (f, i, prog))
    if bads:
        for m in bads[:8]:
            bad("L19", m)
    else:
        ok("L19", "no for-backtick runs a variable-expanded program path "
                  "(%d backtick command(s) inspected)" % inspected)


# ---------------------------------------------------------------- L20
FF_REQ_WHITELIST = {
    # check_env.sh 是"环境盘点"工具: 它故意报告 PATH 上那个 ffmpeg 有没有
    # libvmaf(以及各构建的分布), 不是 libvmaf 的消费者。它拿到的那个对象
    # 只是"待盘点的东西", 不参与能力筛选。
    "test/sh/check_env.sh",
}


def _norm_path(f):
    return f.replace("\\", "/")


def check_ffmpeg_requirement(inv):
    """A .sh tool that hard-requires libvmaf must not simply trust PATH.

    All three calib tools resolve the binary through lib/common.sh's find_ffmpeg,
    which takes --need-filter/--need-encoder and skips builds that lack them.
    That matters on a Windows box: an MSYS2 shell resolves `ffmpeg` to
    /mingw64/bin 8.1 and a Cygwin shell to /usr/bin 7.1.1 - neither has libvmaf -
    while the gyan full build sits further down the search order. A plain PATH
    lookup fails there with a misleading "this ffmpeg build has no libvmaf
    filter" on a machine that has one (2026-09-20).

    Scope note (same day): the .bat half of this rule was removed again. A
    capability argument was added to lib/common.bat's :find_ffmpeg and to both
    calib .bat tools, but it was built as "%1\\ffmpeg.exe" while the caller
    passes an already-quoted %FFBIN% - see L21 - so it mis-detected every
    candidate, and it was the only change between the last working run of
    test\\bat\\bench_calib.bat and the silent exit the user reported right after.
    With no cmd.exe in the dev sandbox there is no way to verify cmd quoting
    behaviour, so the gate was reverted rather than debugged blind. On this
    machine it could not have helped anyway: C:\\Program Files\\ffmpeg\\bin is not
    on PATH at all, so the `where ffmpeg.exe` branch never selects it. If the
    bat side is ever revisited it needs "%~1\\ffmpeg.exe" and a real cmd run.
    """
    bads, inspected = [], []
    for f in inv["test_sh"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        code = [ln for ln in lf_lines(t) if not ln.strip().startswith("#")]
        if not any("libvmaf" in ln for ln in code):
            continue
        if f.replace(os.sep, "/") in FF_REQ_WHITELIST or _norm_path(f) in FF_REQ_WHITELIST:
            continue
        inspected.append(f)
        if not any("find_ffmpeg" in ln and "--need-filter" in ln
                   and "libvmaf" in ln for ln in code):
            bads.append("%s requires libvmaf but does not resolve ffmpeg with "
                        "it - use find_ffmpeg --need-filter libvmaf from "
                        "lib/common.sh instead of trusting PATH" % f)
    if bads:
        for m in bads[:8]:
            bad("L20", m)
    else:
        ok("L20", "libvmaf consumers resolve ffmpeg with --need-filter "
                  "(%d .sh tool(s) inspected)" % len(inspected))


# ---------------------------------------------------------------- L21
_QUOTED_ARG = re.compile(r'"(?P<pct>%{1,2})(?P<digit>[0-9])')


def check_quoted_arg_expansion(inv):
    """Never nest an argument expansion inside another pair of quotes.

    %1 already carries whatever quotes the caller wrote, so

        "%1\\ffmpeg.exe"

    is not "quoted path + suffix". With a caller of `call :x "%FFBIN%"` it
    expands to

        ""C:\\Program Files\\ffmpeg\\bin"\\ffmpeg.exe"

    and cmd's first-token rule reads the program name as the empty string.
    Write "%~1\\ffmpeg.exe" instead - the ~ strips the caller's quotes.

    Not hypothetical: this sat in lib/common.bat's :ff_satisfies behind a
    `2>nul`, so the failure was invisible and every candidate was reported as
    lacking the capability, including the one that has it. Found 2026-09-20
    while chasing the silent exit of test\\bat\\bench_calib.bat; the whole
    bat-side capability gate was then reverted (see L20's note).
    A pure "%1" (verbatim pass-through) and "%~1" both stay legal.
    """
    bads, inspected = [], 0
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for n, ln in enumerate(lf_lines(t), 1):
            if ln.strip().lower().startswith(("rem", "::")):
                continue
            inspected += 1
            for m in _QUOTED_ARG.finditer(ln):
                if ln[m.end():m.end() + 1] == '"':
                    continue          # "%1" - verbatim, correct
                bads.append("%s:%d nests an argument expansion in quotes - "
                            "found \"%s%s\"; write \"%%~%s...\" instead, the ~ "
                            "strips the quotes the caller already passed"
                            % (f, n, m.group("pct"), m.group("digit"),
                               m.group("digit")))
                break
    if bads:
        for m in bads[:8]:
            bad("L21", m)
    else:
        ok("L21", "no argument expansion is nested inside quotes "
                  "(%d .bat line(s) inspected)" % inspected)


# ---------------------------------------------------------------- L22
_CALL_LINE = re.compile(r'\bcall\b\s+(?:"[^"]*"|\S+)?\s*(?P<rest>.*)$', re.IGNORECASE)
_QUOTED_SEG = re.compile(r'"[^"]*"')


def check_call_arg_equals(inv):
    """Never put a bare '=' inside a `call` argument list.

    cmd does not only split a batch argument list on spaces: commas, semicolons
    **and equals signs** are separators too. So

        call "%REPO%\\lib\\common.bat" probe_field "%OUT%" stream=bit_rate DEL

    arrives as  %2=<file>  %3=stream  %4=bit_rate  %5=DEL. The callee takes the
    NAME of its output variable from %4, so it writes into a variable called
    bit_rate and the DEL the caller reads is never set.

    Not hypothetical: that exact line shipped in both test\\bat\\bench_calib.bat
    and test\\bat\\soft_pair_calib.bat on 2026-09-20 - :probe_field was new and
    had never run on a real machine - and it printed a delivered column of 0 for
    all five ladder points while vmaf looked perfectly healthy. The dev sandbox
    cannot run cmd.exe, so no static review could have caught it (user report).
    Pass a KEYWORD and let the callee expand it to the show_entries string.

    A quoted argument such as `call :x "opt=1"` is split-safe and stays legal.
    """
    bads, inspected = [], 0
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        for n, ln in enumerate(lf_lines(t), 1):
            if ln.strip().lower().startswith(("rem", "::")):
                continue
            m = _CALL_LINE.search(ln)
            if not m:
                continue
            inspected += 1
            rest = _QUOTED_SEG.sub(" ", m.group("rest"))
            if "=" in rest:
                tok = [w for w in rest.split() if "=" in w]
                bads.append("%s:%d passes a bare '=' in a call argument - "
                            "found %s; cmd splits batch arguments on '=', so the "
                            "callee's %%-numbers shift and the output variable is "
                            "never set (quote it, or pass a keyword instead)"
                            % (f, n, tok[0] if tok else "="))
    if bads:
        for m in bads[:8]:
            bad("L22", m)
    else:
        ok("L22", "no call passes a bare '=' in its argument list "
                  "(%d .bat line(s) inspected)" % inspected)

# ---------------------------------------------------------------- L23
# An unquoted ')' inside a multi-line ( ) block closes that block EARLY.
#
# Verified against real cmd.exe on 2026-09-22 with a dozen minimal batches.
# The rule cmd follows, as far as the evidence goes:
#   * rem lines, labels and "quoted spans"  -> parens are immune
#   * a lone '(' in argument text           -> immune (does NOT open a group)
#   * for %%A in (list) do                  -> immune (cmd special-cases for)
#   * ')' anywhere else in argument text    -> closes the enclosing block NOW
#   * balanced ( ... ) else ( ... ) on one line -> fine (that IS if syntax)
#
# Why it matters: when the offending line is what was meant to be the block's
# last line, the statement that follows LEAVES the block and becomes a
# top-level command that runs UNCONDITIONALLY. The batch then dies with rc=1,
# and because the closing ')' swallowed the compiler's view of the block, the
# error lines inside it never print - the failure is completely silent.
#
# That is exactly what ffmpeg_dvd_hevc.bat did on its first real run:
#
#     if errorlevel 1 (
#         echo [错误] 这份 ffmpeg 没有 dvdvideo 解复用器
#         echo        需要带 libdvdread + libdvdnav 的构建(gyan.dev full build 有)
#         exit /b 1        <- now top level: runs even when the check passes
#     )
#
# User symptom: two normal lines ("ffmpeg    : ...", "源        : ...") and
# then straight back to the prompt, no error at all. L05 cannot see it - L05
# skips echo lines (line 195) and compares whole-file totals, and those totals
# are balanced. L07 cannot see it either. Diagnosed only by running the file.
#
# Fixes that are always safe: write （全角括号） or [1] [2] [3] instead, or move
# the text out of the block into a plain variable first.
_PAREN_AFTER_KW = re.compile(r'(?i)(\b(else|in)|\|\||&&)\s*$')
_PAREN_IF_HEAD = re.compile(r'(?i)^\s*(if|for)\b')
_PAREN_PURE_CLOSE = re.compile(r'^\)+\s*$')
_PAREN_CLOSE_ELSE = re.compile(r'^(\)+)\s*else\s*(\(+)\s*$')


def _paren_strip_quoted(s):
    """Neutralise everything cmd does NOT count as a block delimiter.

    * "quoted spans"          -> parens are literal
    * ^^ ^( ^)                -> caret escaping; verified immune on real cmd
                                 (`echo escaped ^(vbr^|fbr^) here` inside a
                                 block runs both the echo and the following
                                 lines - repo already relies on this in
                                 lib\\common.bat and test\\bat\\*_calib.bat)
    """
    s = re.sub(r'"[^"]*"', '""', s)
    s = s.replace("^^", "\x00")
    s = s.replace("^(", "\x01").replace("^)", "\x02")
    return s


def _paren_legit_opens(text):
    """Count '(' that sit at a *command* position, i.e. the ones cmd really
    treats as group openers: start of line, after `else`, after `in`, after
    `||` / `&&`, right after another ')' and the first '(' of an `if <cond> (`
    head. `pushd "%X%" || ( endlocal & exit /b 1 )` inside a block is a real
    repo pattern (test\\bat\\nvenc_pair_calib.bat) and verified safe."""
    n = 0
    for m in re.finditer(r'\(', text):
        before = text[:m.start()].rstrip()
        if before == "":
            n += 1
        elif _PAREN_AFTER_KW.search(before):
            n += 1
        elif before.endswith(")"):
            n += 1
        elif _PAREN_IF_HEAD.match(before) and "(" not in before:
            n += 1
    return n


def check_block_paren_text(inv):
    hits, inspected, blocks = [], 0, 0
    for f in inv["all_bat"]:
        p = os.path.join(ROOT, f)
        if not os.path.isfile(p):
            continue
        _, t = read_text(p)
        depth = 0
        for n, ln in enumerate(lf_lines(t), 1):
            s = ln.strip()
            if not s or s.lower().startswith(("rem", "::")) or s.startswith(":"):
                continue
            body = _paren_strip_quoted(s)
            if depth > 0:
                inspected += 1
            m = _PAREN_PURE_CLOSE.match(body)
            if m:
                depth = max(0, depth - len(body.strip()))
                continue
            m = _PAREN_CLOSE_ELSE.match(body)
            if m:
                depth = max(0, depth + len(m.group(2)) - len(m.group(1)))
                continue
            if depth > 0:
                surplus = body.count(")") - _paren_legit_opens(body)
                if surplus > 0:
                    hits.append("%s:%d closes its enclosing ( ) block early - "
                                "%d unquoted ')' beyond the group openers; the "
                                "statement after this line becomes top-level and "
                                "runs unconditionally (silent rc=1). Use full-width "
                                "（）/[1] instead: %s"
                                % (f, n, surplus, s[:60]))
            trail = re.search(r'\(+$', body)
            if trail:
                depth += len(trail.group(0))
                blocks += 1
    if hits:
        for m in hits[:8]:
            bad("L23", m)
    else:
        ok("L23", "no unquoted ')' in argument text inside a multi-line block "
                  "(%d in-block lines inspected, %d block opener(s))"
                  % (inspected, blocks))

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
    p = os.path.join(ROOT, "test", "bat", "smoke_ffmpeg.bat")
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
                bads.append("smoke_ffmpeg.bat %s: expected %d but table says %d"
                            % (logname, val, expected[tbl]))
    p = os.path.join(ROOT, "test", "sh", "smoke_ffmpeg.sh")
    if os.path.isfile(p):
        _, t = read_text(p)
        for m in re.finditer(r"^(?:run_arg|gate_arg)\s+(T\d+)\s+(\S+)\s+(?:ok|fail)?\s*(\d+)",
                             t, re.MULTILINE):
            tid, script, val = m.group(1), m.group(2), int(m.group(3))
            for codec in ("h264", "hevc", "av1"):
                if codec in script or (codec == "h264" and "libx264" in script):
                    tbl = family_table(codec)
                    if tbl and expected[tbl] != val:
                        bads.append("smoke_ffmpeg.sh %s %s: expected %d but table says %d"
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
# ---------------------------------------------------------------- 编码器提取
# 2026-09-28: 编码入口的写法是 `-c:v:0 <编码器>` + 封面槽位 `-c:v:1 copy -c:v:2 copy`
# —— 只对第 0 路(主视频)重编码, 单独映射进来的封面(attached picture)按流号原样
# 复制进 mp4 的 covr。
# (上一版曾用 `-c:v copy -c:v:0 <编码器>`, 两条指令撞在同一条流上, 已废弃, L16 拦。)
# **必须先找 `-c:v:0`**: 沿用"第一个 -c:v"的老写法抓到的是字面量 `copy`, P02/P07
# 会拿 copy 当编码器名互相"对比" —— 一句没有意义的 PASS, 比报错更坏。
def encoder_of(text):
    m = re.search(r"-c:v:0\s+(\S+)", text)
    if m:
        return m.group(1).strip('"')
    m = re.search(r"-c:v\s+(\S+)", text)   # 旧写法 / dvd 入口的 $VENC_NAME|%VENC% 形态
    return m.group(1).strip('"') if m else None


# 同理: profile 现在限定到主视频 `-profile:v:0`。老写法只该出现在 dvd 那种
# 没有 copy 流的入口里 —— 未限定的 `-profile:v` 一旦和 copy 流共存, ffmpeg 会以
# `Error setting option profile to value main` / `Error setting up codec context
# options` 直接失败(L16 会拦)。
def profile_of(text):
    for pat in (r"-profile:v:0\s+([a-z0-9]+)", r"-profile:v\s+([a-z0-9]+)"):
        m = re.search(pat, text)
        if m:
            return m.group(1)
    return None


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
        enc = encoder_of(t)
        if enc and tbl:
            mapping.setdefault(enc, set()).add(tbl)
    for f in inv["root_bat"]:
        p = os.path.join(ROOT, f)
        _, t = read_text(p)
        tbl = table_of(t)
        enc = encoder_of(t)
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
# Kept empty on purpose: an entry belongs here ONLY while a fix is pending.
# The libx265 preset was unified to `fast` on BOTH families (2026-09-16, user
# call: prefer `fast`). Re-adding an entry silences P07 again -- do it
# consciously and document the reason.
PARAM_WHITELIST = {}


def check_encoder_params(inv):
    def parse(text, family):
        enc = None
        prof = None
        preset = None
        pix = None
        enc = encoder_of(text)
        prof = profile_of(text)
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
        enc = encoder_of(t)
        if not enc:
            continue
        sh_map[enc] = parse(t, "sh")[1:]
    for f in inv["root_bat"]:
        p = os.path.join(ROOT, f)
        _, t = read_text(p)
        enc = encoder_of(t)
        if not enc:
            continue
        bat_map[enc] = parse(t, "bat")[1:]
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
        print("         L13 exit-code contract  L14 .sh exec bit")
        print("         L15 failure propagation (family parity of the failure path)")
        print("         L16 stream-map uniformity (mp4 entries keep all streams)")
        print("         L17 moov in front (remux entries use -movflags +faststart)")
        print("         L18 anchor vars (REPO/SELF_DIR) defined before use, "
              "test\\bat self-anchored")
        print("         L19 no for-backtick runs a variable-expanded program path")
        print("         L20 .sh libvmaf consumers resolve ffmpeg with "
              "--need-filter")
        print("         L21 no argument expansion nested inside quotes "
              "(write \"%~1\", not \"%1\")")
        print("         L22 no bare '=' in a call argument list "
              "(cmd splits batch arguments on it)")
        print("         L23 no unquoted ')' in argument text inside a multi-line "
              "( ) block (it closes the block early -> silent rc=1)")
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
        check_exec_bits(inv)
        check_exit_codes(inv)
        check_fail_propagation(inv)
        check_stream_map(inv)
        check_moov_front(inv)
        check_repo_anchor(inv)
        check_backtick_program(inv)
        check_ffmpeg_requirement(inv)
        check_quoted_arg_expansion(inv)
        check_call_arg_equals(inv)
        check_block_paren_text(inv)

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
