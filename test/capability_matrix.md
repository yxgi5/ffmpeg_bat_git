# 能力矩阵：环境 × ffmpeg 构建 × 编解码器

> 最后更新 **2026-09-30**。数据来源：B 机（本机）三套构建实测、A/C 机 SSH 实测、
> Pi 4B 早期实测。姊妹文档：`test/README.md`（测试体系）、`environment_matrix.md`（环境事实条目）。
>
> 正文含两批晚于上次修订日期的更新：**2026-09-20**（Cygwin 路径改写、`find_ffmpeg` 能力筛选）与
> **2026-09-28**（编码类封面保留、位图字幕闸门）。2026-09-30 起入口清单以仓库根目录为准
> （`ffmpeg_hevc_nvenc_cygwin.*` 已合并进 `ffmpeg_hevc_nvenc.*`，见 §8）。

## 0. 状态图例

| 标记 | 含义 | 判据 |
|------|------|------|
| ✅ **实测可用** | 真跑出片 / 真解码 | 3s 320×240 真编，或真解码一片；rc 与错误首行都留档 |
| ❌ **实测不可用** | 真跑失败 | 附错误首行 |
| ⚠️ 编入未验证 | `-encoders` 列出但没真跑 | **本仓库不采信**：`-h encoder=X` 对不存在的编码器也返回 0 |
| — 未编入 | 该构建根本没有这个编码器/滤镜 | 编译期决定，改不了 |
| 🅿️ 仅 /opt | 默认构建没有，靠入口脚本自前置 `/opt` 才可用 | 见 §5 |

**核心原则**：静态清单只能回答「这个 ffmpeg 有没有编进去」，答不了「这台机器跑不跑得动」。
唯一精确判据是真跑一遍（`check_env --probe` / `check_env.bat /probe`）。

## 1. 机器清单

| 机 | CPU + GPU | OS | 关键事实 |
|----|-----------|----|----------|
| **A** | i7-9700T (8c) + **UHD 630 (Gen9.5)** | Ubuntu 22.04.1 | 无独显；`/dev/dri/renderD128`；`andy` 在 `render`/`video` 组 → 硬编不需 sudo |
| **B** | i9-13900HX + **RTX 4080 Laptop (Ada)** + Intel iGPU (Raptor Lake) | Win11（可切 Ubuntu 22.04 双系统） | 本机 `LAPTOP-MECHREVO`；NVENC 双编码器、会话上限 12 |
| **C** | **Ultra 7 265K (Arrow Lake)** + Xe iGPU | Ubuntu 22.04 | 无 NVIDIA；**目前唯一 AV1 硬编可用**的机器 |
| **D** | Raspberry Pi 4B (BCM2711) | Raspberry Pi OS (4.19) | 只有 H.264 编码单元；`h264_v4l2m2m` 可用 |

## 2. B 机：同一台机器，三种 shell → 三个不同的 ffmpeg ★本轮实测

| 环境 | `which ffmpeg` | 版本 | 备注 |
|------|----------------|------|------|
| `cmd.exe` / PowerShell | `C:\Program Files\ffmpeg\bin\ffmpeg.exe` | 2025-05-01-git-707c04fe06 (**gyan full**) | **bat 族入口在此环境跑** |
| Git Bash | `/c/Program Files/ffmpeg/bin/ffmpeg` | 同上（原生构建） | agent/沙箱所在环境 |
| **MSYS2 MINGW64** | `/mingw64/bin/ffmpeg` | **8.1** | sh 族入口在 MSYS2 下会用**这个**构建 |
| **Cygwin** | `/usr/bin/ffmpeg` | **7.1.1** | **没有 libx264/libx265** → 软编入口在 Cygwin 下不可用 |

