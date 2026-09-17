# ffmpeg 编码环境×硬件 能力矩阵

**更新日期:** 2026-09-16  
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
| QSV h264/hevc 编码          |     ✅ 已验证（2026-09-16 A 机 Ubuntu 22.04）     |        ✅ 已验证（本会话，核显 UHD）       |    ✅ 已验证（2026-09-16 Linux 双构建）     |
| QSV AV1 编码                |     ❌ Gen9.5 无 AV1 编码     |    ❌ Raptor Lake 核显无 AV1 编码    | ✅ 已验证（2026-09-16 Linux master 构建，1080p/4K） |
| VAAPI h264/hevc 编码（Linux） | ✅ 已验证（2026-09-16 A 机 Ubuntu 22.04：**h264/hevc 双通，4.4.2 亦可**） |         🟡 核显由 iHD 驱动支持        | ✅ h264 全构建；hevc 需 5.1.2+/master（**4.4.x 全系 ⛔**，两轮实测） |
| AV1 硬解                    |             ❌             |     🟡 4080L + 核显均支持 AV1 解码    |    ✅ 已验证（QSV av1_qsv / VAAPI 解码）    |

> 注：B 机 RTX 4080 Laptop 的 av1_nvenc 已于 2026-09-15 实测通过（三构建冒烟 + cuda 解码→AV1 Main 720p60 CBR 真实转码），AV1 硬编流水线在本机即可铺开。
>
> 注：C 机 Linux 侧的整表实测已于 2026-09-16 完成（两套 ffmpeg 来源 × QSV/VAAPI/软编/硬解 + 全部 .sh 入口与 list 模式），详见下文「机器 C：Ubuntu 22.04 实测记录」；C 机 Win11 行仍为待验证。
>
> 注：**A 机 Linux 侧实测亦已于 2026-09-16 完成两轮**——第一轮发行版 4.4.2 单构建（全部 .sh 入口 × 三种用法 + list 全套，PASS=22/22）；**第二轮（同日下午）/opt master-gpl 到货后双构建复跑，仍 PASS=22/22**，并据此定位了「4.4.2 的 QSV 硬解是**静默回退软解**」这一此前只知其然的行为。详见下文「机器 A：Ubuntu 22.04 实测记录」；A 机 Win11 行仍为待验证。

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
| Ubuntu 22.04 | bash             | 原生 4.4.2                |  ➖  |   ➖   |  ✅ |   ❌   | ⛔ 编 ✅/硬解静默软解 |     ✅    | ❌ 仅 libaom(无 svtav1) | ✅ 22/22 端到端 |   ➖  |
| Ubuntu 22.04 | bash             | /opt/ ffmpeg-master-gpl |  ➖  |   ➖   |  ✅ |   ❌（Gen9.5 无 AV1 编码）  |   ✅  |    ✅    |  ✅ svtav1/aom  | ✅ 22/22 端到端 |   ➖  |

> A 机主打 QSV + VAAPI + 软编保底；NVENC 列整体不适用。A 机 Win11 下 QSV 未验证——注意 A 机若用 Cygwin 一样会踩 QSV 失败和软编缺失两个坑。
>
> **A 机 Ubuntu 实测修正（2026-09-16）**：① 发行版 4.4.2 **已含 `libx264`/`libx265`**，故「软编保底必须走 mingw64」对 Linux 侧不成立，**Linux 侧自足**（Win 侧仍未验证）；② QSV/VAAPI 编码在 4.4.2 上都 ✅，但 **QSV 硬解在 4.4.2 上不可用**（`-hwaccel qsv` **静默回退软解**、显式 `-hwaccel_device hw` 才报 `Device setup failed for decoder`，与 C 机一致）；③ **`/opt/ffmpeg` 已于 2026-09-16 下午安装**（master-gpl `N-117740`，与 C 机同一构建），双构建复跑 PASS=22/22，详见下文 ⑥；④ AV1 编解码在 Gen9.5 上**均不可用**（硬件本身不支持 AV1，master 构建里 `av1_qsv`/`av1_vaapi` 存在但打开编码器即失败）；⑤ VAAPI 硬解虽通但 **1.69s 慢于软解 0.66s**，不建议。

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
> **`.bat` 冒烟进度（2026-09-16）**：沙箱无法调用 cmd.exe（Bash 与命令行工具两条路均被安全策略拦截），改用一次性探针（现位于仓库内 `test/bat/smoke_ffmpeg.bat`〔原名 smoke_ffmpeg_bat.bat〕，一次双击即跑完：4 编码器 + copy_to_mp4 + 交互输入 + 新进程 UTF-8 + 静音输入 + list 模式，日志落 `smoke_logs\`）。
> 第一轮结果：**936 控制台（双击/拖放默认起点）下 5 个含中文 bat 全部在 banner 后立即报 `The system cannot find the path specified.` + `找不到 ffmpeg.exe`** → 定位为守卫 `shift` 连 `%0` 一起移位致 `%~dp0` 失效（详见 code_review_report.md，已修 4ffd990）；同一轮确认 **936→子进程重启路径下 banner 中文完全正常**（原先的 `'�使用方式:'` 报错消失），AVC/HEVC 码率查表值正确（`TARGET_BITRATE` = 3836249 / 2548951，percentage 10~15%）。
> 第二轮结果（v2 探针）：守卫回归已消除、查表值正确、`copy_to_mp4` 通过；但暴露 **① 守卫标记 `FB_UTF8_GUARD` 泄漏到调用者环境**（`call` 链或同会话第二次运行即跳过守卫 → 936 解析下 banner 报错复现）**② `-map 0:a` 缺 `?`**（静音输入整条失败 errorlevel -22）**③ list 驱动 bat 缺 `call` + 清单路径未 `usebackq` 引号化 + 编码器裸名调用**。三类均已修（守卫首行 `setlocal` / 18 处改 `-map 0:a?` / 4 个 list bat 改 `usebackq`+`call`+`%~dp0` 锚定）。
> 第三轮结果（v3 探针）：**编码 bat 主链路全绿** —— T1 AVC-QSV / T2 HEVC-NVENC / T3 HEVC-QSV / T4 libx265 / T5 copy_to_mp4 / T6 交互式输入 / T7 新进程 UTF-8 / T10 静音输入 **全部 PASS**，`TARGET_BITRATE` = 3836249 / 2548951 与码率表一致，**全局 banner 检查 `[PASS]`**（三种用法下均无 `is not recognized`），每个产物另有 ffprobe 复核。同轮暴露 list 驱动 bat **第 4 个缺陷**：`SET SRC_FILE=%1` 保留参数引号 → `in ("%SRC_FILE%")` 展开成双重引号路径，cmd 报 `The system cannot find the file "…\list.txt"`（rc=123，0/2）。已改 `%~1` 去引号（commit 2a58d97），**list 模式待第四轮复核**。
> 探针已同步到 v4：素材每轮强制重生成（v2 复用旧无音轨片源导致 T1–T4 假 FAIL）、T10 静音测试升为断言、新增全局 banner 检查行、新增 `LIST` 子集参数与 T12（无参数 + cwd 在别处）。
> 第四轮结果（v4 探针，只跑 `LIST` 子集）：**list 模式全绿** —— T9（cwd=仓库，含空格路径清单）2/2、T11（UTF-8 清单 + 中文文件名）2/2、T12（无参数 + cwd 在别处）2/2，均 rc=0，**全局 banner 检查 `[PASS]`**。T11 是"选 UTF-8 而非 cp936"这一设计决策的实证：`for /f` 读出的中文名完整无损地传给了 ffmpeg 并生成 `中文 测试-compressed.mp4`。T12 的 cwd 判定另被独立佐证：仓库内恰有一个旧的无意义 `list.txt`，若误读则必然 0 产物。
> **`.bat` 侧至此主链路 + list 模式全部实测通过**（含双击/拖放/交互输入三种用法、936 起点、守卫重启路径与 UTF-8 新进程路径）。
> **第五轮（v5 探针）✅ 已跑完全绿**：本轮改动 = ① 清理 `lib/common.bat` 里 14 行遗留调试 echo（`in extract()` / `%~dp2` / `%~d2` / `"%~n2"` / `%~x2` / `"%~n2-compressed.mp4"` / `in extract_mp4()` / `"%~n2.mp4"` / `!fpA!` / `!fpB!` / `numA / numB` / `ret=`），这些是原版就带的、每次转码都刷屏；② 新增 `lib/common.bat :check_isvideo`，把 `.sh` 侧早就有的 `check_file_isvideo` 前置校验补到 `.bat` 侧，接线于 **4 编码器 + copy_to_mp4**（后者放在 `suffix is not mp4` 早退之后），失败 `exit /b 3`。探针同步 v5：新增 **T13**（audio-only 输入必须被提前拒绝：日志含 `check_isvideo`、**不含** `matches no streams`〔证明根本没走到 ffmpeg〕、无产物、rc=3）与**全局 hygiene 行**（任一日志含 `in extract` / `ret=` 即 FAIL）。因改动落在共享库上，**本轮建议跑全量（不带第 2 参数）**。<br>**结果（2026-09-16 全量跑完）**：**T1–T13 全部 PASS** —— T13（audio-only 输入）被 `check_isvideo` 提前拦下（rc=3、日志含 `check_isvideo`、**无** `matches no streams`、无产物）；全局 `banner check` 与 `debug check` 双双 `[PASS]`（14 行调试 echo 清零后日志再无 `in extract` / `ret=`）；T9/T11/T12 list 三测 2/2 保持全绿。`TARGET_BITRATE` 仍为 3836249（AVC）/ 2548951（HEVC），与码率表一致。

> **第六轮（2026-09-16，路径元字符加固；分 6a / 6b 两步）**：起点是用户反馈**片库确有含 `&` 的片名**。**6a** 做了 5 类改动，但探针实测只 13/20 绿 —— 其中"删掉 `^&` 转义"与"把 `set` 改成包装写法"两项是**误判造成的回归**（原版 `^&` 是在补偿包装写法的不配对，不是缺陷）。**6b** 顺着 6a 的失败日志找到真正病根：**`set "VAR=值"` 包装写法要求「值里不能出现字面量引号」，而本仓库的 `RUN_COM`/`SRC_CODEC`/`SRC_FILE`/`TARGET_FILE` 存的正是带引号的路径或整条命令行** —— 值里第一个引号与包装引号配对闭合后，其后的路径段落落进"未加引号区"，`&` 断行、`( )` 触发 `was unexpected at this time`。修法：所有"值里会出现引号"的 `set` 改非包装写法 `set VAR=值`（引号配对平衡，`& ( ) ^` 全在引号内），并去掉不再需要的 `^&` 补偿（5 文件 57 行），每个脚本头部补「路径/命令行拼接规则」注释块。<br>**6a 中保留有效的部分**：`if [%1] neq []` / `SET SRC_FILE=%1` → `if not "%~1"==""` + `set "SRC_FILE=%~1"`；去掉 `call %RUN_COM%`（避免整条命令行二次 `%` 展开）；4 个 list 驱动 bat 的 `EnableDelayedExpansion` → `DisableDelayedExpansion`；编码器 `%SRC_RESOLUTION%` 移出延迟展开块。<br>**验证方式**：探针 `smoke_special_chars.bat`（仓库外、纯 ASCII + CRLF）—— **A** 19 个文件名字符用例（`&` `%` `!` `( )` `[ ]` `;` `,` `=` `#` `$` `+` `'` `~` `@` 外加 `A & B (2020)` / `Tora! Tora! Tora! (1970)` / `A&B!C(2) 100%` 与子目录 `sub & dir (x)`）走 `ffmpeg_copy_to_mp4`；**C** 3 个真实片名形状走 `ffmpeg_avc_qsv`；**B** `convert_from_list_qsv` 清单驱动 6 条含元字符条目；**D** 无参数模式（stdin，判定 PASS/SKIP/FAIL）；**Z** 构造微测（Z1 = 非包装 `set` 保住含 `& ( ) !` 的带引号值；Z2a/Z2b = `set /p` 读重定向 stdin 在"直接 call"与"经 cp65001 守卫 `cmd /c` 转发"下的差异）。A07（片名含脱字符）标 SKIP：`call` 二次解析会让 `^` 翻倍，探针无法既建同名文件又传参。<br>**静态复核**：`audit_set_forms2.py`（危险 `set` 形态）与 `mini_cmd_scan.py`（用最坏片名展开后逐行找"引号外元字符"，内置已知好/坏行自校准）全仓 0 命中（只剩 `endlocal & set …`、`set /a (…^)/…` 等刻意构造）。<br>**6b 实测结果（2026-09-16）**：A **18 PASS + 1 SKIP**、C **3/3**、B **6/6**、D **SKIP**、Z1 **PASS** —— 元字符片名已全程走通，`set` 写法修正生效。D 的 SKIP 机制**已由四路判别用例定论（2026-09-16）**：**元凶是 `chcp 65001` —— 它会把"文件重定向"的 stdin 读空（EOF），但管道与控制台不受影响**。证据矩阵（探针 part Z/D 同轮实测）：Z2d 守卫复刻 + 文件重定向 → 读到；**Z2e = Z2d + `chcp 65001` → 读空（唯一差异项）**；Z2f = Z2d + `for /f` 子进程 → 读到（排除 `find_ffmpeg`）；Z2g = Z2d + 块内 `set /p` → 读到（排除块语法）；D1 = 真实脚本 + 预置 `FFMPEG_BIN`（短路 `find_ffmpeg`、零子进程）→ 仍读空（与 Z2e 交叉印证）。管道不受影响的解释：管道是流式无"文件位置"概念，守卫子进程接力读也不冲突；文件重定向则依赖句柄位置，`chcp 65001` 切换控制台代码页后 cmd 对该句柄的读返回 EOF。**对真实用法零影响**：双击后手输 = 控制台设备（T 套件 mode-B T6/T7 实测通过）、拖放 = argv、管道 = 流式，三种入口全不受 `chcp 65001` 影响。**探针自身 bug**：写 Z1 判定行的 echo 句里有裸 `&`，把该行劈成两条命令 → `( was unexpected at this time` 致探针提前终止（首跑 summary 缺 Z1/Z2 判定行）；已改写并给 `mini_cmd_scan.py` 补上"只扫仓库内"与"跳过 echo 行"两个盲区，修正后可复现该 bug（旧行标红 / 新行干净）。**新增 `smoke_all.bat`**：一次双击串跑 T1–T13 套件 + 本矩阵探针。**T 套件回归已跑并全绿（2026-09-16）**：4 编码器 × 三种用法共 8 项 PASS（含 mode B 交互输入、mode C 全新 UTF-8 控制台）、`copy_to_mp4` PASS、静音输入 PASS、T13 纯音频拦截 rc=3 PASS、T9/T11/T12 list 三测各 2/2、banner 与 debug 卫生检查双双 PASS。即 6b 对核心路径（RUN_COM 组装 / 非包装 `set` / 交互分支 / list bat 延迟展开 / 编码器延迟块）的改动**未引入回归**。**取证方式**：新增 `smoke_all.bat`（仓库外）一键串跑 T1–T13 套件 + 特殊字符矩阵。<br>**已知边界（刻意未改）**：`call` 传参链路仍会二次解析 `%`（片名 `a%b%c` 形态仍失败，`100% Wolf.mp4` 单 `%` 安全）；**文件名含 `^` 不受支持**；「仓库自身路径含 `!`」不受支持；**6g（2026-09-16，用户实测触发）**：用户在新开的 **cp936** cmd 窗口直接运行 `convert_from_list_cuda.bat`，报出一串「中文注释碎片被当命令执行」—— 4 个 list bat 是全仓最后还剩「文件中途裸 `chcp 65001`、不重启进程」的脚本：936 入口下，第 5 行 `chcp 65001` 把**当前 cmd 进程的批处理读取器**打进错位状态（936 双字节与 65001 三字节的字符计数不一致），之后该进程 `call` 读进来的编码器 bat 凡含中文的行都会被吞掉行首（`rem` 前缀丢失 → 行尾被当命令执行），编码器自己的守卫也因此被吞而失效。此前「多轮实测稳定」只是**入口控制台恰好已是 65001**（`chcp` 为 no-op，无从错位）的运气。修法：4 个 list bat 补上与编码器同款的 ASCII 守卫（`setlocal` + `FB_UTF8_GUARD` + `chcp 65001 >nul` + `cmd /c call "%~f0" %*` 重启 + `:main`），全仓从此**不存在任何文件中途 chcp**。**守卫复核（2026-09-16，smoke_all.bat）**：本次探针**从 cp936 控制台启动（summary 首行 startCP: 936）**——正好是触发 6g 缺陷的那个入口条件：T1–T13 全 PASS、T9/T11/T12 各 2/2、banner 与 debug 检查双 PASS，元字符矩阵 A 18+1 SKIP / C 3/3 / B 6/6 / Z 全符合预期。**此前一直是盲区的「cp936 入口」至此被实测覆盖。**子进程里 marker 已定义 → list bat 调编码器时编码器守卫直接 `goto main`，链路全程 65001、读取器干净。均与片库路径无关。

