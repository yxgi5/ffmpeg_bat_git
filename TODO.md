# TODO / 演进路线：从「一编码器一脚本」到「统一入口 + 参数」

> 状态：**方向已定，分阶段实施**（2026-10-04 讨论结论）。
> 本文是决策记录 + 待办清单，不是操作手册；具体做法见 `readme.md`。
> 关联：干跑开关 `--dry-run` 已落地（2026-10-04），是这条路线上第一个"开关参数化"的样板。

## 1. 背景：为什么现在动这个

开关正在从"环境变量"迁移到"命令行参数"（`parse_switches` 已在两族实现，白名单见 `readme.md`）。
既然解码器 / 编码器 / 编码格式都能当参数传，**"每个编码器一份脚本"就没有存在理由了** ——
它带来的是 9 份近乎相同的 200 行副本，以及副本之间必然发生的漂移。

实测（`diff` 只统计两文件间不同的行）：

| 对比 | 不同行数 | 各自体量 |
|---|---|---|
| `ffmpeg_libx264.sh` vs `ffmpeg_libx265.sh` | **18** | 193 / 193 |
| `ffmpeg_hevc_qsv.sh` vs `ffmpeg_avc_qsv.sh` | 33 | 200 / 209 |
| `ffmpeg_hevc_vaapi.sh` vs `ffmpeg_h264_vaapi.sh` | 32 | 227 / 207 |
| `ffmpeg_hevc_nvenc.sh` vs `ffmpeg_av1_nvenc.sh` | 33 | 197 / 233 |
| `ffmpeg_libx265.sh` vs `ffmpeg_copy_to_mp4.sh` | 171 | 193 / 110 |

即：**9 个编码入口 ≈ 一份 ~170 行公共内核 + 每份 20–40 行差异**。
（`copy_to_mp4` 是 remux，无码率表；`dvd_hevc` 751 行、多 title/ISO —— 两者是真·另一类，不属此列。）

## 2. 目标形态（已同意）

```
ffmpeg_encode.sh / .bat   --venc <编码器>  --dec <解码器>  [既有开关...]
ffmpeg_copy_to_mp4        remux，结构不同，保留
ffmpeg_dvd_hevc           DVD/BD 多 title，独立世界，不动
convert_from_list         3 份 → 1 份，参数化"对每行调哪个入口"
repack_from_list
tools/*                   不动结构，只做开关参数化（环境变量照旧）
```

关键简化：**"编码格式"不需要单独做参数** —— 编码器名已隐含格式
（`hevc_qsv`→hevc 表、`h264_qsv`/`avc_qsv`→avc 表、`av1_qsv`→av1 表）。
这张映射 lint 里已经有了（`P02` 的 `family_table(codec)`），运行时照抄一份即可。
所以真正新增的参数只有两个：**`--venc`（编码器）** 与 **`--dec`（解码器）**。

## 3. 淘汰清单（2026-10-04 调整版）

| 现在的入口 | 将来怎么表达 |
|---|---|
| `ffmpeg_h264_vaapi.sh` / `ffmpeg_hevc_vaapi.sh`（Windows 无孪生，lint 里已是 `sh_only` 白名单） | **淘汰** —— VAAPI 能用 QSV 替代；不单独留参数位 |
| `ffmpeg_hevc_qsv` / `avc_qsv` / `av1_qsv` | `--venc <hevc_qsv/avc_qsv/av1_qsv> --dec <auto/qsv/cuda/cpu>` |
| `ffmpeg_hevc_nvenc` / `av1_nvenc` | `--venc <hevc_nvenc/avc_nvenc/av1_nvenc> --dec <auto/qsv/cuda/cpu>` |
| `ffmpeg_libx264` / `libx265` | `--venc <libx264/libx265> --dec <auto/qsv/cuda/cpu>` |
| `convert_from_list_{cuda,libx265,qsv}` 三份 | 一份 + `--venc` 参数 |

根入口 **20 个 → 5 个**；两族合计的逻辑副本 **40 份 → 10 份**。
以后新增硬件 / 编码器只加一行映射，不再复制 200 行脚本 ×2 族。

## 4. 阶段路线（每步可独立合入、可回滚）

| 阶段 | 内容 | 状态 |
|---|---|---|
| **0** | 抽公共内核 `lib/encode_core.{sh,bat}`：9 个编码入口各剩"编码器 / 码率表 / 解码初始化 / 能力门" | 待做 |
| **1** | 落地 `ffmpeg_encode`（`--venc` / `--dec`）；9 个老名字变薄壳（3 行），CLI 完全兼容 | 待做 |
| **2** | `tools/` 开关参数化（**保留环境变量**），`parse_switches` 支持"按脚本声明键表" | ✅ 已落地（2026-10-04） |
| **3** | 宣布 VAAPI 入口 deprecated → 下个版本删文件 + 改 lint 白名单 + 改文档 / 冒烟 | 待做 |

阶段 0 是阶段 1 的前置：内核不先抽出来，统一入口只会变成"一个大脚本里塞 9 个 if"。

### 阶段 0 的抽取方案（已量化）