> 这条最容易被忽略：同一台机器，换个 shell 就换了个 ffmpeg，能力表跟着变。
> 在 Cygwin 里跑 `ffmpeg_libx264.sh` 会直接失败（该构建未编入 x264）。
>
> **同一台机器，三种 shell 对「路径」的处理也不同（2026-09-20 实测）**：把 POSIX 路径交给
> **原生** `ffmpeg.exe` / `ffprobe.exe`，只有 MSYS2 会替你改写成 Windows 形式。
>
> | 交给原生 ffmpeg 的写法 | MSYS2 | Cygwin | Git Bash |
> |---|---|---|---|
> | `/f/…`（MSYS 系）/ `/cygdrive/f/…`（Cygwin） | ✅ 自动改写 | ❌ `No such file or directory` | ⚠️ 本沙箱不改写（真机 Git for Windows 默认会改写） |
> | `F:/…`（混合写法） | ✅ | ✅ | ✅ |
> | `F:\…`（反斜杠） | ✅ | ✅ | ✅ |
>
> 连**纯 ASCII** 路径也一样（`/cygdrive/c/…` 失败、`C:/…` 成功），所以这不是非 ASCII 字符
> 的问题，而是 Cygwin 不给原生子进程改写 argv。仓库的应对：`lib/common.sh` 的
> **`native_path()`**（`cygpath -m` → `X:/…`）与 **`ff_run()` / `fp_run()`** 包装，
> 三个 `*calib*` 工具已全部走包装。

## 3. 编码能力矩阵

### 3.1 B 机三构建（2026-09-17 实测）

| 构建 | 版本 | libx264 | libx265 | libsvtav1 | libaom-av1 | librav1e | **libvmaf** | h264/hevc/av1<br>NVENC | h264/hevc<br>QSV | av1_qsv | VAAPI |
|------|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 原生 gyan full | 2025-05-01-git | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ ✅ ✅ | ✅ ✅ | ❌ `Current codec type is unsupported` | ❌ 编入无设备 |
| MSYS2 mingw64 | 8.1 | ✅ | ✅ | ✅ | ✅ | ✅ | — 未编入 | ✅ ✅ ✅ | ✅ ✅ | ❌ 同上 | ❌ 编入无设备 |
| **Cygwin** | 7.1.1 | **— 未编入** | **— 未编入** | ✅ | ✅ | — | — 未编入 | ✅ ✅ ✅ | ❌ `Error creating a MFX session: -9` | ❌ MFX -9 | — 未编入 |

**Cygwin 三问的答案（用户存疑项，已核实）**：
* QSV **编码不可用** —— 编码器列得出来，真编一律 `Error creating a MFX session: -9`。可以按「Cygwin 略过 QSV」处理。
* VAAPI **不可用** —— 未编入（`Unknown encoder 'h264_vaapi'`）。
* 但 **NVENC 可用**（h264/hevc/av1 全通过），所以在 Cygwin 里只有 NVENC + 软件 AV1（libsvtav1/libaom）这条组合。

### 3.2 全机对照

| 机器 | h264_nvenc | hevc_nvenc | av1_nvenc | h264_qsv | hevc_qsv | av1_qsv | h264_vaapi | hevc_vaapi | 软编 x264/x265 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **A** UHD630 | ❌ 无 N 卡 | ❌ | ❌ | ✅ | ✅ | ❌ 编入但 Gen9.5 无 AV1 编 | ✅ | ✅ | ✅ |
| **B** 4080L | ✅ | ✅ | ✅ Ada | ✅ | ✅ | ❌ Raptor Lake iGPU 无 AV1 编 | ❌ Win 无 VAAPI | ❌ | ✅ |
| **C** Ultra 7 265K | ❌ 无 N 卡 | ❌ | ❌ | ✅ | ✅ | **✅ Arrow Lake** | ✅ | ✅ | ✅ |
| **D** Pi 4B | — | — | — | — | — | — | — | — | ✅（+ `h264_v4l2m2m` ✅） |

* 「❌ 编入但硬件不支持」和「— 未编入」是两回事：前者换台机器就能用（如 av1_qsv 到 C 机即 ✅），后者得换构建。
* AV1 硬编路线：**B 机走 NVENC（Ada）**，**C 机走 QSV（Arrow Lake）**，A/B 的 Intel 核显都太老。
* 软件 AV1：三套 Windows 构建都有 `libsvtav1`；A/C 的 `/opt` master 另有 `libaom-av1` / `librav1e`。

### 3.3 仓库入口 × 环境 实测结果（`check_env --probe`，3s 片）

| 机器 | ok | fail | 失败者 |
|------|:--:|:--:|--------|
| **A**（4.4.2 默认 + /opt 自前置） | 10 | 4 | `av1_nvenc`, `av1_qsv`, `hevc_nvenc`, `convert_from_list_cuda`（全 CUDA/AV1 系）。旧版此行 5 项含 `hevc_nvenc_cygwin`，该入口 2026-09-30 已合并进 `ffmpeg_hevc_nvenc.*` |
| **C**（同上） | 11 | 3 | 同上减 `av1_qsv` —— **C 的 av1_qsv 是 PROBE-OK**（旧版记 4 项，含已合并的 `hevc_nvenc_cygwin`） |
| **B**（bat 族，原生 gyan） | 12 探针全过（`av1_qsv` **2026-09-30 改判为硬件缺失**：入口返回 **4**、不落 0 字节产物；旧记作 PROBE-FAIL） | 0 | 见 §6 说明 |

