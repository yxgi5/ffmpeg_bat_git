# ffmpeg 编码环境×硬件 能力矩阵

**更新日期:** 2026-09-15
**维护说明:** 本矩阵随实测进度更新状态标记，每格状态必须有两类依据之一——本仓库会话实测记录，或 ffmpeg 构建清单（`-encoders`/`-hwaccels` 输出）。

## 状态图例

| 标记 | 含义 |
|:---:|------|
| ✅ | **已验证**：本仓库会话在目标环境实测通过 |
| 🟡 | **未验证**：预期可用（构建/硬件层面具备），待实测 |
| ❌ | **硬件不支持**：GPU/平台层面不可能实现 |
| 🚫 | **未编入**：该 ffmpeg 构建不含此功能 |
| ⛔ | **构建含但不可用**：编译进去了但运行时无法工作 |
| ➖ | **不适用**：该环境/机器组合下无此项 |

## 目标机器

| 代号 | 机器 | GPU | 备注 |
|:---:|------|-----|------|
| A | i7-9700T | UHD 630（核显） | 无独立显卡 |
| B | i9-13900HX + RTX 4080 Laptop | UHD Graphics（核显）+ Ada NVENC | **本机（当前开发机）** |
| C | Ultra 7 265K | Arrow Lake 核显 | AV1 编码验证平台（待引入） |

**目标 OS:** Windows 11 / Ubuntu 22.04
**目标环境:** linux bash、Windows cmd、Windows PowerShell、Cygwin64、MSYS2(MINGW64)
**Linux ffmpeg 来源:** 发行版原生（22.04 自带 4.4.2）、`/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl`（BtbN 新版构建）

---

## 表 1：机器硬件能力（与 ffmpeg 版本无关）

| 能力 | A: i7-9700T | B: 13900HX+4080L | C: Ultra 7 265K |
|------|:---:|:---:|:---:|
| NVENC h264/hevc 编码 | ➖ 无 N 卡 | ✅ 已验证（本会话） | ➖ 无 N 卡 |
| NVENC AV1 编码 | ➖ | 🟡 **Ada 硬件支持，可随时实测**（当前按计划暂缓） | ➖ |
| QSV h264/hevc 编码 | 🟡 硬件支持 | ✅ 已验证（本会话，核显 UHD） | 🟡 硬件支持 |
| QSV AV1 编码 | ❌ Gen9.5 无 AV1 编码 | ❌ Raptor Lake 核显无 AV1 编码 | 🟡 **硬件支持，AV1 验证就在这台** |
| VAAPI h264/hevc 编码（Linux） | 🟡 UHD630 由 iHD/i965 驱动支持 | 🟡 核显由 iHD 驱动支持 | 🟡 Xe 核显由 iHD 驱动支持 |
| AV1 硬解 | ❌ | 🟡 4080L + 核显均支持 AV1 解码 | 🟡 |

> 注：B 机 RTX 4080 Laptop 是 Ada 架构，**av1_nvenc 硬件上是支持的**（第 8 代 NVENC），如果需要提前铺 AV1 流水线，不必等 C 机，随时可在本机实测 av1_nvenc。

---

## 表 2：本机（B）Win11 三套 ffmpeg 构建实测矩阵 ✅=本会话已验证

| 构建项 | Cygwin 7.1.1<br>`/usr/bin` | MSYS2 MINGW64 8.1<br>`/mingw64/bin` | 原生 gyan 2025-05<br>`C:\Program Files` |
|------|:---:|:---:|:---:|
| ffprobe 输出行尾 | LF | **CRLF** ⚠️ | **CRLF** ⚠️ |
| libx264（软编 AVC） | 🚫 **未编入** | ✅ | ✅ |
| libx265（软编 HEVC） | 🚫 **未编入** | ✅ | ✅ |
| libsvtav1（软编 AV1） | 🟡 构建有 | ✅ | ✅ |
| libaom-av1（软编 AV1） | 🟡 构建有 | ✅ | ✅ |
| h264_nvenc / hevc_nvenc | ✅（含端到端） | ✅（含端到端） | ✅（含端到端） |
| av1_nvenc | 🟡 构建有 | 🟡 构建有 | 🟡 构建有 |
| h264_qsv / hevc_qsv | ⛔ **MFX 会话失败(-9)** | ✅ | ✅ |
| av1_qsv | ❌ 硬件不支持 + ⛔ 同上 | ❌ 硬件不支持 | ❌ 硬件不支持 |
| VAAPI | 🚫 **hwaccel 未编入** | ⛔ Windows 无 VAAPI 后端 | ⛔ Windows 无 VAAPI 后端 |
| 重构版 .sh 端到端 | ✅ hevc_nvenc | ✅ hevc_nvenc + libx265 + libx264 | ✅ hevc_nvenc + libx265 + libx264 |