### 机器 C：Ultra 7 265K（Arrow Lake 核显，AV1 验证平台，待引入）

| OS           | 环境               | ffmpeg 来源               |  NV | NV-A1 |        QS        |        QS-A1       |   VA  | x264/x265 | AV1软 |  .sh | .bat |
| ------------ | ---------------- | ----------------------- | :-: | :---: | :--------------: | :----------------: | :---: | :-------: | :--: | :--: | :--: |
| Win11        | cmd / PowerShell | 原生安装                    |  ➖  |   ➖   |        🟡        |   🟡 **AV1 实测目标**  | ❌ 无后端 |     🟡    |  🟡  |   ➖  |  🟡  |
| Win11        | Cygwin64         | Cygwin 自带               |  ➖  |   ➖   | ⛔ 预期同 7.1.1 构建限制 |   🚫 构建无 av1_qsv?  |   🚫  |     🚫    |  🟡  |  🟡  |   ➖  |
| Win11        | MSYS2 MINGW64    | mingw64 8.1             |  ➖  |   ➖   |        🟡        |  🟡 8.1 有 av1_qsv  |   ❌   |     🟡    |  🟡  |  🟡  |   ➖  |
| Ubuntu 22.04 | bash             | 原生 4.4.2                |  ➖  |   ➖   |  ✅ 已验证  |   ❌ 未编入  | ✅ h264 / ⛔ hevc |     ✅    | 🟡 仅 libaom | ✅ 已验证（hevc_vaapi 入口已加 /opt 软偏好） |   ➖  |
| Ubuntu 22.04 | bash             | /opt/ ffmpeg-master-gpl |  ➖  |   ➖   |  ✅ 已验证  |   ✅ 已验证  |   ✅  |     ✅    | ✅ svtav1/aom | ✅ 已验证（7 入口全绿） |   ➖  |

> C 机是 **QSV AV1 编码的唯一硬件平台**。**结论（2026-09-16 实测）**：master-gpl 构建下 QSV（含 AV1）/VAAPI（含 AV1）/软编/硬解**开箱即用，无需任何 mfx 会话调参**；原生 4.4.2 无 av1_qsv、无 svtav1、QSV 硬解不可用、hevc_vaapi 编码不可用（见下）。
> **`.bat` 侧（Win11）**：2026-09-16 已把入口备齐到 **7 个**（新增 `ffmpeg_av1_nvenc.bat` 与 `ffmpeg_av1_qsv.bat`），静态自检与同族骨架一致；本表 Win11 三行的**实跑仍待补**（探针 **T14 / T15** 已就位，其中 T15 在无 AV1 QSV 硬件的机器上记 `[SKIP]`）。

---

## 机器 A：Ubuntu 22.04 实测记录（2026-09-16，两轮：单构建 → 双构建）

**硬件/系统**：i7-9700T（8 核，CoffeeLake-S）+ **UHD Graphics 630**（Gen9.5，`00:02.0`）；Ubuntu 22.04.1 LTS，内核 6.8.0-136；内存 62 GiB；无独立显卡。
**iHD 驱动**：`intel-media-va-driver-non-free 25.2.4-1146~22.04`，libva 2.22.0 —— **与 C 机同版本**；VPL/MFX 栈 `libmfx1 23.2.2` + `libmfx-gen1 25.2.4` + `libvpl2 2.15.0` + `libmfx-tools`（**2026-04-01 即已装**，早于本轮，非本轮新增）。
**ffmpeg 来源**：`/usr/bin/ffmpeg` **4.4.2-0ubuntu0.22.04.1+esm16**（ESM 通道）；**`/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin/` 已于 2026-09-16 下午到货**（`N-117740-g7f51cf75c6-20241110`）→ 故本记录含**单构建（第一轮）**与**双构建（第二轮，见 ⑥）**两部分。
**设备**：`/dev/dri/renderD128` 存在，用户 `andy` 属 `render`/`video` 组，**无需 sudo**。

### ① 功能边界（发行版 4.4.2，与 C 机同版本对照）

| 能力 | A 机 4.4.2（UHD630） | C 机 4.4.2（Arrow Lake） | 说明 |
| --- | --- | --- | --- |
| h264_vaapi | ✅ | ✅ | 一致 |
| **hevc_vaapi** | **✅**（legacy 路径） | ⛔ issue 24 | **本轮最重要的差异，见下** |
| h264_qsv / hevc_qsv | ✅ / ✅ | ✅ / ✅ | 一致 |
| av1_qsv（编码） | ❌ 未编入（`Unknown encoder 'av1_qsv'`） | ❌ 未编入 | 一致；且 Gen9.5 本身无 AV1 编码器 |
| libx264 / libx265 | ✅ / ✅ | ✅ / ✅ | **A 机软编保底无需 mingw64** |
| svtav1 | ❌ 未编入 | ❌ 未编入 | 仅 libaom |
| VAAPI 硬解 | ✅（`Reinit context to 544x720, pix_fmt: vaapi_vld`） | ✅ | 一致 |
| QSV 硬解 | ⛔ 4.4.2 **静默回退软解**；显式 `-hwaccel_device hw` → `Device setup failed for decoder` | ⛔（native）/ ✅（master） | 一致：**4.4.2 的 QSV 硬解在 Linux 不可用**；机制见 ⑥ |
| av1 硬解 | ❌（Gen9.5 无 AV1 解码） | ✅ | **C 机独有**（Arrow Lake 支持 AV1 解码） |