## 4. 解码能力矩阵（B 机三构建）

| 构建 | 软件解码 h264/hevc | NVDEC（`-hwaccel cuda`） | QSV 硬解 |
|------|:---:|:---:|:---:|
| 原生 gyan full | ✅ | ✅ `Selecting decoder 'h264' because of requested hwaccel method cuda` | ✅ |
| MSYS2 8.1 | ✅ | ✅ 同上 | ✅ |
| Cygwin 7.1.1 | ✅ | ✅（走老 cuvid 路径：`Selecting decoder 'h264_cuvid'`） | ❌ rc=171 |

**判「是否真硬解」看日志不看耗时**：`Selecting decoder ... because of requested hwaccel method` /
`h264_cuvid` / `pixfmt` 才是证据。A 机 4.4.2 的 `-hwaccel qsv` 会**静默回退软解**（不报错），必须看日志。

## 5. `/opt` 软偏好与工具依赖

* 三个 sh 入口（`ffmpeg_av1_qsv.sh`、`ffmpeg_av1_nvenc.sh`、`ffmpeg_hevc_vaapi.sh`）会
  **自前置 `/opt/ffmpeg/*/bin`**（若存在），因为 Ubuntu 22.04 默认 ffmpeg 4.4.2 太老。
  实测有效：A/C 的 `ffmpeg_av1_qsv.sh` 用的就是 `/opt` master（N-117740），不是 4.4.2。
* **libvmaf 分布**（决定 calib 族能不能跑）：

  | 构建 | libvmaf |
  |------|:---:|
  | B 原生 gyan full | ✅ |
  | B MSYS2 8.1 | ❌ 未编入 |
  | B Cygwin 7.1.1 | ❌ 未编入 |
  | A/C `/opt` master | ✅ |
  | A/C 默认 4.4.2 | ❌ |

  → `bench_calib` / `soft_pair_calib` / `nvenc_pair_calib` **只能**在原生 gyan full 或 `/opt` master 下跑（`.sh` 侧现在会自己找到它，见下条）。
  `check_env` 两种模式现在都会打印 `filt libvmaf : yes/NO`，别再靠猜。
