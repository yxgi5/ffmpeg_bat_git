# table_ratio_audit.py - cross-table ratio + power-law audit
#
# Audits the three bitrate tables in lib/ (avc / hevc / av1):
#   1. per-pixel-bucket HEVC/AVC and AV1/HEVC ratios (expect ~0.65 / ~0.85
#      as codec-generation theoretical gains)
#   2. non-monotonic / duplicate bucket detection
#   3. power-law fit  bitrate = a * pixels^e  for each table
#
# Usage:
#   python table_ratio_audit.py [<lib_dir>]
#     lib_dir default: <repo>/lib  (resolved from this script's location)
import csv
import math
import os
import statistics
import sys


def load(path):
    d = {}
    dups = 0
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            p = int(row["max_pixels"]); b = int(row["bitrate"])
            if p in d:
                dups += 1
            d[p] = b  # dup keys overwrite, kept for reporting
    return d, dups


def stats(xs):
    return (f"min={min(xs):.3f} median={statistics.median(xs):.3f} "
            f"mean={statistics.mean(xs):.3f} max={max(xs):.3f}")


def monotonic_violations(d):
    ps = sorted(d)
    return [(p1, p2, d[p2] - d[p1]) for p1, p2 in zip(ps, ps[1:])
            if d[p2] <= d[p1]]


def power_law_fit(d):
    xs = [math.log(p) for p in sorted(d)]
    ys = [math.log(d[p]) for p in sorted(d)]
    n = len(xs); sx = sum(xs); sy = sum(ys)
    sxx = sum(x * x for x in xs); sxy = sum(x * y for x, y in zip(xs, ys))
    e = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    return math.exp((sy - e * sx) / n), e


def main():
    lib = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__)))), "lib")
    tables = {}
    for name in ("avc", "hevc", "av1"):
        path = os.path.join(lib, f"bitrate_table_{name}.csv")
        tables[name], dups = load(path)
        if dups:
            print(f"{name}: {dups} duplicate pixel bucket(s) (overwritten)")
        bad = monotonic_violations(tables[name])
        if bad:
            print(f"{name}: NON-MONOTONIC at {bad}")
        else:
            print(f"{name}: monotonic OK")

    common = sorted(set(tables["avc"]) & set(tables["hevc"])
                    & set(tables["av1"]))
    print(f"\ncommon pixel buckets: {len(common)} "
          f"(avc={len(tables['avc'])}, hevc={len(tables['hevc'])}, "
          f"av1={len(tables['av1'])})")

    rows = []
    for p in common:
        rows.append((p, tables["avc"][p], tables["hevc"][p],
                     tables["av1"][p],
                     tables["hevc"][p] / tables["avc"][p],
                     tables["av1"][p] / tables["hevc"][p]))

    print("\n== HEVC/AVC ratio by pixels ==")
    print("  ", stats([r[4] for r in rows]))
    print("== AV1/HEVC ratio by pixels ==")
    print("  ", stats([r[5] for r in rows]))

    buckets = [(0, 1e5, "<0.1MP (icon)"), (1e5, 5e5, "0.1-0.5MP"),
               (5e5, 1e6, "0.5-1MP (SD)"), (1e6, 2.1e6, "1-2.1MP (720p/1080p)"),
               (2.1e6, 5e6, "2.1-5MP"), (5e6, 1e7, "5-10MP (4K)"),
               (1e7, 2e7, "10-20MP"), (2e7, 2e8, ">20MP")]
    print(f"\n{'bucket':<18}{'n':>3} {'HEVC/AVC':>9} {'AV1/HEVC':>9} "
          f"{'AV1/AVC':>9}")
    for lo, hi, name in buckets:
        seg = [r for r in rows if lo < r[0] <= hi]
        if not seg:
            continue
        m1 = statistics.mean(r[4] for r in seg)
        m2 = statistics.mean(r[5] for r in seg)
        print(f"{name:<18}{len(seg):>3} {m1:>9.3f} {m2:>9.3f} "
              f"{m1 * m2:>9.3f}")

    print("\n== sampled rows ==")
    print(f"{'pixels':>10} {'px(M)':>6} {'AVC':>10} {'HEVC':>10} "
          f"{'AV1':>10} {'H/A':>6} {'A/H':>6}")
    step = max(1, len(rows) // 15)
    for r in rows[::step]:
        print(f"{r[0]:>10} {r[0] / 1e6:>6.2f} {r[1]:>10} {r[2]:>10} "
              f"{r[3]:>10} {r[4]:>6.3f} {r[5]:>6.3f}")

    print("\n== power-law fits ==")
    for name, d in tables.items():
        a, e = power_law_fit(d)
        print(f"{name}: bitrate = {a:.1f} * pixels^{e:.3f}")
        print(f"  e.g. 1080p(2.07M): {a * 2073600 ** e / 1e6:.2f} Mbps ; "
              f"4K(8.29M): {a * 8294400 ** e / 1e6:.2f} Mbps")


if __name__ == "__main__":
    main()