### ② `hevc_vaapi` 差异定位（重要修正）

C 机记录原文把 4.4.2 的 `hevc_vaapi` 失败归为「**属 4.4.2 与新版 iHD 的兼容问题，非硬件限制**」。**A 机实测证明该归因不完整**：A 机是**同样的 4.4.2 + 同样的 iHD 25.2.4**，`hevc_vaapi` 却**直接成功**。

A 机成功时的实际路径（`-v verbose` 取证）：

```
[hevc_vaapi] Using VAAPI profile VAProfileHEVCMain (17).
[hevc_vaapi] Using VAAPI entrypoint VAEntrypointEncSlice (6).
[hevc_vaapi] RC mode: VBR.
[hevc_vaapi] Using intra, P- and B-frames (supported references: 3 / 1).
[hevc_vaapi] All wanted packed headers available (wanted 0xd, found 0x1f).
      encoder         : Lavc58.134.100 hevc_vaapi          <-- 4.4.x 的库版本号
```

即 **A 机与 C 机走的完全是同一条 legacy `VAEntrypointEncSlice` 路径、同一个 Lavc58.134 构建**，差别只在**硬件代际（Gen9.5 CoffeeLake vs Arrow Lake）**。因此正确表述是：

> 4.4.2 的 `hevc_vaapi` 支持**取决于具体核显代际**，不能一概而论「4.4.2 与新版 iHD 不兼容」。C 机上的 issue 24 可能同时包含 4.4.2 对该核显编码路径的处理缺陷 —— 需在 C 机用**其他 4.4.x 之外的构建**或**不同 iHD 版本**交叉验证才能定论（**此项留待后续，本轮不下结论**）。

`low_power=1` 在 A 机**两路都不通**，与 C 机观察一致：Gen9.5 的 `VAProfileHEVCMain` 只有 `VAEntrypointEncSlice`（**无 EncSliceLP**），故
`No usable encoding entrypoint found for profile VAProfileHEVCMain (17)`；
h264 侧虽有 `VAEntrypointEncSliceLP`，但 `-low_power 1` 报 `Driver does not support any RC mode compatible with selected options (supported modes: CQP)`。
**结论：两个平台的脚本都不应使用 `low_power=1`**（当前脚本未使用，符合预期）。

### ③ 脚本层（.sh 端到端，PASS=22 / FAIL=0）

套件 `smoke_sh_a.sh`（仓库外，ASCII+LF，经 SSH 执行）：

| 组 | 用例 | 结果 |
| --- | --- | --- |
| 带参模式 | `h264_vaapi` / `hevc_vaapi` / `libx264` / `libx265` / `avc_qsv` / `hevc_qsv` / `copy_to_mp4`（7 项应成功） | **7/7 产出正确**（`v=h264|hevc` + `a=aac`） |
| 带参模式（预期失败） | `av1_qsv`（`Unknown encoder`）/ `hevc_nvenc`（`Device setup failed`）/ `av1_nvenc` / `hevc_nvenc_cygwin` | **4/4 干净失败**：非零 rc、无产物、错误信息明确 |
| 交互模式 | 无参 + stdin 喂路径；再测**码率覆盖** `900k`（日志 `real TARGET_BITRATE = 900k`） | **2/2 PASS** |
| list 模式 | `convert_from_list_libx265` / `convert_from_list_qsv` / `repack_from_list`（3 条目，含**带空格文件名** `ep 2.mkv`） | **3/3，每条目均产出** |
| list 模式（预期失败） | `convert_from_list_cuda`（本机无 N 卡） | **干净失败** |
| list 容错 | **CRLF + UTF-8 BOM** 清单（记事本风格） | **PASS** —— `run_list` 的 CR/BOM 剥离跨机器成立 |
| 门禁 | 非视频输入 / 缺文件 / 清单条目不存在 | **3/3 正确拦截**（`不是视频文件!` / `file not exists!` / `Convert failed！`） |
| **`</dev/null` 回归** | **5 条目清单**（若 stdin 泄漏，第 2 条起会丢首字符） | **PASS：rc=0，`outputs=5/5`** |

> `</dev/null` 修复（`bed098a`）在 A 机复现成立：修复前 `done < list` 的 fd 被 ffmpeg 继承、Linux 版会读走 1 字节。**A 机实测 5/5，跨机器确认。**

### ④ 速度（90s / 544x720@30 H.264 源，pin 值仅供参考）

| 操作 | 耗时 | 备注 |
| --- | --- | --- |
| hevc_vaapi 编码 | 14.52s | legacy 路径 |
| h264_vaapi 编码 | 6.41s | |
| hevc_qsv 编码 | 11.07s | |
| h264_qsv 编码 | 3.87s | 最快硬件编码 |
| libx264 medium | 7.38s | 与 h264_vaapi 同量级 |
| libx265 medium | 25.48s | 最慢，符合预期 |
| VAAPI 硬解 | 1.69s | **慢于软解 0.66s** —— 与 C 机 4.4.2 结论一致（**不建议**） |
| QSV 硬解 | 0.67s（但脚本路径下 `Device setup failed`） | |

### ⑤ A 机结论

1. **A 机是 VAAPI 的可用平台**：`h264_vaapi` 与 `hevc_vaapi` 在**发行版 4.4.2 上开箱可用**，无需 master 构建 —— 与 C 机相反。
2. **软编保底无需 mingw64**：`libx264`/`libx265` 打包内即有，A 机 Linux 侧自足。
3. **QSV 编码可用、QSV 硬解不可用**（4.4.2 打包缺陷，与 C 机一致；**机制已于 ⑥ 定论：`-hwaccel qsv` 静默回退软解**，装 `/opt` master 后硬解才真正启用）；AV1 编解码在 Gen9.5 **均不可用**（硬件本身不支持）。
4. **list 模式（含 CRLF/BOM 容错与 `</dev/null`）在 A 机全部通过**，跨机器修复确认。
5. **待验证仅剩 A 机 Win11 的 QSV（UHD 630）**；Linux 侧已升级为**双构建 22/22**（⑥）。

### ⑥ 第二轮：`/opt/ffmpeg` master-gpl 到货后的双构建实测（2026-09-16 下午）

**新增来源**：`/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin/{ffmpeg,ffprobe,ffplay}` = **`N-117740-g7f51cf75c6-20241110`**（`--enable-libvpl --enable-vaapi --enable-libsvtav1 --enable-libx264 --enable-libx265`）—— **与 C 机同一个 gyan master-gpl 包**。

**PATH 语义（重要）**：`which ffmpeg` 仍是 `/usr/bin/ffmpeg` —— **装 `/opt` 不改变主机级默认**；只有带软偏好的 3 个脚本（`ffmpeg_av1_qsv.sh` / `ffmpeg_hevc_vaapi.sh` / `ffmpeg_av1_nvenc.sh`）会自行前置 `/opt`。构建指纹（`Lavc` 版本）：4.4.2 = `Lavc58.134.100`，master = `Lavc61.24.100`。
→ 脚本在 A 机的**实际走向**因此变化：`hevc_vaapi` 自动改用 master（仍 ✅）；`av1_qsv` 由「`Unknown encoder 'av1_qsv'`」变成「编码器存在但打开失败」；`av1_nvenc` 无 N 卡仍失败。

**编码器可用性**（grep 校准法 + 对照名，见本节"探测方法学"）：

| 编码器 | 4.4.2 | master | 备注 |
| --- | :---: | :---: | --- |
| h264_vaapi / hevc_vaapi | ✅ / ✅ | ✅ / ✅ | 4.4.2 侧 `hevc_vaapi` 在 Gen9.5 可用（见 ②） |
| av1_vaapi | ❌ 未编入 | ⚠️ 有但不可用 | 编码时 `-22 Invalid argument`（Gen9.5 无 AV1 编码器） |
| h264_qsv / hevc_qsv | ✅ / ✅ | ✅ / ✅ | |
| av1_qsv | ❌ 未编入 | ⚠️ 有但不可用 | 同上；错误 `Error while opening encoder`（脚本侧 rc≠0，干净失败） |
| hevc_nvenc / av1_nvenc | ❌ / ❌ | ✅ / ✅ | 二进制有，无 N 卡 → `CUDA_ERROR_NO_DEVICE`（预期失败） |
| libx264 / libx265 | ✅ / ✅ | ✅ / ✅ | Linux 侧自足 |
| **libsvtav1** | ❌ 未编入 | **✅** | **A 机新增的软编 AV1 选项**（720p 3s 实测 0.77s） |
| libaom-av1 | ✅ | ✅ | |

**编码实测（720p30 3s testsrc2；pin 值仅供相对比较）**：hevc_vaapi 0.65s→0.45s；h264_vaapi 0.32→0.18；hevc_qsv 0.63→0.67；h264_qsv 0.24→0.23；libx264 0.45→0.41；libx265 0.94→1.10（distro→master）。`low_power=1` **两构建都不通**，但报错层级不同：4.4.2 是预检 `No usable encoding entrypoint found for profile VAProfileHEVCMain`，master 是任务级 `-22 Invalid argument` → **结论不变：脚本不应使用 `low_power=1`**。

**解码实测 —— 4.4.2 的 QSV 硬解是「静默回退」（本轮定论）**：4 种源格式（H.264 full-range 544x720 / H.264 1080p / HEVC 1080p / HEVC 4K）× 3 种写法，4.4.2 一侧**全部 rc=0，但滤镜图像素格式仍是源格式**（`pixfmt:yuvj420p` / `pixfmt:yuv420p`）= **软解**；一旦显式加 `-hwaccel_device hw` 就 `Device setup failed for decoder`（rc=1）。master 一侧同一批用例**全部** `Selecting decoder 'h264_qsv' | 'hevc_qsv'` + `pixfmt:qsv` = **真硬解**。
> 这同时解释了第一轮 ④ 表里「QSV 硬解 0.67s（但脚本路径下 `Device setup failed`）」的表面矛盾：**0.67s 那次是静默软解的耗时**。
> 副产物：**发行版 4.4.2 上的 QSV 脚本并非"全硬解链路"** —— 脚本带的 `-init_hw_device qsv=hw:0 -filter_hw_device hw -hwaccel qsv -hwaccel_output_format qsv` 在 4.4.2 上被静默忽略，实际是「软解 + 硬编」；出片正确（套件 22/22），只是 CPU 侧没省下来。**master 上才是名实相符的全硬解**。

**脚本层（双跑，均 PASS=22 / FAIL=0）**：

| 轮次 | PATH | 结果 | 实际用到的构建 |
| --- | --- | --- | --- |
| 1 | 原样（distro 优先） | **PASS=22 FAIL=0** | 带软偏好的 3 个入口（`hevc_vaapi`/`av1_qsv`/`av1_nvenc`）走 master；其余走 4.4.2（指纹 `Lavc58.134.100`，`hevc_vaapi` 为 `Lavc61.24.100` 实测确认） |
| 2 | `/opt/.../bin` 前置 | **PASS=22 FAIL=0** | 全部走 master（`Lavc61.24.100`） |

两轮 `real TARGET_BITRATE` 完全一致（503912 / 719875 / 777968，交互覆盖 `900k`）；`</dev/null` 回归两轮均 `outputs=5/5`；门禁 3/3；CRLF+BOM 清单通过。

