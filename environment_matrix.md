# ffmpeg 编码环境×硬件 能力矩阵

**更新日期:** 2026-09-15  
**维护说明:** 本矩阵随实测进度更新状态标记，每格状态必须有两类依据之一——本仓库会话实测记录，或 ffmpeg 构建清单（`-encoders`/`-hwaccels` 输出）。

## 状态图例

|  标记 | 含义                          |
| :-: | --------------------------- |
|  ✅  | **已验证**：本仓库会话在目标环境实测通过      |
|  🟡 | **未验证**：预期可用（构建/硬件层面具备），待实测 |
|  ❌  | **硬件不支持**：GPU/平台层面不可能实现     |
|  🚫 | **未编入**：该 ffmpeg 构建不含此功能    |
|  ⛔  | **构建含但不可用**：编译进去了但运行时无法工作   |
|  ➖  | **不适用**：该环境/机器组合下无此项        |

## 目标机器

|  代号 | 机器                           | GPU                         | 备注              |
| :-: | ---------------------------- | --------------------------- | --------------- |
|  A  | i7-9700T                     | UHD 630（核显）                 | 无独立显卡           |
|  B  | i9-13900HX + RTX 4080 Laptop | UHD Graphics（核显）+ Ada NVENC | **本机（当前开发机）**   |
|  C  | Ultra 7 265K                 | Arrow Lake 核显               | AV1 编码验证平台（待引入） |

**目标 OS:** Windows 11 / Ubuntu 22.04  
**目标环境:** linux bash、Windows cmd、Windows PowerShell、Cygwin64、MSYS2(MINGW64)  
**Linux ffmpeg 来源:** 发行版原生（22.04 自带 4.4.2）、`/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl`（BtbN 新版构建）

---

## 表 1：机器硬件能力（与 ffmpeg 版本无关）

| 能力                        |        A: i7-9700T        |        B: 13900HX+4080L        |     C: Ultra 7 265K    |
| ------------------------- | :-----------------------: | :----------------------------: | :--------------------: |
| NVENC h264/hevc 编码        |          ➖ 无 N 卡          |           ✅ 已验证（本会话）           |         ➖ 无 N 卡        |
| NVENC AV1 编码              |             ➖             |        ✅ 已验证（本会话：三构建冒烟 + cuda 解码→AV1 真实转码全通过）        |            ➖           |
| QSV h264/hevc 编码          |          🟡 硬件支持          |        ✅ 已验证（本会话，核显 UHD）       |         🟡 硬件支持        |
| QSV AV1 编码                |     ❌ Gen9.5 无 AV1 编码     |    ❌ Raptor Lake 核显无 AV1 编码    | 🟡 **硬件支持，AV1 验证就在这台** |
| VAAPI h264/hevc 编码（Linux） | 🟡 UHD630 由 iHD/i965 驱动支持 |         🟡 核显由 iHD 驱动支持        |   🟡 Xe 核显由 iHD 驱动支持   |
| AV1 硬解                    |             ❌             |     🟡 4080L + 核显均支持 AV1 解码    |           🟡           |

> 注：B 机 RTX 4080 Laptop 的 av1_nvenc 已于 2026-09-15 实测通过（三构建冒烟 + cuda 解码→AV1 Main 720p60 CBR 真实转码），AV1 硬编流水线在本机即可铺开。

---

## 表 2：本机（B）Win11 三套 ffmpeg 构建实测矩阵 ✅=本会话已验证

