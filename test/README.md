# test/ — 测试体系说明

本目录是 `ffmpeg_bat_git` 的**三层测试体系**。三层各管一件事，互不替代：

| 层 | 文件 | 回答的问题 | 耗时 | 需要硬件 |
|----|------|-----------|------|---------|
| ① 静态 + 对等检查 | `lint/lint.py` | 代码本身有没有结构性问题？两族是否对等？ | < 1 秒 | 否 |
| ② 冒烟套件 | `sh/smoke_ffmpeg.sh`、`sh/smoke_special_chars.sh`、`bat/smoke_ffmpeg.bat`、`bat/smoke_special_chars.bat` | 每一次真实编码跑通了吗？断言对不对？ | 数分钟 | 部分是（无则 SKIP） |
| ③ 环境能力报告 | `sh/check_env.sh`、`bat/check_env.bat` | **这台机器**能用哪些入口？为什么不能用？ | 秒级 / 深测数十秒 | 否（深测会真跑） |

三层的退出码语义一致：**`0` = 干净，非 0 = 有问题**（能力报告例外，见 §4）。

**两族文件名一一对应**（去掉族后缀，目录名即族名）——同名文件就是同一件事在两个家族里的孪生实现：

| 用途 | `.sh` 族 | `.bat` 族 |
|------|----------|-----------|
| T 编号回归套件 | `test/sh/smoke_ffmpeg.sh` | `test/bat/smoke_ffmpeg.bat` |
| 元字符文件名矩阵 | `test/sh/smoke_special_chars.sh` | `test/bat/smoke_special_chars.bat` |
| 一键串跑 | `test/sh/smoke_all.sh` | `test/bat/smoke_all.bat` |
| 环境能力报告 | `test/sh/check_env.sh` | `test/bat/check_env.bat` |

---

## 0. 快速上手

```bash
# ① 静态 + 对等检查（任何机器，1 秒）
python3 test/lint/lint.py              # 全部
python3 test/lint/lint.py --lint-only  # 只做静态检查
python3 test/lint/lint.py --parity-only# 只做对等检查
python3 test/lint/selftest.py          # 检查检查器自己（13 个用例）

# ② 冒烟套件（或一条命令跑全套：bash test/sh/smoke_all.sh）
bash test/sh/smoke_ffmpeg.sh           # sh 族回归全量（T1-T25）
bash test/sh/smoke_ffmpeg.sh guard     # 只跑参数校验/退出码段
bash test/sh/smoke_ffmpeg.sh list      # 只跑清单模式段
bash test/sh/smoke_special_chars.sh    # sh 族元字符矩阵（part A/C/B/D/Z）

# ③ 环境能力报告
bash test/sh/check_env.sh              # 快查：秒级，静态盘点
bash test/sh/check_env.sh --probe      # 深测：每个入口真跑一遍
```

Windows 侧双击运行（`.bat` 与 `.sh` 一一对应）：

```
test\bat\smoke_all.bat                 双击    一键串跑两套
test\bat\smoke_ffmpeg.bat              双击    回归套件（T 编号）
test\bat\smoke_special_chars.bat       双击    元字符矩阵
test\bat\check_env.bat                 双击    能力报告（快查）
test\bat\check_env.bat /probe          命令行  能力报告（深测；旧写法 "" PROBE 仍兼容）
```

另有一个**基准工具**（不属于回归体系）：`test\bat\bench_av1_calib.bat`——
把任意视频拖上去，用 hevc_nvenc / av1_nvenc（p4 CBR，与入口脚本同参数）编三档码率梯
并算 VMAF，产出 `results.csv`，用于实测「等画质下 AV1 相对 HEVC 省多少码率」，
校验码率表的代际比例假设。要求 ffmpeg 带 libvmaf + Ada 级 NVENC。
（该工具的使命已完成，结论见 `environment_matrix.md` 第 25/26 条，保留作复测用。）

## ③b 单片源码率标尺 bench_calib（sh/bat 对等）

**用途**：特殊片源需要尽可能保画质时，从原视频实测出「该给多少码率」——
不信任理论表，直接量这一部。

```
bash test/sh/bench_calib.sh [avc|hevc|av1] <source> [max_h] [seconds]   # sh 侧
test\bat\bench_calib.bat <source>          # 双击，默认 hevc
test\bat\bench_calib.bat av1 <source> 1080 # 带编码器与高度上限
```

做法：取片源中段一段（默认 30s），按查表值 T 的 **T/4 → T 五点码率梯**，用该编码器的
**软件编码器**（libx264 fast / libx265 fast / libsvtav1 p8——与码率表同基准，见
`environment_matrix.md` 第 27 条）编码，libvmaf 直接对照源片本身（参照腿与编码腿做同样的
fps30/像素格式归一），产出 `results.csv`。sh 侧附 log 域拟合，解出 VMAF 90/93/95/97 各需
多少码率并给出建议值；bat 侧给出 VMAF≥95 的最小梯点。产物缓存于
`%TEMP%/ffmpeg_bench_calib_<codec>/`，重跑只补缺失点。