**探测方法学（两条教训，供后续复核沿用）**：
1. **`ffmpeg -h encoder=<名>` 判断编码器是否存在会误判**：对不存在的编码器它**同样返回 rc=0**，只在 stdout 打印 `Codec 'x' is not recognized by FFmpeg.`。首轮勘察据此得出「4.4.2 拥有全部编码器」的**错误**表格，用对照名 `definitely_not_a_codec` 校准后才纠正 → 正确做法是 **grep `not recognized`**，或直接跑一次该编码器。
2. **解码是否真走硬件不能用耗时判定，要看日志**：master 有 `Selecting decoder '<编码器>'` + 滤镜 `pixfmt:qsv|vaapi`；**4.4.2 不打印 `Selecting decoder` 这一行**（FFmpeg 5.x 才有），VAAPI 侧看 `pix_fmt: vaapi_vld`，QSV 回退时 `pixfmt:` 就等于源格式。
3. **日志里第一个 `Lavf` 不是运行中的二进制**（第二轮在 C 机踩到）：`Input #0 … Metadata: encoder: Lavf…` 记的是**写这个素材的那个 ffmpeg**。要判断「这次实际用的是哪套构建」，得取 `Output #0` 的 `encoder : Lavc<版本>`（或全局输出元数据的**最后一个** `Lavf`）。第一版指纹全部读到 58.76.100，其实是夹具的输入元数据在误导。
4. **命令行选项位置既是功能也是陷阱**：`-vaapi_device` 是全局选项（放 `-i` 前），而 `-vf` 必须放 `-i` **之后** —— 放到前面会得到 `Option vf cannot be applied to input`，rc=1，看起来像"功能不可用"。两轮探针各踩一次（先是 `-c:v` 在 `-i` 前，后是 `-vf` 在 `-i` 前），**凡"编码器/滤镜不可用"的结论都必须先确认命令行本身合法**。

**⑥ 结论（在 ⑤ 之上增补）**：
1. `/opt` 到货后 A 机具备**双构建能力**，但**默认不生效**（PATH 未含 `/opt`）；仅 3 个软偏好脚本自动升级 → 想让整机走 master 需自行把 `/opt/.../bin` 前置到 `PATH`。
2. **QSV 硬解在 A 机只有 master 能用**；4.4.2 是**静默软解**（不报错，极易误判成"已硬解"）。
3. **AV1 依旧不可用**（Gen9.5 硬件无 AV1 编解码）：master 里 `av1_qsv`/`av1_vaapi` 的"存在"只体现为打开编码器失败；`libsvtav1` 是唯一可用 AV1 路径（软编）。
4. **双构建 22/22** 说明脚本族对两套 ffmpeg 都兼容，**无需按机器改脚本**。

### 机器 C：Ubuntu 22.04 实测记录（2026-09-16）

**平台**：Ubuntu 22.04.1 / 内核 6.8.0-138（i915 驱动，`/dev/dri/renderD128`）/ Core Ultra 7 265K（20 核）/ 核显 PCI 7d67；**无 NVIDIA 设备**。
**驱动栈**：`intel-media-va-driver-non-free 25.2.4`（iHD）+ `libva 2.22.0` + `libvpl2 2.15.0` + `libmfx1 23.2.2` + `libmfx-gen1 25.2.4`。
**ffmpeg 来源**：`/usr/bin/ffmpeg` 4.4.2（`--enable-libmfx`，无 svtav1）；`/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin`（N-117740-g7f51cf75c6-20241110，`libvpl/vaapi/svtav1`）。

**环境坑（非仓库问题）**：`vainfo` 直接跑报 `vaGetDriverNames() failed`（libva 新枚举 API），需 `export LIBVA_DRIVER_NAME=iHD` 才正常；**ffmpeg 不需要该变量**（走旧 `vaGetDriverName`，实测无变量亦可初始化 iHD 并编/解码）。

**① 底层编码矩阵（720p30 3s 素材；✅通过 / ❌失败 / ⛔构建含但不可用）**

| 编码器 | native 4.4.2 | /opt master-gpl |
| --- | :---: | :---: |
| h264_qsv / hevc_qsv | ✅ / ✅ | ✅ / ✅ |
| av1_qsv | ❌ 未编入 | ✅（1080p60、4K30 均通） |
| h264_vaapi（全硬解链路） | ✅ | ✅ |
| hevc_vaapi（全硬解链路） | ⛔ `Failed to end picture encode issue: 24` | ✅ |
| av1_vaapi | ❌ 未编入 | ✅ |
| libx264 / libx265 | ✅ / ✅ | ✅ / ✅ |
| 软编 AV1 | ✅ libaom | ✅ libsvtav1 / libaom |

**hevc_vaapi 失败定位**：iHD 25.2.4 对该核显只暴露 `VAProfileHEVCMain: VAEntrypointEncSlice`（无 EncSliceLP），故 `low_power=1` 先报 `No usable encoding entrypoint found`；默认 legacy 路径下 master 通过、4.4.2 报内部错误 24 → **属 4.4.2 与新版 iHD 的兼容问题，非硬件限制**（同机 master 全绿；h264_vaapi 在 4.4.2 正常，仅 HEVC legacy 路径受影响）。

**② 硬解与速度（4K HEVC 10s/300 帧解码；括号内为帧率）**

| 解码方式 | native 4.4.2 | /opt master-gpl |
| --- | --- | --- |
| 软解 | 0.96s（312fps） | 0.88s（339fps） |
| QSV 硬解 | ⛔ `Device setup failed for decoder`（加 `-hwaccel_device hw`） | **0.72s（415fps）**，日志 `Selecting decoder 'hevc_qsv'` |
| VAAPI 硬解 | 4.23s（70fps，**慢于软解，不建议**） | **0.79s（380fps）** |

AV1 硬解：master `-hwaccel qsv` → `Selecting decoder 'av1_qsv'` ✅；VAAPI 解码亦通。
1080p60 5s（300 帧）编码耗时：native hevc_qsv 0.7s / master hevc_qsv 0.5s / master av1_qsv 0.7s / master hevc_vaapi 0.7s / master av1_vaapi 0.7s / native libx265 preset fast 2.6s / master libsvtav1 1.8s。

**③ 脚本层（.sh 端到端，含 list 批量）**

| 用例 | native 4.4.2 | /opt master-gpl（PATH 前置） |
| --- | :---: | :---: |
| ffmpeg_hevc_qsv.sh | ✅ 720p；1080p60 降帧分支 + 查表 2548951 正确 | ✅ |
| ffmpeg_avc_qsv.sh | ✅（AVC 表 2040182） | ✅ |
| ffmpeg_av1_qsv.sh | ✅（脚本自动前置 /opt，AV1 表 951915） | ✅ |
| ffmpeg_hevc_vaapi.sh | ✅（已加 /opt 软偏好：有 /opt 即走 master，无则回退 4.4.2 仍⛔） | ✅ |
| ffmpeg_h264_vaapi.sh | ✅（已改用 AVC 表，ref 720p = 2040182） | ✅ |
| ffmpeg_libx265.sh / ffmpeg_libx264.sh | ✅ / ✅（已补执行位，可直接 `./` 调用） | ✅ / ✅ |
| ffmpeg_copy_to_mp4.sh | ✅（已 mp4 后缀正确早退；mkv/mov → `<名>.mp4`） | ✅ |
| ffmpeg_hevc_nvenc.sh / av1_nvenc.sh / hevc_nvenc_cygwin.sh | ❌ 预期失败（无 N 卡），rc=1 + `Convert failed！`；cygwin 版已补执行位，`-hwaccel cuvid`+`hwdownload` 命令构建正确 → `CUDA_ERROR_NO_DEVICE` | ❌ 同上 |
| list（qsv / libx265 / repack / cuda） | ✅ CRLF+BOM+中文+空格清单逐条读全（见④）；cuda 版 Linux 分发 + 失败传播 rc=1（见⑤） | ✅ 2/2 且硬解生效 |
| 边界（纯音频 / 不存在 / 2 参数） | rc=1 + 中文提示（不是视频文件! / file not exists! / More than one parameter） | ✅ |

**④ 本轮发现并修复的仓库缺陷（P1，Linux 专属）**：`lib/common.sh` 的 `run_list` 用 `done < "$list_file"` 供输入，子进程继承该 fd 后 **Linux 版 ffmpeg 会从 stdin 吃掉 1 字节**（键盘交互探测；ffprobe 不读、`-nostdin` 可避免；微测同循环内三者对照复现）→ 清单第 2 条起路径被啃掉开头字符 → `file not exists!` → `Convert failed！` 提前退出（修复前 qsv/repack 两测均 1/2 产物即退）。**修复**：`bash "$script" "$line" < /dev/null`；修复后 3 条清单全部正确读取、2/3 产物为 `-n` 拒写重复项（预期）。`.bat` 侧 `for /f` 天然无此问题——又一处 sh/bat 行为不一致。

> **待决发现（三项已于同轮全部处置，2026-09-16）**：① `ffmpeg_h264_vaapi.sh` 查表漏改 → 已改传 `bitrate_table_avc.csv`（720p ref 1359878 → **2040182**，与 libx264 一致，实测 rc=0）；② `ffmpeg_libx264.sh` 无执行位（git 100644）→ 已 `chmod +x`（工作区 755）；③ `ffmpeg_hevc_vaapi.sh` 在 4.4.2 下命中 iHD 兼容问题 → 已仿 av1_qsv 加 /opt 软偏好，实测 rc=0 且产物 `encoder=Lavf61.9.100`（master 构建指纹，4.4.2 为 Lavf58.76.100）；无 /opt 环境仍回退 4.4.2 并⛔。

**⑤ sh 族全覆盖补测与冒烟套件沉淀（2026-09-16 第二轮，merge 后）**：① `convert_from_list_cuda.sh` 补测——Linux 分发打印 `Linux` → 清单条目完整读取 → 调 hevc_nvenc 预期失败 `Convert failed！` 传播 rc=1（同时复证 run_list stdin 修复）；② `ffmpeg_hevc_nvenc_cygwin.sh` 发现无执行位（git 100644，与 libx264 同款）→ 已 `chmod +x`（全仓复核：15 个入口脚本均 755，`lib/common.sh` 作为被 `source` 的库保持 644 合理），修复后直跑：`-hwaccel cuvid` + `hwdownload` 命令构建正确 → `CUDA_ERROR_NO_DEVICE` 预期失败 rc=1；③ 探针整合沉淀为仓库外一键套件 `../ffmpeg_bat_git_smoke/smoke_all.sh`（自生成素材 + 18 用例断言 + PASS/FAIL 汇总，与 smoke_all.bat 对称），实测 **PASS=18 FAIL=0**（含 merge 后两轮复跑）。至此 sh 族 **15/15 入口全部本机实测**并留有断言记录。

**⑥ 复查轮：SSH 远程复跑 + 归因收口（2026-09-16 下午）**

**方式**：由 AI 经 paramiko 直连本机（`100.127.43.115`，Tailscale），`git pull` 到 `b038814` 后上传**与 A 机同一套件**（当时在仓库外，现已随 `test/sh/smoke_sh.sh` 入库）复跑两轮。工作区 `list*.txt`（用户真实片单）与仓库文件**未做任何改动**，试验残留已清理。

