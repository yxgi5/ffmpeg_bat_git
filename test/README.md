# test/ — 测试体系说明

本目录是 `ffmpeg_bat_git` 的**三层测试体系**。三层各管一件事，互不替代：

| 层 | 文件 | 回答的问题 | 耗时 | 需要硬件 |
|----|------|-----------|------|---------|
| ① 静态 + 对等检查 | `lint/lint.py` | 代码本身有没有结构性问题？两族是否对等？ | < 1 秒 | 否 |
| ② 冒烟套件 | `sh/smoke_ffmpeg.sh`、`sh/smoke_special_chars.sh`、`sh/smoke_dvd_tools.sh`、`bat/smoke_ffmpeg.bat`、`bat/smoke_special_chars.bat` | 每一次真实编码跑通了吗？断言对不对？ | 数分钟 | 部分是（无则 SKIP） |
| ③ 环境能力报告 | `sh/check_env.sh`、`bat/check_env.bat` | **这台机器**能用哪些入口？为什么不能用？ | 秒级 / 深测数十秒 | 否（深测会真跑） |

三层的退出码语义一致：**`0` = 干净，非 0 = 有问题**（能力报告例外，见 §4）。

**两族文件名一一对应**（去掉族后缀，目录名即族名）——同名文件就是同一件事在两个家族里的孪生实现：

| 用途 | `.sh` 族 | `.bat` 族 |
|------|----------|-----------|
| T 编号回归套件 | `test/sh/smoke_ffmpeg.sh` | `test/bat/smoke_ffmpeg.bat` |
| 元字符文件名矩阵 | `test/sh/smoke_special_chars.sh` | `test/bat/smoke_special_chars.bat` |
| DVD 工具链（`tools/` 五个脚本） | `test/sh/smoke_dvd_tools.sh` | （暂无，见下） |
| 一键串跑 | `test/sh/smoke_all.sh` | `test/bat/smoke_all.bat` |
| 环境能力报告 | `test/sh/check_env.sh` | `test/bat/check_env.bat` |

**例外（已记录在案）**：`smoke_dvd_tools.sh` 目前只有 `.sh`。它依赖 `dvdauthor` +
`genisoimage/mkisofs`，Windows 上基本没有，孪生过去只会整片 SKIP；等 `tools/` 那五个脚本
有了 `.bat` 版本再一起补。缺工具链的机器也是整段 SKIP（SKIP 不算失败）。

---

## 0. 快速上手