实测状态：sh 侧已在 **B 机（MSYS2）/ A 机 / C 机** 三机用合成源跑通三 codec 全梯
（A/C 结果两机一致，见 `environment_matrix.md` 第 30 条）；bat 侧 B 机合成源通过，
真实片源双击验证待用户执行。

> 建议顺序：**先 ① 后 ②**。静态检查能在 1 秒内抓住语法/标签/引号/编码问题，
> 不必等几分钟的冒烟跑完才发现第 3 行少了个括号。

---

## 1. 目录结构

```
test/
├── README.md                    本文件
├── lint/
│   ├── lint.py                  静态 + 跨族对等检查器（零依赖，仅标准库）
│   └── selftest.py              lint.py 自身的回归测试（recall + precision）
├── sh/
│   ├── smoke_ffmpeg.sh          sh 族回归套件（与 bat 套件同 T 编号）
│   ├── smoke_special_chars.sh   sh 族元字符矩阵（与 bat 套件同 part 字母）
│   ├── smoke_all.sh             sh 族一键串跑
│   ├── check_env.sh             sh 族环境能力报告
│   ├── bench_calib.sh           单片源码率标尺（软编基准，见 ③b）
│   ├── nvenc_pair_calib.sh      NVENC AV1/HEVC 配对校准（bat 孪生）
│   └── soft_pair_calib.sh       软编 SVT-AV1/x265 配对校准（无 bat 对偶，见 ③c）
├── bat/
│   ├── smoke_ffmpeg.bat         bat 族回归套件
│   ├── smoke_special_chars.bat  bat 族元字符矩阵
│   ├── smoke_all.bat            bat 族一键串跑
│   ├── check_env.bat            bat 族环境能力报告
│   ├── bench_calib.bat          单片源码率标尺（sh 孪生）
│   └── nvenc_pair_calib.bat     NVENC AV1/HEVC 配对校准（sh 孪生）
└── py/
    ├── eq_quality_solve.py      软编配对等画质求解器（校准 CSV）
    ├── nvenc_pair_solve.py      NVENC 配对求解器（校准工作目录）
    └── table_ratio_audit.py     三表比例/单调性/幂律审计
```

约定（`.gitattributes` 已钉死）：

* `*.sh` / `*.md` = **LF**；`*.bat` = **CRLF**。
* 所有测试输出**只用 ASCII**。本仓库有长期 cp936/cp65001 踩坑史，日志一旦混入中文，
  控制台码页一变就变乱码，跨机器贴日志会失真。
* `.bat` 的 cp65001 守卫区（`:main` 之前）必须纯 ASCII。
* **同名文件互为孪生**：`smoke_ffmpeg.sh` ↔ `smoke_ffmpeg.bat` 等四处。改名时必须两族同步改
  （2026-09-16 起从 `smoke_sh.sh` / `smoke_ffmpeg_bat.bat` 改为现在的形态，就是为了让
  文件名层面也对等 —— 之前 T 编号对等了，文件名没对等，"哪个文件对应哪个文件"仍要靠脑子记）。

---

## 2. 第一层：静态 + 对等检查（`lint/lint.py`）

零依赖、纯标准库、ASCII 输出，可在任意有 python3 的机器上跑（含 Linux/Cygwin/MSYS）。
所有检查都直接读源文件，不执行 ffmpeg，因此**快且确定**。

### 2.1 静态检查

| ID | 检查内容 | 为什么需要 |
|----|---------|-----------|
| L01 | 行尾约定：`.sh`/`.md`=LF，`.bat`=CRLF | LF 的 `.bat` 在 cmd 下会出现诡异的多行解析错误 |
| L02 | 任何源文件不得有 UTF-8 BOM | BOM 会让 `.bat` 首行 `@echo off` 失效并打印 `'∩╗┐echo' is not recognized` |
| L03 | 每个 `.sh` 以 `#!/bin/bash` 开头 | 历史缺 shebang 导致 `sh` 下用 POSIX shell 跑出错 |
| L04 | cp65001 守卫区（`:main` 之前）纯 ASCII | 守卫区的字节在未知码页下被读取，中文会破坏 `chcp` 流程 |
| L05 | `.bat` 括号配平（排除 `rem`/`echo` 行） | `if (...)` 块漏括号会让后续整段代码被吞进块里 |
| L06 | `.bat` 引号配对（先剔除 `%VAR:"=%` 形式） | 引号不配对会让 `set` 的值跨行吞掉下一条命令 |
| L07 | `call :label` / `goto label` 目标存在 | 标签拼错时 cmd 静默继续执行，症状极难定位 |
| L07b | 所有 `call lib\common.bat <fn>` 的函数名在分派表里 | 公共库改名后调用点会变成静默无操作 |
| L08 | 包装写法 `set "VAR=...%带引号变量%..."` | **2026-09 实际事故**：包装引号与值里第一个引号配对闭合，后半段变量裸奔 |
| L09 | 差分式元字符扫描（见下） | 上述事故的通用形态：值里的 `&` 逃出引号被当成命令分隔符 |
| L10 | `lib/common.sh` 的 `run_list` 仍做 `</dev/null` 重定向 | 5 条目清单只跑第一条的历史回归 |
| L11 | 每个编码入口的 `-i` 出现在 `-c:v` 之前 | 选项顺序错误会让 `-c:v` 被当成输入选项 |
| L12 | `bash -n` 语法检查（找不到 bash 则 SKIP） | 最廉价的一道防线 |
| L13 | `exit` / `exit /b` 取值在白名单内（bat `0,1,2,3,5`；sh 另允许 `8,9`） | 让 §5.2 的退出码契约不漂移 |

