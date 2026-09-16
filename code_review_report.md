# ffmpeg_bat_git 代码质量分析报告

**仓库路径:** `D:\repos\ffmpeg_bat_git`
**分析日期:** 2026-08-14
**代码语言:** Bash / Windows Batch
**文件数量:** 25 个脚本文件 (13 .sh + 12 .bat) + 文档/数据文件

---

## 〇、改进进度跟踪（2026-09-15 第二次更新）

| 状态 | 项目 | 提交 |
|:---:|------|------|
| ✅ 已解决 | P0: .gitignore 添加（压缩包规则因保留 heif-tool.7z 而移除） | 20ade32 + 8492be2 |
| ✅ 已解决 | P0: `TARGET_BITRATE =` 赋值语法错误（9 个 .sh） | 20ade32 |
| ✅ 已解决 | P3: 拼写错误修正（unnomal/TEAR DOWN；ROSOLUTION 由作者提前修复） | d22ea30 / 82a75ff |
| ✅ 已解决 | P3: 清理死代码和调试标记（23 个文件 -2183 行：ABS 注释块、注释掉的旧命令、:: 注释、调试 echo） | 4509f65 |
| ✅ 已解决 | .bat CRLF 行尾被 sed 破坏 → unix2dos 恢复 + .gitattributes `*.bat -text` 防复发 | d22ea30 |
| ✅ 已解决 | P1: 提取公共函数到 lib/common.sh（10 个检查函数 + lookup_bitrate + run_list） | 8cefaef |
| ✅ 已解决 | P1: 码率查找表改为 CSV 数据驱动（三表并存：hevc/avc/av1，`lookup_bitrate` 第二参数选表） | 8cefaef + 9dc5b37 + 6335025 |
| ✅ 已解决 | P1: 编码脚本整合（采用方案 A：保留独立入口文件，14 个 .sh 内部全部迁移至 lib 公共库；.sh 总行数 ~6600 → 1899） | 8cefaef + 443764b + 9dc5b37 + 2e5ee6d |
| ✅ 已解决 | P2: 消除 eval（.sh 全部改数组传参）/ 变量加引号 / 批处理空格文件名（run_list 用 while read） | 8cefaef + 2e5ee6d |
| ✅ 已解决 | P2+: 新建 libx264 保底脚本、AVC 专用码率表（bitrate_calc.xlsx H 列）、av1_nvenc 的 qsv 残留初始化清除 | 443764b + 6335025 + 8b77873 |
| ✅ 已解决 | 新增环境×硬件能力矩阵文档（三机器五环境，已验证/未验证/未编入状态） | 4db4577 + b210379 |
| ✅ 已解决 | P2: .bat 临时文件消除竞争与残留 — 采用评审 2.3 建议的两种做法之一（%TEMP% + RANDOM 唯一名 + 用后即删），固定名 temp/temp.txt 的并发冲突与仓库目录垃圾文件已消除；字面方案 `for /f` 直接捕获因命令串已含 `^&` 转义、再嵌套一层 usebackq 转义脆弱且沙箱无法实测 cmd.exe 而未采用。残余: 进程被强杀时 %TEMP% 下可能残留一个 .tmp（系统目录，无害） | 57c418f |
| ✅ 已解决 | P2: .bat 家族重构 — 新建 lib/common.bat（dispatch + lookup_bitrate 读 CSV + 公共子程序），4 个编码 bat 450→191 行，固定临时文件改 %TEMP% 唯一名，avc_qsv.bat 修正为 AVC 码率表（旧版误用 HEVC 表）。**沙箱无法运行 cmd.exe，静态验证通过，待用户手动冒烟** | 57c418f |
| ✅ 已解决 | 冒烟反馈修复: common.bat lookup_bitrate 比较方向写反（`max_pixels leq pixels` 应为 `pixels leq max_pixels`），导致永远命中表第 1 行 → TARGET_BITRATE 异常小 → percentage=0 → "bitrate abnormal"。修复后与 .sh 语义一致（向上取档），1080p60 实测预期: AVC TARGET=3836249 (21%) / HEVC TARGET=2548951 (14%)。banner 处 `'�使用方式:'` 报错为 cmd 65001 代码页已知解析 bug，原版即有、纯观感，决定保持 UTF-8 现状 | dfd998a |
| ✅ 已解决 | cp65001 解析漂移治本（保持 UTF-8 前提下）: 5 个含中文的 bat（4 编码器 + copy_to_mp4）头部加 ASCII 守卫块——先 chcp 65001 再以 `cmd /c call "%~f0" __cp65001 %*` 子进程重启自身，使整个文件自进程启动起就在 UTF-8 控制台下解析，消除文件中途切换代码页的重读漂移；守卫内 `shift` 剥离标记，参数流转与退出码（exit /b %errorlevel%）不变。5 个纯 ASCII bat（convert_from_list×3 / opencmd / repack）无解析风险，不动（其 chcp 供 for /f 读 UTF-8 list.txt，保留）。**依据: cmd 用打开文件时的代码页解析 .bat，文件中途 chcp 对解析自身不可靠（SO/掘金实测互证）；cp936 方案因 list.txt 为 UTF-8 且 GBK 表示力不足被否决** | 26ccf0e |
| ✅ 已解决 | sh 族可移植性核查: ffmpeg/ffprobe 经 `command -v`/PATH 解析（三环境切换即换 PATH），脚本与 CSV 以 SCRIPT_DIR/realpath 自锚定，无硬编码依赖；仅 av1_nvenc/av1_qsv 的 Linux 分支前置 `/opt/ffmpeg` master 构建——属软偏好（缺失时回退发行版），已补 `-d` 存在性守卫 | (本次) |
| ✅ 已解决 | 守卫优化 + 去绝对路径: ① 守卫增加"控制台已是 65001 则零开销直通"快路径（经 opencmd.bat 或已 UTF-8 控制台运行时无子进程、参数零再解析；chcp 输出解析用"冒号后子串"方式，中英文系统通用）；② 新增 lib/common.bat `find_ffmpeg`——ffmpeg/ffprobe 四级回退定位（环境变量 FFMPEG_BIN > 仓库内 ffmpeg\bin > PATH(where) > C:\Program Files\ffmpeg\bin），5 个 bat 移除硬编码路径，repo 可复制/异机 clone；QSV/NVENC 脚本仍要求构建含对应编码器（见 environment_matrix），异机用 FFMPEG_BIN 指定 | 8e5c631 |
| ✅ 已解决 | **自动化冒烟第一轮暴露并修复守卫回归**（探针 `smoke_ffmpeg_bat.bat` 一次双击跑完：4 编码器 + copy_to_mp4 + 交互输入 + 新进程 UTF-8 + list 模式）。实测：936 控制台（= 双击/拖放的默认起点）下 5 个 bat 全部在 banner 之后立刻报 `The system cannot find the path specified.` + `找不到 ffmpeg.exe`。**根因**：守卫用 `shift` 剥离 `__cp65001` 标记，而 **`shift` 连 `%0` 一起移位**（MS Learn 原文：shifts "the batch parameters %0 through %9 … the value of %1 is copied to %0"），于是 `%~dp0` 变成标记符自身的路径（= 当前目录），`%~dp0lib\common.bat` 解析失败 → errorlevel 1 → NO_PATH_ERR。**修复**：① 标记改环境变量 `FB_UTF8_GUARD`（不碰 `%0` 与参数，也免掉参数再过一次 `cmd /c` 再解析）；② 去掉"已 65001 直通"快路径，**总是以新 cmd 进程重启**（新进程自字节 0 按 UTF-8 读取本文件）；③ 5 个 bat 的 `lib\common.bat` 调用全部改 `%SELF_DIR%` 锚定（`SELF_DIR` 在文件首行捕获）。同一轮证据：936→子进程重启路径下 **banner 中文完全正常**，`欢迎使用ffmpeg视频压缩批处理工具` / `您有两种使用方式:` 均未再出现 `'�使用方式:' is not recognized` | 4ffd990 |
| ✅ 已解决 | **自动化冒烟第二轮暴露并修复三类真实缺陷**（探针 v2 一次双击：4 编码器 A 用法 + copy_to_mp4 + 交互输入 B + 新进程 C + 静音输入 + list 模式）。<br>**① 守卫标记经环境变量泄漏（P1，首次修复引入的回归）**：守卫 `set "FB_UTF8_GUARD=1"` 写在 `setlocal` 之前，`call` 场景下标记留在**调用者**环境里（list 驱动 bat 调编码器、或同一 cmd 会话里跑第二次），后续调用直接 `goto main` 跳过守卫 → 936 解析下 banner 腰斩报错复现（本轮日志 T2/T9 取证）。修复：守卫首行加 `setlocal`，标记只存活于本次调用（子进程仍继承）。<br>**② `-map 0:a` 缺 `?`（P2，原版即有）**：静音输入（无音轨）被 ffmpeg 判 `Stream map '' matches no streams` + `Failed to set value '0:a'` → errorlevel -22，整条转码失败、无输出（本轮 T10 静音素材取证；同文件里 `-map 0:s?` 本来就有 `?`，属遗漏）。修复：18 处统一改 `-map 0:a?`（4 bat + 14 sh）。<br>**③ list 驱动 bat 三个缺陷（P2，原版即有、从未重构）**：`for /f "delims=" %%i in (%SRC_FILE%) do <enc>.bat "%%i"` —— 缺 `call`（cmd 链式语义下不返回，只处理清单第一项）、清单路径未用 `usebackq` 引号化（传引号路径时被当成字面串，本轮 T9 实测 ffmpeg 收到 list.txt 本身）、编码器裸名调用（要求 cwd = 仓库）。修复：`for /f "usebackq delims=" %%i in ("%SRC_FILE%") do call "%~dp0<enc>.bat" "%%i"`（4 个 bat） | (本次) |
| ✅ 已解决 | 探针 v2 自身缺陷修正：素材复用导致旧（无音轨）片源未重生成 → 4 个编码器全挂在 `-map 0:a`（T1–T4 假 FAIL）；v3 改为每轮强制重生成素材并用 `-t` 限长避免 `-shortest` 双无限源挂起风险；T10 静音测试由 INFO 升级为断言（`-map 0:a?` 回归测试）；新增全局 banner 检查行（任一日志含 `is not recognized` 即 FAIL） | (本次) |
| ✅ 已解决 | **自动化冒烟第三轮：.bat 家族主链路全绿**。探针 v3 一次双击结果：T1 AVC-QSV / T2 HEVC-NVENC / T3 HEVC-QSV / T4 libx265 / T5 copy_to_mp4 / T6 交互式输入 / T7 新进程 UTF-8 / T10 **静音输入**（`-map 0:a?` 生效）**全部 PASS**，`TARGET_BITRATE` = 3836249(AVC) / 2548951(HEVC) 与码率表一致，**全局 banner 检查 `[PASS]`**（原 `'�使用方式:' is not recognized` 彻底消失，三种用法下均干净）。副产物：`*_probe.txt` 由 ffprobe 复核每个产物的编解码/分辨率。<br>同轮暴露 **list 驱动 bat 第 4 个缺陷**：`SET SRC_FILE=%1` 保留了参数自带引号，使 `in ("%SRC_FILE%")` 展开成`双重引号`路径 → cmd 报 `The system cannot find the file "…\list.txt"`（rc=123，0/2 产物）。已改为 `%~1` 去引号 + `if not "%~1"==""` 判空（4 个 bat，commit 2a58d97）；探针 v4 增加 T12（无参数 + cwd 在别处，验证 `list.txt` 相对 cwd 的默认用法与 `%~dp0` 锚定的 cwd 无关性） | (本次) |
| ✅ 已解决 | **自动化冒烟第四轮：.bat 家族 list 模式全绿，探针复核闭环**。`smoke_ffmpeg_bat.bat ... LIST` 结果：**T9**（cwd=仓库，含空格路径清单）**2/2 产物 rc=0**、**T11**（UTF-8 清单 + 中文文件名）**2/2 rc=0**、**T12**（无参数 + cwd 在别处，走 list.txt 相对 cwd 的默认用法）**2/2 rc=0**，全局 banner 检查 `[PASS]`（三份日志均无 `is not recognized`）。<br>**T11 是当初选 UTF-8 而非 cp936 的实证**：日志中 `for /f` 从 UTF-8 清单读出的中文名完整无损 —— `-i "…\中文 测试.mp4"` → `Output #0 … to '…\中文 测试-compressed.mp4'`，两个条目（含空格名 `list b.mp4`）全部处理。<br>**T12 的 cwd 判定被独立佐证**：仓库内恰有一个旧的无意义 `list.txt`（内容 `exam  ple.mp4` 等不存在文件），若误读它必然 0 产物；实测 2/2 → 确认读的是 cwd 下的清单。 | (本次) |
| ✅ 已解决 | **sh 族端到端复核 + 修掉 2 个此前未被任何测试覆盖的缺陷**（沙箱可直接跑 bash，故本轮由 AI 自行实跑，无需用户介入）。<br>**基线验证**：6 个 sh 编码入口逐个实跑（hevc_nvenc / av1_nvenc / avc_qsv / hevc_qsv / libx264 / libx265）均 **rc=0 且产出文件**；`-map 0:a?` 回归确认：静音输入下 ffmpeg 报 `Stream map '?' matches no streams; ignoring.` 并**继续转码、rc=0、产物生成**（修复前为 `Failed to set value '0:a'` → errorlevel -22 整条失败）；中文名 `中文 测试.mp4` → `中文 测试-compressed.mp4` 正常。<br>**① `check_file_is_text` 悬空调用（P1，重构漏搬）**：4 个 list 脚本（cuda/qsv/libx265/repack）仍调用该函数，但 P1 重构把各脚本内联的重复实现删除后**未搬进 lib/common.sh** → 运行时 `command not found`（非致命但是哑弹）。已按原实现补进公共库，并加无 `file` 命令环境的兜底（NUL 字节探测；git-bash 常见无 `file`）。<br>**② 清单文件 CRLF/BOM 兼容（P2，原版即有）**：`run_list` 用 `while IFS= read -r`，**Windows 记事本保存的 CRLF 清单会把 `\r` 带进路径** → 第一项即 `file not exists!` → `Convert failed！` 退出（实测 rc=1、0 产物）；而 .bat 侧 `for /f` 天然吞 CRLF，形成 sh/bat 行为不一致。已修：行尾 `${line%$'\r'}` 去 CR + 首行剥 BOM。修复后 4 个 list 脚本在 **CRLF+BOM 清单**下全部 rc=0、各 2/2 产物。 | (本次) |
| ✅ 已解决 | **lib 调试输出清理 + 新增 `check_isvideo` 输入守卫（.bat 侧补上与 .sh 对等的前置校验）**。<br>**① 清理遗留调试 echo（原版即有、P1 重构时原样迁移过来）**：`lib/common.bat` 的 `:calc_bitrate_fromsize`/`:extract`/`:extract_mp4` 共 14 行调试输出（`in extract()`、`%~dp2`、`%~d2`、`"%~n2"`、`%~x2`、`"%~n2-compressed.mp4"`、`in extract_mp4()`、`"%~n2.mp4"`、`!fpA!`、`!fpB!`、`%numA% / %numB% = !div!`、`ret=`），每次转码都刷屏（T9 日志取证：单次 `:extract` 就吐 6 行噪声）。已全部删除，函数体语义逐字节不变（仅删整行，带 CRLF 断言）。<br>**② 新增 `lib/common.bat :check_isvideo`**：与 .sh 的 `check_file_isvideo` 对齐 —— ffprobe 取 `-select_streams v:0 stream=codec_type`，为空即打印 `[check_isvideo] "<file>" 不是视频文件, 未检测到视频流` 并 `exit /b 1`；探测命令已在沙箱实测（真视频→`video`、纯音频→空、不存在文件→空、**静音视频→`video` 不误伤**）。接线于 **5 个 bat**（4 编码器 + copy_to_mp4，后者置于 `suffix is not mp4` 早退分支之后）→ `if errorlevel 1 exit /b 3`（新增专用退出码 3）。<br>**为何这个缺口此前是真问题**：无视频流输入时 `SRC_PIX=0`、`SRC_FRAMERATE` 为空，`percentage` 可能落在 0~100 之间从而**不触发** `bitrate abnormal` 分支，用户最终只看到 ffmpeg 的英文 `Stream map '' matches no streams` —— 而 `.sh` 侧一直有中文前置拦截，属 sh/bat 行为不一致。<br>**探针 v5 新增两条断言**：T13（audio-only 输入必须被提前拒绝：日志含 `check_isvideo`、**不含** `matches no streams`〔证明根本没走到 ffmpeg〕、无产物、rc=3）+ 全局 hygiene 行（任一日志含 `in extract` / `ret=` 即 FAIL）<br>**第五轮实测（v5 探针全量跑完，2026-09-16）**：T1–T13 **全部 PASS** —— T13（纯音频输入）被 `check_isvideo` 提前拦下：rc=3、日志**无** `matches no streams`（证明确实没走到 ffmpeg）、无产物；全局 `banner check` 与 `debug check` 双双 `[PASS]`（14 行调试 echo 清零后，日志里再没有 `in extract` / `ret=`）；list 三测 T9/T11/T12 2/2 保持全绿 | 6826a9b |
| ✅ 已确认 | **`-map 0:v` 保持严格、不加 `?`（设计决策，附实测对照）**：纯音频输入实测 —— `-map 0:v -map 0:a?` → ffmpeg 报 `Stream map '' matches no streams` + `Failed to set value '0:v'`，无产物、非零退出；改 `-map 0:v?` → **rc=0 且静默产出只有音轨的 mp4**（对视频压缩工具而言是"错误的成功"）。故 `0:v` 作为工具目的本身应当失败而非降级，`?` 只给真正可选的 `0:a?`（无音轨的录屏/延时摄影是合法输入，且当时无其他守卫）与 `0:s?`。全仓 14 处 `-map 0:v -map 0:a? -map 0:s?` 完全一致。**该「疑点」已于 6b 更正**：`%SRC_FILE:&=^&%` **并非缺陷** —— 它是在补偿「包装写法」造成的不配对（`^` 之所以必要，正是因为那里已经"没有引号可用"，详见第六轮条目）；6a 把这个补偿当缺陷删掉、又把 `set` 改成包装写法，反而造成了回归 | 本次核查 |
| ⚠️ 已修正 | **第六轮 6a 首版探针实测: 20 例仅 13 绿 —— 该轮改动本身引入了回归**。part A 13/20（`&`、`( )`、`&`+`( )` 混合、子目录含元字符 共 7 例红）、part C 完整编码 0/3、part B 清单驱动 2/6（只有不含 `&`/`( )` 的 `smoke_plain` 与 `smoke_bang ! test` 成功）、part D 0/1。日志把失败钉在三处: `SET "RUN_COM=%RUN_COM% -i %SRC_FILE% …"`（`&` 处断行 → `RUN_COM0` 截断在 `-i`、报 `'B' is not recognized`、`TARGET_FILE` 随后也被清空）、`set "RUN_COM=%RUN_COM% %TARGET_FILE%"` 与新增的 `set "TARGET_FILE="…""`（`( )` → `was unexpected at this time`）。**根因即「包装写法」本身**，见下一行 | d1ddca3 实测 |
| ✅ 已解决 | **6b 修正: `set "VAR=值"`（包装写法）才是元字符真正的病根 —— 原版的 `^&` 是在补偿它, 不是缺陷**。<br>**机制**: `set "VAR=值"` 靠"剥掉最外层一对引号"工作, **前提是值里不能出现字面量引号**。而本仓库的 `RUN_COM` / `SRC_CODEC` / `SRC_FILE` / `TARGET_FILE` 存的正是"已经用引号包好的路径或整条命令行": 值里第一个引号会与包装引号配对闭合, **其后的路径段落就落进「未加引号区」**, `&` 立即断行、`( )` 触发语法错误。原版把 `&` 预转义成 `^&`, 正是因为那里"已经不在引号内", 靠 `^` 在未引号区转义 —— **这是补偿, 不是缺陷**（6a 把"引号内 `^` 是字面量"孤立套用, 得出了反向结论）。<br>**修法**: 凡是「值里会出现引号」的 `set` 一律改非包装写法 `set VAR=值`（整行引号配对平衡, `& ( ) ^` 全落在引号内被保护）, 同时去掉不再需要的 `^&` 补偿; 共 **5 文件 57 行**。每个脚本头部加「路径/命令行拼接规则」注释块防回退。<br>**日志逆向实证**（同一片名 `A & B (2020).mov`）: `set SRC_FILE="%SRC_FILE:"=%"`（非包装）→ 值完整正确; `SET "RUN_COM=%RUN_COM% -i %SRC_FILE% …"`（包装）→ 截断在 `-i`。<br>**附加收益**: 非包装写法下引号是配对的, 路径里的 `^` 不再被吃掉（原版补偿写法做不到）。<br>**静态复核**: 新增 `audit_set_forms2.py`（查危险 `set` 形态）与 `mini_cmd_scan.py`（用最坏片名展开后逐行找"引号外元字符", 内置已知好/坏行自校准）—— 全仓 0 命中（只剩 `endlocal & set …`、`set /a (…^)/…` 等刻意构造）。<br>**6a 中保留有效的部分**: `%1` 裸展开 → `if not "%~1"==""` + `set "SRC_FILE=%~1"`; 去掉 `call %RUN_COM%`（避免整条命令行被二次 `%` 展开）; 4 个 list 驱动 bat `EnableDelayedExpansion` → `DisableDelayedExpansion`; 编码器 `%SRC_RESOLUTION%` 移出延迟展开块。<br>**验证（探针 v6b, 2026-09-16 实测）**: part A **18 PASS + 1 SKIP**（A07 脱字符）、part C **3/3**、part B **6/6**、part D **SKIP**（见下）、part Z **Z1 PASS** —— 含 `&` `( )` `!` `%` `[ ]` 的片名（含真实形状 `A & B (2020)` / `Tora! Tora! Tora! (1970)` / `A&B!C(2) 100%` 与子目录 `sub & dir (x)`）已能全程走通。**D 为 SKIP, 但机制尚未定论（上一版把原因写成"守卫转发丢 stdin"，已被本轮证据推翻）**: part Z2a/Z2b 实测 `set /p` **在直接 `call` 与经 `cmd /c` 转发两种情况下都能读到被重定向的文件**；而 T 套件的 mode-B 用例把**真实脚本**用**管道**喂 stdin 也是通过的（T6/T7）—— 于是嫌疑收敛到"**文件重定向 + cp65001 重启**"这个组合。新增 part Z2d 用 ASCII 复刻守卫构造专门判别它（若 Z2d 读不到而 Z2a 读得到，则确认是守卫重启丢掉了文件重定向的 stdin）。无论结论如何都只是**探针的取证限制**：真实用法是双击后手输，不受影响。**Z1 PASS**: `Z1.log` 里 `Z1VAL=["…\a & b (c) d!e.mov"]` 原样保住带引号值。**探针自身的坑（本轮新增沉淀）**: 写 Z1 判定行的那句 `>>"%SUM%" echo … with & ( ) ! …` **自己踩了同一个坑** —— 裸 `&` 把该行劈成两条命令, 后半个 ` ( ) !   (rc=…)` 被当命令执行 → `( was unexpected at this time` → 探针当场终止, Z1/Z2 判定行缺失（首跑 summary 停在 `---- part Z ----`）。已改写该行; 并给 `mini_cmd_scan.py` 补了两个盲区: **①只扫仓库内 .bat, 探针在仓库外没被扫到 ②跳过 echo 行**。修正后扫描器可复现（旧行标红 col 59、新行干净）, 且全仓 + 两个探针 **0 命中**: A 19 例（A07 片名含脱字符 SKIP: `call` 二次解析会让 `^` 翻倍, 探针无法既建同名文件又传参; 片库无此字符）+ C 3 例 + B 6 例 + D（stdin 判定改 PASS/SKIP/FAIL）+ **新增 part Z 构造微测**（Z1 = 非包装 `set` 保住含 `& ( ) !` 的带引号值; Z2a/Z2b = 分辨 `set /p` 读不到重定向 stdin 是 `set /p` 本身还是 cp65001 守卫的 `cmd /c` 转发丢 stdin）。<br>**已知边界**: `call` 传参链路仍会二次解析 `%`（片名 `a%b%c` 形态仍失败, `100% Wolf.mp4` 这种单 `%` 安全）; **文件名含 `^` 不受支持**; 「仓库自身路径含 `!`」不受支持 —— 均与片库路径无关 | 本次 |
| ✅ 已解决 | **Linux（C 机 Ultra 7 265K / Ubuntu 22.04）矩阵实测 + 1 个 Linux 专属 P1 修复**（2026-09-16）。**底层**：两套 ffmpeg 来源全量实测 —— 原生 4.4.2：h264_qsv/hevc_qsv/h264_vaapi/libx264/libx265/libaom ✅，av1_qsv 未编入、**hevc_vaapi ⛔**（`Failed to end picture encode issue: 24`；iHD 25.2.4 对本核显只暴露 `EncSlice` 无 `EncSliceLP`，`low_power=1` 报 `No usable encoding entrypoint found`，默认路径 master 通过而 4.4.2 报错 → 构建与新版 iHD 的兼容问题，非硬件限制）、QSV 硬解 ⛔（`Device setup failed for decoder`）、VAAPI 硬解 70fps 反慢于软解 312fps；master-gpl（N-117740）：QSV 三件套（含 av1_qsv，1080p60/4K30）+ VAAPI 三件套（含 av1_vaapi）+ svtav1/aom 全绿，4K HEVC 硬解 QSV 415fps / VAAPI 380fps > 软解 339fps，AV1 硬解日志 `Selecting decoder 'av1_qsv'`。**脚本层**：native 轮除 hevc_vaapi（同上）与两个 NVENC（无 N 卡，rc=1 预期）外全绿；master 轮 7/7 全绿；1080p60 降帧分支与查表值（HEVC 2548951 / AVC 2040182 / AV1 951915）正确；纯音频/不存在文件/多参数三边界均 rc=1 + 中文提示。<br>**① 修复（P1，Linux 专属）：`run_list` stdin 泄漏** —— `while read` 循环以 `done < "$list_file"` 供输入时子进程继承该 fd，**Linux 版 ffmpeg 会从 stdin 吃走 1 字节**（键盘交互探测；同循环三对照微测：ffprobe 不读、ffmpeg 破坏、`ffmpeg -nostdin` 不破坏）→ 清单第 2 条起路径被啃掉开头字符 → `file not exists!` → `Convert failed！` 提前退出（修复前 qsv/repack 两测均 1/2 产物即退）。已改为 `bash "$script" "$line" < /dev/null`；修复后 3 条（CRLF+BOM/中文/空格）清单逐条读全、第 3 条因重复项被 `-n` 拒写属预期。`.bat` 侧 `for /f` 天然无此问题（又一处 sh/bat 行为不一致）。<br>**② 环境坑（非仓库）**：`vainfo` 需 `export LIBVA_DRIVER_NAME=iHD` 才正常（libva 新枚举 API 报 `vaGetDriverNames() failed`），ffmpeg 不需要（走旧 `vaGetDriverName`）。<br>**③ 待决三项已于同轮全部处置**：`ffmpeg_h264_vaapi.sh` 漏改查表 → 改传 `bitrate_table_avc.csv`（720p ref 1359878→2040182，与 libx264 一致）；`ffmpeg_libx264.sh` 无执行位 → `chmod +x`；`ffmpeg_hevc_vaapi.sh` 4.4.2/iHD 兼容问题 → 仿 av1_qsv 加 /opt 软偏好（复测 rc=0，产物 encoder=Lavf61.9.100 为 master 构建指纹）。三项均端到端复测通过。详见 environment_matrix.md「机器 C：Ubuntu 22.04 实测记录」 | 本次 |
| 🔲 待办 | A 机（i7-9700T）Linux/Win11 实测；C 机 Win11 行；matrix 清单 13（A 机 Ubuntu 首次上机时复跑 list 用例）。见 environment_matrix.md 待验证清单 | — |

