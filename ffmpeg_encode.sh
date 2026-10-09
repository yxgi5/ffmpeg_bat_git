#!/bin/bash
# ffmpeg_encode.sh - 统一编码入口 (TODO.md 阶段 1)
# 用法: ./ffmpeg_encode.sh --venc <编码器> [--dec <解码器>] [视频文件]
#   不带文件参数: 交互输入文件路径(编码器还会问输出码率)
#   带文件参数  : 文件路径, 码率/输出文件名自动决定
#
# --venc 取值(编码器, 与 ffmpeg_dvd_hevc.sh 的 --venc 同义, avc_* 是 h264_* 的别名):
#   libx264 libx265 libsvtav1        软件
#   avc_qsv hevc_qsv av1_qsv         QSV 硬编(需 QSV 硬件)
#   avc_nvenc hevc_nvenc av1_nvenc   NVENC 硬编(需 NVIDIA 显卡)
#   avc_vaapi hevc_vaapi             VAAPI 硬编(仅 Linux; 阶段 3 撤)
#   copy                             无损转封装, 不重编码
# --dec 取值(解码器, 可省; 省了就用编码器族的固定拓扑):
#   auto / cpu(=none) / none / qsv / cuda
#   与编码器族不一致时**只警告不拦**(混合硬解有人用), 但会说明 10bit 降位滤镜不跟过来。
#
# 公共流程全在 lib/encode_core.sh 的 enc_run 里(阶段 0 抽的); 本文件只做三件事:
# 解析开关、校验 --venc、给人看用法。

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/encode_core.sh
source "${SCRIPT_DIR}/lib/encode_core.sh"

# 命令行开关解析: --key value -> 同名大写环境变量(见 lib/common.sh)
#   --venc -> VENC, --dec -> DEC。两者都在公共 SWITCH_KEYS 里, 所以老写法的
#   环境变量 VENC= / DEC= 照样有效(优先级 参数 > 环境变量 > defaults.cfg)。
parse_switches "$@"
set -- ${PS_REST[@]+"${PS_REST[@]}"}

declare -F ff_help_guard >/dev/null 2>&1 && ff_help_guard "$0" "$@" -- \
    "ffmpeg_encode.sh  -  统一压缩入口（软件 / QSV / NVENC / VAAPI + 转封装）" \
    "用法: ./ffmpeg_encode.sh --venc <编码器> [--dec <解码器>] 视频文件" \
    "  --venc libx264 libx265 libsvtav1" \
    "        avc_qsv  hevc_qsv  av1_qsv" \
    "        avc_nvenc hevc_nvenc av1_nvenc" \
    "        avc_vaapi hevc_vaapi   (仅 Linux)" \
    "        copy                  (无损转封装, 不重编码)" \
    "  --dec  auto | cpu | none | qsv | cuda   (可省, 默认用编码器族的固定解码)" \
    "老入口仍然可用: ffmpeg_libx264.sh / ffmpeg_hevc_qsv.sh / ffmpeg_copy_to_mp4.sh …" || :

# ---------- 校验 --venc ----------
# parse_switches 只认键名不认语义, 所以取值是否合法由每个脚本自己判(tools/ 那批
# 脚本同理)。--venc 不给时无法猜 —— 各老入口的编码器是写死的, 没有默认值可继承。
#
# 这里**不做**别名归一: 内核的表(`enc_vargs` / `enc_dec_args` / `enc_known`)以
# `avc_*` 为主键, `enc_ffenc` 那一层是"键 -> ffmpeg 编码器名"的翻译, 只在核心里用。
# 所以用户写 avc_qsv 就原样传 avc_qsv。ffmpeg_dvd_hevc.sh 那边是反过来(以 h264_* 为主、
# avc_* 当别名), 两边对用户来说都认这两个名字, 只是内部主键不同 —— 阶段 1 之后
# dvd_hevc 也改调 enc_ffenc, 那时两边就是同一份映射了。
if [ -z "${VENC:-}" ]; then
    echo -e "\033[41;36m要指定编码器: --venc <编码器>\033[0m"
    echo "可选: $(enc_known)"
    exit 1
fi
VENC_KEY="$VENC"
case " $(enc_known) " in
    *" $VENC_KEY "*) ;;
    *)
        echo -e "\033[41;36m不认识的编码器: $VENC\033[0m"
        echo "可选: $(enc_known)"
        exit 1
        ;;
esac

# copy 没有解码器可言(不重编码); 给了 --dec 就说清楚, 而不是默默忽略
if [ "$VENC_KEY" = copy ] && [ -n "${DEC:-}" ]; then
    echo "注意: --venc copy 是转封装, 不解码也不重编码, --dec 对它无效(已忽略)。"
    DEC=""
fi

enc_run "$VENC_KEY" "$@"