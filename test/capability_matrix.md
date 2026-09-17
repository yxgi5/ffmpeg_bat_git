# 能力矩阵：环境 × ffmpeg 构建 × 编解码器

> 最后更新 **2026-09-17**。数据来源：B 机（本机）三套构建实测、A/C 机 SSH 实测、
> Pi 4B 早期实测。姊妹文档：`test/README.md`（测试体系）、`environment_matrix.md`（环境事实条目）。

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
| **A**（4.4.2 默认 + /opt 自前置） | 10 | 5 | `av1_nvenc`, `av1_qsv`, `hevc_nvenc`, `hevc_nvenc_cygwin`, `convert_from_list_cuda`（全 CUDA/AV1 系） |
| **C**（同上） | 11 | 4 | 同上减 `av1_qsv` —— **C 的 av1_qsv 是 PROBE-OK** |
| **B**（bat 族，原生 gyan） | 12 探针全过（改判产物后 av1_qsv 转为 PROBE-FAIL） | 0 | 见 §6 说明 |

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

  → `bench_calib` / `soft_pair_calib` / `nvenc_pair_calib` **只能**在原生 gyan full 或 `/opt` master 下跑。
  `check_env` 两种模式现在都会打印 `filt libvmaf : yes/NO`，别再靠猜。

## 6. 未验证 / 待补清单（诚实记录）

| 项 | 状态 | 说明 |
|----|------|------|
| B 机 **Ubuntu 22.04 侧** | ⏳ 未验证 | 双系统，待用户切换后补测（sh 族 + NVENC/VAAPI/QSV） |
| C 机 `av1_qsv` 真实片源 | ⚠️ 仅探针 | 3s 320×240 探针 PROBE-OK；真实 1080p/4K 迁移率与质量待测 |
| B 机 bat 族探针新逻辑 | ⏳ 待双击 | 探针改判产物 + 回显原因行，需用户复跑 `/probe` 确认 |
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
| `ffmpeg_av1_qsv.sh/.bat` | Arrow Lake 或更新 | **仅 C** |
| `ffmpeg_hevc_nvenc.sh/.bat` | NVIDIA | **仅 B** |
| `ffmpeg_av1_nvenc.sh/.bat` | Ada (RTX 40) 或更新 | **仅 B** |
| `ffmpeg_h264_vaapi.sh` / `hevc_vaapi.sh` | Linux + `/dev/dri` | A / C |
| `ffmpeg_hevc_nvenc_cygwin.sh` | Cygwin + NVIDIA | B（Cygwin shell） |
| `ffmpeg_copy_to_mp4.*` / `repack_from_list.*` | 只要 ffmpeg/ffprobe | 全部 |
| `bench_calib.*` / `soft_pair_calib.*` / `nvenc_pair_calib.*` | **libvmaf** | B（原生 gyan）/ A、C（`/opt` master） |