**验证状态**：全部 14 个 .sh 重构完毕，eval 与 if-elif 查表在 .sh 中清零；试点+推广脚本在 Cygwin / MSYS2 mingw64 / 原生 gyan 三套 ffmpeg 下端到端验证通过（Cygwin 的 QSV 与 libx264/libx265 为构建限制，见矩阵文档）。

---

## 一、项目概述

这是一个 FFmpeg 视频压缩批处理工具集，核心功能：

1. 根据视频分辨率（像素总数）查表选取目标码率，将视频转码为 H.265/HEVC（或 AV1/H.264）格式
2. 支持多种硬件加速：Intel QSV、NVIDIA NVENC、AMD VAAPI、软件 libx265
3. 提供批量转换（从 list.txt 读取文件列表）和单文件转换两种模式
4. 同时提供 Windows `.bat` 和 Linux `.sh` 版本

**整体评价：功能可用，但工程质量较低。** 作为一个个人工具脚本集，它完成了预期的工作；但从代码质量角度审视，存在大量可维护性和健壮性问题。

---

## 二、严重缺陷（Critical / High）

### 2.1 🔴 大规模代码重复 — 94 分支码率查表被复制 11 次

**严重级别：Critical**

这是最突出的问题。一个包含 **94 个 elif 分支**的码率查找表（从 `SRC_PIX leq 12288` 到 `leq 141557760`），被完整复制粘贴到以下文件中：

