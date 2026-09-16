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
| QSV h264/hevc 编码          |          🟡 硬件支持          |        ✅ 已验证（本会话，核显 UHD）       |    ✅ 已验证（2026-09-16 Linux 双构建）     |
| QSV AV1 编码                |     ❌ Gen9.5 无 AV1 编码     |    ❌ Raptor Lake 核显无 AV1 编码    | ✅ 已验证（2026-09-16 Linux master 构建，1080p/4K） |
| VAAPI h264/hevc 编码（Linux） | 🟡 UHD630 由 iHD/i965 驱动支持 |         🟡 核显由 iHD 驱动支持        | ✅ h264 双构建；hevc 仅 master（4.4.2 ⛔） |
| AV1 硬解                    |             ❌             |     🟡 4080L + 核显均支持 AV1 解码    |    ✅ 已验证（QSV av1_qsv / VAAPI 解码）    |

> 注：B 机 RTX 4080 Laptop 的 av1_nvenc 已于 2026-09-15 实测通过（三构建冒烟 + cuda 解码→AV1 Main 720p60 CBR 真实转码），AV1 硬编流水线在本机即可铺开。
>
> 注：C 机 Linux 侧的整表实测已于 2026-09-16 完成（两套 ffmpeg 来源 × QSV/VAAPI/软编/硬解 + 全部 .sh 入口与 list 模式），详见下文「机器 C：Ubuntu 22.04 实测记录」；C 机 Win11 行仍为待验证。

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
> **第五轮（v5 探针）✅ 已跑完全绿**：本轮改动 = ① 清理 `lib/common.bat` 里 14 行遗留调试 echo（`in extract()` / `%~dp2` / `%~d2` / `"%~n2"` / `%~x2` / `"%~n2-compressed.mp4"` / `in extract_mp4()` / `"%~n2.mp4"` / `!fpA!` / `!fpB!` / `numA / numB` / `ret=`），这些是原版就带的、每次转码都刷屏；② 新增 `lib/common.bat :check_isvideo`，把 `.sh` 侧早就有的 `check_file_isvideo` 前置校验补到 `.bat` 侧，接线于 **4 编码器 + copy_to_mp4**（后者放在 `suffix is not mp4` 早退之后），失败 `exit /b 3`。探针同步 v5：新增 **T13**（audio-only 输入必须被提前拒绝：日志含 `check_isvideo`、**不含** `matches no streams`〔证明根本没走到 ffmpeg〕、无产物、rc=3）与**全局 hygiene 行**（任一日志含 `in extract` / `ret=` 即 FAIL）。因改动落在共享库上，**本轮建议跑全量（不带第 2 参数）**。<br>**结果（2026-09-16 全量跑完）**：**T1–T13 全部 PASS** —— T13（audio-only 输入）被 `check_isvideo` 提前拦下（rc=3、日志含 `check_isvideo`、**无** `matches no streams`、无产物）；全局 `banner check` 与 `debug check` 双双 `[PASS]`（14 行调试 echo 清零后日志再无 `in extract` / `ret=`）；T9/T11/T12 list 三测 2/2 保持全绿。`TARGET_BITRATE` 仍为 3836249（AVC）/ 2548951（HEVC），与码率表一致。