* **两族现在都会自己挑一个"够用"的构建（2026-09-20）**：上面这张 shell → ffmpeg 的错位表，
  过去只写在文档里，工具本身并不知道 —— 于是 MSYS2 用户跑 sh 侧 calib 必然得到
  `no libvmaf filter`，而机器上明明装着 gyan full。现在：
  * `.sh`：`lib/common.sh` 的 **`find_ffmpeg [--need-filter <名>] [--need-encoder <名>]`**
    按 `FFMPEG_BIN/FFMPEG > 仓库内 ffmpeg/bin > PATH 的每一项 > 常见前缀` 逐级找，**跳过**不含所需能力的
    候选（跳过的每个都会在标准错误里说明"缺少什么"）；显式指定的 `FFMPEG_BIN`/`FFMPEG` 若不够用，
    只报错、不换别的构建。
    * PATH 必须**逐项遍历**：`command -v ffmpeg` 只给第一个命中，而本机 PATH 首位恰好就是没 libvmaf 的那个
      —— 后面能用的构建永远轮不到。
    * 常见前缀由 `cygpath` 生成（`C:\Program Files\ffmpeg\bin` → `/c/...` 或 `/cygdrive/c/...`）。
      **硬写 `/c/...` 在 Cygwin 必然落空**：Cygwin 没有 `/c` 挂载点（只有 `/cygdrive/c`，另有 `/proc/cygdrive`），
      而 MSYS2 没有 `/cygdrive` —— 这就是「同一条命令在 MSYS2 报 `ERROR: source video not found`、
      在 Cygwin 报 `ERROR: no ffmpeg with the libvmaf filter was found`」的直接原因（两个报错都各错一半）。
    * `normalize_source_path <路径>`（`lib/common.sh`）让 calib 族**直接吃 Windows 路径**
      （`F:\dir\file.mp4`），有 `cygpath` 才转 POSIX、没有则原样返回（纯函数，可安全用于纯 Linux）；
      源文件检查失败时会打印 `tried: [...]`，不再让人猜"这条 shell 到底收到了什么"。
    * `find_ffprobe <ffmpeg>` 取同目录的 ffprobe（尊重 `FFPROBE`），`ffmpeg_build_id` 打版本串。
  * `.bat`：**没有能力筛选**（2026-09-20 当天加过 `:ff_satisfies` + 第 3 参数，同日**整体回退**）。
    回退原因：`:ff_satisfies` 写成 `"%1\ffmpeg.exe"`，而调用方传进来的是**已带引号**的 `%FFBIN%`
    → 展开成 `""C:\Program Files\ffmpeg\bin"\ffmpeg.exe"` → cmd 取首 token 得到**空程序名** →
    报 `'' is not recognized…`，又被该行尾部的 `2>nul` 吞掉 → **每个候选都被判"缺少能力"**。
    何况本机 ffmpeg 不在 PATH 上，走的是 `C:\Program Files\ffmpeg\bin` 兜底，这道门对本机毫无作用。
    开发沙箱跑不了 `cmd.exe`（Bash / PowerShell 两条路都被硬拦），盲改不划算 —— 于是 `:find_ffmpeg`
    回到 `环境变量 > 仓库内 ffmpeg\bin > PATH(where) > C:\Program Files\ffmpeg\bin`。
    写法陷阱已固化为 lint **L21**（引号里不得再嵌参数展开）。
  * 灰度对照（本机，2026-09-20 实测）：`/mingw64/bin/ffmpeg`(8.1) 无 libvmaf、Cygwin 7.1.1 无 libvmaf、
    `C:\Program Files\ffmpeg\bin`(gyan full 2025-05-01) 有 libvmaf —— sh 侧定位器会跳过前两个并落到第三个
    （`[find_ffmpeg] 跳过 … 缺少 filter:libvmaf`）。已实证：MSYS2 与 Cygwin **两个真实运行时**都选中了它
    （分别是 `/c/Program Files/ffmpeg/bin/ffmpeg` 与 `/cygdrive/c/Program Files/ffmpeg/bin/ffmpeg`）。

## 6. 未验证 / 待补清单（诚实记录）

| 项 | 状态 | 说明 |
|----|------|------|
| B 机 **Ubuntu 22.04 侧** | ⏳ 未验证 | 双系统，待用户切换后补测（sh 族 + NVENC/VAAPI/QSV） |
| C 机 `av1_qsv` 真实片源 | ⚠️ 仅探针 | 3s 320×240 探针 PROBE-OK；真实 1080p/4K 迁移率与质量待测 |
| B 机 bat 族探针新逻辑 | 🟡 部分确认 | 探针改判产物 + 回显原因行。**2026-09-30 已由 `ffmpeg_av1_qsv.bat` 实测确认**（返回 4、无产物、原因行明确）；其余入口仍需用户复跑 `/probe` |
| Cygwin 下 sh 族入口整体 | ⏳ 未系统验证 | 已知：软编入口不可用（无 x264/x265）、QSV 不可用、NVENC 可用 |
| D 机（Pi 4B）本仓库工具 | ⏳ 未补测 | 早期只测过 `h264_v4l2m2m` 硬编与 check_env 误报修复 |
| Windows 侧 VAAPI | ❌ 不适用 | VAAPI 是 Linux 内核 API，Windows 无设备，无需再验 |

## 7. 复现命令

```bash
# B 机：三套构建的编码器清单 + 真编（320x240x3s → null，不落盘）
FF="C:/Program Files/ffmpeg/bin/ffmpeg.exe"     # 换成 cygwin / msys64 的路径同理
"$FF" -hide_banner -encoders | grep -E 'libx264|hevc_nvenc|av1_qsv|libvmaf'
"$FF" -hide_banner -filters  | grep libvmaf
"$FF" -hide_banner -loglevel error -y -i clip.mp4 -c:v av1_qsv -f null -   # rc≠0 即不可用

# B 机：三种 shell 各解析到哪个 ffmpeg
D:/cygwin64/bin/bash.exe -lc 'which ffmpeg && ffmpeg -version | head -1'
D:/msys64/usr/bin/bash.exe -lc 'which ffmpeg && ffmpeg -version | head -1'

# 硬解证据（看日志，别看耗时）
"$FF" -hide_banner -loglevel verbose -hwaccel cuda -i clip_h264.mp4 -f null - 2>&1 | grep -i "Selecting decoder"

# A/C 机（Linux）：仓库自带的两套探针
bash test/sh/check_env.sh --probe        # 精确判据：真跑每个入口
bash test/sh/check_env.sh                # 秒级静态预筛
```