| 文件                            | 行数   |
| ----------------------------- | ---- |
| `ffmpeg_hevc_nvenc.sh`        | 607  |
| `ffmpeg_hevc_nvenc_cygwin.sh` | 607  |
| `ffmpeg_libx265.sh`           | 604  |
| `ffmpeg_hevc_qsv.sh`          | ~607 |
| `ffmpeg_av1_nvenc.sh`         | 628  |
| `ffmpeg_av1_qsv.sh`           | 628  |
| `ffmpeg_avc_qsv.sh`           | 607  |
| `ffmpeg_h264_vaapi.sh`        | 609  |
| `ffmpeg_hevc_vaapi.sh`        | 608  |
| `ffmpeg_hevc_nvenc.bat`       | 641  |
| `ffmpeg_hevc_qsv.bat`         | 659  |
| `ffmpeg_avc_qsv.bat`          | 643  |
| `ffmpeg_libx265.bat`          | 634  |

此外，辅助函数（`check_param_number`、`check_file_exists`、`check_file_isvideo`、`check_file_codec`、`check_file_framerate`、`check_file_resolution`、`check_file_size`、`check_file_duration`、`check_file_bitrate`）也完整复制在每个 .sh 文件中。

**特别荒谬的例子：**

- `ffmpeg_hevc_nvenc.sh` 与 `ffmpeg_hevc_nvenc_cygwin.sh` 仅 **1 行不同**（hwaccel 参数），其余 606 行完全一致
- `ffmpeg_hevc_nvenc.sh` 与 `ffmpeg_libx265.sh` 约 90% 代码相同，仅编码器选择和部分参数不同

