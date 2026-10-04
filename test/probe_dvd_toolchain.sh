#!/bin/bash
# probe_dvd_toolchain.sh - 探测本机 DVD 工具链(dvdauthor / genisoimage / ffmpeg)可用性与版本
# 只做只读探测, 不修改任何素材。用于定位上一轮会话用过的那套工具到底装在哪。
case "${1:-}" in
    --help|-help|-h)
        # 统一 --help / -help / -h。本脚本刻意**不**依赖 lib/common.sh(定位一套工具链
        # 时要能单文件拷走), 所以这里用与 ff_print_usage 同款的那段 awk 打印文件头说明。
        # 说明文字放在 case 里面而不是上面: 那段 awk 一直打到第一个非注释行为止, 放在
        # 上面会把这段解释也当成"用法"打出来。
        awk 'NR>=2 && !/^#/ { exit } NR>=2 && /^# =+$/ { next } NR>=2 { sub(/^# ?/, ""); print }' "$0"
        exit 0 ;;
esac

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