**本机已验证事实记录（2026-09-15）：**
- Cygwin QSV 失败根因：链接 `cygvpl-2.dll`（oneVPL 调度器）但找不到 GPU 运行时实现 → MFX session -9。**结论：Cygwin 上放弃 QSV，只跑 NVENC 和软编（无 x264/x265）。**
- **Cygwin 不支持 vaapi 的答案：不支持**。其 ffmpeg 的 `-hwaccels` 清单只有 `cuda dxva2 qsv d3d11va d3d12va`，没有编入 vaapi；且 vaapi 依赖 Linux 内核 DRM + libva 栈，Cygwin 上即使编入也无设备可用。
- mingw64 与原生 ffprobe 输出 CRLF——**旧脚本在此环境下 SRC_PIX 会算术失败、永远命中首行码率**，重构版 `lib/common.sh` 已统一剥 `\r` 修复。
- MSYS2 `usr/bin` 无 ffmpeg/ffprobe，MINGW64 子环境才有。
- 原生 ffprobe 不认 `/c/...` 路径，只认 `C:/...`；路径风格必须与所用 ffmpeg 配套。

---

## 表 3：全目标平台总矩阵（机器 × OS/环境 × ffmpeg 来源）

功能列说明：**NV**=NVENC(h264/hevc)，**NV-A1**=NVENC AV1，**QS**=QSV(h264/hevc)，**QS-A1**=QSV AV1，**VA**=VAAPI(h264/hevc)，**x264/x265**=软编 AVC/HEVC，**AV1软**=libsvtav1/libaom，**.sh**=bash 脚本路线，**.bat**=cmd 脚本路线

### 机器 A：i7-9700T（UHD 630，无 N 卡）

| OS | 环境 | ffmpeg 来源 | NV | NV-A1 | QS | QS-A1 | VA | x264/x265 | AV1软 | .sh | .bat |
|----|------|------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Win11 | cmd / PowerShell | 原生安装（待定版本） | ➖ | ➖ | 🟡 | ❌ | ❌ 无后端 | 🟡 | 🟡 | ➖ | 🟡 |
| Win11 | Cygwin64 | Cygwin 自带 7.1.1 | ➖ | ➖ | ⛔ | ❌ | 🚫 | 🚫 | 🟡 | 🟡 | ➖ |
| Win11 | MSYS2 MINGW64 | mingw64 8.1 | ➖ | ➖ | 🟡 | ❌ | ❌ | 🟡 | 🟡 | 🟡 | ➖ |
| Ubuntu 22.04 | bash | 原生 4.4.2 | ➖ | ➖ | 🟡 | ❌ | 🟡 | 🟡 | 🟡(4.4 较老, 视打包) | ✅ 模式已验证 | ➖ |
| Ubuntu 22.04 | bash | /opt/ ffmpeg-master-gpl | ➖ | ➖ | 🟡 | ❌ | 🟡 | 🟡 | 🟡 | ✅ 模式已验证 | ➖ |

> A 机主打 QSV + VAAPI + 软编保底；NVENC 列整体不适用。A 机 Win11 下 QSV 未验证——注意 A 机若用 Cygwin 一样会踩 QSV 失败和软编缺失两个坑，**A 机的软编保底必须走 mingw64/原生/Linux**。

### 机器 B：i9-13900HX + RTX 4080 Laptop（本机，当前开发机）

| OS | 环境 | ffmpeg 来源 | NV | NV-A1 | QS | QS-A1 | VA | x264/x265 | AV1软 | .sh | .bat |
|----|------|------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Win11 | cmd / PowerShell | 原生 gyan | ✅ | 🟡 | ✅ | ❌ | ❌ 无后端 | ✅ | ✅ | ➖ | 🟡 |
| Win11 | Cygwin64 | Cygwin 自带 7.1.1 | ✅ | 🟡 | ⛔ MFX-9 | ❌ | 🚫 | 🚫 | 🟡 | ✅ | ➖ |
| Win11 | MSYS2 MINGW64 | mingw64 8.1 | ✅ | 🟡 | ✅ | ❌ | ❌ 无后端 | ✅ | ✅ | ✅ | ➖ |
| Ubuntu 22.04 | bash | 原生 4.4.2 | 🟡 | 🟡 | 🟡 | ❌ | 🟡 | 🟡 | 🟡 | ✅ 模式 | ➖ |
| Ubuntu 22.04 | bash | /opt/ ffmpeg-master-gpl | 🟡 | 🟡 | 🟡 | ❌ | 🟡 | 🟡 | 🟡 | ✅ 模式 | ➖ |