**影响：** 任何一处修改（如调整码率值）需要同步修改 11+ 个文件，极易遗漏导致不一致。

### 2.2 🔴 `eval` 执行拼接命令字符串 — 注入风险

**严重级别：High**

所有 .sh 脚本通过字符串拼接构建 ffmpeg 命令，然后用 `eval` 执行：

```bash
RUN_COM="ffmpeg -hide_banner -threads 0 -v verbose"
RUN_COM="${RUN_COM} -init_hw_device qsv=hw:0 -filter_hw_device hw -hwaccel cuda -hwaccel_output_format cuda -i \"${ABS_NAME}\""
# ...
eval "${RUN_COM}"
```

如果文件名包含反引号、`$()`、分号等 shell 元字符，`eval` 会执行注入代码。虽然文件名通常由用户自己提供，但这仍是不安全的模式。

**正确做法：** 使用数组构建命令参数，直接执行：

```bash
ffmpeg_args=(ffmpeg -hide_banner -threads 0 -v verbose -i "$ABS_FILE" ...)
"${ffmpeg_args[@]}"
```

### 2.3 🔴 .bat 文件使用固定名称临时文件 — 竞争/符号链接攻击

**严重级别：High**

`ffmpeg_hevc_nvenc.bat` 等脚本将 ffprobe 输出写入当前目录的固定文件名：