**环境核对（与首轮一致）**：`andy-zirui` / 内核 6.8.0-138 / Ultra 7 265K（20 核）/ 62 GiB；核显 `8086:7d67`，`/dev/dri/renderD128`，用户 `andy` 在 `render`+`video` 组（**无需 sudo**）；iHD 25.2.4 + libva 2.22.0 + libvpl2 2.15.0 + libmfx1 23.2.2 + libmfx-gen1 25.2.4；**PATH 不含 `/opt`**（`which ffmpeg` = `/usr/bin/ffmpeg`）。

**脚本层双跑（与 A 机同协议）**：

| 轮次 | PATH | 结果 | 实际用到的构建（`encoder : Lavc` 指纹） |
| --- | --- | --- | --- |
| 1 | 原样（distro 优先） | **PASS=22 FAIL=0** | 除 3 个软偏好入口外全为 `Lavc58.134.100`；`av1_qsv` / `hevc_vaapi` = `Lavc61.24.100`（软偏好生效） |
| 2 | `/opt/.../bin` 前置 | **PASS=22 FAIL=0** | 全部 `Lavc61.24.100` |

`</dev/null` 回归两轮 `outputs=5/5`；门禁 3/3；CRLF+BOM 清单通过；1080p60 降帧分支三个入口（hevc_qsv / avc_qsv / av1_qsv）均正确降到 30fps 且查表正确。

**查表跨机器一致性**（1080p 夹具）：AVC `3836249`、HEVC `2548951`、**AV1 `1656818`** —— 与 B 机 Windows 侧 `.bat` 探针的 T1/T2 期望值完全相同，三张表在 `.sh`/`.bat` 与三平台间一致；`ffmpeg_h264_vaapi` 亦为 `3836249`，**首轮修掉的「h264_vaapi 误用 HEVC 表」在本轮复测中保持正确**。

**与 A 机的核心差异（唯一一处）**：`ffmpeg_av1_qsv.sh` 在 C 机 **rc=0 且产物 `v=av1`**（Arrow Lake 有 AV1 硬件编码器），A 机为干净失败（Gen9.5 无 AV1 编码器）→ 套件里该用例的期望值已参数化（`EXPECT_AV1_QSV=ok|fail`）。

**归因收口：`hevc_vaapi` 在 4.4.x 全系失效（非 Ubuntu 打包问题）**

`/opt/ffmpeg` 下另有 gyan 静态包（4.4.3 / 5.1.2 的 `.tar.xz`）与 BtbN 7.0.2 static，解出后得到四个可对比构建：

| 构建 | 版本 | av1_qsv | av1_vaapi | hevc_vaapi | svtav1 | h264_vaapi | hevc_vaapi |
| --- | --- | :---: | :---: | :---: | :---: | --- | --- |
| Ubuntu 发行版 | 4.4.2+esm16 | ❌ | ❌ | ✅ 有 | ❌ | ✅ rc=0 | ⛔ rc=1 `Encode failed: -5` |
| gyan 静态 | n4.4.3（2022-12-31） | ❌ | ❌ | ✅ 有 | ✅ | ✅ rc=0 | ⛔ rc=1 **同一错误** |
| gyan 静态 | n5.1.2（2022-12-31） | ❌ | ❌ | ✅ 有 | ✅ | ✅ rc=0 | **✅ rc=0** |
| gyan master-gpl | N-117740（2024-11-10） | ✅ | ✅ | ✅ 有 | ✅ | ✅ rc=0 | ✅ rc=0 |

→ **`hevc_vaapi` 的失败是 FFmpeg 4.4.x 的 VAAPI HEVC 编码老路径在 Arrow Lake 上的问题，与 Ubuntu 打包/编译选项无关**（换一个打包者的 4.4.3 复现同一错误），**5.1 起修复**；结合 A 机（Gen9.5）同一 4.4.2 却成功，完整表述为 **4.4.x 的 `hevc_vaapi` 可用性取决于核显代际**。
附带两条：① 两个 gyan 静态包**都自带 `libsvtav1`**（Ubuntu 4.4.2 没有）→ 「4.4.2 无 svtav1」属**打包差异**而非版本能力；② 它们用旧 libmfx API 对接新 VPL 运行时会**直接段错误**（`Error setting child device handle: -17` + core dumped），在 libvpl2 2.15.0 下**不能用于 QSV**。BtbN `7.0.2-static` 则是**纯软编构建**（av1_qsv / hevc_vaapi / h264_vaapi / svtav1 全无）。

**`low_power=1` 三构建一致失败**：`No usable encoding entrypoint found for profile VAProfileHEVCMain (17)`（Arrow Lake 的 iHD 对该 profile 只暴露 `VAEntrypointEncSlice`，无 `EncSliceLP`）→ 与 A 机同因，**脚本不应使用 `low_power=1`**（当前未使用）。

**QSV 硬解（与 A 机机制统一）**：`-hwaccel qsv` 在 4.4.2 上 rc=0 但 `pixfmt:yuv420p`（**静默软解**），显式 `-hwaccel_device hw` 才报 `Device setup failed for decoder`；master 上 `pixfmt:qsv` + `Selecting decoder 'h264_qsv'|'hevc_qsv'`（真硬解）。→ 首轮记录的 C 机「QSV 硬解 ⛔」与 A 机「静默软解」是**同一现象的两种观测**，已在两机统一表述。

**本轮定位到的两个探测陷阱**（已并入上文「探测方法学」3/4 条）：`Lavf` 指纹取错（输入元数据 ≠ 运行中的二进制）、`-vaapi_device`/`-vf` 的选项位置。

---

## 表 4：环境约束速查（写脚本时用）

| 环境                 | 路径风格              | 自带 ffmpeg            |   行尾输出(CR 剥除必要性)  | VAAPI |   QSV  |
| ------------------ | ----------------- | -------------------- | :---------------: | :---: | :----: |
| linux bash         | `/home/...`       | 4.4.2 或 /opt/ master | LF（不剥也安全，但保留剥除无害） | ✅ C 机实测可用 | ✅ C 机实测可用（**硬解须 master**；4.4.2 是静默软解，见 ⑥） |
| Windows cmd        | `C:\...`          | 依赖系统安装               |    —（.bat 无此问题）   |   ❌   |   🟡   |
| Windows PowerShell | `C:\...`          | 同上                   |         —         |   ❌   |   🟡   |
| Cygwin64           | `/cygdrive/c/...` | 7.1.1（功能残缺）          |         LF        |   🚫  |    ⛔   |
| MSYS2 MINGW64      | `/c/...`          | 8.1                  |   **CRLF（必须剥）**   |   ❌   |    ✅   |
| git-bash           | `/c/...`          | 无（用原生）               |   **CRLF（必须剥）**   |   ❌   |    ✅   |

**两条跨环境硬约束（踩过坑，写脚本/探针时必守）**

* **MSYS 只改写「命令参数」里的路径，不改写「作为值传入」的路径**（2026-09-16 实测）：把相对路径
  交给入口，入口内部规范化后会变成 `/c/Users/...` POSIX 形式 —— 而**原生 `ffmpeg.exe` 打不开
  POSIX 路径**（报 `Error opening input`，且文件明明存在，极易误判成"入口坏了"）。
  → 跨环境脚本与清单文件一律用 **`C:/...` mixed 形式**（`cygpath -m` 产生）最稳。
* **可用性探针的片源不得小于 160 宽**：`hevc_nvenc` / `av1_nvenc` 在 128×128 下
  `InitializeEncoder failed: invalid argument`，160×120 起正常（QSV 无此限制）。
  探针用 128×128 会让**有 N 卡**的机器把硬件用例误记成 SKIP，静默丢覆盖。本仓库统一用 320×240。

---

## 待验证清单（按优先级）

