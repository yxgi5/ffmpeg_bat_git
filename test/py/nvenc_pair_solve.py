# nvenc_pair_solve.py - NVENC AV1/HEVC equal-quality pair solver
#
# Companion analysis tool for test/bat/nvenc_pair_calib.bat (and its
# sh twin test/sh/nvenc_pair_calib.sh). Scans the
# bench work dir for <res>_<br>k_<av1|hevc>_nvenc.json + .mp4 pairs,
# reads delivered bitrate via ffprobe and pooled VMAF from the JSON,
# then reports the bitrate ratio r = AV1/HEVC at each VMAF target.
#
# Usage:
#   python nvenc_pair_solve.py [<work_dir>]
#     work_dir default: %LOCALAPPDATA%\Temp\ffmpeg_bat_nvenc_pair
#
# Requires ffprobe on PATH. Historical results (B machine RTX 4080
# Laptop, 2026-09-17): r ~ 0.72-1.0 depending on quality target,
# see environment_matrix.md #26.
import glob
import json
import math
import os
import statistics
import subprocess
import sys


def load(work):
    d = {}
    for js in sorted(glob.glob(os.path.join(work, "*_nvenc.json"))):
        tag = os.path.basename(js)[:-5]   # e.g. 1920x1080_3300k_av1_nvenc
        p = tag.split("_")                # res, br, av1|hevc, nvenc
        res, codec = p[0], p[2] + "_" + p[3]
        mp4 = js[:-5] + ".mp4"
        out = subprocess.check_output([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=bit_rate", "-of", "csv=p=0", mp4])
        delivered = int(out.decode().strip())
        vm = json.load(open(js))["pooled_metrics"]["vmaf"]["mean"]
        d.setdefault((res, codec), []).append((delivered, vm))
    return d


def fit(pts):
    xs = [math.log2(b) for b, _ in pts]; ys = [v for _, v in pts]
    n = len(xs); sx = sum(xs); sy = sum(ys)
    sxx = sum(x * x for x in xs); sxy = sum(x * y for x, y in zip(xs, ys))
    a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    return a, (sy - a * sx) / n


def main():
    work = sys.argv[1] if len(sys.argv) > 1 else os.path.expandvars(
        r"%LOCALAPPDATA%\Temp\ffmpeg_bat_nvenc_pair")
    d = load(work)
    if not d:
        sys.exit(f"no *_nvenc.json found under {work}")
    allr = []
    for res in sorted({k[0] for k in d}):
        hx, ax = d[(res, "hevc_nvenc")], d[(res, "av1_nvenc")]
        lo = max(min(v for _, v in hx), min(v for _, v in ax))
        hi = min(max(v for _, v in hx), max(v for _, v in ax))
        targets = [t for t in (93, 95, 96, 97, 98, 99) if lo <= t <= hi]
        ah, bh = fit(hx); aa, ba = fit(ax)
        print(f"{res}:  hevc slope={ah:.2f}  av1 slope={aa:.2f}  "
              f"vmaf range [{lo:.1f},{hi:.1f}]")
        for t in targets:
            bhe = 2 ** ((t - bh) / ah); bav = 2 ** ((t - ba) / aa)
            r = bav / bhe
            allr.append(r)
            print(f"   VMAF{t}:  HEVC={bhe / 1e6:.2f} Mbps   "
                  f"AV1={bav / 1e6:.2f} Mbps   r={r:.3f}")
    print(f"\noverall mean r = {statistics.mean(allr):.3f}")


if __name__ == "__main__":
    main()