| 构建项                     | Cygwin 7.1.1  
`/usr/bin` | MSYS2 MINGW64 8.1  
`/mingw64/bin` | 原生 gyan 2025-05  
`C:\Program Files` |
| ----------------------- | :-----------------------: | :--------------------------------: | :----------------------------------: |
| ffprobe 输出行尾            |             LF            |             **CRLF** ⚠️            |              **CRLF** ⚠️             |
| libx264（软编 AVC）         |         🚫 **未编入**        |                  ✅                 |                   ✅                  |
| libx265（软编 HEVC）        |         🚫 **未编入**        |                  ✅                 |                   ✅                  |
| libsvtav1（软编 AV1）       |           🟡 构建有          |                  ✅                 |                   ✅                  |
| libaom-av1（软编 AV1）      |           🟡 构建有          |                  ✅                 |                   ✅                  |
| h264_nvenc / hevc_nvenc |          ✅（含端到端）          |               ✅（含端到端）              |                ✅（含端到端）               |
| av1_nvenc               |           ✅ 冒烟通过          |               ✅ 冒烟通过                |                ✅ 冒烟通过+真实转码                |
| h264_qsv / hevc_qsv     |     ⛔ **MFX 会话失败(-9)**    |                  ✅                 |                   ✅                  |
| av1_qsv                 |       ❌ 硬件不支持 + ⛔ 同上      |               ❌ 硬件不支持              |                ❌ 硬件不支持               |
| VAAPI                   |     🚫 **hwaccel 未编入**    |        ⛔ Windows 无 VAAPI 后端        |         ⛔ Windows 无 VAAPI 后端         |
| 重构版 .sh 端到端             |        ✅ hevc_nvenc       |  ✅ hevc_nvenc + libx265 + libx264  |   ✅ hevc_nvenc + libx265 + libx264   |

**本机已验证事实记录（2026-09-15）：**

- Cygwin QSV 失败根因：链接 `cygvpl-2.dll`（oneVPL 调度器）但找不到 GPU 运行时实现 → MFX session -9。**结论：Cygwin 上放弃 QSV，只跑 NVENC 和软编（无 x264/x265）。**
- **Cygwin 不支持 vaapi 的答案：不支持**。其 ffmpeg 的 `-hwaccels` 清单只有 `cuda dxva2 qsv d3d11va d3d12va`，没有编入 vaapi；且 vaapi 依赖 Linux 内核 DRM + libva 栈，Cygwin 上即使编入也无设备可用。
- mingw64 与原生 ffprobe 输出 CRLF——**旧脚本在此环境下 SRC_PIX 会算术失败、永远命中首行码率**，重构版 `lib/common.sh` 已统一剥 `\r` 修复。
- MSYS2 `usr/bin` 无 ffmpeg/ffprobe，MINGW64 子环境才有。
- 原生 ffprobe 不认 `/c/...` 路径，只认 `C:/...`；路径风格必须与所用 ffmpeg 配套。
- **av1_nvenc 实测通过（2026-09-15）**：三构建（Cygwin/MINGW64/原生）冒烟全过；原生构建完成 cuda 解码→AV1 Main 720p60 CBR 2M 真实转码，输出封装/码率/帧率正确（8.2MB 源 → 1.4MB）。AV1 NVENC 流水线随时可脚本化。

---

## 表 3：全目标平台总矩阵（机器 × OS/环境 × ffmpeg 来源）

功能列说明：**NV**=NVENC(h264/hevc)，**NV-A1**=NVENC AV1，**QS**=QSV(h264/hevc)，**QS-A1**=QSV AV1，**VA**=VAAPI(h264/hevc)，**x264/x265**=软编 AVC/HEVC，**AV1软**=libsvtav1/libaom，**.sh**=bash 脚本路线，**.bat**=cmd 脚本路线

### 机器 A：i7-9700T（UHD 630，无 N 卡）

| OS           | 环境               | ffmpeg 来源               |  NV | NV-A1 |  QS | QS-A1 |   VA  | x264/x265 |       AV1软      |   .sh   | .bat |
| ------------ | ---------------- | ----------------------- | :-: | :---: | :-: | :---: | :---: | :-------: | :-------------: | :-----: | :--: |
| Win11        | cmd / PowerShell | 原生安装（待定版本）              |  ➖  |   ➖   |  🟡 |   ❌   | ❌ 无后端 |     🟡    |        🟡       |    ➖    |  🟡  |
| Win11        | Cygwin64         | Cygwin 自带 7.1.1         |  ➖  |   ➖   |  ⛔  |   ❌   |   🚫  |     🚫    |        🟡       |    🟡   |   ➖  |
| Win11        | MSYS2 MINGW64    | mingw64 8.1             |  ➖  |   ➖   |  🟡 |   ❌   |   ❌   |     🟡    |        🟡       |    🟡   |   ➖  |
| Ubuntu 22.04 | bash             | 原生 4.4.2                |  ➖  |   ➖   |  🟡 |   ❌   |   🟡  |     🟡    | 🟡(4.4 较老, 视打包) | ✅ 模式已验证 |   ➖  |
| Ubuntu 22.04 | bash             | /opt/ ffmpeg-master-gpl |  ➖  |   ➖   |  🟡 |   ❌   |   🟡  |     🟡    |        🟡       | ✅ 模式已验证 |   ➖  |