1. ~~**本机 av1_nvenc 实测**~~ ✅ 已完成（2026-09-15：三构建冒烟 + 真实转码全通过）
2. ~~**C 机 Linux（Ubuntu 22.04）**：master-gpl 的 QSV/VAAPI/AV1 + 原生 4.4.2 功能边界~~ ✅ 已完成（2026-09-16 两轮：首轮整合表 + **下午 SSH 远程复跑**，见「机器 C：Ubuntu 22.04 实测记录」；含 run_list stdin 泄漏缺陷修复、sh 族 15/15 全覆盖、`smoke_all.sh` 套件沉淀〔PASS=18/18〕、**复查轮双构建各 PASS=22/22** 与 `hevc_vaapi` 归因收口）；**C 机 Win11 下 QSV AV1（mingw64 8.1 或原生）仍待验证**；原描述： Linux 下 master-gpl 的 QSV/VAAPI/AV1
3. ~~**A 机 i7-9700T**：Ubuntu VAAPI~~ ✅ **已完成（2026-09-16，PASS=22/22）**，见「机器 A：Ubuntu 22.04 实测记录」；**同日下午 `/opt` master-gpl 到货后又做了双构建复跑（2026-09-16，PASS=22/22，见 ⑥）**；**仅剩 A 机 Win11 的 QSV（UHD 630）待验证**；软编保底已确认走 Linux（`libx264`/`libx265` 打包内可用，无需 mingw64）
4. ~~**Linux 双 ffmpeg 来源验证**~~ ✅ C 机已完成（2026-09-16 两轮）：原生 4.4.2 边界 = 无 av1_qsv/无 svtav1/QSV 硬解不可用（实为**静默软解**）/hevc_vaapi 不可用（h264_vaapi 可用），master-gpl = QSV/VAAPI 含 AV1 全家桶；**A 机 Ubuntu 已复测两轮（2026-09-16）：发行版 4.4.2 同样「无 av1_qsv、无 svtav1」，但 hevc_vaapi 可用（与 C 机不同，见机器 A 记录）；第二轮双构建（/opt master-gpl 到货）再证 ① 4.4.2 的「QSV 硬解 ⛔」实为静默软解、② master 上 QSV 硬解真启用、③ A 机新增 libsvtav1 软编 AV1 可用、④ 两套构建下脚本族均 22/22**；**此外 C 机复查轮已用 gyan 4.4.3 / 5.1.2 静态包完成第三方交叉验证：`hevc_vaapi` 在 4.4.x 全系失效、5.1.2 起恢复，且 svtav1 属打包差异**。原描述：原生 4.4.2 的功能边界（av1_nvenc/svtav1 是否在打包内）vs master-gpl 全家桶
5. ~~**.bat 路线**~~ ✅ 已完成（2026-09-16：57c418f 重构 + 26ccf0e cp65001 守卫 + 8e5c631 find_ffmpeg 去硬编码路径 + 4ffd990 守卫改环境变量标记并修 `shift` 吃掉 `%0` 的回归）
6. ~~**`.bat` list 模式复核（阻塞项，第四轮）**~~ ✅ 已完成（2026-09-16：T9 / T11 / T12 各 2/2 rc=0 + banner 检查 `[PASS]`，见上）
7. **`.bat` 真实拖放/双击**：探针只能模拟代码页起点，真·Explorer 拖放与新窗口 banner 观感需人工扫一眼；含中文文件名的拖放同样值得顺手验一次
8. **可选**：其余 3 个 list bat（convert_from_list_cuda / convert_from_list_libx265 / repack_from_list）与本轮修复的 convert_from_list_qsv 共享同一行 `for /f "usebackq …" do call "%~dp0…"` 代码，且其调用的编码器 bat 已各自单独实测；如需凑满 `.bat 10/10` 可再跑一次探针复核
9. **清单文件编码边界**：`run_list` 已兼容 CRLF 与 UTF-8 BOM 清单（原 CRLF 会因 `\r` 混入路径导致第一项即 `file not exists!` 退出，而 .bat 侧 `for /f` 天然吞 CRLF → 属 sh/bat 行为不一致，已修）。**`.bat` 侧的 UTF-8 BOM 尚未实测**：`for /f` 读带 BOM 文件时首行可能带上 3 字节 BOM 前缀（记事本默认存 UTF-8 无 BOM 时不触发）；若日后的清单由其它工具导出，建议顺手验一次首行条目
10. ~~**`.bat` 第五轮复核**~~ ✅ 已完成（2026-09-16：T1–T13 全部 PASS，T13 = audio-only 被提前拒绝 rc=3，banner/debug 双检查 `[PASS]`，见上）。原描述：本轮清理了 `lib/common.bat` 的 14 行遗留调试 echo 并新增 `:check_isvideo`，改动落在**共享库**上，建议跑一次**全量**探针（不带第 2 参数）；期望 T13 PASS（日志含 `check_isvideo`、不含 `matches no streams`、无产物、rc=3）、全局 hygiene 行 `[PASS]`，且 T1–T12 回归不变
11. **`&` 文件名** → 第六轮 6a 的结论**已在 6b 更正**：`^&` 不是缺陷而是原版对"包装写法"的补偿；真正病根是 `set "VAR=值"` 包装写法 + 值内含引号，已全量改非包装写法（5 文件 57 行），并保留 6a 中 `%1` 裸展开、`call %RUN_COM%` 二次解析、list bat 延迟展开、编码器延迟块内含路径等**确实有效**的修复；**已由 v6b 探针实测通过**（A 18 PASS + 1 SKIP / C 3/3 / B 6/6 / D SKIP / Z1 PASS，见上）；**T1–T13 套件回归已跑并全绿**（6b 触及核心路径，见上）；D 段 SKIP 机制已定论 = `chcp 65001` 吃掉文件重定向 stdin（管道/控制台不受影响，真实用法零影响，见上）
12. ~~**待决（C 机 Linux 轮发现）**~~ ✅ 已完成（2026-09-16 同轮处置：① `ffmpeg_h264_vaapi.sh` 改传 `bitrate_table_avc.csv`（ref 720p 1359878→2040182）；② `ffmpeg_libx264.sh` 补执行位 `chmod +x`；③ `ffmpeg_hevc_vaapi.sh` 仿 av1_qsv 加 /opt 软偏好（实测走 master 产物 Lavf61.9.100，无 /opt 回退 4.4.2 仍⛔）；三项均端到端复测 rc=0）。原描述：C 机 Linux 轮发现三项：① 查表表不符 ② 无执行位 ③ 4.4.2 iHD 兼容
13. **Linux list 模式（`run_list`）**：本轮 `</dev/null` 修复为跨机器通用（所有 Linux ffmpeg 都会从 stdin 吃 1 字节），~~**A 机（i7-9700T Ubuntu）首次上机时需一并复跑 list 用例**~~ ✅ **已于 2026-09-16 复跑：5 条目清单全部产出（`outputs=5/5`），且 3 条目含空格的 CRLF+BOM 清单亦通过 —— `</dev/null` 修复跨机器成立**；`.bat` 侧无需改动
14. ~~**A 机 `/opt/ffmpeg` master-gpl（2026-09-16 下午到货）**~~ ✅ 已完成：双构建各跑一遍套件**均 PASS=22/22**，并据本轮证据定论 **4.4.2 的 QSV 硬解=静默软解**（`-hwaccel qsv` 不报错但 `pixfmt` 仍是源格式；显式 `-hwaccel_device hw` 才 `Device setup failed`），AV1 在 Gen9.5 仍不可用（master 里 `av1_qsv`/`av1_vaapi` 打不开编码器），**`libsvtav1` 为 A 机新增可用软编 AV1**；另沉淀两条探测方法学教训（`-h encoder=<名>` 对未知编码器**也返回 rc=0** → 必须 grep `not recognized`；解码是否真硬解**看 `pixfmt`/`Selecting decoder` 而非耗时**）。**遗留观察项（非缺陷，暂不改）**：4.4.2 下 QSV 脚本实为「软解+硬编」，若日后希望"要么真硬解、要么显式告警"，可在 QSV 脚本里加一条 hwaccel 生效判定
15. ~~**C 机 Linux 复查轮**~~ ✅ 已完成（2026-09-16 下午，SSH 远程）：同一套件双构建各 **PASS=22/22**；`ffmpeg_av1_qsv.sh` 在 C 机**真产出 AV1**（A 机为预期失败，已把套件期望值参数化）；1080p 查表值与 B 机 `.bat` 探针一致（AVC `3836249` / HEVC `2548951` / AV1 `1656818`）；**`hevc_vaapi` 归因收口**——用 `/opt` 里的 gyan 4.4.3 复现同一错误、gyan 5.1.2 与 master 成功，判定为 **FFmpeg 4.4.x 老路径在 Arrow Lake 上的缺陷、与 Ubuntu 打包无关**；QSV 硬解「静默软解」机制与 A 机统一；新增两条探测陷阱入档（`Lavf` 指纹取错、`-vf` 置于 `-i` 前）
16. **新增 `ffmpeg_av1_nvenc.bat`（本轮）待 B 机 Windows 侧实测**：`.bat` 家族此前只有 AVC-QSV / HEVC-QSV / HEVC-NVENC / libx265 / copy_to_mp4 五个入口，**唯独缺 AV1 NVENC**（而 `lib/common.bat` 的 `lookup_bitrate` 早已把 `bitrate_table_av1.csv` 列为受支持表、`.sh` 侧也已有实测通过的 `ffmpeg_av1_nvenc.sh`）→ 已补该 `.bat`（以 `ffmpeg_hevc_nvenc.bat` 为骨架，仅改编码器段/码率表/标题，静态自检与 `hevc_nvenc.bat` 同结果）。~~**尚需在 B 机跑一次探针**~~ ✅ **已完成（2026-09-16 晚，B 机双击探针）：T14 PASS — `TARGET_BITRATE=1656818`、产物 `v=av1`、rc=0**（沙箱无法调用 `cmd.exe`，由用户双击执行；**同一轮又补了 `av1_qsv` 入口，见条目 17**）
17. ~~**`av1_qsv.bat` 的对称缺口**~~ ✅ **已补（2026-09-16 晚）**：新增 `ffmpeg_av1_qsv.bat`（以 `ffmpeg_hevc_qsv.bat` 为骨架，diff 仅 5 处：标题/头部注释、两处码率表引用、`lookup_bitrate` 实参、编码器段；参数与 `ffmpeg_av1_qsv.sh` 对齐 = `-c:v av1_qsv -profile:v main -preset fast`），静态自检（`check_bat_static` / `audit_set_forms2` / `mini_cmd_scan`）与骨架**同结果**、守卫区仍 ASCII-only、CRLF 保持。探针新增 **T15** 用例（1080p 期望 `TARGET_BITRATE=1656818`，与 C 机 `.sh` 实测同值）：因 AV1 QSV 取决于硬件，**T15 先用 1 帧 lavfi 试编探测能力，失败则记 `[SKIP]` 而非 FAIL**（探针日志 `smoke_logs\T15_av1_qsv_probe.txt`）→ 在无 AV1 QSV 硬编的机器上跑探针不会变红。**实测（2026-09-16 晚，B 机双击探针 v6）：T15 按预期记 `[SKIP]`**（`Current codec type is unsupported` / rc=-40，该机 Raptor Lake 核显确无 AV1 编码器），**其余 T1–T14 不受影响，banner 与 debug 卫生检查均 `[PASS]`**；**C 机 Win11 侧实跑待补**（用户当前无该环境）

18. **测试套件已入库（2026-09-16 晚）**：`.bat` 族与 `.sh` 族冒烟套件此前放在会话工作区（仓库外），现迁入仓库 `test/bat/`（`smoke_ffmpeg_bat.bat` v6 / `smoke_special_chars.bat` / `smoke_all.bat`）与 `test/sh/`（`smoke_sh.sh`），并**统一改为自定位仓库根**（脚本位置上两级）→ 克隆到任意路径都能跑；`.bat` 运行日志目录（`test/bat/smoke_logs/`、`test/bat/chars_logs/`）已进 `.gitignore`。迁移后已在 **A 机 / C 机** 各按仓库内路径复跑一轮 `.sh` 套件：**均 PASS=22/22**，自定位逻辑验证通过。用法与环境开关见 `test/README.md`

19. **三层测试体系落地 + 三处硬件/环境层定论（2026-09-16 晚，B 机）**
    * **① NVENC 有最小尺寸门槛（本轮最重要的环境事实）**：`hevc_nvenc` / `av1_nvenc` 在 **128×128** 下报
      `InitializeEncoder failed: invalid argument` 直接失败，**160×120 起正常**；**QSV 无此限制**。
      这条本身与仓库无关，但它**曾经伪装成"本机没有 N 卡"**：冒烟套件用 128×128 做可用性探针，
      探针失败 → 硬件用例被记 `SKIP` → `T2 hevc_nvenc` / `T14 av1_nvenc` / `T20 hevc_nvenc_cygwin`
      三条在**有硬件**的机器上长期静默不测（该机 `nvidia-smi` 恰又坏，见 ③，两个假象互相加固）。
      定位方式是把深测（同一入口 320×240 真跑成功、写出 90 帧）与冒烟（同入口 SKIP）交叉比对。
      **修复**：两族探针夹具统一 320×240 → 同一次全量运行 `PASS=19/SKIP=7` ⟶ **`PASS=22/SKIP=4`**。
      **教训：可用性探针的输入规格本身就是覆盖率的隐性上限，必须可辩护。**
    * **② bat 探针补上对等的硬件门控**：`test/bat/smoke_ffmpeg_bat.bat` v8 新增 `:gate` / `:skipcase`
      子程序，与 sh 侧 `gate_arg` 语义一致 —— 先用 320×240 小片试编一次，失败则记 `SKIP` +
      `hardware absence, not a repo defect`，而不是 FAIL。门控落在 T1/T2/T3/T7/T14（五个依赖硬件的用例）。
      此前无硬件的机器跑 bat 套件必然冒出无意义 FAIL，是**跨机器噪声源**。
    * **③ 快查的 `NO-DEVICE` 是假阴性**：本机 `nvidia-smi` 以 255 退出并报 `Failed to initialize NVML`
      （打到 stdout），快查据此把两个 `*_nvenc` 标成 `NO-DEVICE`；而 `--probe` 深测同一入口是
      `PROBE-OK rc=0`。**判据修正**：`NO-DEVICE` 只表示"说不清、值得深测"，不是判决。
    * **④ MSYS 只改写「命令参数」里的路径，不改写「作为值传入」的路径**（新坑）：深测的 list 族全部
      rc=1 `Error opening input`。日志显示入口把相对名 `clip.mp4` 规范化成了 `/c/Users/.../clip.mp4`
      （POSIX 形式），而**原生 `ffmpeg.exe` 打不开 POSIX 路径** —— 文件确实存在、路径确实被改写坏了。
      修复：① 深测前用 `cygpath -m "$W"` 把工作目录规范成 `C:/...`；② 清单改用**绝对路径**，不再写相对名。
      与既有的「MSYS2/git-bash 下 ffmpeg 输出是 CRLF」并列，属同族环境陷阱（见表 4）。
    * **⑤ 新增两套工具**（均已入库，见 `test/README.md`）：`test/lint/`（13 项静态 + 7 项对等检查，
      带双向自校准 selftest）与 `test/{sh,bat}/check_env.*`（环境能力报告，默认快查 + 深测）。
      能力报告的价值正是把 ①②③ 这类"硬件在但测不到 / 硬件不在却报错"的模糊态显式化：
      `OK / NO-ENCODER / NO-DEVICE / N/A-OS / UNKNOWN / PROBE-OK / PROBE-FAIL / NO-ENTRY`。