> **第六轮（2026-09-16，路径元字符加固；分 6a / 6b 两步）**：起点是用户反馈**片库确有含 `&` 的片名**。**6a** 做了 5 类改动，但探针实测只 13/20 绿 —— 其中"删掉 `^&` 转义"与"把 `set` 改成包装写法"两项是**误判造成的回归**（原版 `^&` 是在补偿包装写法的不配对，不是缺陷）。**6b** 顺着 6a 的失败日志找到真正病根：**`set "VAR=值"` 包装写法要求「值里不能出现字面量引号」，而本仓库的 `RUN_COM`/`SRC_CODEC`/`SRC_FILE`/`TARGET_FILE` 存的正是带引号的路径或整条命令行** —— 值里第一个引号与包装引号配对闭合后，其后的路径段落落进"未加引号区"，`&` 断行、`( )` 触发 `was unexpected at this time`。修法：所有"值里会出现引号"的 `set` 改非包装写法 `set VAR=值`（引号配对平衡，`& ( ) ^` 全在引号内），并去掉不再需要的 `^&` 补偿（5 文件 57 行），每个脚本头部补「路径/命令行拼接规则」注释块。<br>**6a 中保留有效的部分**：`if [%1] neq []` / `SET SRC_FILE=%1` → `if not "%~1"==""` + `set "SRC_FILE=%~1"`；去掉 `call %RUN_COM%`（避免整条命令行二次 `%` 展开）；4 个 list 驱动 bat 的 `EnableDelayedExpansion` → `DisableDelayedExpansion`；编码器 `%SRC_RESOLUTION%` 移出延迟展开块。<br>**验证方式**：探针 `smoke_special_chars.bat`（仓库外、纯 ASCII + CRLF）—— **A** 19 个文件名字符用例（`&` `%` `!` `( )` `[ ]` `;` `,` `=` `#` `$` `+` `'` `~` `@` 外加 `A & B (2020)` / `Tora! Tora! Tora! (1970)` / `A&B!C(2) 100%` 与子目录 `sub & dir (x)`）走 `ffmpeg_copy_to_mp4`；**C** 3 个真实片名形状走 `ffmpeg_avc_qsv`；**B** `convert_from_list_qsv` 清单驱动 6 条含元字符条目；**D** 无参数模式（stdin，判定 PASS/SKIP/FAIL）；**Z** 构造微测（Z1 = 非包装 `set` 保住含 `& ( ) !` 的带引号值；Z2a/Z2b = `set /p` 读重定向 stdin 在"直接 call"与"经 cp65001 守卫 `cmd /c` 转发"下的差异）。A07（片名含脱字符）标 SKIP：`call` 二次解析会让 `^` 翻倍，探针无法既建同名文件又传参。<br>**静态复核**：`audit_set_forms2.py`（危险 `set` 形态）与 `mini_cmd_scan.py`（用最坏片名展开后逐行找"引号外元字符"，内置已知好/坏行自校准）全仓 0 命中（只剩 `endlocal & set …`、`set /a (…^)/…` 等刻意构造）。<br>**6b 实测结果（2026-09-16）**：A **18 PASS + 1 SKIP**、C **3/3**、B **6/6**、D **SKIP**、Z1 **PASS** —— 元字符片名已全程走通，`set` 写法修正生效。D 的 SKIP 机制**已由四路判别用例定论（2026-09-16）**：**元凶是 `chcp 65001` —— 它会把"文件重定向"的 stdin 读空（EOF），但管道与控制台不受影响**。证据矩阵（探针 part Z/D 同轮实测）：Z2d 守卫复刻 + 文件重定向 → 读到；**Z2e = Z2d + `chcp 65001` → 读空（唯一差异项）**；Z2f = Z2d + `for /f` 子进程 → 读到（排除 `find_ffmpeg`）；Z2g = Z2d + 块内 `set /p` → 读到（排除块语法）；D1 = 真实脚本 + 预置 `FFMPEG_BIN`（短路 `find_ffmpeg`、零子进程）→ 仍读空（与 Z2e 交叉印证）。管道不受影响的解释：管道是流式无"文件位置"概念，守卫子进程接力读也不冲突；文件重定向则依赖句柄位置，`chcp 65001` 切换控制台代码页后 cmd 对该句柄的读返回 EOF。**对真实用法零影响**：双击后手输 = 控制台设备（T 套件 mode-B T6/T7 实测通过）、拖放 = argv、管道 = 流式，三种入口全不受 `chcp 65001` 影响。**探针自身 bug**：写 Z1 判定行的 echo 句里有裸 `&`，把该行劈成两条命令 → `( was unexpected at this time` 致探针提前终止（首跑 summary 缺 Z1/Z2 判定行）；已改写并给 `mini_cmd_scan.py` 补上"只扫仓库内"与"跳过 echo 行"两个盲区，修正后可复现该 bug（旧行标红 / 新行干净）。**新增 `smoke_all.bat`**：一次双击串跑 T1–T13 套件 + 本矩阵探针。**T 套件回归已跑并全绿（2026-09-16）**：4 编码器 × 三种用法共 8 项 PASS（含 mode B 交互输入、mode C 全新 UTF-8 控制台）、`copy_to_mp4` PASS、静音输入 PASS、T13 纯音频拦截 rc=3 PASS、T9/T11/T12 list 三测各 2/2、banner 与 debug 卫生检查双双 PASS。即 6b 对核心路径（RUN_COM 组装 / 非包装 `set` / 交互分支 / list bat 延迟展开 / 编码器延迟块）的改动**未引入回归**。**取证方式**：新增 `smoke_all.bat`（仓库外）一键串跑 T1–T13 套件 + 特殊字符矩阵。<br>**已知边界（刻意未改）**：`call` 传参链路仍会二次解析 `%`（片名 `a%b%c` 形态仍失败，`100% Wolf.mp4` 单 `%` 安全）；**文件名含 `^` 不受支持**；「仓库自身路径含 `!`」不受支持；4 个 list 驱动 bat 未加 cp65001 守卫（其 `chcp 65001` 之前仍是中文 rem，多轮实测稳定）—— 均与片库路径无关。

