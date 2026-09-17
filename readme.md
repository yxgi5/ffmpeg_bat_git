# 存档视频压缩码率（ffmpeg_bat_git）

按**分辨率查表**定码率，把收藏的视频压成 HEVC / AVC / AV1 的 mp4 用于长期存档。
同一套逻辑提供两个脚本家族，行为对齐、共用码率表：

- **Windows 批处理**（`*.bat`）：拖放 / 双击 / 命令行 三种用法
- **Linux / Cygwin / MSYS2**（`*.sh`）：命令行 / 交互 两种用法

## 目录结构

```
lib/common.bat             .bat 侧公共函数: 查表 / 路径提取 / ffmpeg 定位 / 视频流校验
lib/common.sh              .sh  侧公共函数: 查表 / 参数检查 / 清单遍历 / 文件校验
lib/bitrate_table_hevc.csv 码率表 (默认)
lib/bitrate_table_avc.csv  AVC 专用表
lib/bitrate_table_av1.csv  AV1 专用表
ffmpeg_*.bat | .sh         单个文件转换入口
convert_from_list_*.bat|sh 按清单批量转换
repack_from_list.bat | .sh 按清单批量无损转封装
opencmd.bat                打开一个 UTF-8(cp65001) 的新 cmd 窗口 (Windows 辅助)
archive/bitrate_calc.xlsx 码率曲线拟合原始表 (早期存档, 历史溯源用)
code_review_report.md      多轮代码评审与冒烟记录
environment_matrix.md      机器 × 平台 × ffmpeg 来源 实测矩阵与待验证清单
test/README.md             测试体系说明（三层：静态检查 / 冒烟套件 / 能力报告）
test/lint/lint.py          静态 + 跨族对等检查器（零依赖，1 秒内跑完）
test/lint/selftest.py      检查器自身的回归测试（recall + precision 双向验证）
test/sh/smoke_ffmpeg.sh    Linux 侧回归套件（T1–T25，与 .bat 套件同 T 编号）
test/bat/smoke_*.bat       Windows 侧冒烟套件（T1–T17 回归 + 元字符矩阵 + 合并运行器）
test/sh/check_env.sh       Linux 侧能力报告（快查 / --probe 深测）
test/bat/check_env.bat     Windows 侧能力报告（双击快查，`"" PROBE` 深测）
```

## 测试体系（三层，各管一件事）

| 层 | 命令 | 回答的问题 | 耗时 |
|----|------|-----------|------|
| ① 静态 + 对等检查 | `python3 test/lint/lint.py` | 代码有没有结构性问题？两族对等吗？ | < 1 秒 |
| ② 冒烟套件 | `bash test/sh/smoke_all.sh` / 双击 `test\bat\smoke_all.bat` | 真实编码跑通了吗？断言对不对？ | 数分钟 |
| ③ 能力报告 | `bash test/sh/check_env.sh [--probe]` / 双击 `test\bat\check_env.bat` | **这台机器**能用哪些入口？ | 秒级 / 数十秒 |

建议顺序：先 ① 后 ② —— 静态检查 1 秒就能抓出行尾/括号/标签/引号/编码问题，不必等几分钟的冒烟跑完才发现。
逐项检查清单、T 编号对照表、SKIP 策略、两族对等矩阵与历史踩坑记录见 **`test/README.md`**。

> 测试套件随仓库分发，运行日志与产物已由 `.gitignore` 排除。
> 套件自己定位仓库根（从脚本位置向上两级），**克隆到任意路径都能跑**。

## 码率怎么来的

码率表是「像素总数 → 参考码率」的分档表，曲线拟合的原始数据见 `archive/bitrate_calc.xlsx`。
三张表各自逼近一条幂律曲线（2026-09-17 全表最小二乘拟合，方法与逐档比例见 `environment_matrix.md` 第 24 条）：