**L09 的做法值得单独说明**：它把「脚本语法」和「数据逃逸」区分开，而不是见 `&` 就报。

1. 只检查**确实替换了带引号变量**的行；
2. 对同一行算两份文本：*neutral*（把变量替换成空串，保留行本身的 `&`、`(`、`>` 等）
   与 *worst case*（把变量替换成含 `& | ( ) ^ !` 的样例值）；
3. 只有**在 worst case 里活跃、而在 neutral 里不活跃**的 `&` / `|` 才算缺陷。

`>`、`<`、`(`、`)` 故意**不参与**判定：它们在批处理里本来就有大量合法用途
（`cmd > file`、`if x gtr 1 (`、`for ... in (...)`），行级扫描无法区分它们与数据逃逸，
报了只会淹没真问题。围栏由 L06/L08 与冒烟套件的特殊字符用例负责。

带引号变量是**按文件、按行序**推定的，这两点都是踩过坑才加上的：

* **按文件**：同名变量在两族里形态不同——`convert_from_list_*.bat` 是
  `SET "SRC_FILE=%~1"`（裸值），`ffmpeg_*.bat` 是 `set SRC_FILE="%SRC_FILE:"=%"`（带引号）。
  做成全仓库共用，就会把 ffmpeg 族的性质套到 list 族上，凭空造出 8 条假报告。
* **按行序**：`SRC_BITRATE` 先被赋成一条探测命令（含引号），随后被
  `set /p SRC_BITRATE=<"%FB_TMP%"` 和 `set /a` 覆盖成数字。只看最后赋值才符合实际；
  `set /p` / `set /a` 的结果一律视为裸值（引号属于重定向，不属于值）。

### 2.2 跨族对等检查

| ID | 检查内容 |
|----|---------|
| P01 | 入口清单盘点：共享 12 个 + sh 独有 3 个（白名单）+ bat 独有 0 个 |
| P02 | 编码器 ↔ 码率表映射在编码器族内一致（忽略 `rem` 注释，优先读 `lookup_bitrate` 调用点） |
| P03 | 退出码契约跨族数值一致：码率异常=5、查表越界=2、无视频流=3 |
| P04 | 码率表结构健全：`max_pixels` 不回退、同像素不映射到两个码率、720p/1080p 有覆盖 |
| P05 | sh 侧 `lookup_bitrate` 与 Python 参考实现逐样本对照（含越界用例） |
| P06 | 两族套件里硬编码的 1080p 期望值 = `table(2073600)/2`，防止表与测试各走各的 |
| P07 | 编码器参数跨族比对（差异必须落在白名单内） |

### 2.3 检查器自测（`lint/selftest.py`）

**一个只会输出「全部干净」的检查器是没有价值的——它可能只是瞎了。**
`selftest.py` 用 13 个合成小仓库同时验证两个方向：

* **recall**：已知有问题的写法**必须**被报出来（L01/L04/L06/L07/L08/L09/L13 各一例）；
* **precision**：已知正确的写法**必须不报**，其中 6 例正是开发过程中真实出现过的假阳性
  （`%VAR:"=%` 引号计数、`endlocal & set` 字面量、`%%~zA` 循环修饰符、
  `set /p` 覆盖、安全的 `set VAR=%QVAR%` 惯用法）。

### 2.4 退出码

| 码 | 含义 |
|----|------|
| `0` | 干净（WARN 不算失败） |
| `1` | 有 findings |
| `2` | 扫描器自校准失败——**其余所有结果都不可信**，请先修检查器 |

自校准（`calibrate_scanner`）用三条自包含探针：安全的 `set X=%QVAR%` 必须干净、
包装写法 `set "X=%QVAR%"` 必须被捕获、字面量 `endlocal & set X=%QVAR%` 必须干净。
探针不读仓库内容，避免「被仓库现状带绿」。

---

## 3. 第二层：冒烟套件

两族套件是**对等的**：同一 T 编号 = 同一用例、同一 1080p60 夹具、同一期望
`TARGET_BITRATE`。所以**两族 T 编号的差异就是真实的跨族分歧**。

### 3.1 运行方式

```bash
bash test/sh/smoke_ffmpeg.sh [all|parity|list|guard]
```
环境开关：`REPO=`、`WORK=`（临时目录）、`WIPE=0`（保留现场）、`FIXTURE=`（自带素材）、
`EXPECT_AV1_QSV=auto|ok|fail|skip`。

> ⚠️ **不要把日志重定向到 `WORK` 目录里面**：套件启动时会 `rm -rf "$WORK"` 清场，
> 重定向目标正好在里面的话，输出会写进一个已被删除的 inode，跑完什么也没有。
> 日志写到 `WORK` 外面，或 `WIPE=0`。

