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
ffmpeg_encode.sh / .bat   --venc <编码器|copy>  --dec <解码器>  [既有开关...]
ffmpeg_dvd_hevc           DVD/BD 多 title，独立世界，不动
convert_from_list         3 份 → 1 份，参数化"对每行调哪个入口"
repack_from_list
tools/*                   不动结构，只做开关参数化（环境变量照旧）
```

关键简化：**"编码格式"不需要单独做参数** —— 编码器名已隐含格式
（`hevc_qsv`→hevc 表、`h264_qsv`/`avc_qsv`→avc 表、`av1_qsv`→av1 表）。
这张映射 lint 里已经有了（`P02` 的 `family_table(codec)`），运行时照抄一份即可。
所以真正新增的参数只有两个：**`--venc`（编码器）** 与 **`--dec`（解码器）**。

`copy_to_mp4` 按 2026-10-08 拍板**并入**为 `--venc copy`（见 §6 第 4 项：moov 前置一起带过来）。

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
| **0** | 抽公共内核 `lib/encode_core.{sh,bat}`：9 个 sh + 7 个 bat 编码入口各剩"编码器键 + usage 文案" | ✅ 已落地（2026-10-08，分支 `feature/encode-core`） |
| **1** | 落地 `ffmpeg_encode`（`--venc` / `--dec`）；9 个老名字变薄壳（3 行），CLI 完全兼容 | 待做（6 项决策已拍板，见 §6） |
| **2** | `tools/` 开关参数化（**保留环境变量**），`parse_switches` 支持"按脚本声明键表" | ✅ 已落地（2026-10-04） |
| **3** | 宣布 VAAPI 入口 deprecated → 下个版本删文件 + 改 lint 白名单 + 改文档 / 冒烟 | 待做 |

### 阶段 0 的实际落法（与 §4 原方案的差异）

原方案说"9 个编码入口各剩编码器/码率表/解码初始化/能力门"。实际做成**两张表 +
两个钩子 + 一个键**：

| | 内容 |
| --- | --- |
| sh `enc_ffenc` / `enc_table` | 编码器键 → ffmpeg 能力筛选名 / 码率表 csv。入口名按格式命名（`avc_qsv`）而 ffmpeg 里叫 `h264_qsv`，这层翻译只在 `enc_ffenc` 一处 |
| sh `enc_vargs` | 编码器 → `-c:v:0` 系列 |
| sh 钩子 `enc_dec_args` | 解码/设备初始化（软编 / QSV / VAAPI / NVENC 四种拓扑，含 `-i` 与 `-vf` 的相对位置） |
| sh 钩子 `enc_gate` | 硬件能力门（`av1_qsv` → `exit 4`） |
| sh 钩子 `enc_prefer_newbuild` | 是否把 `/opt` 下新构建前置到 PATH |
| bat `ENC_TABLE` / `ENC_ARGS` | 同上两表 |
| bat 钩子 `DEC_BLOCK` / `GATE_BLOCK` | 同上两钩子 |

**bat 侧的关键约束**（sh 侧没有）：`cmd` 没有函数作用域、`goto` 不能跨文件，所以内核
只能做"**`RUN_COM` 拼装器**"——banner → ffmpeg 定位 → 源探测 → 码率 → 拼出
`RUN_COM`（含输出路径）后交回。这三样必须留在入口文件里：

1. cp65001 重入守卫 + `:HWACCEL_FALLBACK` —— 守卫区必须纯 ASCII（L04），且那个标签
   要被入口的执行段 `call`，`goto` 跨不了文件；
2. 执行段（`auto` 才拦 stderr 做 D3D 回退）与失败守卫 —— 与运行期语义绑在一起；
3. 自己的 usage 文案与头部说明。

因此 bat 入口是 146~153 行（不是 sh 的 25~31 行），换来执行路径**零改动**。

**验证**（Windows 真机 + Linux）：

- sh：9 入口 `--dry-run` 全量输出 + 3 个 `--help` 逐字比对 **diff 0 行**；
  冒烟 27/0/3 + 28/0/0 + 22/0/0 rc=0。
- bat：8 入口 `--dry-run` 逐字比对**只剩 2 行**——`avc_qsv` 的 `echo SRC_PIXFMT=` 移位，
  因为它原先把 QSV 块拆成两处（hwdec 判据在 `-i` 前、10bit 判据在码率表后），
  而 `hevc_qsv`/`av1_qsv` 是整块在 `-i` 前；统一成后者，功能等价。
  `smoke_all.bat` 的 PASS/SKIP/FAIL 集合**逐项完全一致**（37/6/5，5 个既存失败未变）。
- lint `31 PASS / 0 FAIL`；L11/L16 各配4~5 个变异测试，确认逐入口覆盖未丢
  （详见 `test/README.md` 的「阶段 0 抽内核后 lint 的两处适配」）。

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

## 6. 拍板结果（2026-10-08）

| # | 问题 | 结论 |
|---|---|---|
| 1 | 统一入口**叫什么** | **`ffmpeg_encode`**（`ffmpeg_encode.sh` / `.bat`） |
| 2 | 老名字薄壳**保留多久** | **待定** —— 阶段 1 落地时再定；本次只保证老名字 CLI 完全兼容 |
| 3 | `--dec` 的取值集合 | **含 `cpu` 语义，语义就是 `none`**（一次 `-hwaccel` 都不加），与现有 `FF_HWACCEL=none` 对齐 |
| 4 | `copy_to_mp4` 是否并入 | **并入**（`--venc copy`）。⚠️ **`-movflags +faststart`（moov 前置）必须一起带过来** —— 它是转封装能"拷走/边下边播"的关键，且 9 个编码入口目前都**没有**它，合并时别漏 |
| 5 | 阶段 1 后冒烟 T1–T31 怎么改 | **按新入口名重写断言**，老 T-id 保留含义 |
| 6 | VAAPI 淘汰后，Linux 上的 VAAPI 用户怎么走 | **用 QSV 等替代**（`--venc <hevc_qsv/avc_qsv> --dec qsv`）；不保留 `--dec vaapi` 取值 |

## 7. 阶段 1 的实际落法（2026-10-08 ~ 09，已落地）

### 落了什么

| 项 | 内容 |
|---|---|
| 统一入口 | `ffmpeg_encode.sh` / `ffmpeg_encode.bat`：`--venc <编码器>` + 可选 `--dec <解码器>` + 视频文件 |
| `--venc` | `libx264` `libx265` `libsvtav1`（软件 AV1，本轮新增） / `avc_qsv` `hevc_qsv` `av1_qsv` / `avc_nvenc` `hevc_nvenc` `av1_nvenc` / `avc_vaapi` `hevc_vaapi`（仅 sh） / `copy`（转封装） |
| `--dec` | `auto` `cpu`（= `none`） `none` `qsv` `cuda`（`vaapi` 仅 sh）。**省略时用编码器族的固定拓扑**；与族不一致**只警告不拦**（混合硬解有人用），但会如实说明「10bit 降位滤镜属原族解码路径、不跟过来」 |
| `copy` | 与 9 个编码器一起并入。无码率表、产物**不带 `-compressed`**（与源同名换后缀）、源已是目标容器直接退 0、`-c copy` + `-movflags +faststart` |
| 别名翻译 | `--venc` 的 `avc_* → h264_*` 收敛成**一份**（`enc_ffenc` / `:enc_ffenc`）。此前手工维护三处（`ffmpeg_dvd_hevc.{sh,bat}` 与内核），`ffmpeg_dvd_hevc` 两族均改为调用它 |

老入口**全部保留为薄壳**，CLI 完全兼容。§6 第 2 条「保留多久」仍**待定**（本轮没删）。

### 验证

* **逐字对拍**（阶段 0 基线 vs 阶段 1）：sh 侧 9 个老入口 `--dry-run`/`--help` 逐字 diff **0**；
  `ffmpeg_encode.sh` 对拍老入口 **9/9 IDENTICAL**。bat 侧 7 个老入口 + `copy_to_mp4.bat` **7/7 IDENTICAL**。
* `copy` 的 `RUN_COM` 与 `ffmpeg_copy_to_mp4` 一致（含 `-c:s mov_text` 与 `+faststart`）。
* `--dec` 五个取值逐一实测；混合组合的警告实测。
* `smoke_all.bat`：**44 PASS / 6 SKIP / 5 FAIL**，5 个失败全是阶段 0 既存项（未扩大）。
* lint `31 PASS / 0 FAIL`。

### 测试覆盖（**这是阶段 1 唯一没做完的部分**）

| 族 | 统一入口的断言 | 状态 |
|---|---|---|
| sh | T32–T40（10 条：实跑 / 与老入口 `RUN_COM` 逐字一致 / `--dec` 五取值 / 不一致警告 / 参数校验 / `copy` 三面 / 软件 AV1 / `copy`+`--dec` 说明） | **全部通过**，PASS=37 |
| bat | T32–T33（实跑、与老入口 `RUN_COM` 逐字一致） | **通过**，PASS=39 |
| bat | T32–T37（6 条：实跑 / 与老入口 `RUN_COM` 逐字一致 / `--dec` auto·cpu / 不一致警告 / 参数校验 / `copy` 三要点） | **全部通过**，PASS=44 |  

bat 侧的 T34–T37 最初是**一次性加 7 条**，真机上 T35/T36 恒 FAIL 且让元字符矩阵多出一条
`A19 rc=3`（FAIL 从 5 涨到 8），于是整批撤回。改为**逐条加、每加一条就在真机跑一遍冒烟**
后，6 条全部通过且 `A19` 未复发 —— 差别只在于一次加多少：**批量加时出问题定位不到是哪一行**，
而逐条加时每一步的基线都是已知的。

**T35 还抓出一个真的产品 bug**：bat 侧 `--dec` 不一致时的 10bit 说明挂在
`if "%DEC_ARG%"=="qsv"` 上，只有「请求 qsv 解码」才提示；但真正需要提示的是
「**编码器属于 qsv 族、而解码器不是 qsv**」—— 那时该族的 10bit 判据与 `scale_qsv`
降位滤镜会被悄悄丢掉。判据该看族（`DEC_FAMILY`）而不是请求的解码器（`DEC_ARG`）；
sh 侧 `enc_dec_warn` 用的是 `$fam_d`（族）。这是一处**两族漂移**，已修。

### 本轮在 bat 上踩的坑（**续做前必读**）

同一天栽了四次，其中两次是同一个 cmd 语义：

| # | 坑 | 症状 |
|---|---|---|
| 1 | `set X=Y & goto Z` 里 `&` **前的空格算进变量值** | `avc_qsv`/`hevc_nvenc` 的 `RUN_COM0` 变成 `... hw  -hwaccel qsv` 多一个空格。**软编族恰好没走这支所以看不出来**，靠逐字对拍才发现 |
| 2 | `if <cond> cmd1 & cmd2` 里 **`cmd2` 与 `if` 无关，无条件执行** | 断言恒 FAIL（`set "N=..."` 照样跑，于是 `why` 里永远有内容）。54 处已拆成两行 |
| 3 | `for /f "delims=" %%L in ('... "..." ')` 的**嵌套引号被吞** | 整个文件被当命令执行，套件跑不到断言就死。改用 `findstr` 抽行 + `fc` 字节比对 |
| 4 | `:enc_ffenc` 取 `%~1` 而不是 `%~2` | dispatcher 约定（同 `lib/common.bat`）：`%~1` 是**函数名**，`%~2` 起才是参数。写成 `%~1` 会把 `enc_ffenc` 自己原样 echo 回去 |

另外两条纪律：

* **冒烟断言要抓 ASCII 标记**（`check_isvideo` 就是这么做的），`findstr /c:"警告"` 在 bat 编码下匹配不上。
  核心的 `--dec` 不一致警告已加 `[warn]` ASCII 标签（该改动**保留**在 `lib/encode_core.bat`，即使 T35 未绿）。
* **bat 文件的行尾必须 CRLF**，且 `echo` 描述里**不能出现半角括号**（会提前闭块，L23 已能拦）。

### 顺带发现的既存问题（未修，与阶段 1 无关）

* `smoke_all.bat` 日志里一直有 `'…--filt' 不是内部或外部命令` 这类噪声，来自 `lib/common.bat:716` 的
  `rem` 行被当命令执行 —— **阶段 0 之前就有**。它让「日志里出现解析错误」这个信号失去意义，
  本轮我因此一度分辨不出哪些错误是自己引入的。建议单独查。

> 第 4 项对阶段 0 的约束：`copy_to_mp4` 与 9 个编码入口有**四处**结构差异 ——
> 无码率表、输出名不带 `-compressed`、源已是目标容器即跳过、`-c copy` + faststart。
> 抽内核时要把这些留成钩子位，不能让公共流程假设"一定有码率表"。

## 7. 已落地的同类改动（可当样板）

- 干跑开关 `--dry-run` / `DRY_RUN`（2026-10-04，提交 `0154da1`）：
  - sh 侧闸门放在 `ff_run`（所有入口共用出口）→ 11 个入口**零改动**；
  - bat 侧 `:dry_run` + 每个执行点两行；
  - 布尔开关不吃文件名（`SWITCH_FLAGS`），清单驱动 FWD 转发改裸 `--key`；
  - 两族冒烟各加 T31。
- 这个改动证明了"参数化开关 + 公共出口"这条路是可行的，阶段 0/1 是它的自然延伸。
