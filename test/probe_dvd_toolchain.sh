#!/bin/bash
# probe_dvd_toolchain.sh - 探测本机 DVD 工具链(dvdauthor / genisoimage / ffmpeg)可用性与版本
# 只做只读探测, 不修改任何素材。用于定位上一轮会话用过的那套工具到底装在哪。
echo "=== uname: $(uname -s) ==="
echo "=== shell: $BASH ==="
echo "=== PATH ==="
printf '%s\n' "$PATH" | tr ':' '\n'
echo "=== tools ==="
for t in genisoimage mkisofs dvdauthor xorriso isoinfo lsdvd dvdtree; do
    p="$(command -v "$t" 2>/dev/null)"
    if [ -n "$p" ]; then
        printf '%-12s = %s\n' "$t" "$p"
    else
        printf '%-12s = MISSING\n' "$t"
    fi
done
echo "=== versions ==="
for t in genisoimage mkisofs dvdauthor; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] || continue
    printf '%-12s : %s\n' "$t" "$("$t" --version 2>&1 | head -1)"
done