`.bat` 套件：双击运行；或 `smoke_ffmpeg.bat [repo_path] [LIST]`。
日志与汇总在 `test/bat/smoke_logs/`。

### 3.2 T 编号对照表

| T | 用例 | 输入/模式 | 期望 | sh | bat |
|---|------|----------|------|----|-----|
| T1 | `ffmpeg_avc_qsv` | arg | 3836249 / h264 | ✅ | ✅ |
| T2 | `ffmpeg_hevc_nvenc` | arg | 2548951 / hevc | ✅ | ✅ |
| T3 | `ffmpeg_hevc_qsv` | arg | 2548951 / hevc | ✅ | ✅ |
| T4 | `ffmpeg_libx265` | arg | 2548951 / hevc | ✅ | ✅ |
| T5 | `ffmpeg_copy_to_mp4` | arg, mov→mp4 | 不复码率 / h264 | ✅ | ✅ |
| T6 | `ffmpeg_avc_qsv` | stdin 交互（路径 + 空行） | 3836249 / h264 | ✅ | ✅ |
| T7 | 全新进程 / 控制台码页 | — | — | SKIP（无对应物） | ✅ usage C |
| T8 | `ffmpeg_h264_vaapi` | arg | 3836249 / h264 | ✅ | 无此入口 |
| T9 | `convert_from_list_qsv` | 2 条目清单，cwd=仓库 | 2/2 产物 | ✅ | ✅ |
| T10 | `ffmpeg_avc_qsv` | 无音轨输入 | 3836249 / h264 | ✅ | ✅ |
| T11 | 清单模式 + UTF-8 文件名 | 清单 2 条目 | 2/2 产物 | ✅ | ✅ |
| T12 | 清单模式，无参数，cwd 在别处 | 清单 2 条目 | 2/2 产物 | ✅ | ✅ |
| T13 | 非视频输入必须被拦下 | 纯音频 | `rc=3` | ✅ | ✅ |
| T14 | `ffmpeg_av1_nvenc` | arg | 1707157 / av1 | ✅ | ✅ |
| T15 | `ffmpeg_av1_qsv` | arg | 1707157 / av1 | ✅ | ✅ |
| T16 | `ffmpeg_libx264` | arg | 3836249 / h264 | ✅ | ✅ |
| T17 | 低码率源 clamp（400k 源） | arg | `< 3836249` / h264 | ✅ | ✅ |
| T18 | `ffmpeg_libx264` stdin 指定码率 900k | stdin | `900k` / h264 | ✅ | — |
| T19 | `ffmpeg_hevc_vaapi` | arg | 2548951 / hevc | ✅ | 无此入口 |
| T20 | `ffmpeg_hevc_nvenc_cygwin` | arg | 2548951 / hevc | ✅ | 无此入口 |
| T21 | 清单 CRLF + UTF-8 BOM | 清单 3 条目 | 3/3 产物 | ✅ | — |
| T22 | `run_list` 的 `</dev/null` 隔离 | 5 条目清单 | 5/5 产物 | ✅ | — |
| T23 | 清单条目文件缺失 → 中止 | 清单含不存在的路径 | `rc=1` | ✅ | — |
| T24 | 输入文件不存在 | 不存在的路径 | `rc=1` | ✅ | — |
| T25 | 清单不是文本文件 | 传一个 mp4 当清单 | `rc=1` | ✅ | — |

补充断言（两族都有）：`banner check` —— 任何日志里都不得出现
`is not recognized`（守卫标记泄漏回归）。

T7 是一个**编号对齐用的占位**：bat 侧 T7 是「控制台已经是 UTF-8 的全新进程」，
属于 Windows 控制台特性，sh 侧没有对应物，因此 sh 记录一条 SKIP 而不是删掉这个编号，
以免两族编号错位。

### 3.3 SKIP 策略（两族一致）

依赖硬件的用例**先探测、后断言**：先拿一个小片子真跑一遍入口，跑不通就记 SKIP，
**绝不记 FAIL**，并把探测日志路径写进汇总。这样套件在任意机器上都保持绿色且诚实——
SKIP 明确表示「本机跑不了」，不是「没测过」。

探测夹具用 **320×240**，这一点有实测依据：NVENC 拒绝初始化过小的编码器
（128×128 报 `InitializeEncoder failed: invalid argument`），
用 128×128 当探针会把**一台完全正常的 GPU** 判成 SKIP，静默丢掉真实覆盖。
（2026-09-16 实测：128×128 下 `hevc_nvenc`/`av1_nvenc` 失败，160×120 起正常；QSV 128×128 可用。）

### 3.4 退出码

| 码 | 含义 |
|----|------|
| `0` | 全部通过（SKIP 不算失败） |
| `1` | 存在 FAIL |
| `2` | 环境/安装错误（仓库、ffmpeg、夹具生成） |

### 3.5 元字符矩阵（`smoke_special_chars.*`，两族同构）

片库里有 `A & B (2020).mp4`、`Tora! Tora! Tora!.mov` 这类名字。两族各有一套
**同构**的矩阵，part 字母与用例编号一致（A 段同为那 20 个文件名）：