```bash
# ① 静态 + 对等检查（任何机器，1 秒）
python3 test/lint/lint.py              # 全部
python3 test/lint/lint.py --lint-only  # 只做静态检查
python3 test/lint/lint.py --parity-only# 只做对等检查
python3 test/lint/selftest.py          # 检查检查器自己（38 个用例）

# ② 冒烟套件（或一条命令跑全套：bash test/sh/smoke_all.sh）
bash test/sh/smoke_ffmpeg.sh           # sh 族回归全量（T1-T25）
bash test/sh/smoke_ffmpeg.sh guard     # 只跑参数校验/退出码段
bash test/sh/smoke_ffmpeg.sh list      # 只跑清单模式段
bash test/sh/smoke_special_chars.sh    # sh 族元字符矩阵（part A/C/B/D/Z）
bash test/sh/smoke_dvd_tools.sh        # tools/ 五个 DVD 脚本端到端（需 dvdauthor + genisoimage）

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

## ③b 单片源码率标尺 bench_calib（sh/bat 对等）

**用途**：特殊片源需要尽可能保画质时，从原视频实测出「该给多少码率」——
不信任理论表，直接量这一部。

```
bash test/sh/bench_calib.sh [avc|hevc|av1] <source> [max_h] [seconds]   # sh 侧
test\bat\bench_calib.bat <source>          # 双击，默认 hevc
test\bat\bench_calib.bat av1 <source> 1080 # 带编码器与高度上限
```

> **source 被 shell 切成几段也能跑**（2026-09-20 加）：路径若来自**没加引号**的命令替换
> （``test/sh/bench_calib.sh `cygpath "F:\a b\c.mp4"` ``），shell 会把它按空格拆成好几个参数 ——
> `tried: [...]` 会显示成 `[/cygdrive/f/👍]`。`test/sh/bench_calib.sh` 与
> `test/sh/nvenc_pair_calib.sh` 现在走 `lib/common.sh` 的 **`rejoin_split_path()`**：
> 把「拼起来确实存在的」最长前缀片段粘回一条路径，并打印一行
> `note: the shell had split the source path on spaces … glued back to [...]`（**不静默**）；
> 只有**粘不回去**时才报 `ERROR: source video not found` + `tried: [...]` 并附诊断。
> 注意 `test/sh/soft_pair_calib.sh` 收的是 **MODE**（`full|1080|probe`）而不是路径 ——
> 它校验 MODE，没有这层粘回逻辑。

做法：取片源中段一段（默认 30s），按查表值 T 的 **T/4 → T 五点码率梯**，用该编码器的
**软件编码器**（libx264 fast / libx265 fast / libsvtav1 p8——与码率表同基准，见
`environment_matrix.md` 第 27 条）编码，libvmaf 直接对照源片本身（参照腿与编码腿做同样的
fps30/像素格式归一），产出 `results.csv`。sh 侧附 log 域拟合，解出 VMAF 90/93/95/97 各需
多少码率并给出建议值；bat 侧给出 VMAF≥95 的最小梯点。产物缓存于
`%TEMP%/ffmpeg_bench_calib_<codec>/<参数指纹>/`，重跑只补缺失点。

> **两族的梯子与产物名已经完全一样**（2026-09-20）。sh 侧原先是 `T*25/100, T*33/100, …`，
> bat 侧是 `T/4, T/3, T/2, 3T/4, T` —— **33% 不是 1/3**：T=2719757 时第二个梯点 sh 侧算成
> 897519、bat 侧 906585，产物名也对不上（`1280x720_33.mp4` vs `1280x720_906585.mp4`）。
> 现在 sh 侧用同一套整数除法，产物名同样用**码率**，两族在同一目录下可以共用同一批产物。

实测状态：sh 侧已在 **B 机（MSYS2）/ A 机 / C 机** 三机用合成源跑通三 codec 全梯
（A/C 结果两机一致，见 `environment_matrix.md` 第 30 条）；bat 侧 B 机合成源通过，
真实片源双击验证待用户执行。

## ③c 编解码配对校准（nvenc_pair / soft_pair，两族对等）

**用途**：实测「等画质下 AV1 相对 HEVC 到底省多少码率」，用于校验码率表的代际比例假设。
不带回归断言，属于研究/校准工具（`.sh` 侧重跑远端 Linux，`.bat` 侧双击拖片即可）。

| 工具 | 配对 | 结论 |
|------|------|------|
| `test/sh/nvenc_pair_calib.sh` + `test\bat\nvenc_pair_calib.bat` | **硬编** hevc_nvenc vs av1_nvenc（p4 CBR） | `environment_matrix.md` #26，r≈0.72–1.0 |
| `test/sh/soft_pair_calib.sh` + `test\bat\soft_pair_calib.bat` | **软编** libx265 fast vs libsvtav1 p8 | #25，r≈0.53–0.61（表哲学的基准侧） |

两者都产出 `results.csv`（列 `clip,codec,br_req,br_delivered,vmaf[,model]`），求解交给
`test/py/` 下对应的脚本：`eq_quality_solve.py`（吃 CSV）与 `nvenc_pair_solve.py`（扫描工作目录）。
soft_pair 首次运行会从 test-videos.co.uk 下载 10s 样本（1080p 两片；`full` 模式另加 720p 与
2160p——2160p 参照是 1080p 上变换，两侧同等承担该 caveat）；`SKIP_DOWNLOAD=1` 可离线
（预置 `src_*.mp4`）。工作目录 `%TEMP%\ffmpeg_soft_pair_calib`（`SOFT_PAIR_WORK` 可改）。
（上表两对工具的校准使命均已完成；保留作复测，见 #25/#26。）

> 建议顺序：**先 ① 后 ②**。静态检查能在 1 秒内抓住语法/标签/引号/编码问题，
> 不必等几分钟的冒烟跑完才发现第 3 行少了个括号。

---

## 1. 目录结构

```
test/
├── README.md                    本文件
├── capability_matrix.md         环境 × ffmpeg 构建 × 编解码器 能力矩阵（全机实测）
├── lint/
│   ├── lint.py                  静态 + 跨族对等检查器（零依赖，仅标准库）
│   └── selftest.py              lint.py 自身的回归测试（recall + precision）
├── sh/
│   ├── smoke_ffmpeg.sh          sh 族回归套件（与 bat 套件同 T 编号）
│   ├── smoke_special_chars.sh   sh 族元字符矩阵（与 bat 套件同 part 字母）
│   ├── smoke_dvd_tools.sh       tools/ 五个 DVD 脚本端到端（样例盘 -> 体检 -> 出盘）
│   ├── smoke_all.sh             sh 族一键串跑（含上面三套）
│   ├── check_env.sh             sh 族环境能力报告
│   ├── bench_calib.sh           单片源码率标尺（软编基准，见 ③b）
│   ├── nvenc_pair_calib.sh      NVENC AV1/HEVC 配对校准（bat 孪生）
│   └── soft_pair_calib.sh       软编 SVT-AV1/x265 配对校准（bat 孪生，见 ③c）
├── bat/
│   ├── smoke_ffmpeg.bat         bat 族回归套件
│   ├── smoke_special_chars.bat  bat 族元字符矩阵
│   ├── smoke_all.bat            bat 族一键串跑
│   ├── check_env.bat            bat 族环境能力报告
│   ├── bench_calib.bat          单片源码率标尺（sh 孪生）
│   ├── nvenc_pair_calib.bat     NVENC AV1/HEVC 配对校准（sh 孪生）
│   └── soft_pair_calib.bat      软编 AV1/x265 配对校准（sh 孪生）
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
| L13 | `exit` / `exit /b` 取值在白名单内（bat `0,1,2,3,4,5,6`；sh 另允许 `6,8,9`） | 让 §5.2 的退出码契约不漂移（`4` 为 2026-09-30 新增的「硬件缺失」，`6` 为同日新增的「产物已存在」） |
| L14 | `test/` 下的 `.sh` 在 **git 索引**里必须是 `100755`（读 `git ls-files -s`，不读文件系统） | Windows 上 `core.fileMode=false`，pull 出来丢执行位 |
| L15 | **失败路径的两族对等**：入口 `.bat` 在 `%RUN_COM%` 之后、清单 wrapper 在子调用之后必须有 `exit /b 1`；`.sh` 入口在编码命令之后必须有 `exit 1`。**且 `.bat` 入口的守卫必须是「负数安全」的**（`if not "%X%"=="0"` 或 `%X% NEQ 0`，`X` = `%ERRORLEVEL%` 或紧接着从它赋值的变量），不允许用 `if errorlevel N` | **2026-09-17 实际缺口（两层）**：① `.bat` 入口一律以无条件 `exit /b 0` 收尾，任何编码失败对调用方都伪装成成功（wrapper 继续跑、探针报 OK）；② 改成 `if errorlevel 1` 后**仍然没修好**——它是**带符号比较**，而 Windows 版 ffmpeg 失败时返回**负** AVERROR（本机 `av1_qsv` 退出码 **-40 / Function not implemented**），`-40 >= 1` 不成立 → 守卫不触发 → 依旧落到 `exit /b 0`。用户正是在复跑探针时看到 `rc=0 but no real output (0B) \| ERRORLEVEL:-40` 才揪出来的。L13 只查取值词表，查不出「失败路径根本不可达」 |
| L16 | **流映射一致性**：每个 mp4 出口（两族 21 个 `ffmpeg_*`）都必须带 `-map 0:a? -map 0:s? -c:s mov_text -map_metadata 0 -map_chapters 0`，且**视频映射按出口类型区分**：编码类必须 `-map 0:V`，remux 两族必须 `-map 0:v`（两边写反都报 FAIL）；**且编码类必须"保留封面"**：① 引用封面映射变量（`.sh` 的 `${COVER_MAP[@]}` / `.bat` 的 `%COVERMAP%`）② **不得出现未加流号的 `-c:v copy`**（会和 `-c:v:0` 撞在同一条流上，ffmpeg 报 `Multiple -codec ... only the last option will be used`；只有 remux 允许）③ 必须有 `-c:v:0 <编码器>` ④ 不得出现未加作用域的 `-profile:v`（会打死 copy 流）；⑤ **闸门变量必须排在 `-map 0:s?` 之后**（变量里兼带位图字幕的负映射 `-map -0:s:<i>`，而负映射只排除"已映射进来"的流，顺序反了就失效 → 位图字幕把整条打成 0 字节）；`lib/common.{sh,bat}` 必须定义封面映射字面量**且**带上封面复制指令 `-c:v:1 copy`**且**定义位图字幕名单（含 `hdmv_pgs_subtitle`）（封面复制下标**由 ffprobe 数流算出**，写死槽位在多路视频源上会错位到「整条 rc=127 写 0 字节」，`-c:v:1 copy` 现为探测失败时的兜底字面量；remux 与 DVD 入口按白名单豁免） | **2026-09-17 实际缺口**：两个 remux 入口（`ffmpeg_copy_to_mp4.{bat,sh}`）没有 `-map`，ffmpeg 默认选流只保留 1 视频 + 1 音频，**多音轨/字幕被静默丢弃**（转封装是个"看不见的破坏"）。该缺口活了很久，直到用户问「`-map 0:v` 是否加」才暴露。<br>**2026-09-28 实际缺口（用户报障「前一个命令失败，后一个命令成功」）**：编码类的 `-map 0:v` 会把 **mkvmerge 写入的封面图**（attached picture）当成第二路输出视频流送进编码器，而 mp4 只能把封面存成 mjpeg/png/bmp → `Could not find tag for codec hevc in stream #1, codec not currently supported in container` → `Could not write header … Invalid argument` → **0 字节、整条白跑**（用户那份 2h13m 的 mkv 第 4 条流就是 `mjpeg (attached pic)`，ffprobe `attached_pic=1`）。改 `-map 0:V` 修掉，共 19 文件 21 处。remux 两族**不能**跟着改：它们 `-c:v copy`，mp4 存得下复制过来的 mjpeg 封面（实测输出 3 条流全在、`attached_pic=1`），改成 `0:V` 反而会把今天还在的封面悄悄丢掉。<br>**2026-09-28 同日，用户追加要求「如果有封面的尽可能保留封面呗」**：`0:V` 只是"别炸"，封面本身还是丢了。真正保留封面的写法是「**复制默认 + 只编码主视频**」—— `-c:v copy -c:v:0 libx264`，配 `-map 0:v:disp:attached_pic?`（按 **disposition** 选流，**几层封面都能一起选中**，也不用去数封面在第几路）。`disp:` 是 ffmpeg 7.1+ 才有的说明符，老构建视为**语法错误**、结尾的 `?` 救不了 → 两族各加一个**能力闸门**（`.sh` 的 `cover_map_gate` / `.bat` 的 `:cover_map`：lavfi 假源探一次，不认就只丢封面、绝不让整条编码失败）。copy 流会吃下未加作用域的编码参数，实测**只有 `-profile:v` 致命**（`Error setting up codec context options`）→ profile 一律写 `-profile:v:0`，Cygwin 入口的 `-vf` 同理改 `-filter:v:0`。详见 `environment_matrix.md` 第 52/53 条。<br>**2026-09-28 再追加，位图字幕（用户给了 7 个 DVD ISO 样本后实测）**：`-c:s mov_text` 只能吃文本字幕，遇到 `hdmv_pgs_subtitle` / `dvd_subtitle` 会报 `Subtitle encoding currently only possible from text to text or bitmap to bitmap` → rc=-22 **写 0 字节**。扫用户 838 条清单（657 可访问）**命中 14 个**（Chernobyl 全 5 集、花と蛇 8 部等）。修法：lib 数流时按字幕的 **per-type 下标**发 `-map -0:s:<i>` 负映射（用下标而非 `-map -0:s`，否则同文件里能救的 ass/subrip 会一起丢），随同一变量下发 → 入口零改动。详见 `environment_matrix.md` 第 54 条 |
| L17 | **moov 前置**：两个 remux 入口（`ffmpeg_copy_to_mp4.{bat,sh}`）必须带 `-movflags +faststart` | **2026-09-17 用户要求**：默认 mp4 把索引 `moov` 写在 `mdat` **之后**，播放器要拿到文件末尾才能起播（大文件拷走/边下边播时很难受）。实测同一夹具：不加 = `ftyp/free/mdat/moov`，加了 = `ftyp/moov/free/mdat`，**字节数完全相同**（ffmpeg 就地搬索引，日志里是 `Starting second pass: moving the moov atom to the beginning of the file`）。当前只管 remux 两个出口，11 个编码入口仍是默认布局（等用户裁定是否一并前置） |
| L18 | **锚定变量**：凡是读 `%REPO%` / `%SELF_DIR%` 的 `.bat`，必须在**首次读取之前**赋值；且 `test\bat\` 下的工具必须用 `%~dp0..\..` 自锚定 | **2026-09-20 实际缺口（用户报障）**：`bench_calib.bat` 里 `call "%REPO%\lib\common.bat"` 的 `REPO` **从未定义** → 路径塌缩成 `"\lib\common.bat"`（盘根路径）→ 任何 cwd 下都报 `The system cannot find the path specified.`，而调用方把它伪装成「ffmpeg/ffprobe not on PATH」。更早一版是 `"%SELF_DIR%lib\common.bat"`（`SELF_DIR` 同样未定义）→ 退化为**相对路径**，只在 cwd = 仓库根时碰巧可用。两类症状不同（一个必崩、一个看运气），根因同源 |
| L20 | **libvmaf 消费者必须带能力要求去定位 ffmpeg**（**只管 `.sh` 侧**，2026-09-20 修订）：`test/sh/*.sh` 里凡是要 libvmaf 的（非注释行出现 `libvmaf`），必须有一行同时出现 `find_ffmpeg` / `--need-filter` / `libvmaf`。白名单：`test/sh/check_env.sh`（环境盘点工具，报告 libvmaf 有无所用，自带的 `find_ffmpeg` 只是挑一个"待盘点对象"） | **2026-09-20 实际缺口（用户报障）**：用户在 MSYS2 MINGW64 里跑 `test/sh/bench_calib.sh` 得到 `ERROR: this ffmpeg build has no libvmaf filter`，而**同一台机器**上 `C:\Program Files\ffmpeg\bin` 的 gyan full（2025-05-01）是带 libvmaf 的 —— 缺的不是工具链，是 sh 侧**一律信 PATH**：MSYS2 的 `/mingw64/bin/ffmpeg` 是 8.1、无 libvmaf，却排在 PATH 前面（`test/capability_matrix.md` 早写明「同一台机器三种 shell 解析到三个不同 ffmpeg」，但 sh 侧从没有对应机制）。bat 侧同一个坑换了个形态：从 MSYS2 终端跑 `.bat` 时 cmd 继承的 PATH 同样把 `/mingw64/bin` 排在前面 → `find_ffmpeg` 选中它 → NO_VMAF。两族同一天各踩一次，故立此规则。**bat 半边同日回退**：曾要求 `.bat` 调用行带第 3 参数（能力名）并在 `lib/common.bat` 里加 `:ff_satisfies` 子过程，但那个子过程正是 L21 的形态 —— 对**每一个**候选都判「缺少能力」；而且本机 ffmpeg 根本不在 PATH 上（走的是兜底目录），这道门对本机毫无作用。cmd 语义在开发沙箱里无法验证（`cmd.exe` 被拦），盲改不划算，故**整体回退**，能力筛选只留在 `.sh` 侧，写法陷阱改由 L21 永久拦截 |
| L19 | **反引号里的程序路径**：`for /f` 反引号内被执行的**程序名**不得是 `%VAR%` 展开（不得出现 `` `%FFPROBE_PATH% ...` ``，也不得出现 `` `"%FFPROBE_PATH%" ...` ``）；程序路径必须走「常规命令行 + 重定向到临时文件」，再由 `for /f "usebackq"` 读文件 | **2026-09-20 实际缺口（用户报障，与 L18 同一次）**：`bench_calib.bat` 三行 `` for /f ... in (`%FFPROBE_PATH% -v error ...`) `` → cmd 打印三次 `'C:\Program' is not recognized as an internal or external command`（`C:\Program Files\ffmpeg\bin\ffprobe.exe` 在空格处被切断），紧接着工具自己的兜底文案又把它解释成「ffprobe failed / pixel count overflow on this source」。**同一文件第 161 行**还有更隐蔽的一处：它在反引号里给路径**加了**引号，看似"已经修过"，实则撞上 `cmd /c` 的引号剥离规则（「行首是引号时，剥掉首个引号与**该行最后一个**引号」）→ 末尾参数的收尾引号被吃掉，路径含空格时同样散架，而且它**静默**把 delivered 记成 0。`nvenc_pair_calib.bat` 里的裸 `ffprobe`（PATH 解析，程序名不是变量）不受影响，也不该被报 |
| L21 | **引号里不得再嵌参数展开**：`.bat` 里不得把「**已经带引号**传进来的参数」再套一层引号（`"%1\ffmpeg.exe"` 这种）。合法形态只有两种：`"%~1\path"`（剥引号修饰符）与 `"%1"`（右引号**紧跟在** `%1` 之后，表示原样照传） | **2026-09-20 实际缺口（与 L20 的 bat 半边回退同源）**：`lib/common.bat` 新加的 `:ff_satisfies` 写成 `"%1\ffmpeg.exe" -hide_banner -filters 2>nul`，而调用方传进来的是**带引号**的 `%FFBIN%`（`C:\Program Files\ffmpeg\bin` 含空格，不加引号传不过去）→ 展开成 `""C:\Program Files\ffmpeg\bin"\ffmpeg.exe"`，cmd 取首 token 得到**空程序名**，报 `'' is not recognized as an internal or external command`，而该行尾部挂着 `2>nul` → 错误被彻底吞掉 → **任何**候选都被判成「缺少能力」。这个坑极隐蔽（表面看是「加引号更安全」），故固化成规则 |
| L22 | **`call` 的参数里不得出现裸等号**：给批处理传参时，`=` 与空格/逗号/分号一样是**分隔符**，所以 `call ... probe_field "%OUT%" stream=bit_rate DEL` 会被切成 `%2=<文件> %3=stream %4=bit_rate %5=DEL` —— 被调用方从 `%4` 取"输出变量名"，于是它写进一个叫 `bit_rate` 的变量，而调用方读的 `DEL` **从未被赋值**。要传"带等号的值"就**加引号**（`call :x "opt=1"`，引号内不切），更好的是改成**关键词**、由被调用方内部展开（`vbr` / `fbr`） | **2026-09-20 实际缺口（用户真机报障，与 L19/L20/L21 同一现场）**：`lib/common.bat` 的 `:probe_field` 是 `e34a21c` 当天新增、**从未在真机跑过**的子过程（沙箱无 `cmd.exe`），两个调用方都写成了 `probe_field "%OUT%" stream=bit_rate DEL` → 五个梯点全跑完、`vmaf` 完全健康（87.04→96.38），**`delivered` 一列恒为 0**。静态审查查不出来，只有真机能暴露。修法：show_entries 串收到 `:probe_field` 内部按关键词展开（`vbr`=视频流码率 / `fbr`=容器平均码率，后者兼作回退，因为容器无 per-stream 码率时 ffprobe 返回字面量 `N/A`），并让 lint 拦住老写法。**召回已用真文件验证**：把 `HEAD` 版 `bench_calib.bat` 临时落到 `test/bat/`，L22 精确报出 `:188` |

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
`selftest.py` 用 38 个合成小仓库同时验证两个方向：

* **recall**：已知有问题的写法**必须**被报出来（L01/L04/L06/L07/L08/L09/L13/L15/L16/L17/L18/L19/L20/L21/L22 各一例起，
  其中 L15 三例：吞掉 ffmpeg 失败的入口、`if errorlevel 1` 这种**看不见负退出码**的守卫、
  忽略失败子调用的清单 wrapper；L17 一例：remux 出口漏了 `+faststart`；
  L18 三例：读了 `%REPO%` 却从未赋值、锚定赋值出现在首次使用**之后**、`test\bat` 工具没有
  `%~dp0..\..` 自锚定；L19 两例：`for /f` 反引号里裸写 `%FFPROBE_PATH%`、以及给它套普通
  双引号（两种写法都不可靠，见 L19 行）；L20 一例：`.sh` 要 libvmaf 却信 PATH；
  L21 一例：给已展开的参数再套引号（`"%1\ffmpeg.exe"`，正是 `:ff_satisfies` 的形态）；
  L22 一例：`call` 的参数里出现裸等号（`probe_field "%OUT%" stream=bit_rate DEL` ——
  正是把 `delivered` 打成 0 的那一行）；
  L16 四例（同日两批）：remux 被改成 `0:V` 会丢掉它本来保留的封面；编码类停止映射封面
  （`.sh` 与 `.bat` 各一例）；编码类把封面映射与**未加作用域**的 `-profile:v` 配在一起；
  以及「`lib/` 里的封面映射字面量被删」；
* **precision**：已知正确的写法**必须不报**，其中 8 例正是开发过程中真实出现过的假阳性
  （`%VAR:"=%` 引号计数、`endlocal & set` 字面量、`%%~zA` 循环修饰符、
  `set /p` 覆盖、安全的 `set VAR=%QVAR%` 惯用法、带失败传播的入口尾部、
  `%ERRORLEVEL% NEQ 0` 守卫、带 `+faststart` 的 `.sh` remux 入口），另加 L18 一例
  （正确自锚定的 `test\bat` 工具）、L19 一例（反引号里跑的是 PATH 解析的 `ffprobe` /
  PowerShell，程序名不是变量，合法）、L20 两例（`--need-filter libvmaf` 的 `.sh`、
  白名单里的 `check_env` 盘点工具——它报告 libvmaf 的有无，不消费它）与 L21 两例
  （`"%FF_BIN%\ffmpeg.exe"`——路径来自变量、变量自身已带引号，合法；`"%~1\ffmpeg.exe"`
  剥引号形式与右引号紧随 `%1` 之后的原样传递，也都合法）与 L22 两例
  （关键词形态 `probe_field "%OUT%" vbr DEL`、以及被引号包住的 `call :probe "opt=1"`
  —— 引号内不切分，两种都合法）。

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
| T20 | 已撤销：Cygwin NVENC 变体 2026-09-30 合并进 T2（`hevc_nvenc`） | — | — | — | — |
| T21 | 清单 CRLF + UTF-8 BOM | 清单 3 条目 | 3/3 产物 | ✅ | — |
| T22 | `run_list` 的 `</dev/null` 隔离 | 5 条目清单 | 5/5 产物 | ✅ | — |
| T23 | 清单条目文件缺失 → 中止 | 清单含不存在的路径 | `rc=1` | ✅ | ✅ |
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

### 3.6 耗时构成与提速（2026-09-17）

冒烟套件的墙钟时间 ≈ **入口调用次数 × 单次入口成本**，与片长、编码器几乎无关。
实测（本机 Win11 + MSYS bash + 原生 gyan ffmpeg，1080p60 2s 夹具）：

| 对象 | 改造前 | 改造后 |
|------|--------|--------|
| 纯 ffmpeg 直编同一夹具（libx265 fast） | 1.6s | 1.6s（编码器自身只 1.15s / 104fps） |
| 单次入口 `ffmpeg_libx265.sh` | 9.7s | **5.6s** |
| 5 条目清单用例（T22 形状） | 51.1s | **30.5s** |
| `smoke_ffmpeg.sh parity` 整段（16 用例） | 398s | **305s**（-23%，同为 12 PASS / 4 SKIP） |

最后一行才是"套件实际快了多少"的答案：**比单次入口的 43% 少**，因为每个用例除了
入口调用还有侧车 ffprobe、夹具拷贝、硬件探测等**未被本次改造覆盖的固定开销**。
换句话说，套件耗时的构成是「入口调用次数 × 单次成本 + 用例固定开销」，本次只砍了前者。

改造前那 9.7s 里**只有 1.7s 在编码**：`lib/common.sh` 的 7 个 `check_file_*` 各自起一条
`ffprobe`（`check_file_bitrate` 还有 stream→format 两级回退），一个入口走完就是 **8 个独立
ffprobe 进程**，每条外面还套一个 `tr -d '\r'` 命令替换。Windows/MSYS 下每次「fork + exe 启动」
实测约 0.5s，光问路就 5.5s。**清单用例更是 条目数 × 这个成本**。

改法：新增 `probe_source()`，一条 `ffprobe -of flat` 取回全部字段（v:0 的
`codec_name/width/height/r_frame_rate/bit_rate` + `format.size/duration/bit_rate`），
按文件路径缓存进关联数组 `_PROBE`，解析全用 bash 内建（不再逐字段起 `tr`/`sed`）。
7 个 helper 的**对外行为逐条不变**，由一次 56 组合的等价性对比钉住：8 种输入
（正常 mp4 / mkv / 纯音频 / 缺失文件 / 中文+空格名 / 分数帧率 / 双流 mkv / 无音轨 mp4）
× 7 个 helper，新旧两版逐条比 stdout 与退出码。

> **改造时发现一个既有 bug（"假判据"），同日修复（用户裁定）**：旧代码写
> `local x=$(ffprobe ... | tr -d '\r')` 再接 `if [ "$?" -ne 0 ]`，而 `$?` 取的是
> **管道末尾 `tr` 的退出码**，所以那个「检查出错！/ exit 1」分支**从未触发过**，
> 探测失败一直被静默成「输出空 + rc=0」。合并探测时先沿用了该行为，随后用户裁定修复：
> codec / framerate / resolution / duration 四个 helper 现在判 `_PROBE_RC`，探测失败
> 真正打印错误并 `exit 1`（`check_file_isvideo` 的 exit 3 与 `check_file_size` 的
> `-z` 兜底本来就是真判据，不动）。修复后重跑 56 组合对比：**52 条完全一致，
> 仅「缺失文件 × 这 4 个 helper」按预期从 rc=0 变 rc=1** —— 这 4 条差异就是修复本身。
> 入口以 `SRC_X=$(check_file_...)` 捕获且不查 rc，`exit 1` 只退出命令替换子 shell，
> 对入口而言失败后果与从前相同，差别只在多一条可见报错。

**还能再榨但刻意没做**：入口里的 `dirname`/`basename`/`realpath` 各一次外部进程、
`lookup_bitrate` 的一次 `awk`。换成 bash 内建即可，但真实终端里每项只值 0.1s 量级，
收益 <10% 而改动面涉及 11 个入口 —— 风险与收益不成比例。

**bat 侧同步（2026-09-17 同日完成）**：`lib/common.bat` 新增 `:probe_source` ——
字段集与 sh 侧逐字一致的同一条 ffprobe `-of flat`，结果存进 `P_*` 变量
（`for /f tokens=1,* delims==` + `%%~b` 剥引号），同文件重复调用命中缓存
（`PS_LAST`/`PS_RC`）。`check_isvideo` 改走 `probe_source`；7 个编码入口把
6 段「ffprobe + 临时文件 + `del`」探测换成直接读 `P_*`（入口探测进程数 7 → 1），
宽高段顺带省掉了 `EnableDelayedExpansion` 块（片名感叹号不再有被吃风险）。
入口在 `check_isvideo` 之后对 `probe_source` 的退出码做负数安全检查（失败
`exit /b 1`，与 sh 侧探测失败报错对齐）。P_* 字段缺失时展开为空，与原实现的
空值路径一致。**bat 侧无法在沙箱运行，需真机双击验证**（见 6.5 节）。

---

## 4. 第三层：环境能力报告（`check_env`）

回答「**这台机器现在能用哪些入口**」。这是**报告**不是测试：一个用不了的入口
不是缺陷，只是这台机器缺硬件。所以它**始终以 0 退出**（只有装不上才返回 2）。

两种模式：

* **快查**（默认）：静态盘点 ffmpeg 构建特性、hwaccels、渲染节点/GPU、编码器、
  **`libvmaf` 滤镜**（calib 族的硬依赖）、三张码率表行数、测试工具是否齐全。秒级。
* **深测**（`--probe` / `PROBE`）：再建一个 3 秒小片，把每个候选入口真跑一遍，
  报真实退出码，失败时**附 `run.log` 的末条错误**（两族同样的呈现方式）。数十秒。

> ⚠️ **`.sh` 侧请在 MSYS2 **MINGW64** 下跑，不要在 Cygwin 下跑**（2026-09-29 实测）。
> 深测的第一步是用 `libx264` 造那张 3 秒探针片，而 Cygwin 的 ffmpeg 7.1.1 **不带
> `libx264` / `libx265`**（快查里就是 `enc libx264 : NO`）。后果不是「libx264 入口 FAIL」，
> 而是探针片根本造不出来 —— 整份深测以 `FATAL: cannot build the probe clip` 收场，
> **一条结果都没有**。同一台机器换 MINGW64（`/mingw64/bin/ffmpeg` 8.1，软编齐全），
> 同一条命令是 `ok=12 / fail=3`，`ffmpeg_libx264` / `ffmpeg_libx265` /
> `convert_from_list_libx265` 三条全 `PROBE-OK`。
>
> ```bash
> MSYSTEM=MINGW64 bash -lc 'cd /d/repos/ffmpeg_bat_git && bash test/sh/check_env.sh --probe'
> ```
>
> 两个附带细节：MSYS2 的路径是 `/d/...`（**没有** `/cygdrive` 前缀，那是 Cygwin 的写法）；
> 且**必须带 `-l`**，否则 PATH 里没有 coreutils，连 `dirname` 都找不到，脚本会误报
> `repo not found`。另有一条**走不通的绕法**：给报告单独指定 `FFMPEG=` 只能改变**报告自己**
> 用的构建，入口脚本仍会按自己的规则挑中 PATH 上的那个 —— 于是出现「报告用 gyan full、
> 入口用 Cygwin 7.1.1」的混合态，libx264/libx265 被判 `PROBE-FAIL rc=1 | [libopenh264 …]`，
> 看起来像入口坏了，其实是两个构建对不上。**不要在 Cygwin 里跑深测。**

状态词表（两族**完全一致**，两份报告可以直接逐行对比）：

| 状态 | 含义 |
|------|------|
| `OK` | 可用（静态证据充分，或深测 rc=0） |
| `NO-ENCODER` | 这个 ffmpeg 构建里没有该编码器 |
| `NO-DEVICE` | 编码器有，但本机没有可用设备/GPU |
| `N/A-OS` | 该入口在当前系统无意义（VAAPI 是 Linux 内核 API） |
| `N/A-INPUT` | 入口本身没问题，但**这份报告喂不了它**：输入不是普通视频文件（ISO 镜像 / VIDEO_TS 目录 / 光驱盘符）。快查与深测**都列出**它，深测只标 `skipped` 而不真跑 —— 用 3 秒 mp4 小片探它必然失败，那条假 FAIL 会混进真 FAIL 里稀释报告 |
| `UNKNOWN` | 静态判断不了 → 用深测决定 |
| `PROBE-OK` / `PROBE-FAIL` | 深测真跑的结果：两族都要求 **rc=0 且 `run.log` 里没有 `Conversion failed`**，bat 侧另外要求**真实输出文件**存在且 >4096 字节；失败行带 rc 与 `run.log` 末条错误 |
| `NO-ENTRY` | 仓库里没有这个文件 |

这些实现细节值得记住，它们都是**踩过的坑**（后两条是 2026-09-17 新踩的）：

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
5. **bat 侧探针判产物，不判 rc（判据要独立于被检对象）** —— 入口 `.bat` 是交互式设计，
   历史上以无条件 `exit /b 0` 收尾，ffmpeg 失败也报成功，于是初版深测把**不支持 AV1 编码
   的机器**上的 `av1_qsv` 也判成 `PROBE-OK`。2026-09-17 起入口已按 `.sh` 孪生改为失败传回
   `1`（L15 钉住），但探针**仍然判真实输出文件**（存在且 >4096 字节）——
   因为「rc=0 却没写出文件」还有别的来源：`copy_to_mp4` 对 mp4 输入直接 no-op，
   remux 入口的 `-n` 与同名输入冲突（故探针给 remux 喂 `.mkv` 夹具，与冒烟 T5 同思路）；
   实测连 `ffmpeg -n` 拒绝覆盖同名输出时**自身就返回 0**（只在日志里留
   `already exists / Error opening output file`），两族入口都传不出非零。
   判据与被检对象解耦，缺一个都还能说真话。
6. **Windows 上 ffmpeg 的失败码是「负」的，`if errorlevel 1` 看不见它们（2026-09-17 实测）** ——
   用 `subprocess` 取原始 32 位退出码，三种典型失败**全是负数**：

   | 失败 | 原始码 | 含义 |
   |------|--------|------|
   | `av1_qsv`（本机无 AV1 硬编） | `0xFFFFFFD8` = **-40** | `ENOSYS` / Function not implemented |
   | 输入文件不存在 | `0xFFFFFFFE` = **-2** | `ENOENT` |
   | 参数错误 | `0xFFFFFFEA` = **-22** | `EINVAL` |

   而 cmd 的 `if errorlevel N` 读作「errorlevel ≥ N」且**按有符号比较**，`-40 ≥ 1` 为假
   → 守卫不触发，入口照样走到末尾的 `exit /b 0`。也就是说：**上一轮「失败传回 1」的修复
   在 Windows 上等于没生效**（`.sh` 侧 `[ $? -ne 0 ]` 一直是对的，只有 `.bat` 侧漏了）。
   现在的守卫是 `set "FB_RC=%ERRORLEVEL%"` + `if not "%FB_RC%"=="0"`（字符串相等比较，
   负数/正数/空值一律判成失败），L15 已钉住这个形式，selftest 有专门的 recall 例。
   顺带纠正一条早先的错判：沙箱里 bash 报的 `rc=127`（以及另一处的 `-40`）是 MSYS 对
   同一个负码的渲染，**不是** ffmpeg 真返回 127；当时据此写下「所以 `.bat` 侧必须写
   `if errorlevel 1`」，方向正好反了。

---

## 5. 两族对等矩阵

### 5.1 入口清单

**共享（12）**：`ffmpeg_avc_qsv`、`ffmpeg_hevc_qsv`、`ffmpeg_av1_qsv`、`ffmpeg_hevc_nvenc`、
`ffmpeg_av1_nvenc`、`ffmpeg_libx264`、`ffmpeg_libx265`、`ffmpeg_copy_to_mp4`、
`convert_from_list_qsv`、`convert_from_list_cuda`、`convert_from_list_libx265`、`repack_from_list`

**sh 独有（2，均有正当理由）**

| 入口 | 理由 |
|------|------|
| `ffmpeg_h264_vaapi.sh` / `ffmpeg_hevc_vaapi.sh` | VAAPI 是 Linux 内核 DRM API，Windows 无对应物 |

**bat 独有（0 个编码入口）**：`opencmd.bat` 是「开一个 UTF-8 控制台」的辅助脚本，
不是编码入口，因此不计入对等缺口。

> 历史缺口 `ffmpeg_libx264.bat` 已于 2026-09-16 补齐（H.264 软编保底，无硬件要求）。

### 5.2 退出码契约（跨族数值一致）

| 码 | 含义 |
|----|------|
| `0` | 成功 |
| `1` | 参数错误 / 输入文件不存在 / 清单非文本 / 清单条目缺失 / **编码或转换失败**（ffmpeg 非零返回原样传回）/ **找不到 ffmpeg** |
| `2` | 查表越界（像素数超出码率表范围） |
| `3` | 输入没有视频流 |
| `4` | **硬件缺失**：编码器在 ffmpeg 里列着，但这台机器的硬件打不开它（2026-09-30 新增，见下） |
| `5` | 码率异常（`percentage <= 0`） |
| `6` | 产物已存在且 `FF_ON_EXIST=fail`（一个字节都没转，且调用方要求察觉；默认策略 `skip` 仍是 `0`） |

`lib/common.sh` 的 `check_file_isvideo` 与 10 个 `.sh` 入口的码率异常分支
已在 2026-09-16 从 `1`/`4` 统一为 `3`/`5`，与 `.bat` 侧数值一致。（`4` 这个号当时
被腾空，2026-09-30 复用为「硬件缺失」，见下。）

**`4` = 硬件缺失（2026-09-30 新增）**：`ffmpeg -encoders` 里列着 `av1_qsv` 不代表这台
机器能用它 —— UHD 770 实测一开编码器就是 `Current codec type is unsupported`、
`rc=-40`，跑到最后只留下一个 0 字节的 mp4。入口在动源文件之前先拿 1 帧 lavfi 源试
开一次（`qsv_encoder_ready`），开不起来就返回 `4`，不再产空文件。它与 `1` 的区别是
**作用域**：`1` 只是这一个文件转失败了，`4` 对清单里**每一个**文件都成立 —— 所以
`convert_from_list_*`（两族：`.bat` 的 for 块、`lib/common.sh` 的 `run_list`）遇到 `4`
**既不跳过也不继续，直接中止整份清单并把 `4` 原样传回**（用户裁定：剩下的条目只会
一条接一条撞同一堵墙）。`.bat` 侧判定写成 `if errorlevel 4 if not errorlevel 5`：
for 块里 `%ERRORLEVEL%` 在块解析时就冻结了，读不到子调用的返回值；而
「`if errorlevel 4` + `if not errorlevel 5`」才是「正好等于 `4`」——不会把 `5`/`6`
截走，负的 AVERROR（`-40`）也进不来（带符号比较）。

**`FF_HWACCEL`：软编入口的解码加速器（2026-09-30 新增）**：`ffmpeg_libx264` /
`ffmpeg_libx265`（两族 4 个脚本）原先写死 `-hwaccel auto` —— 由 ffmpeg 挑第一个能初
始化的加速器（核显与 N 卡并存时选谁不可控），且锁屏会话下 D3D 会直接崩。现在由
`FF_HWACCEL` 选：`auto`（默认，逐字等同改动前）/ `cuda` / `none`（完全不加 `-hwaccel`）
/ `qsv`、`vaapi` 等原样透传。实测：默认与 `cuda`、`none` 均 rc=0 且产物正常；
`qsv` 在软编入口**跑不通**（QSV 表面帧喂不进 libx264，`Could not open encoder before
EOF`、rc=1、产物 0 字节）——要 QSV 解码请走 `ffmpeg_*_qsv` 入口。只影响解码，编码器不变。
`.bat` 侧把值存进 `FF_HWACCEL` 后再拼 `FF_HW_ARG`，D3D 回退 `set RUN_COM=%RUN_COM:
-hwaccel %FF_HWACCEL%=%` 因此按实际值删参数（显式指定时也会回退一次）；
`.sh` 侧 `ff_run` 的回退只认字面量 `auto`，显式指定时不再回退（cuda 不会撞 D3D 那个坑）。

**`6` = 产物已存在（2026-09-30 新增）**：ffmpeg 的 `-n` 在输出已存在时打印
`File already exists. Exiting.` 却**返回 0**，于是「一个字节都没转」被当成成功 ——
批量跑（`convert_from_list_*`）时尤其隐蔽。两族现在都在动手前先看一眼产物，
由 `FF_ON_EXIST` 决定：`skip`（默认，明确打印 SKIPPED，退出码仍为 `0`，保住断点
续转的语义）/ `overwrite`（换成 `-y` 真的重转）/ `fail`（打印并返回 `6`）。
`.sh` 侧在 `ff_run` 里统一处理（`fail` 必须 `exit 6` 而不是 `return 6`，否则入口
那道 `if [ $? -ne 0 ]; then exit 1; fi` 会把 `6` 抹成 `1`）；`.bat` 侧由
`lib/common.bat` 的 `:on_exist` 导出 `FF_OUT_FLAG` / `FF_EXIST_SKIP` / `FF_EXIST_FAIL`，
入口据此 `exit /b 6` 或直接跳过。

**「编码失败 = 1」是两族共同语义**（`.sh` 入口一直是 `exit 1`；`.bat` 入口在
2026-09-17 之前以无条件 `exit /b 0` 收尾、吞掉失败，同日修为 `exit /b 1`）。
注意 Windows 上 ffmpeg **自己**返回的是负码（`-40`/`-22`/`-2`…，见 §4 第 6 条），
入口负责把它归一成 `1` 再传出去：**契约里不存在负码**，调用方只判「非零」。
因此清单 wrapper 必须 **fail-fast**：`.sh` 的 `run_list` 与 `.bat` wrapper
都在第一个失败条目处中止并传回 `1`，不再跑完整份清单还报成功。

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

> **当前基线（2026-09-28）**：`lint 31 PASS / 0 FAIL / 5 WARN`、`selftest 56 cases / 0 FAIL`
> （用例增长史：38 → 40（L07 加固）→ 49（新增 L23）→ 51（L16 增加两条：编码类残留
> `-map 0:v` 必须被抓、remux 被改成 `-map 0:V` 必须被抓 —— 2026-09-28 封面图事故，
> 详见 `environment_matrix.md` 第 51 条）→ **56**（L16 再加五条：两族编码类漏映射封面、
> 编码类带未加作用域的 `-profile:v`、库里的封面映射字面量被删、以及一条 precision ——
> 同日晚些时候用户追加要求「有封面的尽可能保留」，详见第 52/53 条）。
> 「哪台机器能跑哪个入口」「哪个构建带哪些编码器/vmaf」的权威表格见
> **[`capability_matrix.md`](capability_matrix.md)**（含 A/B/C/D 全机、B 机三套 ffmpeg 构建、
> 编码/解码两个维度、已验证/未验证标注）。

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

SKIP 的 4 条全为正当硬件/平台 SKIP：T2/T14（无 N 卡）、T15（Gen9.5 无 AV1 QSV）、T7（cp65001 是 Windows 特性）。
（旧版此处列到 T20；`ffmpeg_hevc_nvenc_cygwin.*` 已于 2026-09-30 合并进 `ffmpeg_hevc_nvenc.*`，
**T20 随之撤销**，覆盖与 T2 重合，故不再计入 —— 见 §3 的 T20 行。）

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
（2026-09-30 后续：`ffmpeg_hevc_nvenc_cygwin.sh` 已合并进 `ffmpeg_hevc_nvenc.sh`，
T20 随之撤销 —— 实测两版解码路径完全相同，覆盖与 T2 重合。）

### 6.5 待人工补跑

`.bat` 侧套件无法在本环境的自动化通道里执行（cmd.exe 的输出拿不到），
需要手工双击验证：`test\bat\smoke_all.bat`（或 `smoke_ffmpeg.bat`）与
`test\bat\check_env.bat`。需要重点看的是本轮新增的部分：

* **T23**（新增：清单条目缺失必须在那一刻中止，两族共享）；
* **`soft_pair_calib.bat`**（新增：拖一部片上去；首次会下 10s 样本，离线设 `SKIP_DOWNLOAD=1`）；
* **`check_env.bat /probe`**（本机预期：`av1_qsv` → `PROBE-FAIL rc=1 | Conversion failed!`
  —— 入口现在把 ffmpeg 的负码 `-40` 归一成契约里的 `1`，`run.log` 里仍能看到原始的
  `ERRORLEVEL:-40`；其余 `PROBE-OK out=…B`；表尾还有 `filt libvmaf : yes`）；
* ~~**失败守卫的运行时实证**~~ ✅ **2026-09-29 已实证**（原为「本轮最重要的待验项」：`.bat` 侧的 `if not "%FB_RC%"=="0"` 从未在真机跑过一次，静态 + lint 只能证明形状对）：拿 `ffmpeg_dvd_hevc.bat` 在**无章节**的 title 上跑 `SPLIT_CHAPTER=2`，part2 必然失败 —— ffmpeg 返回 **-1094995529**，日志打出 `Convert failed! rc=-1094995529` 且进程 `exit /b 1`（`if errorlevel 1` 是带符号比较，看不见这个负数）。详见 `code_review_report.md` 同日条目；原建议的验证路径（无 AV1 硬编的机器上跑 `ffmpeg_av1_qsv.bat`，期望 `Convert failed! rc=-40`）仍然有效。
* **拖一部含多音轨的 mkv 上 `ffmpeg_copy_to_mp4.bat`**：除了音轨数要对得上，
  还要确认 moov 前置 —— 用 `ffprobe -v trace` 看原子顺序是 `ftyp` → **`moov`** → `mdat`；
* **`probe_source` 合并探测的运行时实证**（本轮新增）：拖一部普通片源上任意编码入口
  （如 `ffmpeg_libx265.bat`），窗口的探测段应照旧打出
  `SRC_CODEC / SRC_FRAMERATE / SRC_W / SRC_H / SRC_PIX / SRC_SIZE / SRC_DURATION / SRC_BITRATE / TARGET_BITRATE`
  且数值与改造前一致；再拖一个**纯音频文件**，应报
  `[check_isvideo] … 不是视频文件` 并退出（探测段不再执行）；
* T1/T2/T3/T7/T14 的 `[SKIP]` 行是否只在**真的没有硬件**时出现；
* `gate_*.log` 是否生成、内容是否指向硬件缺失而非脚本错误。

---

### 6.6 全机能力矩阵（2026-09-17，含 B 机三套 ffmpeg 构建）

权威表格见 **[`capability_matrix.md`](capability_matrix.md)**，这里只记结论：

| 事项 | 结果 |
|------|------|
| A 机 `--probe`（4.4.2 + `/opt` master） | `ok=10 / fail=5` —— 5 个 FAIL 全是 CUDA/AV1 系（无 N 卡、Gen9.5 无 AV1 编） |
| C 机 `--probe`（同上） | `ok=11 / fail=4` —— **`ffmpeg_av1_qsv.sh` 在 C 机是 `PROBE-OK`**（Arrow Lake 有 AV1 硬编） |
| B 机三套 ffmpeg 构建 | 原生 gyan full **全能力**（含 libvmaf）；MSYS2 8.1 有全部软编/硬编但**无 libvmaf**；Cygwin 7.1.1 **无 libx264/libx265**、QSV 真编一律 `MFX session: -9`、无 VAAPI（详见矩阵） |
| 同一台机器的环境差异 | `cmd` / 系统自带 shell / Git Bash → 原生 gyan；MSYS2 shell → `/mingw64/bin/ffmpeg` 8.1；Cygwin shell → `/usr/bin/ffmpeg` 7.1.1。**换个 shell 就换个 ffmpeg** |
| `check_env` 新增 | 两族都打印 `filt libvmaf : yes/NO`（calib 族硬依赖）；bat 深测失败行附 `run.log` 末条错误，与 sh 侧呈现对齐 |

> 本轮 A/C 的验证方式：本地未推送（用户手动 push），故用 `tar` 打包当前工作树经 SFTP 投到
> `/tmp/fbgit` 后真跑，不是 `git pull` 来的。打包必须带 `--exclude` —— 仓库根目录有 4.3 GB
> 被 `.gitignore` 忽略的测试片（`*.mp4`/`*.mov`），不排除会把包撑到 4.5 GB 并传断。

### 6.7 四环境全量检测 + 真素材（2026-09-30）

| 环境 | 回归套件 | 元字符矩阵 | DVD 工具链（`tools/` 五个脚本） |
|---|---|---|---|
| Windows cmd（`smoke_all.bat` → `smoke_ffmpeg.bat` / `smoke_special_chars.bat`） | **PASS=15 / SKIP=2**（T15 本机无 AV1 QSV；T11 报 UTF-8 清单 fixture 缺失，待补） | 全 PASS（A01–A20 / C81–C83 / Z…） | 无 `.bat` 孪生（`tools/` 只有 `.sh`） |
| Cygwin64 | PASS=21 FAIL=0 SKIP=4 | PASS=28 SKIP=1 | PASS=22 SKIP=0 |
| MINGW64（MSYS2，需显式 `MSYSTEM=MINGW64` + `PATH=/mingw64/bin:/usr/bin:/bin`） | PASS=21 FAIL=0 SKIP=4 | PASS=28 SKIP=1 | PASS=22 SKIP=0 |
| WSL Ubuntu-22.04 | 三套 `rc=0` | 同套 | PASS=22 SKIP=0 |
| Linux `192.168.31.246`（i7-9700T / UHD 630，ffmpeg master `N-117740`） | PASS=21 FAIL=0 SKIP=4 | PASS=28 SKIP=0 | PASS=22（首轮经非交互 ssh 跑时误报过一次「缺 dvdauthor」，复跑正常 —— `/usr/bin` 里三个工具都在） |

真素材（`H:\Downloads` 的 x265 10bit 剧集、仓库 `input_*.mov`、中高艺 DVD ISO）：

- 完整剧集（路径含中文 + 方括号 + 逗号 + 空格）拖 `ffmpeg_libx264.bat`：端到端 **308 MB** 产物，命令行装配正确；
- 切 40 s 片段（文件名 `真 素材 [A&B] (测试).mkv`，hevc + ac3 + ass 字幕）跑 6 个 `.bat` 入口：
  `libx265` / `hevc_qsv` / `hevc_nvenc` / `av1_nvenc` / `copy_to_mp4` 全 rc=0，**`avc_qsv` rc=1、产物 0 字节**（见下）；
- ISO：`H:\Downloads\中高艺\中高艺丝袜视频DVD系列\DVD001(Canndy)\DVD001(Canndy).iso`（3.4 GB，中文路径 + 括号）
  走 `ffmpeg_dvd_hevc.bat`：预览识别到正片 720x576 / 1682 s，`APPLY=1` 端到端出片
  （title1 182 MB、title2 224 MB，speed 25x）。盘本身带 `libdvdread: CHECK_VALUE failed`
  警告，不影响出片。

**本轮实质缺陷：10bit 源的三个缺口（两族同症状）**

| 缺口 | 根因（实测原话） | 修法 |
|---|---|---|
| ① H.264 **High 10** 源 + QSV 三入口（`avc` / `hevc` / `av1_qsv`） | `Codec h264 profile 110 not supported for hardware decode.` —— 卡在**解码**侧，硬解挂掉后 10bit 帧退回系统内存，编码器要硬件表面 → `Impossible to convert ... auto_scale_0` → rc=1 / 0 字节 | 认出这种源就**不加 `-hwaccel`**：软解 + `-vf format=nv12,hwupload=extra_hw_frames=64` |
| ② 10bit 源 + VAAPI 两入口（`h264` / `hevc_vaapi`） | 同上的 High 10 解码问题 **+** `hevc_vaapi` 写死 `-profile:v:0 main`（Main 不吃 10bit 输入） | High 10 源同上走软解 + `hwupload`；其余 10bit 保留硬解，加 `scale_vaapi=format=nv12` |
| ③ `av1_qsv` 在本机无 AV1 硬件 | `Current codec type is unsupported` → rc=-40，跑到底只留 0 字节产物 | 入口先用 1 帧 lavfi 源试开编码器，开不起来直接说明并退出，**不产生空产物** |

① 与 ② 里的"编码器不吃 10bit"（HEVC Main10 那种）是**另一回事**，修法是硬件内降 8bit
（`scale_qsv` / `scale_vaapi=format=nv12`）；软滤镜 `format=nv12` 不行 —— 帧还在硬件表面，
`auto_scale` 接不上（`Impossible to convert ... auto_scale_0`）。

**素材**：10bit 与 4K 六种源由 `test/make_fixtures.sh` 造（`bash test/make_fixtures.sh [all|10bit|4k|4k60|4k25|<文件名>]`），
均含 ac3 音轨 + ass 字幕；产物 `input_*.mkv` 被 `.gitignore` 忽略，**入库的只有那个脚本**。
修完的矩阵（Windows UHD 770 + N 卡 / Linux UHD 630）：

| 入口 | hevc 10bit | h264 10bit | 8bit |
|---|---|---|---|
| `avc_qsv` / `hevc_qsv`（bat + sh） | ✅ rc=0 | ✅ rc=0（修前 rc=69/1） | ✅ 命令行一字不改 |
| `h264_vaapi` / `hevc_vaapi` | ✅ rc=0 | ✅ rc=0（修前 rc=1 / 0 字节） | ✅ |
| `av1_qsv` | 无硬件 → 明说并退出 | 同左 | 同左 |
只在探到 10bit 时插入：8bit 源回归实测命令行里 `scale_qsv` 出现 **0 次**（一字未改）。
`.bat` 侧的探测必须走临时文件 + `set /p`，不能用 `for /f in('...')` —— 文件名里的
`(` `)` 会被 cmd 当语法，实测探测直接落空（修的就是这一版）。

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
9. **带缓存的工具，缓存键必须覆盖所有影响结果的参数**（2026-09-20，用户报障「为什么建议
   码率不一样」）。两族都有复用守卫（`if [ ! -f "$out" ]` / `if not exist "%OUT%"`），
   而守卫只问「文件在不在」：先前一次 **2 秒段** 的测试产物躺在同一个工作目录里，之后的
   **30 秒段** 运行照用不误，表头却印着 `seg 30s` —— 同一片源上 sh 报 1783203 bps、
   bat 报 2039817 bps，差的 30% 全部来自那批旧产物（把 bat 的 30s 数据喂给 sh 的拟合器，
   结果 ~2125739 bps，与 bat 的离散选点只差约 3%）。现在两族工作目录都带参数指纹
   `s<ss>t<len>_<W>x<H>_T<T>_<源字节数>`：参数一变就换目录，旧产物不可能被读到，目录名本身
   也是「这批产物是怎么来的」的记录。**新增任何带缓存的工具都照此办理。**
10. **Cygwin 不给原生 exe 改写参数里的 POSIX 路径**（2026-09-20 实测）。同一个 gyan full
    构建、同一条路径：MSYS2 里 `/f/👍…/x.mp4` 能打开，Cygwin 里 `/cygdrive/f/👍…/x.mp4`
    报 `No such file or directory` —— **纯 ASCII 的 `/cygdrive/c/…` 同样失败**，所以与非
    ASCII 字符无关。修正：`lib/common.sh` 的 **`native_path()`** 用 `cygpath -m` 换成
    `X:/…` 混合写法（三个 shell 都认），并由 **`ff_run()` / `fp_run()`** 包装所有会读写文件
    的 ffmpeg/ffprobe 调用（规则：参数以 `/` 开头就当路径改写；过滤串、`-map`、数字原样传递）。
    **新写的 sh 工具不要用 `"$FF"` / `"$FP"` 直接碰文件**，走这两个包装。仍用直接调用的：
    `smoke_ffmpeg.sh` / `smoke_special_chars.sh` / `check_env.sh`（MSYS2/Linux 由运行时改写
    所以可用，Cygwin 下会失败，待补）。
11. **「原生 exe」与「shell 自己那一份」不是一回事，挑外部程序时要挑对**（2026-09-29 实测，
    `tools/dvd_restore.sh` 打一张 991 MB 的 DVD）。Cygwin 的 PATH 上常有 WinCDEmu 自带的
    `mkisofs.exe` —— 它是**原生** Windows 程序，于是
    `mkisofs -dvd-video … /cygdrive/h/…/VIDEO_TS` 直接 `Invalid node`，中文路径还变成乱码；
    而同一台机器上的 `/usr/bin/genisoimage`（Cygwin 侧构建）一次就过。**MSYS2 不受影响**
    （它替原生子进程改写 argv），于是同一条命令 MINGW64 能跑、Cygwin 不能 —— 又是
    「换个 shell 换个世界」。修法已落在 `lib/common.sh`：
    * `pick_mkisofs()`：Cygwin 下优先挑 `/cygdrive/` 之外的那一份；`MKISOFS=/path` 可强制指定；
    * `mkisofs_path()`：只有「Cygwin + 候选在 `/cygdrive/` 下」时才把路径换成 `X:/...`；
    * 纯 Linux 两条分支**都不进** —— 仍是 `mkisofs` 优先、路径原样，行为与改造前一致。

    同一个坑在 ffmpeg 上的对应物是 `ff_run` / `fp_run`：**新写的脚本不要裸调
    `"$FF"` / `"$FP"`**。    `tools/dvd_repair.sh` 原先有 8 处裸调 ffprobe + 1 处裸调 ffmpeg，
    已全部改走 `fp_run` / `ff_run`；实测 Cygwin 下给同一份 DVD 探流，裸 POSIX 路径 `rc=1`，
    走 `fp_run` 改写后 `rc=0`。`tools/dvd_shrink.sh` 一开始就用对了，所以它没有这个毛病。
12. **Windows 上造 DVD 测试素材只能跑到第 ① 步**（`tools/dvd_make_sample.sh`，2026-09-29
    实测）。它四步走完才是一张完整的盘，而**这在 Windows 上做不到，两个 shell 缺的还不一样**：

    | 步骤 | Cygwin64 | MSYS2 MINGW64 |
    |------|----------|---------------|
    | ① 合成 MPEG-2 PS（`-target pal-dvd`） | ✅ | ✅ |
    | ② `dvdauthor` 建 VIDEO_TS | ❌ 没装 | ❌ 没装 |
    | ③ `dvd_restore.sh` 打 ISO | ⚠️ 有 `/usr/bin/genisoimage` | ❌ 打包器一个都没有 |
    | ④ 回读校验（`-f dvdvideo`） | ❌ 无 `dvdvideo` 解复用器 | ❌ 同左 |

    所以在这台机器上验证就加 `NO_VIDEOTS=1`（只跑第 ① 步，两个 shell 都通过，
    产物 `mpeg2video 720x576@25/1 DAR=4:3 / ac3 48000Hz 2ch`）；**要跑完整四步得回 Ubuntu**。
    两个环境都提供不了 `dvdauthor`（`pacman -Ss dvdauthor` 空、`cygcheck -p dvdauthor`
    = 0 matches），MINGW64 连 `mkisofs` / `genisoimage` / `xorriso` 全都没有 —— 就算装上
    dvdauthor，第 ③ 步也会停在 `找不到 mkisofs / genisoimage`。Cygwin 是这台机器上更接近
    能跑通的那个：它有 shell 侧的 `genisoimage`，而 PATH 上那个 WinCDEmu 的原生
    `mkisofs.exe` 会被 `pick_mkisofs` 正确跳过（见第 11 条）。

    这一轮顺带修掉的四处，全都是**只在 Windows 上才露出来**的：

    * **`drawtext` 的值必须转义冒号**（`ff_esc()`）。两处值自带冒号：MSYS2 的 `fc-match`
      给的是 `C:/Windows/fonts\msyh.ttc`（盘符冒号，还混着反斜杠），静态标签的
      `scene 1  0:00:10.00` 时间码也是。不转义的话 ffmpeg 从第一个冒号处把值切断，
      报 `No option name near '...'` 然后整条滤镜链 `Error: Invalid argument` ——
      MINGW64 与「Cygwin + 原生 ffmpeg」两边都死在这。**这处与平台无关**：本机 Linux 上
      一直没撞见，只是因为那份构建没有 drawtext、`LABEL` 直接关掉了。修法是新增的
      `ff_esc()`：先把值里的反斜杠统一成正斜杠，再把冒号 `:` 转成 `\:`；
      `%{pts\:hms}` 那处本来就有转义，**别对它再转一次**（会变成 `\\:`）。
    * **原生 exe 的 ffprobe 输出 CRLF**。字段值末尾会挂一个 `\r`，于是
      `"25/1\r"` 与 `"25/1"` 不相等 —— 素材打印出来看着**完全合规**，却照样被判
      「不合规」（Cygwin + 原生 ffmpeg 实测）。与 `lib/common.sh` 里 `probe_source`
      的 `${raw//$'\r'/}` 同款处理。
    * **`du` 要 `LC_ALL=C`**。中文 locale 下合计行是「总用量」不是 `total`，
      `awk '/total/'` 匹配不到 → 「素材体积」那行是空的。
    * **`$FF` / `$FP` 要走 `ff_run` / `fp_run`**（第 10 条）。这个脚本是那批跨平台修改
      **之前**新增的，漏了这一层；回读那个"另一个 ffprobe"（挑带 `dvdvideo` 的那个）
      同理走 `_ff_native_exec`。另外 `MPGS` 从空格拼的串改成数组、`pick_dvd_ff` 里
      PATH 遍历加了引号 —— 输出目录带空格时（`C:\Program Files\...` 就是）前者会被
      切成几段，报出来的错完全看不出是路径问题。