```bat
%SRC_CODEC% > "temp"
set /p SRC_CODEC=<"temp"
del "temp"

%SRC_RESOLUTION% >  "temp.txt"
%SRC_SIZE% > "size"
%SRC_DURATION% > "duration"
%SRC_BITRATE% > "bit_rate"
```

这些可预测的文件名存在以下风险：

- 并发执行多个实例时互相覆盖
- 恶意用户可预先创建同名符号链接指向敏感文件
- 脚本异常退出时残留垃圾文件

**正确做法：** 使用 `%TEMP%` 目录下的随机文件名，或使用 `for /f` 直接捕获命令输出。

### 2.4 🟠 无 .gitignore — 大文件误提交风险

**严重级别：High**

仓库中 **没有 .gitignore 文件**。工作目录中存在大量不应纳入版本控制的大文件：

| 文件                             | 大小        |
| ------------------------------ | --------- |
| `input_4k25.mov`               | 1.96 GB   |
| `input_1080p60.mov`            | 269 MB    |
| `input_1080p60-compressed.mp4` | 27 MB     |
| `input_4k25-compressed.mp4`    | 424 MB    |
| `output_hevc_libx265_cbr.mp4`  | 642 MB    |
| 其他 output_*.mp4                | ~100 MB 各 |

虽然这些大文件目前未被 git 跟踪，但没有任何机制防止误操作。`heif-tool.7z`（2.7 MB 二进制压缩包）已被提交到 git 仓库中。