| part | 内容 | sh 侧 | bat 侧 |
|------|------|-------|--------|
| A | 20 个元字符文件名过 `copy_to_mp4` | ✅ 20/20 实测 | ✅ |
| C | 3 个真实形状走**完整编码** | `ffmpeg_libx264.sh`（无需硬件） | `ffmpeg_avc_qsv.bat` |
| B | 6 个元字符条目走 **list 模式** | `convert_from_list_libx265.sh`（无需硬件） | `convert_from_list_qsv.bat` |
| D | 无参模式，路径从 stdin 喂 | **真 PASS**（重定向确实到达 `read`） | SKIP（cp65001 重启的探针取证限制，见其头注释） |
| Z | 构造微测试 | `${name%.*}` 剥后缀 / `while IFS= read -r` 往返 / **反斜杠文件名**（Linux 合法，Windows 造不出→SKIP） | `set` 形态与 cp65001 守卫复刻（Windows 专属构造） |

三处**刻意分歧**都有依据：sh 侧 C/B 段选软编入口是为了**整套不需要任何硬件**；
**A07 脱字符在 sh 侧是真用例**（bash 不二次解析参数），bat 侧必须 SKIP（`CALL` 会把 `^` 翻倍，
探针造不出同名文件）；bat 侧 Z 段的守卫复刻是 Windows 专属构造，sh 侧没有对应物。

---

## 4. 第三层：环境能力报告（`check_env`）

回答「**这台机器现在能用哪些入口**」。这是**报告**不是测试：一个用不了的入口
不是缺陷，只是这台机器缺硬件。所以它**始终以 0 退出**（只有装不上才返回 2）。

两种模式：

* **快查**（默认）：静态盘点 ffmpeg 构建特性、hwaccels、渲染节点/GPU、三张码率表行数、
  测试工具是否齐全。秒级。
* **深测**（`--probe` / `PROBE`）：再建一个 3 秒小片，把每个候选入口真跑一遍，
  报真实退出码。数十秒。

状态词表（两族**完全一致**，两份报告可以直接逐行对比）：

| 状态 | 含义 |
|------|------|
| `OK` | 可用（静态证据充分，或深测 rc=0） |
| `NO-ENCODER` | 这个 ffmpeg 构建里没有该编码器 |
| `NO-DEVICE` | 编码器有，但本机没有可用设备/GPU |
| `N/A-OS` | 该入口在当前系统无意义（VAAPI 是 Linux 内核 API） |
| `UNKNOWN` | 静态判断不了 → 用深测决定 |
| `PROBE-OK` / `PROBE-FAIL` | 深测真跑的结果（bat 侧还要求真实输出文件；sh 侧看 rc） |
| `NO-ENTRY` | 仓库里没有这个文件 |

两个实现细节值得记住，它们都是**踩过的坑**：

1. **`nvidia-smi` 不能单独当判据**：驱动异常时它会以 255 退出，同时在 **stdout**
   打印 `Failed to initialize NVML: Unknown Error`。天真地把 stdout 当 GPU 名，
   会让所有 `*_nvenc` 入口被报成 OK。必须**同时**要求退出码为 0 且名称看起来像名字。
2. **Windows 上没有 `/dev/dri`**：QSV 走 Intel 驱动而非 DRM 子系统，
   所以 `.bat` 报告改为读 `Win32_VideoController` 列表：有 Intel 控制器 → `UNKNOWN`
   （等深测），没有 → `NO-DEVICE`。
3. **快查的 `NO-DEVICE` 可能是假阴性** —— 它只是「`nvidia-smi` 说不出话」的推论，
   不等于编码器真不可用。本机（B，RTX 4080 Laptop）就是反例：`nvidia-smi` 以 255
   退出报 NVML 错误，快查因此把 `*_nvenc` 标成 `NO-DEVICE`，而 `--probe` 深测
   同一入口是 `PROBE-OK rc=0`（真编出了 HEVC / AV1）。**结论：`NO-DEVICE` 只用来
   提示"值得深测"，别拿它下判决**；要定论就跑 `--probe`。
4. **快查回答的问题和"哪些脚本真能用"不是同一个问题** —— 快查盘点的是 **PATH 上
   那个 ffmpeg 构建**，而入口脚本可能自带 `/opt` 软偏好、实际用另一个构建跑；
   且静态证据到不了"编码这一步"。C 机实测（2026-09-17）：4.4.2 PATH 下快查说
   `av1_qsv` 是 `NO-ENCODER`、`hevc_vaapi` 是 `OK`，而深测两者都 `PROBE-OK`
   —— 因为这两个入口自己偏好 `/opt` 的 master 构建（master 才有 `av1_qsv`，
   且 4.4.x 的 HEVC VAAPI 老路径在 Arrow Lake 上编码失败，master 正常）。
   **所以：要精确知道"本机哪些脚本能用"，唯一判据是 `--probe` 深测
   （`PROBE-OK / PROBE-FAIL` + 真实 rc 和日志）；快查只是秒级预筛。**