## 8. 与入口脚本的对应关系

| 入口 | 需要的条件 | 本矩阵中可跑的机器 |
|------|-----------|-------------------|
| `ffmpeg_libx264.sh/.bat` | libx264 | 除 Cygwin 7.1.1 外全部 |
| `ffmpeg_libx265.sh/.bat` | libx265 | 除 Cygwin 7.1.1 外全部 |
| `ffmpeg_avc_qsv.sh/.bat` | Intel GPU + QSV | A / B / C |
| `ffmpeg_hevc_qsv.sh/.bat` | Intel GPU + QSV | A / B / C |
| `ffmpeg_av1_qsv.sh/.bat` | Arrow Lake 或更新；**不满足时入口返回 4（硬件缺失）并中止清单、不落 0 字节文件** | **仅 C** |
| `ffmpeg_hevc_nvenc.sh/.bat` | NVIDIA | **仅 B** |
| `ffmpeg_av1_nvenc.sh/.bat` | Ada (RTX 40) 或更新 | **仅 B** |
| `ffmpeg_h264_vaapi.sh` / `hevc_vaapi.sh` | Linux + `/dev/dri` | A / C |
| `ffmpeg_dvd_hevc.bat` / `.sh` | DVD-Video 源（ISO / `VIDEO_TS` / 光驱）+ ffmpeg 带 `libdvdread`/`libdvdnav`（`dvdvideo` 解复用器），否则脚本报错退出 | 有 `dvdvideo` 的构建（本机 gyan full；A / C 的 `/opt` master） |
| `convert_from_list_{qsv,cuda,libx265}.*` | 清单 wrapper：能力取自被调入口；**被调入口返回 4（硬件缺失）时中止整份清单** | 同各自编码器 |
| `ffmpeg_copy_to_mp4.*` / `repack_from_list.*` | 只要 ffmpeg/ffprobe | 全部 |
| （全部 mp4 出口） | 带 `-map 0:a? -map 0:s? -c:s mov_text …`，多音轨/字幕不再被默认选流丢弃（lint L16 钉住）；**视频映射分两类**：编码类 `-map 0:V`（排除封面图等 attached picture，否则 mp4 装不下重编码后的封面 → 0 字节失败），remux 两族 `-map 0:v`（复制路径保留封面）；**封面保留（2026-09-28）**：编码类 `-c:v:0 <编码器>` 只编码主视频，配合 `-map 0:v:disp:attached_pic?` + **由 ffprobe 流表算出**的 `-c:v:<n> copy`（封面在输出侧的 per-type 下标 = [m, m+n)，m = 非封面视频路数；**写死槽位在 m≥2 时整体错位，会让整条转码 rc=127 写 0 字节**）把封面原样带进 mp4 的 `covr` atom（映射与复制同在 lib 变量里，一起开关；探测不可用时退回槽位 1、2）。`disp:` 说明符需 **ffmpeg 7.1+**；两族各有一个能力闸门，不认就只丢封面、不让编码失败。**注意**：早期版本用全局 `-c:v copy -c:v:0 <编码器>`，会和 `-c:v:0` 撞在同一条流上触发 `Multiple -codec` 警告，已废弃（lint L16 拦）。**位图字幕（2026-09-28）**：mp4 装不下 `hdmv_pgs_subtitle` / `dvd_subtitle`，一进 `-c:s mov_text` 就 EINVAL 写 0 字节；闸门按字幕的 per-type 下标发 `-map -0:s:<i>` 逐条排除（**不是** `-map -0:s`，那会把能救的 ass/subrip 一起丢），文本字幕照常转 mov_text。位图名单是黑名单（PGS / DVD / XSUB / DVB，来源封闭），漏列只会回到"跑失败"，不会静默丢字幕 | 全部 |
| `bench_calib.*` / `soft_pair_calib.*` / `nvenc_pair_calib.*` | **libvmaf** | B（原生 gyan）/ A、C（`/opt` master） |