---

## 三、中等缺陷（Medium）

### 3.1 IFS 设置错误导致带空格文件名处理失败

所有 .sh 脚本开头设置：

```bash
IFS=$(echo -en "\n\b")
```

然后在批量处理中使用：

```bash
for line in $(cat ${LIST_FILE})
```

这设置 IFS 为换行符和退格符，但 `$(cat ...)` 未加引号仍会进行分词。正确处理带空格文件名的方式应该用 `while read` 循环（代码中已有注释掉的版本）：

```bash
while IFS= read -r line; do
    ./ffmpeg_xxx.sh "$line"
done < "$LIST_FILE"
```

### 3.2 变量未加引号

大量地方使用未加引号的变量扩展：

```bash
echo $line              # 应为 echo "$line"
echo $SRC_FRAMERATE     # 应为 echo "$SRC_FRAMERATE"
echo $SRC_RESOLUTION    # 应为 echo "$SRC_RESOLUTION"
for line in $(cat ${LIST_FILE})  # 应为 "$LIST_FILE"
```

这在文件名包含空格或特殊字符时会出错。

### 3.3 .bat 码率查找表存在重复分支

`ffmpeg_hevc_nvenc.bat` 中的 if-else 链有重复条件：

```bat
) else if %SRC_PIX% leq 153600 (   rem 12M<br<16M, 30%
    set /a BIT=678641
) else if %SRC_PIX% leq 153600 (   rem 12M<br<16M, 30%   ← 重复！
    set /a BIT=678641
```

同样 `leq 168960`、`leq 202752`、`leq 3686400` 各出现两次。虽然不影响结果（值相同），但表明是复制粘贴时的疏忽。

### 3.4 Bash 赋值语法错误

`ffmpeg_hevc_nvenc.sh` 第 517 行（及所有同类 .sh 文件）：

```bash
TARGET_BITRATE = "$TARGET_BITRATE_1"    # 错误！等号两边有空格
```

Bash 中变量赋值 **不能有空格**，这行实际上会报错 `command not found: TARGET_BITRATE`。正确写法：

```bash
TARGET_BITRATE="$TARGET_BITRATE_1"
```

这意味着交互模式下手动输入码率的功能从未生效。

### 3.5 硬编码路径

.bat 文件硬编码 ffmpeg 路径：

```bat
set FFPROBE_PATH=C:\Program Files\ffmpeg\bin\ffprobe.exe
set FFMPEG_PATH=C:\Program Files\ffmpeg\bin\ffmpeg.exe
```

如果用户安装在其他位置则无法工作。.sh 版本正确地使用了 `command -v` 检查 PATH。

### 3.6 大量死代码和调试残留