5. **入口 `.bat` 无条件 `exit /b 0`，rc 不是判据（bat 侧探针判产物）** ——
   入口脚本是交互式设计，ffmpeg 失败也照样走到 `exit /b 0`（"转换已出错或
   完成，默认不替换"）。初版深测只看入口 rc，结果 `av1_qsv` 在不支持 AV1
   编码的机器上也 `PROBE-OK`。现改为判定**真实输出文件**（存在且 >4096 字节；
   remux 入口因拒绝 mp4 进 mp4 出、且 `-n` 会与同名输入冲突，改喂 `.mkv`
   夹具，与冒烟 T5 同思路）。sh 侧入口如实传 ffmpeg 的退出码，无此问题。

---

## 5. 两族对等矩阵

### 5.1 入口清单

**共享（12）**：`ffmpeg_avc_qsv`、`ffmpeg_hevc_qsv`、`ffmpeg_av1_qsv`、`ffmpeg_hevc_nvenc`、
`ffmpeg_av1_nvenc`、`ffmpeg_libx264`、`ffmpeg_libx265`、`ffmpeg_copy_to_mp4`、
`convert_from_list_qsv`、`convert_from_list_cuda`、`convert_from_list_libx265`、`repack_from_list`

**sh 独有（3，均有正当理由）**

| 入口 | 理由 |
|------|------|
| `ffmpeg_h264_vaapi.sh` / `ffmpeg_hevc_vaapi.sh` | VAAPI 是 Linux 内核 DRM API，Windows 无对应物 |
| `ffmpeg_hevc_nvenc_cygwin.sh` | Cygwin 专用变体（`cuvid` + `hwdownload`），与 MSYS2 行为不同 |

**bat 独有（0 个编码入口）**：`opencmd.bat` 是「开一个 UTF-8 控制台」的辅助脚本，
不是编码入口，因此不计入对等缺口。

> 历史缺口 `ffmpeg_libx264.bat` 已于 2026-09-16 补齐（H.264 软编保底，无硬件要求）。

### 5.2 退出码契约（跨族数值一致）

| 码 | 含义 |
|----|------|
| `0` | 成功 |
| `1` | 参数错误 / 输入文件不存在 / 清单非文本 / 清单条目缺失 |
| `2` | 查表越界（像素数超出码率表范围） |
| `3` | 输入没有视频流 |
| `5` | 码率异常（`percentage <= 0`） |

`lib/common.sh` 的 `check_file_isvideo` 与 10 个 `.sh` 入口的码率异常分支
已在 2026-09-16 从 `1`/`4` 统一为 `3`/`5`，与 `.bat` 侧数值一致。

### 5.3 已知差异（白名单，检查器不报错）

| 项 | sh | bat | 说明 |
|----|----|-----|------|
| 硬件用例缺硬件时 | SKIP（探测） | SKIP（探测） | 已于 2026-09-16 统一 |

`libx265` preset 曾在白名单里（sh=`fast` / bat=`veryfast`），2026-09-16 按用户约定
「参数分歧一般取 `fast`」统一为两侧 `fast`，并从白名单移除 —— 现在它受 P07 硬检查。
白名单应保持为空：只有「修复待办」才允许进，且必须写明原因。
| 低码率 clamp 生效范围 | 全部模式 | 全部模式 | 原 `.bat` 只在交互模式生效，2026-09-16 修复 |

---

## 6. 实测记录

（本节记录各机器上的真实运行结果，用于回归对照。）

### 6.1 本机（Windows 11 / MSYS2 MINGW64 / LAPTOP-MECHREVO / 2026-09-16）

| 命令 | 结果 |
|------|------|
| `python3 test/lint/lint.py` | `21 PASS / 0 FAIL / 6 WARN`，退出码 0 |
| `python3 test/lint/selftest.py` | `13 cases / 0 FAIL` |
| `bash test/sh/smoke_ffmpeg.sh all` | `PASS=22 FAIL=0 SKIP=4`，harness `rc=0` |
| `bash test/sh/check_env.sh` | 快查：`OK 5 / 不可用 6 / 待深测 4` |
| `bash test/sh/check_env.sh --probe` | 深测：**`ok=12 / fail=3`**，rc=0 |

深测的 3 个 FAIL 全部是**本机环境所限、与仓库无关**，且都是"期望失败"：

### 6.2 A 机（Ubuntu 22.04 / i7-9700T + UHD630 Gen9.5 / ffmpeg 4.4.2 ESM / 2026-09-16）

| 命令 | 结果 |
|------|------|
| `python3 test/lint/lint.py` / `selftest.py` | `21 PASS / 0 FAIL / 6 WARN`、`13 cases / 0 FAIL` |
| `bash test/sh/smoke_ffmpeg.sh all` | `PASS=21 FAIL=0 SKIP=5`，harness `rc=0` |
| `bash test/sh/smoke_special_chars.sh` | `PASS=28 FAIL=0 SKIP=0`（Linux 上 Z3 反斜杠文件名是真用例） |
| `bash test/sh/check_env.sh` | 快查：`OK 10 / 不可用 5 / 待深测 0` |

SKIP 的 5 条全为正当硬件/平台 SKIP：T2/T14/T20（无 N 卡）、T15（Gen9.5 无 AV1 QSV）、T7（cp65001 是 Windows 特性）。