公共部分（~170 行）：头部样板、`init_ext`、`find_ffmpeg_for_encoder`、参数个数 / 交互、
源文件校验、源探测 6 项 + 帧率归一 + 分辨率拆分、码率 / 时长双兜底、
码率查表 + `bitrate_from_table` + percentage + 低码率沿用 + `exit 5`、
交互覆盖码率、输出路径、命令拼装的公共段、`RUN_COM` 回显 + `ff_run` + 失败 `exit 1`。

差异压成"两张表 + 三个钩子"：

| 机制 | 内容 |
|---|---|
| 表1 `enc_table(enc)` | 编码器 → 码率表 csv（抄 lint 的 `family_table`） |
| 表2 `enc_vargs(enc)` | 编码器 → `-c:v:0 X -profile:v:0 Y -preset Z [-pix_fmt P] [-sws_flags …]` |
| 钩子1 `enc_dec_args(enc)` | 解码 / 设备初始化：软编 `auto`；QSV `-init_hw_device` + High10 源降级 `hwupload`；NVENC cuda；VAAPI（阶段 3 后移除） |
| 钩子2 `enc_gate(enc)` | 能力探测与 `exit 4`（仅 QSV / AV1 类需要，其余为空） |
| 钩子3 `enc_prefer_newbuild(enc)` | 是否前置 `/opt/ffmpeg/...` 到 PATH（`av1_qsv`、`hevc_vaapi` 为是） |

## 5. 风险

1. **能力门控 + 退出码 4 是唯一有技术含量的部分**。现在每个硬件入口各自探测
   （`qsv_encoder_ready` / `src_is_10bit` / `src_hw_decode_hostile` / AV1 硬件缺失 rc=4）。
   统一后要变成"编码器 → 需要哪些探测"的表。做不好就会重演
   "AV1 QSV 明明没硬件却报 OK、只留一个 0 字节文件"的老毛病。
2. **拖放用法不能破**。Windows 用户是拖文件到 `.bat` 上的 → 老名字保留为**薄壳**
   （设默认 `VENC` 后 `call` 统一入口），标 deprecated 一两个版本后再删。
3. **bat 侧的 cmd 引号陷阱**。bat 没有数组，公共段只能 `call :label` 化；跨文件 `call`
   传路径比同文件更凶险，必须沿用仓库现有那条"非包装 `set`"约定
   （见 `ffmpeg_libx264.bat` 顶部那段"第六轮实测"注释）。
4. **冒烟套件是一次性大成本**。T1–T31 大量按入口名断言（`ffmpeg_hevc_qsv` 等），
   `test/README.md` 有完整表格，`.bat` 侧孪生也要同步。阶段 1 的贵点在测试不在代码。
5. **`SWITCH_KEYS` 不能被污染**。它被 `convert_from_list_*` 用来做 FWD 转发；
   `tools/` 有 10 个脚本、约 100 个开关变量（`dvd_repair` 一个就 20+ 个），
   且会撞名（tools 的 `VENC` / `MODE` / `AUDIO` / `FORMAT` 与入口同名不同义）
   → 阶段 2 必须走"按脚本声明键表"（`PS_KEYS`），不进公共表。
6. **两族必须同步抽**，否则会制造新的结构漂移。

## 6. 待定（需要拍板）

| # | 问题 | 当前倾向 |
|---|---|---|
| 1 | 统一入口**叫什么**：`ffmpeg_encode`？`ffmpeg_conv`？ | `ffmpeg_encode` |
| 2 | 老名字薄壳**保留多久** | 保留到下次改硬件支持时再删；VAAPI 两个可在阶段 1 就删 |
| 3 | `--dec` 的取值集合是否含 `cpu` 语义 | 用 `none`（= `--dec none`，一次 `-hwaccel` 都不加），与现有 `FF_HWACCEL=none` 对齐；摘要里的 `cpu` 归到 `none` |
| 4 | `copy_to_mp4` 是否也并入统一入口（`--venc copy`） | 暂保留独立入口：它的"后缀已是 mp4 就跳过"和输出命名都不同 |
| 5 | 阶段 1 后冒烟 T1–T31 怎么改 | 按新入口名重写断言，老 T-id 保留含义 |
| 6 | VAAPI 淘汰后，Linux 上 VAAPI 用户怎么走 | `--venc <名> --dec vaapi` 仍留 `--dec` 取值，只是不再有独立入口文件；若驱动只能用 VAAPI，用 `--venc hevc_vaapi --dec vaapi` |

## 7. 已落地的同类改动（可当样板）

- 干跑开关 `--dry-run` / `DRY_RUN`（2026-10-04，提交 `0154da1`）：
  - sh 侧闸门放在 `ff_run`（所有入口共用出口）→ 11 个入口**零改动**；
  - bat 侧 `:dry_run` + 每个执行点两行；
  - 布尔开关不吃文件名（`SWITCH_FLAGS`），清单驱动 FWD 转发改裸 `--key`；
  - 两族冒烟各加 T31。
- 这个改动证明了"参数化开关 + 公共出口"这条路是可行的，阶段 0/1 是它的自然延伸。