| 表 | 拟合式 bitrate (bps) | 1080p 参考 | 4K 参考 |
| --- | --- | --- | --- |
| `bitrate_table_avc.csv` | `92.5 × pixels^0.779` | 7.67 Mbps | 22.6 Mbps |
| `bitrate_table_hevc.csv` | `65.1 × pixels^0.775` | 5.10 Mbps | 14.9 Mbps |
| `bitrate_table_av1.csv`  | `58.1 × pixels^0.755` | 3.43 Mbps | 9.76 Mbps |

三代编码器的省码比例内嵌在表中：**HEVC/AVC ≈ 0.665 恒定；AV1 表为连续幂律**
`58.1 × pixels^0.755`，对 HEVC 的隐含比例随分辨率从 ≈0.68（720p）缓降到 ≈0.63（8K），无档位台阶。
AV1 定位为软件编码参考表（SVT-AV1 实测等画质 r≈0.53–0.61，本表偏宽松、画质保守侧），见 `environment_matrix.md` 第 25–28 条。

**表的定位**：三张表描述的是*编解码器代际的理论收益*，衡量基准是各代最佳实用软编
（x265 / SVT-AV1），不针对某个硬件编码器校准。硬编入口（qsv/nvenc/vaapi）沿用同表时，
硬件达不到理论收益的部分表现为同码率下画质更低——这是编码器实现折损，不是表的问题；
实测标定见 `environment_matrix.md` 第 25–27 条。

实际目标码率 = **查表值 ÷ 2**（中等质量）；**若源码率本身已低于该值，则沿用源码率**，避免低码率源被重编码放大。

## Windows 用法

每个编码器 bat 都支持三种用法：

1. **拖放**：把视频文件拖到 .bat 上
2. **双击**：按提示输入视频地址
3. **命令行**：`.\ffmpeg_hevc_qsv.bat "D:\video\xxx.mov"`

| 脚本 | 编码器 | 运行条件 |
| --- | --- | --- |
| `ffmpeg_avc_qsv.bat` | H.264 QSV | Intel 核显 |
| `ffmpeg_hevc_qsv.bat` | HEVC QSV | Intel 核显 |
| `ffmpeg_av1_qsv.bat` | AV1 QSV | **Arrow Lake 及更新的 Intel 核显** + 较新的 ffmpeg 构建（老构建没编入 `av1_qsv`） |
| `ffmpeg_hevc_nvenc.bat` | HEVC NVENC | NVIDIA 显卡（cuvid 全硬解链路） |
| `ffmpeg_av1_nvenc.bat` | AV1 NVENC | NVIDIA **Ada 及以后**（RTX 40 系起） |
| `ffmpeg_libx265.bat` | HEVC 软编 | 无硬件要求（保底方案） |
| `ffmpeg_libx264.bat` | H.264 软编 | 无硬件要求（H.264 保底，与 `.sh` 侧对齐） |
| `ffmpeg_copy_to_mp4.bat` | 不重编码 | 仅换容器，已是 mp4 则直接退出 |

**清单批量**（不带参数默认读 `list.txt`，也可指定）：

```
.\convert_from_list_qsv.bat            :: 默认 list.txt
.\convert_from_list_qsv.bat list0.txt
.\convert_from_list_cuda.bat  ...      :: NVENC 版
.\convert_from_list_libx265.bat ...    :: 软编版
.\repack_from_list.bat ...             :: 无损转封装
```

清单文件**每行一个视频路径**，建议存为 UTF-8（含中文名时）。`opencmd.bat` 可开一个 UTF-8 新窗口。

> 所有 `.bat` 内置 cp65001 守卫：不管从什么代码页的窗口启动，都会自动切到 UTF-8 并在新进程中重跑，中文 banner 与中文路径不会乱码。**请勿移除该守卫，也勿在文件中途写 `chcp`。**

## Linux / Cygwin / MSYS2 用法

脚本已带执行位，直接 `./` 调用：