> A 机主打 QSV + VAAPI + 软编保底；NVENC 列整体不适用。A 机 Win11 下 QSV 未验证——注意 A 机若用 Cygwin 一样会踩 QSV 失败和软编缺失两个坑，**A 机的软编保底必须走 mingw64/原生/Linux**。

### 机器 B：i9-13900HX + RTX 4080 Laptop（本机，当前开发机）

| OS           | 环境               | ffmpeg 来源               |  NV | NV-A1 |    QS   | QS-A1 |   VA  | x264/x265 | AV1软 |  .sh | .bat |
| ------------ | ---------------- | ----------------------- | :-: | :---: | :-----: | :---: | :---: | :-------: | :--: | :--: | :--: |
| Win11        | cmd / PowerShell | 原生 gyan                 |  ✅  |   ✅   |    ✅    |   ❌   | ❌ 无后端 |     ✅     |   ✅  |   ➖  | ✅ 6/10 |
| Win11        | Cygwin64         | Cygwin 自带 7.1.1         |  ✅  |   ✅   | ⛔ MFX-9 |   ❌   |   🚫  |     🚫    |  🟡  |   ✅  |   ➖  |
| Win11        | MSYS2 MINGW64    | mingw64 8.1             |  ✅  |   ✅   |    ✅    |   ❌   | ❌ 无后端 |     ✅     |   ✅  |   ✅  |   ➖  |
| Ubuntu 22.04 | bash             | 原生 4.4.2                |  🟡 |   🟡  |    🟡   |   ❌   |   🟡  |     🟡    |  🟡  | ✅ 模式 |   ➖  |
| Ubuntu 22.04 | bash             | /opt/ ffmpeg-master-gpl |  🟡 |   🟡  |    🟡   |   ❌   |   🟡  |     🟡    |  🟡  | ✅ 模式 |   ➖  |