### 机器 C：Ultra 7 265K（Arrow Lake 核显，AV1 验证平台，待引入）

| OS           | 环境               | ffmpeg 来源               |  NV | NV-A1 |        QS        |        QS-A1       |   VA  | x264/x265 | AV1软 |  .sh | .bat |
| ------------ | ---------------- | ----------------------- | :-: | :---: | :--------------: | :----------------: | :---: | :-------: | :--: | :--: | :--: |
| Win11        | cmd / PowerShell | 原生安装                    |  ➖  |   ➖   |        🟡        |   🟡 **AV1 实测目标**  | ❌ 无后端 |     🟡    |  🟡  |   ➖  |  🟡  |
| Win11        | Cygwin64         | Cygwin 自带               |  ➖  |   ➖   | ⛔ 预期同 7.1.1 构建限制 |   🚫 构建无 av1_qsv?  |   🚫  |     🚫    |  🟡  |  🟡  |   ➖  |
| Win11        | MSYS2 MINGW64    | mingw64 8.1             |  ➖  |   ➖   |        🟡        |  🟡 8.1 有 av1_qsv  |   ❌   |     🟡    |  🟡  |  🟡  |   ➖  |
| Ubuntu 22.04 | bash             | 原生 4.4.2                |  ➖  |   ➖   |  ✅ 已验证  |   ❌ 未编入  | ✅ h264 / ⛔ hevc |     ✅    | 🟡 仅 libaom | ✅ 已验证（hevc_vaapi 入口已加 /opt 软偏好） |   ➖  |
| Ubuntu 22.04 | bash             | /opt/ ffmpeg-master-gpl |  ➖  |   ➖   |  ✅ 已验证  |   ✅ 已验证  |   ✅  |     ✅    | ✅ svtav1/aom | ✅ 已验证（7 入口全绿） |   ➖  |

> C 机是 **QSV AV1 编码的唯一硬件平台**。**结论（2026-09-16 实测）**：master-gpl 构建下 QSV（含 AV1）/VAAPI（含 AV1）/软编/硬解**开箱即用，无需任何 mfx 会话调参**；原生 4.4.2 无 av1_qsv、无 svtav1、QSV 硬解不可用、hevc_vaapi 编码不可用（见下）。

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
| ffmpeg_hevc_nvenc.sh / ffmpeg_av1_nvenc.sh | ❌ 预期失败（无 N 卡），rc=1 + `Convert failed！` | ❌ 同上 |
| list（qsv / libx265 / repack） | ✅ CRLF+BOM+中文+空格清单逐条读全（见④） | ✅ 2/2 且硬解生效 |
| 边界（纯音频 / 不存在 / 2 参数） | rc=1 + 中文提示（不是视频文件! / file not exists! / More than one parameter） | ✅ |