20. **软编 AV1 入口的评估结论（2026-09-16，决策：不做）**：用户问「软件 AV1 是否过于慢、有没有必要做」。
    实测（10 秒 1080p30、单遍 CBR 2548951 bps、与仓库入口同款参数）：
    * B 机（gyan master，SVT-AV1 3.0.2）：`libx264 veryfast` 1.2s / `libx265 fast` 3.4s /
      `svtav1 p8` **3.1s** / `p6` 4.9s / `p4` 23.3s —— **p8 与 x265 fast 同速**，"过于慢"不成立于新版本 SVT-AV1；
    * A 机（i7-9700T，/opt master 同版 SVT-AV1）：`libx265 fast` 4.5s / `svtav1 p8` 6.0s / `p6` 11.7s；
    * D 机（Pi 4B，ffmpeg 4.1.3）：**无 svtav1**（只有 libaom，慢 50–100 倍）——软编 AV1 在 Pi 上不存在可行性。
    不做的理由是**矩阵位置而非速度**：① 有硬编 AV1 的机器（B: NVENC、C: QSV）永远不会选软编；
    ② 无硬编 AV1 的机器里 A 机不是转码产线（100 部 × ~36 分钟/部 ≈ 60 小时，且主线是 NVENC HEVC）、
    D 机根本没有 svtav1；③ 质量收益（同码率 VMAF 略高）对"看电影学英语"场景感知弱，
    而 AV1 的**播放端兼容性反而更差**（Pi NAS / 旧设备软解 AV1 会卡）；④ 若未来出现
    "无硬编 AV1 但算力强的产线机器"或"存储成本敏感"的需求，加入口成本可控
    （bitrate_table_av1.csv 已存在，只需 2 个入口文件 + lint/T 用例）——届时再评估。

21. **测试文件名对等 + sh 侧补齐元字符矩阵（2026-09-16 深夜，本轮）**：T 编号对等之后，用户指出
    **文件名层面也不对等**（bat 侧 4 个套件、sh 侧只有 2 个，且名字对不上）→ 两族文件名去掉族后缀、
    **同名文件互为孪生**：
    | 用途 | sh | bat |
    |------|----|----|
    | T 编号回归 | `test/sh/smoke_ffmpeg.sh`（原 `smoke_sh.sh`） | `test/bat/smoke_ffmpeg.bat`（原 `smoke_ffmpeg_bat.bat`） |
    | 元字符矩阵 | `test/sh/smoke_special_chars.sh`（**新增**，part A/C/B/D/Z 与 bat 同构） | `test/bat/smoke_special_chars.bat` |
    | 一键串跑 | `test/sh/smoke_all.sh`（**新增**） | `test/bat/smoke_all.bat` |
    | 能力报告 | `test/sh/check_env.sh` | `test/bat/check_env.bat` |
    sh 侧元字符矩阵的三处**刻意分歧**（都在脚本头注释里写明）：① part C/B 用 `libx264`/`libx265`
    软编入口 → **全套无需硬件**（bat 用 QSV 是因为 Windows 测试机上它总在）；② **A07 脱字符在 sh 侧
    是真用例**（bat 必须 SKIP：`CALL` 会二次解析参数、把 `^` 翻倍，探针造不出同名文件）；③ part D
    在 sh 侧是**真 PASS**（文件重定向的 stdin 能到达无参分支；bat 侧是 cp65001 重启的探针取证限制）。
    part Z 的定位改为钉住 `run_list` 与后缀剥离所依赖的 shell 构造（`${name%.*}`、
    `while IFS= read -r`），并新增 **Z3 反斜杠文件名**（Linux 合法、Windows 文件系统造不出 → 条件 SKIP）。
    沙箱权限复核：用户称已给完全权限，但实测 **cmd.exe 调用仍被拦截、外部 exe 的重定向输出仍为 0 字节**
    —— `.bat` 侧验证仍需用户双击。

22. **check_env.sh 的 mawk 陷阱（2026-09-16 深夜，用户在 D 机复跑时发现）**：D 机快查把
    libx264 / libx265 报成 NO、`encoders : 0 listed`，hwaccels 粘连成一词 `vdpauvaapidrm`。
    用户存疑「Pi 应该支持 libx264/libx265」——实测确认用户正确，是**检测脚本自己的 bug**：
    * 根因①：D 机默认 awk 是 **mawk 1.3.3**（Raspbian），不支持区间表达式——`/^[A-Z.]{6}$/`
      静默匹配 0 行 → `ENCODERS` 为空 → 所有编码器 NO。mawk 报错都不报，gawk/A 机完全无感。
    * 根因②：`tr -d '[:space:]'` 本想清空白，实际把 hwaccel 名字全部粘连成一词。
    * 修复（check_env.sh）：区间表达式展开为 6 个显式字符类 + `$2 != "="` 滤掉图例行；
      hwaccels 改 `tr -s '[:space:]' ' '`。B 机（gawk）复跑 `237 listed` 不变，D 机修复后
      `187 listed`、libx264/libx265 转 yes、OK=7。
    * 结论修正：「Pi 无硬件编码器」应精确为「无 QSV/NVENC」——Raspbian 4.1.3 编译进了
      `h264_vaapi`/`hevc_vaapi` 编码器本体，但 Pi GPU 没有 VAAPI 驱动，真跑与否以
      `--probe` 为准（快查 OK 只是静态证据）。
    * 教训：sh 侧工具脚本要按 POSIX 最小公共子集写——**mawk 1.3.3 连区间表达式都不支持**，
      任何「只在 gawk 下验证过」的正则都可能在 Debian 系机器上静默失效。
      B 机有双系统（Win11 / Ubuntu 22.04），待用户切 Ubuntu 轮再补一轮 sh 侧实测。

23. **Pi 4B 的硬件编解码真相（2026-09-17，用户质疑「Pi 4 怎么也有硬编解码器吧」——正确）**：
    check_env/本矩阵说 D 机「无硬件编码器」指的是**仓库 12 个入口对应的 QSV/NVENC/VAAPI 路径**；
    Pi 4 的硬件编解码走 **V4L2 mem2mem**（`/dev/video10-12`），不在入口覆盖范围内。实测（ffmpeg 4.1.3，OMV armv7l）：
    * **硬编有且只有 H.264**：`h264_v4l2m2m` 真跑成功——1080p30、10 秒素材 **9.2s**（≈1.1× 实时），
      同机软编参照：`libx264 ultrafast` 13.9s、`libx264 fast` 40.2s → **硬编 ≈ 4.4× 于主线 preset**。
      代价是控制极粗：B 帧/GOP/profile/qmin/qmax 全被硬件忽略（日志逐条 `Failed to set ...`），基本只有码率可调。
    * **无 HEVC 硬编**：`hevc_v4l2m2m` 编码器虽在构建里，真跑报 `Could not find a valid device`
      —— Pi 4 的 VideoCore VI 只有 H.264 编码单元；HEVC 是**只解不编**（4K60 解码）。
    * 解码器齐全：`h264/hevc/mpeg2/mpeg4/vc1/vp8/vp9` 的 v4l2m2m + h264/mpeg2/mpeg4/vc1 的 mmal，
      另有 `h264_omx`（OpenMAX 老接口）。
    * 结论：D 机定位不变——暴露隐式硬件依赖 + 跑软编/纯 shell 逻辑。它的 H.264 硬编画质一般、
      参数模型（无 B 帧、固定 QP 倾向）与仓库码率表不匹配，**不值得为它加入口**；若未来要做
      Pi 产线转码，加 `h264_v4l2m2m` 入口成本可控（一张码率表 + 1 个入口 + lint/T 用例）。24. **三张码率表的实测比例与幂律拟合（2026-09-17，本轮）**：用户问「AV1 表是不是对 HEVC 再 /2」——**不是**。
    94 个共同 max_pixels 桶逐点配对（临时脚本 ratio_analysis.py，最小二乘）：
    * **逐桶比例**：HEVC/AVC ≈ 0.665 几乎恒定（0.678→0.657 缓降）；**AV1/HEVC 分四档**——
      ≤25344 桶 0.75、38400–1638400 桶 0.70、**2073600（1080p）–67108864 桶 0.65**（修正后）、
      ≥132710400（8K）桶 0.60；AV1/AVC ≈ 0.42–0.49。此前「÷2 链式会让 AV1 系统性缺码 20–30%」的担忧不成立，
      表的代际设计（逐代省 30–35%）恰好落在建议区间内。
    * **幂律拟合**（log-log 最小二乘）：AVC = 92.5×px^0.779（1080p 7.67M / 4K 22.6M）、
      HEVC = 65.1×px^0.775（5.10M / 14.9M）、AV1 = 58.1×px^0.755（3.43M / 9.76M）。
      三条曲线近于平行；AV1 指数略小，高分辨率端省得更多。已落 `readme.md`「码率怎么来的」。
    * **顺带修掉 AV1 表非单调 bug（`bd44fb5`）**：1764000 桶（2923448）低于相邻 1638400 桶（2973216）。
      根因不是单行笔误（该行严格 =0.6500×HEVC，是刻意的档位），而是 **0.70→0.65 台阶（-7.1%）大于
      该区间相邻桶的码率增幅（~6–7%）**——台阶画在 1764000 或 1920000 都必回落。
      修法：0.65 档从 1080p（2073600）起算，1764000/1920000 两桶钳到 3148328（=0.70×hevc[1764000]），
      全表恢复单调；lint 回落 WARN 消失（22 PASS / 0 FAIL / 5 WARN，剩 5 条全是 AVC 表已知重复行）。
    * 遗留：AVC 表 5 条重复行（WARN，不可达）可顺手清理；拟合指数 0.775 与用户
      FormatFactory power-law 模型（pixels^0.775）一致，可视为模型的正式化。