### 6.3 C 机（Ubuntu 22.04 / Ultra 7 265K Arrow Lake / ffmpeg 4.4.2 ESM / 2026-09-16）

| 命令 | 结果 |
|------|------|
| `python3 test/lint/lint.py` / `selftest.py` | `21 PASS / 0 FAIL / 6 WARN`、`13 cases / 0 FAIL` |
| `bash test/sh/smoke_ffmpeg.sh all` | `PASS=22 FAIL=0 SKIP=4`，harness `rc=0` |
| `bash test/sh/smoke_special_chars.sh` | `PASS=28 FAIL=0 SKIP=0` |
| `bash test/sh/check_env.sh` | 快查：`OK 10 / 不可用 5 / 待深测 0` |
| `bash test/sh/check_env.sh --probe` | 深测（2026-09-17 复测，4.4.2 与 `/opt` master 两构建**结果一致**）：**`ok=11 / fail=4`** —— 4 个 FAIL 全是 NVENC/CUDA 系（`cu->cuInit failed`，本机无可用 N 卡） |

与 A 机的唯一差异：**T15 av1_qsv 在 Arrow Lake 上真 PASS**（真产出 AV1），与硬件代际一致。
T19 hevc_vaapi 在 C 机 4.4.2 上通过探针与全用例（此前记录的 4.4.x `Encode failed: -5`
与片源/参数相关，320×240 探针与 1080p60 用例均未复现）。

**快查与深测可能不一致，判定"能用/不能用"以深测为准**（2026-09-17 用户实测确认）：
快查盘点的是 **PATH 上那个 ffmpeg 构建**，而入口脚本可能自带 `/opt` 软偏好——
4.4.2 PATH 下快查说 `av1_qsv` 是 `NO-ENCODER`（4.4.2 确实没有），深测却 `PROBE-OK`
（入口自己切到了 master）。静态证据也到不了"编码这一步"，所以深测才是唯一精确判据。

**三机的这轮结果由 `can_run` 修复（a1a4557）之后测得**——修复前 A/C 的 QSV/VAAPI 门控
存在 stdin 泄漏（ffmpeg 吃掉 heredoc 后续行导致 T3/T19 错乱 SKIP）与探针产物残留
（T6/T10 误 SKIP）两类假 SKIP，详见该提交说明。

### 6.4 D 机（树莓派 4B / openmediavault / armv7l 32 位 / ffmpeg 4.1.3 Raspbian / 2026-09-16）

`ssh_run.py --machine d`（`100.70.213.69`，用户 `pi`）。这是四台机器里唯一
**没有 QSV / NVENC 硬件编码器**的：能力报告快查 `OK 7`（libx264、libx265、
h264/hevc vaapi、copy_to_mp4 及两个 wrapper），QSV/NVENC 系全部 `NO-ENCODER`。
ffmpeg 是 Raspbian 源的 4.1.3 —— 比 A/C 的 4.4.2 更老，但全部入口脚本照常工作
（`check_file_isvideo` / `lookup_bitrate` 等纯 shell 逻辑与 ffmpeg 版本解耦）。

| 命令 | 结果 |
|------|------|
| `python3 test/lint/lint.py` / `selftest.py` | `21 PASS / 0 FAIL / 6 WARN`、`13 cases / 0 FAIL` |
| `bash test/sh/check_env.sh` | 首轮被 mawk bug 误报成全 NO（`0 listed`）→ 修复后 **OK=7 / 其余 8 个 NO-ENCODER** |
| `bash test/sh/smoke_ffmpeg.sh all` | 首轮 `PASS=12 FAIL=3 SKIP=11` → 门控修复后 **`PASS=12 FAIL=0 SKIP=14`** |
| `bash test/sh/smoke_special_chars.sh` | `PASS=28 FAIL=0 SKIP=0`（Z3 反斜杠文件名在 Linux 是真用例） |

**check_env 在 D 机首轮全 NO 是检测脚本自己的 bug**（环境矩阵第 22 条）：Pi 默认 awk 是
mawk 1.3.3，不支持区间表达式 `/^[A-Z.]{6}$/`，编码器清单被静默提取成空。快查报 `OK`
只代表静态证据；D 机列出的 `h264_vaapi`/`hevc_vaapi` 编码器在 Pi GPU 上并没有 VAAPI
驱动，能不能真跑以 `--probe` 为准。

首轮的 3 个 FAIL（T9/T11/T12）**不是 D 机的问题，是套件的门控缺口**：list 模式用例
走 `convert_from_list_qsv`，隐式依赖 QSV AVC 硬件，而 A/B/C 三台恰好都有 QSV，
缺口一直不可见。修复（4e42fbc）后三个用例在无 QSV 机器上正确记 SKIP —— 这正是
把 Pi 拉进测试矩阵的价值：**它专门负责暴露"软编也要有、硬件依赖要显式"这类问题**。

| 入口 | 失败原因 |
|------|----------|
| `ffmpeg_av1_qsv.sh` | 本机是 Raptor Lake 核显，**无 AV1 硬编**（`Current codec type is unsupported`） |
| `ffmpeg_h264_vaapi.sh` / `ffmpeg_hevc_vaapi.sh` | 本机是 Windows，**无 VAAPI 可连**（`Failed to initialise VAAPI connection`） |