**④ 本轮发现并修复的仓库缺陷（P1，Linux 专属）**：`lib/common.sh` 的 `run_list` 用 `done < "$list_file"` 供输入，子进程继承该 fd 后 **Linux 版 ffmpeg 会从 stdin 吃掉 1 字节**（键盘交互探测；ffprobe 不读、`-nostdin` 可避免；微测同循环内三者对照复现）→ 清单第 2 条起路径被啃掉开头字符 → `file not exists!` → `Convert failed！` 提前退出（修复前 qsv/repack 两测均 1/2 产物即退）。**修复**：`bash "$script" "$line" < /dev/null`；修复后 3 条清单全部正确读取、2/3 产物为 `-n` 拒写重复项（预期）。`.bat` 侧 `for /f` 天然无此问题——又一处 sh/bat 行为不一致。

> **待决发现（三项已于同轮全部处置，2026-09-16）**：① `ffmpeg_h264_vaapi.sh` 查表漏改 → 已改传 `bitrate_table_avc.csv`（720p ref 1359878 → **2040182**，与 libx264 一致，实测 rc=0）；② `ffmpeg_libx264.sh` 无执行位（git 100644）→ 已 `chmod +x`（工作区 755）；③ `ffmpeg_hevc_vaapi.sh` 在 4.4.2 下命中 iHD 兼容问题 → 已仿 av1_qsv 加 /opt 软偏好，实测 rc=0 且产物 `encoder=Lavf61.9.100`（master 构建指纹，4.4.2 为 Lavf58.76.100）；无 /opt 环境仍回退 4.4.2 并⛔。

---

## 表 4：环境约束速查（写脚本时用）

| 环境                 | 路径风格              | 自带 ffmpeg            |   行尾输出(CR 剥除必要性)  | VAAPI |   QSV  |
| ------------------ | ----------------- | -------------------- | :---------------: | :---: | :----: |
| linux bash         | `/home/...`       | 4.4.2 或 /opt/ master | LF（不剥也安全，但保留剥除无害） | ✅ C 机实测可用 | ✅ C 机实测可用 |
| Windows cmd        | `C:\...`          | 依赖系统安装               |    —（.bat 无此问题）   |   ❌   |   🟡   |
| Windows PowerShell | `C:\...`          | 同上                   |         —         |   ❌   |   🟡   |
| Cygwin64           | `/cygdrive/c/...` | 7.1.1（功能残缺）          |         LF        |   🚫  |    ⛔   |
| MSYS2 MINGW64      | `/c/...`          | 8.1                  |   **CRLF（必须剥）**   |   ❌   |    ✅   |
| git-bash           | `/c/...`          | 无（用原生）               |   **CRLF（必须剥）**   |   ❌   |    ✅   |

---

## 待验证清单（按优先级）