25. **AV1/HEVC 等画质码率比首次实测校准（2026-09-17，C 机主跑 + A 机交叉验证）**：方法——两类内容
    （BBB 动画 / Sintel CG 动作，test-videos.co.uk 10s 片段）× 720p/1080p/2160p × SVT-AV1(p8) 与
    x265(fast) 各三档码率梯，全部按 ffprobe 实测 delivered 码率 + libvmaf 出分，log-domain 拟合求
    等质量交叉点。脚本为会话工作区 calib_av1.sh（~80 行 bash + python 汇总），C 机 20 核全程 ≈8 分钟。
    * **结果（r = AV1 码率 / HEVC 码率 @ 等画质）**：
      - bbb_1080 VMAF93：**r=0.573（C）/ 0.576（A）**——两机独立一致，方法可信；
      - 720p：0.534（bbb）/ 0.532（sil）；2160p（1080 上变换，caveat）：0.580；
      - **r 随目标画质上升**：bbb_1080 从 VMAF90 的 0.402 升到 V93 的 0.573（sil_1080 V96→V98 为
        0.451→0.611）——接近透明的档位上 AV1 优势收窄。
    * **结论方向反转**：软件配对（SVT-AV1 p8 vs x265 fast）实测 r ≈ 0.53–0.61，**低于码率表现行的
      0.65–0.75 阶梯——AV1 表不是缺码，反而偏宽松 10–15%**。此前「÷2 链式会缺码」的担忧被数据否定。
    * **但先别改表**：此配对是软编对照，而 AV1 表实际服务 av1_nvenc/av1_qsv 硬编入口；硬件 AV1 的
      压缩效率低于 SVT-AV1 p8，硬件配对的 r 必然更高。定论等 B 机 `bench_av1_calib.bat`
      （现名 `nvenc_pair_calib.bat`，2026-09-17 更名，见第 30 条）
      （hevc_nvenc vs av1_nvenc，p4 CBR，与产线同参数，提交 4d2b074）跑出硬件配对数字后再下。
    * 其他 caveat：源为 h264 压缩片源（VMAF 参照=压缩源，比例仍自洽）；单片段代表性有限；
      2160p 无可下载源，由 1080 参考上变换生成。
26. **NVENC 硬件配对校准完成（2026-09-17，B 机 RTX 4080 Laptop，hevc_nvenc vs av1_nvenc 同为 p4 CBR）**：
    用户把一部电影拖上 `test\bat\bench_av1_calib.bat`（现名 `nvenc_pair_calib.bat`）。首跑暴露两个 bat 级 bug（`212a27a` 修复）：
    ① **libvmaf 的 log_path 用绝对路径必炸**——盘符冒号被滤镜语法解析器当成选项分隔符
    （`No option name near '/Users/...'`），且 bat 里 `2>nul` 吞错 → 18 行全部静默失败、CSV 只剩表头。
    修法：pushd 进工作目录用相对 log_path。② 出口无 pause，双击窗口秒关看不到任何信息。
    修复后借助已缓存的 18 个编码产物（沙箱可直接调 ffmpeg 补跑 VMAF，无需重编码）出齐 18 对分数：
    * **结果（r = 等画质 AV1 码率 / HEVC 码率，按 delivered 码率 + libvmaf，log 域拟合）**：
      720p VMAF97 **r=0.830** / V98 r=0.998；1080p V97 **r=0.719** / V98 r=0.940；4K V99 r=0.748。
      AV1 的 VMAF-log(码率) 斜率全面低于 HEVC（1080p 0.77 vs 1.10）→ **画质目标越高，AV1 优势越窄**。
    * **对照第 25 条软编结果（SVT-AV1 vs x265，r≈0.53–0.61）：NVENC 硬件 AV1 的压缩效率明显低于
      SVT-AV1 p8，等画质要多花 20–30% 码率**。现行 AV1 表的 0.65–0.70 阶梯在 V97 带偏乐观 7–19%，
      在 V98+（近透明）带几乎无节省（r≈1.0）。
    * **决策建议**：AV1 表骨架保留（查表语义/单调性/代际结构不动），但给 av1_nvenc 产线的实际取值
      建议在近透明档按 r≈0.75–0.80 兜底（即 AV1 档码率别按 0.65 拿满优惠），中低画质档 0.65–0.70 仍成立。
    * caveat：单部电影单段 10s（内容复杂度未标定）；VMAF 带偏高（96–99），恰是 AV1 优势最窄的区间；
      VMAF 参照为 x264 crf10 缩放参考，非原始母版。跨内容方差待后续多片校准。
27. **码率表的定位澄清：表 = 编解码器理论档，以最佳软编为衡量基准（2026-09-17，用户裁定，AV1 表不动）**：
    用户澄清三张表的设计哲学——AVC/HEVC/AV1 表都是「编解码器代际理论收益」的产物，衡量基准是各代
    *最佳实用软编*（x265 / SVT-AV1），从不针对某个硬件编码器校准。硬编入口（qsv/nvenc/vaapi）沿用
    同一张表属于「搭便车」：硬件编码器达不到理论收益的部分，表现为同表值下画质更低，这是编码器
    实现的折损，不是码率表的错误。
    * 在此框架下重读两轮校准：**AV1 表对软编基准（SVT-AV1 p8，r≈0.53–0.61）偏宽松 10–20%**——
      多给码率落在画质保守侧，方向安全，无需调整；第 26 条的「硬编近透明档 r≈0.75–0.80 兜底」
      建议作废——那是把「编码器折损」误记到「表」头上的结论。
    * 硬编 AV1 的真实含义：av1_nvenc/av1_qsv 用现表时，产物画质低于 hevc_nvenc 同表值一档
      （近透明带几乎追平）。若未来某条硬编 AV1 产线要补齐画质，正确做法是给入口加**硬件折减系数**
      （同表值 ×1.1–1.3，实测标定），而不是改表。
    * 同理检查 HEVC 主线：hevc_nvenc 相对 x265 同样有实现折损，而 HEVC 表按理论收益给出——
      意味着产线码率一直是理论宽松口径，这解释了为何码率表历年来工作良好（宁多勿少）。
28. **AV1 表按纯公式重出：`bitrate = round(58.1 × px^0.755)`（2026-09-17，用户裁定）**：
    双校准（第 25/26 条）证明 r 的主变量是画质目标而非分辨率，阶梯信念失去依据；且 AV1 非主力格式，
    定位降为「不差的软件 AV1 参考表」——保留 94 个 max_pixels 桶，码率全部由连续幂律公式生成。
    * 结果：全表严格单调（台阶回落类 bug 结构性消失，P04 对 AV1 表零告警）；隐含 AV1/HEVC 比例
      连续漂移 ≈0.68（720p）→ 0.67（1080p）→ 0.65（4K）→ 0.63（8K）。
    * 产线桶变化：720p -2.8%、1080p +3.0%、1440p +1.9%、4K +0.3%、8K -3.0%——中等幅度，
      方向是「高分辨率端少给一点」（更贴 SVT-AV1 实测）。
    * 联动更新：T14/T15 期望 1656818 → **1707157**（=3414314/2，sh/bat 两侧 harness + test/README.md
      用例表同步；P06 先抓到 bat 侧两处 FAIL 后修复归位，验证了守卫有效）。sed 改坏 bat CRLF 被
      L01 抓到并归位——本轮 P06/L01 两个守卫各立一功。
    * 状态：lint 22 PASS / 0 FAIL / 5 WARN，selftest 13/13。smoke 需待 push 后用户双击复验
      （T14/T15 目标值变了，产物期望随表更新）。
29. **单片源码率标尺 bench_calib（2026-09-17，sh/bat 对等）**：用户需求——特殊片源需要尽可能
    保画质时，从原视频实测出该给的目标码率。设计为**通用引擎 + codec 参数**（avc/hevc/av1）而非
    三份拷贝（bat 侧无函数库可共享）：`test/sh/bench_calib.sh` + `test/bat/bench_calib.bat`。
    * 方法：片源中段默认 30s，查表值 T 的五点梯（T/4 T/3 T/2 3T/4 T），**软件编码器**
      （libx264 fast / libx265 fast / libsvtav1 p8——与码率表同基准，呼应第 27 条），libvmaf
      **直接对照源片**（参照腿与编码腿做同样的 fps30/pixfmt/[可选缩放] 归一，不经有损代理）；
      4K 源自动换 vmaf_4k model。支持高度上限参数（4K 源标 1080 档）。
    * sh 侧输出 log 域拟合 + VMAF 90/93/95/97 交叉码率 + 建议值 /（T/2）比值；bat 侧输出
      VMAF≥95 最小梯点。产物缓存于 work dir，重跑只补缺失点。
    * 开发中 sh 侧踩了两个 libvmaf 新坑（bat 侧 bench_av1_calib 未暴露因为参照是独立文件）：
      ① **参照腿必须带与编码腿相同的 -ss/-t**——否则逐帧错位配对，VMAF 掉到 ~0.7-21 的垃圾值；
      ② **JSON 解析不能抓第一个 "mean"**——pooled_metrics 里 integer_adm2 等对象在 vmaf 之前，
        且每帧还有裸 "vmaf": <num> 行，必须匹配 `"vmaf": {` 对象键再取内部 mean。
    * 本机实测（合成 720p testsrc2，6s 段）：三 codec 全链路通，AVC 建议 2.39M=1.17×(T/2)、
      HEVC 2.32M=1.71×(T/2)（合成源偏难，真实电影通常更低）。lint 22/0/5、selftest 13/13。
      bat 侧待用户双击验证。
30. **bench 工具族更名对齐 + py 分析脚本入库 + bench_calib.sh 三机验证（2026-09-17）**：
    * **更名**：`test/bat/bench_av1_calib.bat` → `test/bat/nvenc_pair_calib.bat`（工作目录同步改名
      `%TEMP%\ffmpeg_bat_nvenc_pair`）。旧名"AV1 基准"名不副实——它测的是 **NVENC AV1/HEVC 配对**，
      且校准使命已收官；`bench_calib` 才是从片源推导目标码率的通用标尺。改名保留（用户裁定），
      未来 A/C 机做 QSV/VAAPI 配对校准可复用此骨架。
    * **sh 对等补齐**：新增 `test/sh/nvenc_pair_calib.sh`（bat 的 1:1 孪生：同 10s 中段静音段、
      同 x264 crf10 slow 近透明参照 720p/1080p/4K、同三档码率梯、同 results.csv 列、同相对
      log_path 与缓存补点逻辑；曲线拟合不入盒，交 `nvenc_pair_solve.py`）。
    * **py 分析脚本入库**（`test/py/`，三个，已参数化去硬编码路径，均用当时真实数据复验输出一致）：
      - `eq_quality_solve.py`（原工作区 calib_solve.py）：软编配对（SVT-AV1 vs x265）等画质求解，
        复算 r≈0.53–0.61 与第 25 条一致；
      - `nvenc_pair_solve.py`（原 calib_solve_b.py）：NVENC 配对求解，复算 overall r=0.847
        与第 26 条一致；
      - `table_ratio_audit.py`（原 ratio_analysis.py）：三表比例/单调性/幂律审计，能直接报出
        AVC 表 5 条重复桶（P04 同源）。
    * **bench_calib.sh A/C 机真实验证（合成 720p testsrc2 12s、6s 段，/opt master N-117740，
      Ubuntu 默认 mawk 下拟合/解析全通过）**：三 codec × 两机全链路 rc=0，两机数字高度一致——
      AVC VMAF95 ≈2.19M/2.21M（1.07/1.08×T/2）、HEVC ≈2.17M/2.16M（**两机同为 1.59×T/2**）、
      AV1 ≈1.75M/1.87M（1.89/2.02×T/2，6s 短段拟合斜率敏感，差异可接受）。
      至此 bench_calib sh 侧三机（B=MSYS2、A、C）全部实测通过。
    * 文档同步：test/README.md 工具段与目录树补齐 bench 工具族 + py/ 三件套。