- .bat 文件中有调试标记 `aaaaaaaa`、`bbbbbbbb`、`cccccccc`、`dddddddd`、`eeeeeeee`、`fffffffff`、`gggggggggggg`
- 每个 .sh 文件开头都有 25 行 ABS 内部变量参考注释（完全相同）
- 大段注释掉的旧代码（替代方案、实验性代码）
- 被注释掉的函数 `name_output_file`、`DivideByInteger` 等

### 3.7 错误处理不一致

- `check_file_exists` 在函数内直接 `exit 1`，无法被调用方捕获处理
- `check_file_size` 使用 `return 1`，但调用处未检查返回值
- 部分函数 `echo` 错误信息后 exit，部分 return，没有统一模式

---

## 四、低级别问题（Low）

### 4.1 拼写错误（已传播到所有文件）

| 错误                  | 正确                        | 出现位置                   |
| ------------------- | ------------------------- | ---------------------- |
| `check_file_istext` | `check_file_is_text`      | convert_from_list_*.sh |
| `unnomal`           | `abnormal`                | 多处错误提示                 |
| `TEAR DOWN`         | `GEAR DOWN` / `TURN DOWN` | .bat 文件                |

### 4.2 Git 提交信息无意义

20 条最近的 git log 中，18 条是 `update:`，无法从历史中了解变更内容。

### 4.3 `heif-tool.7z` 二进制文件纳入 git

2.7 MB 的 7z 压缩包被 git 跟踪。应使用 Git LFS 或作为 GitHub Release 附件。

> **作者决策（2026-09-15）**：保留入库，.gitignore 中压缩包规则已相应移除。

### 4.4 码率查找表应该是数据而非代码

94 个硬编码的 `if-elif` 分支本质上是一张像素数→码率的查找表，数据来源于 `bitrate_calc.xlsx`。应将其提取为外部数据文件（CSV/JSON），用脚本读取，而非硬编码在源码中。

> **✅ 已落地**：现为 `lib/` 下三张 CSV（hevc/avc/av1），`lookup_bitrate` 按编码器选表；后续改码率只需改 CSV。

### 4.5 `list.txt` 包含个人文件路径（隐私风险）

工作目录中的 `list.txt` 包含真实的个人文件路径，虽然 git 跟踪的是示例内容，但工作目录中的实际内容如果误提交会泄露隐私。

---

## 五、改进建议

### 5.1 架构重构（最高优先级）

> **✅ 已落地（方案 A 变体，2026-09-15）**：未合并为单一 `ffmpeg_encode.sh`，而是保留各编码器独立入口文件（使用习惯零变化），内部全部 `source lib/common.sh`。实际结构如下：

```
ffmpeg_bat_git/
├── lib/
│   ├── common.sh              # 公共函数（check_file_* 等 10 个 + lookup_bitrate + run_list）
│   ├── bitrate_table_hevc.csv # HEVC 码率数据（xlsx output 页 G 列去重）
│   ├── bitrate_table_avc.csv  # AVC 码率数据（xlsx output 页 H 列 H7~H105）
│   └── bitrate_table_av1.csv  # AV1 码率数据（HEVC 表按分辨率档位打折）
├── ffmpeg_hevc_nvenc.sh       # 各编码器独立入口（14 个 .sh，内部结构统一）
├── convert_from_list_*.sh     # 批量处理（调用 run_list）
├── environment_matrix.md      # 环境×硬件能力矩阵
├── .gitignore
└── readme.md
```

原设想的统一入口方案（`--encoder` 参数）保留给 .bat 家族重构时参考：

```
ffmpeg_bat_git/
├── lib/
│   ├── common.sh          # 公共函数（check_command, check_file_*等）
│   ├── bitrate_table.sh   # 码率查找表（函数，接受像素数返回码率）
│   └── bitrate_table.bat  # Windows 版码率查找
├── ffmpeg_encode.sh       # 统一编码脚本，通过参数选择编码器
├── ffmpeg_encode.bat      # Windows 统一编码脚本
├── convert_from_list.sh   # 批量处理脚本
├── convert_from_list.bat
├── bitrate_table_hevc.csv # 码率数据（从 xlsx 导出）
├── .gitignore
└── readme.md
```

**统一编码脚本设计：**

```bash
#!/bin/bash
# 用法: ./ffmpeg_encode.sh --encoder nvenc|qsv|vaapi|libx265 [文件名]
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/bitrate_table.sh"

ENCODER="${1:-hevc_nvenc}"
SRC_FILE="${2:-}"
# ... 统一逻辑，仅编码器参数不同
```

### 5.2 码率查找表改为数据驱动

> **✅ 已落地**：`lookup_bitrate` 位于 `lib/common.sh`，默认读 `lib/bitrate_table_hevc.csv`，第二参数可选 `bitrate_table_avc.csv` / `bitrate_table_av1.csv`。以下为实现示意（实际版本含 CR 剥除与错误处理）：

将 94 分支 if-elif 替换为读取 CSV 文件：

```bash
# lib/bitrate_table_hevc.csv 格式:
# max_pixels,bitrate
# 12288,95892
# 19200,135504
# ...

lookup_bitrate() {
    local pixels="$1"
    awk -F',' -v p="$pixels" '
        NR>1 && p<=$1 { print $2; exit }
        END { exit 2 }
    ' "$(dirname "$0")/bitrate_table_hevc.csv"
}
```

### 5.3 消除 eval — 使用数组

> **✅ 已落地**：全部 14 个 .sh 的 ffmpeg 命令均改为数组构建直接执行，实测含空格/括号/方括号的文件名不再有注入风险。

```bash
# 替代 eval "${RUN_COM}"
ffmpeg_cmd=(ffmpeg -hide_banner -threads 0 -v verbose)
ffmpeg_cmd+=(-i "$ABS_NAME")
if (( SRC_FRAMERATE > 31 )); then
    ffmpeg_cmd+=(-r 30)
fi
ffmpeg_cmd+=(-c:v hevc_nvenc -b:v "$TARGET_BITRATE" -n "$TARGET_FILE")
"${ffmpeg_cmd[@]}"
```

### 5.4 添加 .gitignore

> **✅ 已落地**：实际版本见仓库 `.gitignore`（压缩包规则已移除，见 4.3 备注）。

```gitignore
# 输入/输出视频文件
*.mov
*.mp4
*.mkv
*.avi

# 临时文件
temp
temp.txt
size
duration
bit_rate

# 大文件
*.7z

# 列表文件（用户私有）
list*.txt
!list.txt
```