1. ~~**本机 av1_nvenc 实测**~~ ✅ 已完成（2026-09-15：三构建冒烟 + 真实转码全通过）
2. ~~**C 机 Linux（Ubuntu 22.04）**：master-gpl 的 QSV/VAAPI/AV1 + 原生 4.4.2 功能边界~~ ✅ 已完成（2026-09-16，见「机器 C：Ubuntu 22.04 实测记录」；含 run_list stdin 泄漏缺陷修复）；**C 机 Win11 下 QSV AV1（mingw64 8.1 或原生）仍待验证**；原描述： Linux 下 master-gpl 的 QSV/VAAPI/AV1
3. **A 机 i7-9700T**：Win11 QSV（UHD 630）+ Ubuntu VAAPI；确认软编保底走 mingw64/Linux
4. ~~**Linux 双 ffmpeg 来源验证**~~ ✅ C 机已完成（2026-09-16）：原生 4.4.2 边界 = 无 av1_qsv/无 svtav1/QSV 硬解不可用/hevc_vaapi 不可用（h264_vaapi 可用），master-gpl = QSV/VAAPI 含 AV1 全家桶；A 机 Ubuntu 待复测。原描述：原生 4.4.2 的功能边界（av1_nvenc/svtav1 是否在打包内）vs master-gpl 全家桶
5. ~~**.bat 路线**~~ ✅ 已完成（2026-09-16：57c418f 重构 + 26ccf0e cp65001 守卫 + 8e5c631 find_ffmpeg 去硬编码路径 + 4ffd990 守卫改环境变量标记并修 `shift` 吃掉 `%0` 的回归）
6. ~~**`.bat` list 模式复核（阻塞项，第四轮）**~~ ✅ 已完成（2026-09-16：T9 / T11 / T12 各 2/2 rc=0 + banner 检查 `[PASS]`，见上）
7. **`.bat` 真实拖放/双击**：探针只能模拟代码页起点，真·Explorer 拖放与新窗口 banner 观感需人工扫一眼；含中文文件名的拖放同样值得顺手验一次
8. **可选**：其余 3 个 list bat（convert_from_list_cuda / convert_from_list_libx265 / repack_from_list）与本轮修复的 convert_from_list_qsv 共享同一行 `for /f "usebackq …" do call "%~dp0…"` 代码，且其调用的编码器 bat 已各自单独实测；如需凑满 `.bat 10/10` 可再跑一次探针复核
9. **清单文件编码边界**：`run_list` 已兼容 CRLF 与 UTF-8 BOM 清单（原 CRLF 会因 `\r` 混入路径导致第一项即 `file not exists!` 退出，而 .bat 侧 `for /f` 天然吞 CRLF → 属 sh/bat 行为不一致，已修）。**`.bat` 侧的 UTF-8 BOM 尚未实测**：`for /f` 读带 BOM 文件时首行可能带上 3 字节 BOM 前缀（记事本默认存 UTF-8 无 BOM 时不触发）；若日后的清单由其它工具导出，建议顺手验一次首行条目
10. ~~**`.bat` 第五轮复核**~~ ✅ 已完成（2026-09-16：T1–T13 全部 PASS，T13 = audio-only 被提前拒绝 rc=3，banner/debug 双检查 `[PASS]`，见上）。原描述：本轮清理了 `lib/common.bat` 的 14 行遗留调试 echo 并新增 `:check_isvideo`，改动落在**共享库**上，建议跑一次**全量**探针（不带第 2 参数）；期望 T13 PASS（日志含 `check_isvideo`、不含 `matches no streams`、无产物、rc=3）、全局 hygiene 行 `[PASS]`，且 T1–T12 回归不变
11. **`&` 文件名** → 第六轮 6a 的结论**已在 6b 更正**：`^&` 不是缺陷而是原版对"包装写法"的补偿；真正病根是 `set "VAR=值"` 包装写法 + 值内含引号，已全量改非包装写法（5 文件 57 行），并保留 6a 中 `%1` 裸展开、`call %RUN_COM%` 二次解析、list bat 延迟展开、编码器延迟块内含路径等**确实有效**的修复；**已由 v6b 探针实测通过**（A 18 PASS + 1 SKIP / C 3/3 / B 6/6 / D SKIP / Z1 PASS，见上）；**T1–T13 套件回归已跑并全绿**（6b 触及核心路径，见上）；D 段 SKIP 机制已定论 = `chcp 65001` 吃掉文件重定向 stdin（管道/控制台不受影响，真实用法零影响，见上）
12. ~~**待决（C 机 Linux 轮发现）**~~ ✅ 已完成（2026-09-16 同轮处置：① `ffmpeg_h264_vaapi.sh` 改传 `bitrate_table_avc.csv`（ref 720p 1359878→2040182）；② `ffmpeg_libx264.sh` 补执行位 `chmod +x`；③ `ffmpeg_hevc_vaapi.sh` 仿 av1_qsv 加 /opt 软偏好（实测走 master 产物 Lavf61.9.100，无 /opt 回退 4.4.2 仍⛔）；三项均端到端复测 rc=0）。原描述：C 机 Linux 轮发现三项：① 查表表不符 ② 无执行位 ③ 4.4.2 iHD 兼容
13. **Linux list 模式（`run_list`）**：本轮 `</dev/null` 修复为跨机器通用（所有 Linux ffmpeg 都会从 stdin 吃 1 字节），**A 机（i7-9700T Ubuntu）首次上机时需一并复跑 list 用例**；`.bat` 侧无需改动