```
./ffmpeg_hevc_qsv.sh                    # 不带参数: 交互输入路径 (可再输入码率覆盖默认)
./ffmpeg_avc_qsv.sh  "/dss/xxx/xxx.mov" # 带参数: 码率与输出名自动决定
./ffmpeg_libx265.sh  xxx.mov
./ffmpeg_libx264.sh  xxx.mov

./convert_from_list_qsv.sh              # 不带参数默认 list.txt
./convert_from_list_qsv.sh list0.txt
./convert_from_list_cuda.sh | _libx265.sh | repack_from_list.sh
```

平台差异（实测见 `environment_matrix.md`）：

- **Cygwin**：ffmpeg 的 QSV 会话初始化失败，且未编入 libx265 → 请用 `convert_from_list_cuda.sh` 或改在 MSYS2 / Linux 下跑
- **发行版自带 ffmpeg 偏旧**：`hevc_vaapi` 在 **4.4.x 全系对 Arrow Lake 核显失效**（4.4.2 与另一个打包者的 4.4.3 报同一错误，**5.1.2 起恢复**；Gen9.5 等老核显的 4.4.2 反而可用 —— 取决于核显代际），AV1 硬编同样要新构建；`av1_qsv.sh`、`hevc_vaapi.sh`、`av1_nvenc.sh` 对 `/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin` 有**软偏好**（存在即前置 PATH，不存在则回退发行版）。**装了这个目录不会改变整机默认**（`which ffmpeg` 仍是 `/usr/bin/ffmpeg`），只有上面 3 个脚本会切到它
- **Linux 的 QSV 硬解只在 master 构建上生效**：发行版 ffmpeg（如 4.4.2）遇到 `-hwaccel qsv` 会**静默回退软解**（不报错，但滤镜像素格式仍是源格式），实际是「软解+硬编」；显式要求硬件设备才报 `Device setup failed for decoder`。想要名实相符的全硬解链路，请把 `/opt/ffmpeg/.../bin` 前置到 `PATH`
- 清单兼容 CRLF 与 UTF-8 BOM（记事本直接存即可）

## ffmpeg 依赖怎么找

- **`.bat`**：`lib/common.bat` 的 `find_ffmpeg` 四级回退
  `FFMPEG_BIN` 环境变量（指向 bin 目录）→ 仓库内 `ffmpeg\bin` → `PATH`（where）→ `C:\Program Files\ffmpeg\bin`
- **`.sh`**：直接用 `PATH` 里的 `ffmpeg`/`ffprobe`（缺任一即报错退出）

## 已知边界与注意事项

| 项 | 说明 |
| --- | --- |
| 行尾 | `.bat` **必须 CRLF**（`.gitattributes` 已锁定 `*.bat -text`），编辑时勿用会改写行尾的工具 |
| 片名元字符 | 空格、`&`、`(` `)`、`!`、`%`（单个）、`[` `]`、`;` `,` `=` `#` `$` `+` `'` `~` `@`、中文 均已实测通过（含 `A & B (2020)`、`Tora! Tora! Tora! (1970)`、子目录 `sub & dir (x)`） |
| 片名含 `^` | **不支持**（`call` 链路二次解析会让脱字符翻倍） |
| 成对百分号 | 片名形如 `a%b%c`（中间是合法变量名）**不支持**；`100% Wolf.mp4` 这类单个 `%` 安全 |
| 清单 BOM | `.bat` 侧 `for /f` 读带 BOM 清单尚未实测（记事本存 UTF-8 无 BOM 时不触发）；`.sh` 侧已兼容 |
| 交互 stdin | 双击后手输不受影响；只有「文件重定向喂 stdin + `chcp 65001`」这一组合读不到（`.bat` 的 UTF-8 守卫所致，非缺陷） |
| 修改 `.bat` 时的 set 写法 | 值为「已带引号的路径 / 整条命令行」的变量，**一律用非包装写法** `set VAR=值`；包装写法 `set "VAR=值"` 会与值内引号配对闭合，使后续路径段落裸露、被 `&`/`()` 截断 |