> B 机是矩阵验证最充分的一台：NVENC 三环境通、QSV 双环境通（Cygwin 豁免）、软编双环境通。
> **cmd/PowerShell 行的 ✅ 指二进制本身**（ffmpeg.exe 直接调用已验证）；`.bat` 老脚本未重构，重构时需注意 LF-only 行尾坑。

### 机器 C：Ultra 7 265K（Arrow Lake 核显，AV1 验证平台，待引入）

| OS | 环境 | ffmpeg 来源 | NV | NV-A1 | QS | QS-A1 | VA | x264/x265 | AV1软 | .sh | .bat |
|----|------|------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Win11 | cmd / PowerShell | 原生安装 | ➖ | ➖ | 🟡 | 🟡 **AV1 实测目标** | ❌ 无后端 | 🟡 | 🟡 | ➖ | 🟡 |
| Win11 | Cygwin64 | Cygwin 自带 | ➖ | ➖ | ⛔ 预期同 7.1.1 构建限制 | 🚫 构建无 av1_qsv? | 🚫 | 🚫 | 🟡 | 🟡 | ➖ |
| Win11 | MSYS2 MINGW64 | mingw64 8.1 | ➖ | ➖ | 🟡 | 🟡 8.1 有 av1_qsv | ❌ | 🟡 | 🟡 | 🟡 | ➖ |
| Ubuntu 22.04 | bash | 原生 4.4.2 | ➖ | ➖ | 🟡 | 🟡 4.4 无 av1_qsv→❌ | 🟡 | 🟡 | 🟡 | ✅ 模式 | ➖ |
| Ubuntu 22.04 | bash | /opt/ ffmpeg-master-gpl | ➖ | ➖ | 🟡 | 🟡 **AV1 实测目标** | 🟡 | 🟡 | 🟡 | ✅ 模式 | ➖ |

> C 机是 **QSV AV1 编码的唯一硬件平台**，且用户注记：新版 ffmpeg（master-gpl 静态构建）在 Linux 上 QSV 可能开箱即用（构建含 QSV，运行时需 intel-media 驱动 + oneVPL/libmfx runtime），**待实际平台验证**。原生 4.4.2 太老没有 av1_qsv，AV1 的 QSV 验证应直接用 master-gpl 构建。

---

## 表 4：环境约束速查（写脚本时用）

| 环境 | 路径风格 | 自带 ffmpeg | 行尾输出(CR 剥除必要性) | VAAPI | QSV |
|------|---------|------------|:---:|:---:|:---:|
| linux bash | `/home/...` | 4.4.2 或 /opt/ master | LF（不剥也安全，但保留剥除无害） | 🟡 可用 | 🟡 待验证 |
| Windows cmd | `C:\...` | 依赖系统安装 | —（.bat 无此问题） | ❌ | 🟡 |
| Windows PowerShell | `C:\...` | 同上 | — | ❌ | 🟡 |
| Cygwin64 | `/cygdrive/c/...` | 7.1.1（功能残缺） | LF | 🚫 | ⛔ |
| MSYS2 MINGW64 | `/c/...` | 8.1 | **CRLF（必须剥）** | ❌ | ✅ |
| git-bash | `/c/...` | 无（用原生） | **CRLF（必须剥）** | ❌ | ✅ |

---

## 待验证清单（按优先级）

1. **本机 av1_nvenc 实测**（4080L Ada 硬件支持，不必等 C 机）——半小时能出结论
2. **C 机 Ultra 7 265K**：Win11 下 QSV AV1（mingw64 8.1 或原生）+ Linux 下 master-gpl 的 QSV/VAAPI/AV1
3. **A 机 i7-9700T**：Win11 QSV（UHD 630）+ Ubuntu VAAPI；确认软编保底走 mingw64/Linux
4. **Linux 双 ffmpeg 来源验证**：原生 4.4.2 的功能边界（av1_nvenc/svtav1 是否在打包内）vs master-gpl 全家桶
5. **.bat 路线**：cmd/PowerShell 下重构（重构版脚本目前只有 .sh）