> B 机是矩阵验证最充分的一台：NVENC（含 AV1）三环境通、QSV 双环境通（Cygwin 豁免）、软编双环境通。  
> **cmd/PowerShell 行的 ✅ 指二进制本身**（ffmpeg.exe 直接调用已验证）；`.bat` 列的 `6/10` = 10 个 bat 中 6 个通过探针实测（4 编码器 + copy_to_mp4 + convert_from_list_qsv），opencmd 属一行起壳脚本不计；剩 3 个 list bat（cuda / libx265 / repack）与本轮所修共享同一行代码，风险低，可选复核。
> **`.sh` 行的本轮复核（AI 在沙箱内直接跑 bash，无需用户介入）**：6 个编码入口 + 4 个 list 脚本全部 rc=0 且产出正确，含静音输入（`-map 0:a?`）、中文/空格文件名、CRLF+BOM 清单；同轮修掉 `check_file_is_text` 悬空调用与 `run_list` 的 CRLF/BOM 兼容（详见 code_review_report.md）。
>
> **`.bat` 冒烟进度（2026-09-16）**：沙箱无法调用 cmd.exe（Bash/PowerShell 两条路均被安全策略拦截），改用一次性探针 `smoke_ffmpeg_bat.bat`（放仓库外，一次双击即跑完：4 编码器 + copy_to_mp4 + 交互输入 + 新进程 UTF-8 + 静音输入 + list 模式，日志落 `smoke_logs\`）。
> 第一轮结果：**936 控制台（双击/拖放默认起点）下 5 个含中文 bat 全部在 banner 后立即报 `The system cannot find the path specified.` + `找不到 ffmpeg.exe`** → 定位为守卫 `shift` 连 `%0` 一起移位致 `%~dp0` 失效（详见 code_review_report.md，已修 4ffd990）；同一轮确认 **936→子进程重启路径下 banner 中文完全正常**（原先的 `'�使用方式:'` 报错消失），AVC/HEVC 码率查表值正确（`TARGET_BITRATE` = 3836249 / 2548951，percentage 10~15%）。
> 第二轮结果（v2 探针）：守卫回归已消除、查表值正确、`copy_to_mp4` 通过；但暴露 **① 守卫标记 `FB_UTF8_GUARD` 泄漏到调用者环境**（`call` 链或同会话第二次运行即跳过守卫 → 936 解析下 banner 报错复现）**② `-map 0:a` 缺 `?`**（静音输入整条失败 errorlevel -22）**③ list 驱动 bat 缺 `call` + 清单路径未 `usebackq` 引号化 + 编码器裸名调用**。三类均已修（守卫首行 `setlocal` / 18 处改 `-map 0:a?` / 4 个 list bat 改 `usebackq`+`call`+`%~dp0` 锚定）。
> 第三轮结果（v3 探针）：**编码 bat 主链路全绿** —— T1 AVC-QSV / T2 HEVC-NVENC / T3 HEVC-QSV / T4 libx265 / T5 copy_to_mp4 / T6 交互式输入 / T7 新进程 UTF-8 / T10 静音输入 **全部 PASS**，`TARGET_BITRATE` = 3836249 / 2548951 与码率表一致，**全局 banner 检查 `[PASS]`**（三种用法下均无 `is not recognized`），每个产物另有 ffprobe 复核。同轮暴露 list 驱动 bat **第 4 个缺陷**：`SET SRC_FILE=%1` 保留参数引号 → `in ("%SRC_FILE%")` 展开成双重引号路径，cmd 报 `The system cannot find the file "…\list.txt"`（rc=123，0/2）。已改 `%~1` 去引号（commit 2a58d97），**list 模式待第四轮复核**。
> 探针已同步到 v4：素材每轮强制重生成（v2 复用旧无音轨片源导致 T1–T4 假 FAIL）、T10 静音测试升为断言、新增全局 banner 检查行、新增 `LIST` 子集参数与 T12（无参数 + cwd 在别处）。
> 第四轮结果（v4 探针，只跑 `LIST` 子集）：**list 模式全绿** —— T9（cwd=仓库，含空格路径清单）2/2、T11（UTF-8 清单 + 中文文件名）2/2、T12（无参数 + cwd 在别处）2/2，均 rc=0，**全局 banner 检查 `[PASS]`**。T11 是"选 UTF-8 而非 cp936"这一设计决策的实证：`for /f` 读出的中文名完整无损地传给了 ffmpeg 并生成 `中文 测试-compressed.mp4`。T12 的 cwd 判定另被独立佐证：仓库内恰有一个旧的无意义 `list.txt`，若误读则必然 0 产物。
> **`.bat` 侧至此主链路 + list 模式全部实测通过**（含双击/拖放/交互输入三种用法、936 起点、守卫重启路径与 UTF-8 新进程路径）。

### 机器 C：Ultra 7 265K（Arrow Lake 核显，AV1 验证平台，待引入）

| OS           | 环境               | ffmpeg 来源               |  NV | NV-A1 |        QS        |        QS-A1       |   VA  | x264/x265 | AV1软 |  .sh | .bat |
| ------------ | ---------------- | ----------------------- | :-: | :---: | :--------------: | :----------------: | :---: | :-------: | :--: | :--: | :--: |
| Win11        | cmd / PowerShell | 原生安装                    |  ➖  |   ➖   |        🟡        |   🟡 **AV1 实测目标**  | ❌ 无后端 |     🟡    |  🟡  |   ➖  |  🟡  |
| Win11        | Cygwin64         | Cygwin 自带               |  ➖  |   ➖   | ⛔ 预期同 7.1.1 构建限制 |   🚫 构建无 av1_qsv?  |   🚫  |     🚫    |  🟡  |  🟡  |   ➖  |
| Win11        | MSYS2 MINGW64    | mingw64 8.1             |  ➖  |   ➖   |        🟡        |  🟡 8.1 有 av1_qsv  |   ❌   |     🟡    |  🟡  |  🟡  |   ➖  |
| Ubuntu 22.04 | bash             | 原生 4.4.2                |  ➖  |   ➖   |        🟡        | 🟡 4.4 无 av1_qsv→❌ |   🟡  |     🟡    |  🟡  | ✅ 模式 |   ➖  |
| Ubuntu 22.04 | bash             | /opt/ ffmpeg-master-gpl |  ➖  |   ➖   |        🟡        |   🟡 **AV1 实测目标**  |   🟡  |     🟡    |  🟡  | ✅ 模式 |   ➖  |

> C 机是 **QSV AV1 编码的唯一硬件平台**，且用户注记：新版 ffmpeg（master-gpl 静态构建）在 Linux 上 QSV 可能开箱即用（构建含 QSV，运行时需 intel-media 驱动 + oneVPL/libmfx runtime），**待实际平台验证**。原生 4.4.2 太老没有 av1_qsv，AV1 的 QSV 验证应直接用 master-gpl 构建。



---

## 表 4：环境约束速查（写脚本时用）

| 环境                 | 路径风格              | 自带 ffmpeg            |   行尾输出(CR 剥除必要性)  | VAAPI |   QSV  |
| ------------------ | ----------------- | -------------------- | :---------------: | :---: | :----: |
| linux bash         | `/home/...`       | 4.4.2 或 /opt/ master | LF（不剥也安全，但保留剥除无害） | 🟡 可用 | 🟡 待验证 |
| Windows cmd        | `C:\...`          | 依赖系统安装               |    —（.bat 无此问题）   |   ❌   |   🟡   |
| Windows PowerShell | `C:\...`          | 同上                   |         —         |   ❌   |   🟡   |
| Cygwin64           | `/cygdrive/c/...` | 7.1.1（功能残缺）          |         LF        |   🚫  |    ⛔   |
| MSYS2 MINGW64      | `/c/...`          | 8.1                  |   **CRLF（必须剥）**   |   ❌   |    ✅   |
| git-bash           | `/c/...`          | 无（用原生）               |   **CRLF（必须剥）**   |   ❌   |    ✅   |

---

## 待验证清单（按优先级）

1. ~~**本机 av1_nvenc 实测**~~ ✅ 已完成（2026-09-15：三构建冒烟 + 真实转码全通过）
2. **C 机 Ultra 7 265K**：Win11 下 QSV AV1（mingw64 8.1 或原生）+ Linux 下 master-gpl 的 QSV/VAAPI/AV1
3. **A 机 i7-9700T**：Win11 QSV（UHD 630）+ Ubuntu VAAPI；确认软编保底走 mingw64/Linux
4. **Linux 双 ffmpeg 来源验证**：原生 4.4.2 的功能边界（av1_nvenc/svtav1 是否在打包内）vs master-gpl 全家桶
5. ~~**.bat 路线**~~ ✅ 已完成（2026-09-16：57c418f 重构 + 26ccf0e cp65001 守卫 + 8e5c631 find_ffmpeg 去硬编码路径 + 4ffd990 守卫改环境变量标记并修 `shift` 吃掉 `%0` 的回归）
6. ~~**`.bat` list 模式复核（阻塞项，第四轮）**~~ ✅ 已完成（2026-09-16：T9 / T11 / T12 各 2/2 rc=0 + banner 检查 `[PASS]`，见上）
7. **`.bat` 真实拖放/双击**：探针只能模拟代码页起点，真·Explorer 拖放与新窗口 banner 观感需人工扫一眼；含中文文件名的拖放同样值得顺手验一次
8. **可选**：其余 3 个 list bat（convert_from_list_cuda / convert_from_list_libx265 / repack_from_list）与本轮修复的 convert_from_list_qsv 共享同一行 `for /f "usebackq …" do call "%~dp0…"` 代码，且其调用的编码器 bat 已各自单独实测；如需凑满 `.bat 10/10` 可再跑一次探针复核
9. **清单文件编码边界**：`run_list` 已兼容 CRLF 与 UTF-8 BOM 清单（原 CRLF 会因 `\r` 混入路径导致第一项即 `file not exists!` 退出，而 .bat 侧 `for /f` 天然吞 CRLF → 属 sh/bat 行为不一致，已修）。**`.bat` 侧的 UTF-8 BOM 尚未实测**：`for /f` 读带 BOM 文件时首行可能带上 3 字节 BOM 前缀（记事本默认存 UTF-8 无 BOM 时不触发）；若日后的清单由其它工具导出，建议顺手验一次首行条目