### 5.5 .bat 临时文件改用 for /f

```bat
# 替代: %SRC_CODEC% > "temp" & set /p SRC_CODEC=<"temp" & del "temp"
for /f "delims=" %%i in ('%SRC_CODEC%') do set SRC_CODEC=%%i
```

### 5.6 修复已知 Bug

| Bug                          | 修复                           |
| ---------------------------- | ---------------------------- |
| `TARGET_BITRATE = "$..."` 空格 | 改为 `TARGET_BITRATE="$..."`   |
| `for line in $(cat...)`      | 改为 `while IFS= read -r line` |
| `echo $line` 未加引号            | 改为 `echo "$line"`            |
| .bat 重复分支                    | 删除重复的 `leq` 条件               |

### 5.7 提取公共函数到 source 文件

> **✅ 已落地**：见 5.1。`lib/common.sh` 现含 10 个检查函数 + `lookup_bitrate` + `run_list`（批量清单执行，顺带修复了空格文件名问题）。

### 5.8 合并 nvenc 和 nvenc_cygwin

> **✅ 已落地（保留双入口）**：两脚本均已迁移至公共库，差异仅剩 hwaccel 段各自保留（nvenc_cygwin 的 cuvid 硬解 + hwdownload 是 Cygwin 兼容路径）。是否进一步合并为参数化单脚本，待 .bat 重构时一并决策。

---

## 六、量化评估

> **注**：以下为 2026-08-14 首次评审时的评分，供历史对照。.sh 侧改进完成后，可维护性/健壮性/安全性/代码复用四项已实质改善（.bat 家族与 Linux 平台实测除外），待全部收尾后可做一次复评。

| 维度    | 评分 (1-10) | 说明                                 |
| ----- |:---------:| ---------------------------------- |
| 功能完整性 | 7         | 覆盖了多种编码器和硬件加速，基本功能可用               |
| 代码可读性 | 4         | 大量死代码、调试标记、中英混杂注释                  |
| 可维护性  | 2         | 94 分支查表复制 11 份，任何修改都需同步多处          |
| 健壮性   | 3         | 空格文件名处理失败，eval 注入风险，临时文件竞争         |
| 安全性   | 3         | eval 拼接、固定临时文件名、无 .gitignore       |
| 代码复用  | 1         | 几乎零复用，完全靠复制粘贴                      |
| 版本控制  | 3         | 无 .gitignore，提交信息无意义，二进制入库         |
| 文档    | 5         | 有 readme 但简略，video_compress.md 较详细 |

**综合评分：3.5 / 10（评审时）**

---

## 七、优先级排序的改进路线图

| 优先级 | 改进项                                 | 预期收益                    | 状态 |
|:---:| ----------------------------------- | ----------------------- |:---:|
| P0  | 添加 .gitignore                       | 防止大文件误入库                | ✅ |
| P0  | 修复 `TARGET_BITRATE =` 语法错误          | 交互输入码率功能恢复              | ✅ |
| P1  | 提取公共函数到 lib/common.sh               | 减少 ~60% 重复代码            | ✅ |
| P1  | 码率查找表改为 CSV 数据驱动                    | 94 分支→1 个函数，修改码率只需改 CSV | ✅ |
| P1  | 合并 nvenc/nvenc_cygwin/libx265 为统一脚本 | 11 个文件→1 个脚本+参数         | ✅（方案 A：保留独立入口，内部统一 source lib） |
| P2  | 消除 eval，改用数组                        | 安全性提升                   | ✅（.sh 数组传参；.bat 重构为 call 子程序 + CSV 查表，无 eval/if-elif） |
| P2  | 修复变量引号和文件名空格处理                      | 健壮性提升                   | ✅ |
| P2  | .bat 临时文件消除竞争与残留                   | 消除竞争风险                  | ✅（采用 %TEMP%+RANDOM 唯一名 + 用后即删，见上表说明；字面 for /f 未采用） |
| P3  | 清理死代码和调试标记                          | 可读性提升                   | ✅ |
| P3  | 修正拼写错误                              | 专业性提升                   | ✅ |
| P3  | 规范 git commit message               | 可追溯性提升                  | ✅ |

| 🔲 → ✅ | **6g: 4 个 list 驱动 bat 补 cp65001 守卫**（用户在 cp936 cmd 窗口直跑 `convert_from_list_cuda.bat` 实测触发：文件中途裸 `chcp 65001` 使当前进程的批处理读取器错位，之后 `call` 进来的编码器 bat 含中文的行被吞行首、注释碎片被当命令执行、编码器自身守卫也失效）。修法与编码器同款：ASCII 守卫块 + 环境变量标记 + 重启子进程；全仓从此不存在任何文件中途 chcp。此前「多轮实测稳定」是入口控制台恰好 65001 的运气。|

**遗留事项**：.bat 家族重构与 T1–T13 冒烟已完成；第六轮 6b 的 `set` 写法修正已由探针 v6b 复核通过（A 18 PASS + 1 SKIP / C 3/3 / B 6/6 / D SKIP / Z1 PASS，**D 的 SKIP 机制已由 Z2d/Z2e/Z2f/Z2g/D1 四路判别定论：`chcp 65001` 吃掉文件重定向 stdin（管道与控制台不受影响，真实用法零影响）**）；**随后又跑了 T1–T13 回归套件，全绿**（2026-09-16，新增的 `smoke_all.bat` 一键串跑两层）：4 编码器 × 三种用法共 8 项 **PASS**（含 mode B 交互输入 / mode C 全新 UTF-8 控制台）、`copy_to_mp4` PASS、静音输入 PASS、**T13 纯音频输入被 `check_isvideo` 拦下 rc=3 PASS**、T9/T11/T12 list 三测各 2/2、全局 banner 与 debug 卫生检查双双 PASS。这正好补上矩阵探针未覆盖的面（`hevc_nvenc`/`hevc_qsv`/`libx265`、另 3 个 list bat、banner/debug/`check_isvideo` 断言）—— 6b 对核心路径的改动**未引入回归**）；Linux（A 机）与 Ultra 265K（C 机）平台实测（见 environment_matrix.md）；README/使用说明。
