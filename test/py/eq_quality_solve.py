# eq_quality_solve.py - equal-quality bitrate-ratio solver (software pair)
#
# Reads calibration CSVs produced by a bench_calib-style ladder run
# (columns: clip,codec,br_req,br_delivered,vmaf; codec values x265/av1),
# fits vmaf ~ a*log2(delivered)+b per (clip, codec), and reports the
# bitrate ratio r = AV1/HEVC needed to reach each VMAF target.
#
# Usage:
#   python eq_quality_solve.py <results.csv> [<results.csv> ...]
#
# Historical inputs (2026-09-17 calibration, see environment_matrix.md #25):
#   c_results.csv  = C machine main run (20 cores)
#   a_results.csv  = A machine cross-check (1080p)
import csv
import math
import statistics
import sys

TARGETS = (90, 93, 96, 98)


def load(path):
    d = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            if not r.get("br_delivered"):
                continue
            key = (r.get("clip", "src"), r["codec"])
            d.setdefault(key, []).append(
                (float(r["br_delivered"]), float(r["vmaf"])))
    return d


def fit(pts):
    xs = [math.log2(b) for b, _ in pts]
    ys = [v for _, v in pts]
    n = len(xs)
    sx = sum(xs); sy = sum(ys)
    sxx = sum(x * x for x in xs); sxy = sum(x * y for x, y in zip(xs, ys))
    a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    return a, (sy - a * sx) / n


def report(name, d, targets):
    print(f"== {name} ==")
    agg = {}
    for c in sorted({k[0] for k in d}):
        hx = d.get((c, "x265")); ax = d.get((c, "av1"))
        if not hx or not ax:
            continue
        lo = max(min(v for _, v in hx), min(v for _, v in ax))
        hi = min(max(v for _, v in hx), max(v for _, v in ax))
        line = f"  {c:<12}"
        for t in targets:
            if lo <= t <= hi:
                ah, bh = fit(hx); aa, ba = fit(ax)
                bhv = 2 ** ((t - bh) / ah); bav = 2 ** ((t - ba) / aa)
                r = bav / bhv
                agg.setdefault(c.rstrip("0123456789_"), []).append(r)
                line += f"  V{t}: H={bhv / 1e6:.2f}M A={bav / 1e6:.2f}M r={r:.3f}"
        print(line)
    for k, v in agg.items():
        print(f"  AGG {k:<8} r={statistics.mean(v):.3f}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        report(path, load(path), TARGETS)


if __name__ == "__main__":
    main()