## 验证状态

测试体系分三层，先用 1 秒的静态检查过滤低层次问题，再跑数分钟的冒烟套件：

| 层 | 命令 | 本机最近一轮（2026-09-16，Win11 + MSYS2 + RTX） |
|----|------|--------------------------------------------|
| ① 静态 + 对等 | `python3 test/lint/lint.py` | `21 PASS / 0 FAIL / 6 WARN`，退出码 0 |
| ① 检查器自测 | `python3 test/lint/selftest.py` | `13 cases / 0 FAIL` |
| ② sh 冒烟 | `bash test/sh/smoke_all.sh` | `PASS=22 FAIL=0 SKIP=4`，`rc=0` |
| ③ 能力报告 | `bash test/sh/check_env.sh [--probe]` | 列出本机可用入口与原因 |

- **`.sh` 家族**：`test/sh/smoke_ffmpeg.sh` 共 **T1–T25**，与 `.bat` 套件**同 T 编号、同夹具、同期望码率**。
  2026-09-16 本机全量 **PASS=22 FAIL=0 SKIP=4**；A / C 两机（Ubuntu 22.04）此前各轮均为全 PASS。
  本轮修掉一个**假 SKIP**：可用性探针夹具原用 128×128，而 NVENC 拒绝初始化这么小的编码器，
  导致本机明明有可用 NVENC，`T2`/`T14`/`T20` 却一直被记 SKIP；改用 320×240 后三条恢复为真实 PASS
  （`T14` 断言 `codec=av1`）。SKIP 现仅剩 VAAPI 两条（Windows 无 DRM 设备）、cp65001（无对应物）、
  AV1 QSV（需 Arrow Lake+ 核显）。
- **`.bat` 家族**：`test/bat/smoke_all.bat`（双击即跑）串跑 T1–T17 回归 + 元字符矩阵。
  硬件相关用例（T1/T2/T3/T7/T14）本轮起也改为**先探测后断言**，与 `.sh` 侧策略一致：
  本机跑不起来记 `[SKIP]` 并留下 `gate_<入口>.log`，而不是记 FAIL —— 让「缺硬件」不再伪装成「仓库有缺陷」。
  `ffmpeg_av1_nvenc.bat`（T14）与 `ffmpeg_libx264.bat`（T16）为本轮新增/补齐入口；
  T15（`ffmpeg_av1_qsv.bat`）在无 AV1 核显的机器上记 SKIP，**待 Arrow Lake+ 的 Windows 机器补证**。
- **架构/对等结论**：两族共享 **12 个编码入口**；`.sh` 独有的 3 个（`h264_vaapi`/`hevc_vaapi`/
  `hevc_nvenc_cygwin`）分别对应 Linux 内核 API 与 Cygwin 专用链路，`.bat` 侧无编码入口缺口
  （`opencmd.bat` 只是开 UTF-8 窗口的辅助脚本）。退出码契约已跨族统一为
  `0 成功 / 1 参数与文件错误 / 2 查表越界 / 3 无视频流 / 5 码率异常`。
- 逐项检查清单、T 编号对照表、SKIP 策略、对等矩阵与踩坑记录见 **`test/README.md`**
- 详细矩阵与逐条记录见 `environment_matrix.md`，各轮缺陷的定位与修法见 `code_review_report.md`

## 硬件加速速查

```
lspci -vnn | grep -i VGA -A 12          # 查显卡
ffmpeg -hide_banner -hwaccels           # 支持的硬件加速方式
ffmpeg -hide_banner -init_hw_device list
ffmpeg -hide_banner -encoders  | grep hevc    # 编入的编码器
ffmpeg -hide_banner -decoders  | grep hevc
vainfo                                  # VAAPI 能力 (新 libva 需 export LIBVA_DRIVER_NAME=iHD)
```

参考：<https://en.wikipedia.org/wiki/Intel_Quick_Sync_Video#Hardware_decoding_and_encoding>