反过来看，深测把两个**快查看不到的事实**挖了出来：`*_nvenc` 在快查里是 `NO-DEVICE`
（`nvidia-smi` 坏了），深测却 `PROBE-OK rc=0` —— 真编出来了（见上文第 3 条坑）。
这就是深测存在的意义：**快查的 `NO-DEVICE` 只是"说不清"，深测才给判决。**

深测的另一处验证点是 list 族：4 个包装器全部 `PROBE-OK rc=0 - list mode`。
这一条是**修过才对的** —— 修复前它们全报 rc=1 `Error opening input`，
根因是 MSYS 路径改写（见 §4 与 `environment_matrix.md` 表 4）：入口把相对名 `clip.mp4`
规范化成 `/c/...` POSIX 形式，原生 `ffmpeg.exe` 打不开。修法是深测前 `cygpath -m`
规范化工作目录 + 清单写绝对路径。

7 条 WARN 全部是**数据观察**而非代码缺陷：

* `bitrate_table_avc.csv` 第 17/19/21/39/67 行是与前一行完全相同的重复行（值相同、不可达）。

（`bitrate_table_av1.csv` 第 51/52 行曾有的码率回落已修正，两行均钳到 3148328
（= 0.70 × hevc[1764000]）：AV1/HEVC 的 0.65 档台阶（-7.1%）大于 1764000 前后相邻桶的
码率增幅（~6-7%），台阶无论画在哪个桶都必然产生回落。修正后 0.65 档从 1080p
（2073600 桶）起算，1764000/1920000 两桶沿用 0.70 档值，全表恢复单调。）

（原第 3 条 `libx265` preset 白名单 WARN 已随参数统一而消失；参数分歧的处理约定：
一般取 `fast`，改前需用户确认。）

SKIP 的 4 条：T8 / T19（VAAPI —— 本机是 Windows，无 Linux DRM 设备）、
T7（cp65001 守卫是 Windows 控制台特性，sh 侧无对应物）、T15（AV1 QSV 需要 Arrow Lake+ 核显）。

**探针夹具修复带来的覆盖恢复**：把可用性探针夹具从 128×128 改成 320×240 之后，
同一次全量运行从 `PASS=19 / SKIP=7` 变为 `PASS=22 / SKIP=4` —— 恢复的正是
`T2 ffmpeg_hevc_nvenc`、`T14 ffmpeg_av1_nvenc`（断言到 `codec=av1`）、
`T20 ffmpeg_hevc_nvenc_cygwin` 三个硬件用例。这三条在本机原本一直是被探针自身
判成 SKIP 的，属于「有硬件却静默不测」。这也说明：**探针夹具的规格必须经得起推敲**，
它本身可以成为覆盖率的隐性上限。

### 6.2 待人工补跑

`.bat` 侧套件无法在本环境的自动化通道里执行（cmd.exe 的输出拿不到），
需要手工双击验证：`test\bat\smoke_all.bat`（或 `smoke_ffmpeg.bat`）与
`test\bat\check_env.bat`。需要重点看的是本轮新增的部分：

* T16 / T17（新增 `ffmpeg_libx264.bat` 与低码率 clamp 回归）；
* T1/T2/T3/T7/T14 的 `[SKIP]` 行是否只在**真的没有硬件**时出现；
* `gate_*.log` 是否生成、内容是否指向硬件缺失而非脚本错误。

---

## 7. 约定与坑（都在本仓库真实发生过）

1. **`.bat` 里 `if cond cmd1 & cmd2` 的 `&` 不受 `if` 约束**，`cmd2` 会无条件执行。
   想让子程序提前返回，必须写成括号块，不能靠 `&` 串联：
   ```bat
   if not exist "%REPO%\%E%" (
       call :emit NO-ENTRY "%E%" "file missing"
       exit /b 0
   )
   ```
2. **`set "VAR=值"` 包装写法遇到带引号的值会崩**（L08）。本仓库的
   `RUN_COM`/`SRC_FILE`/`TARGET_FILE` 存的是带引号路径，必须用非包装写法 `set VAR=值`。
3. **`%VAR:"=%` 会剥掉值里的引号**，因此 `set X="%VAR:"=%"` 是正确惯用法；
   给裸形式 `%VAR:"=%` 补引号则是错的（检查器最初就是这么误报的）。
4. **`%SRC_FILE%` 不要再用引号包一层**（`"%SRC_FILE%"` 会变成 `""路径""`，
   值里的 `&` 会逃出引号）；应先用 `:"=` 形式剥引号再重新加。
5. **`%%~zA` 是 for 变量修饰符**，不是 `%~1` 形式的参数引用，两者在静态分析里必须区分。
6. **日志不要落在会被清场的目录里**（见 §3.1 的 `rm -rf` 陷阱）。
7. **判编码器构建版本要看 `Output #0` 的 `Lavc`，不是首个 `Lavf`**——首个 `Lavf`
   是输入素材的元数据。
8. **行尾/编码判读一律用字节统计**（Python），不要用 `grep -c $'\r'`（会给出假读数）。
