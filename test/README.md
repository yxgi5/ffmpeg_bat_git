# test/ — 冒烟套件

两族自检套件，**随仓库分发**。套件自己定位仓库根（从脚本所在位置向上两级），
所以克隆到任意路径都能直接跑；运行日志与产物已由 `.gitignore` 排除，不会污染 `git status`。

```
test/
├─ README.md                    本文件
├─ bat/                         Windows 侧（cmd.exe）
│  ├─ smoke_all.bat             合并运行器：双击这一个
│  ├─ smoke_ffmpeg_bat.bat      回归套件 T1–T15
│  └─ smoke_special_chars.bat   路径元字符矩阵
└─ sh/
   └─ smoke_sh.sh               Linux 侧（bash），22 用例
```

## .bat 族（Windows）

双击 `test/bat/smoke_all.bat`，它会依次串跑两套套件，各自落一份汇总：

| 套件 | 汇总文件 |
| --- | --- |
| `smoke_ffmpeg_bat.bat` | `test/bat/smoke_logs/summary.txt` |
| `smoke_special_chars.bat` | `test/bat/chars_logs/summary.txt` |

覆盖范围（T1–T15）：

- 每个编码器入口 × 三种用法（拖放/命令行、双击交互、UTF-8 新窗口）
- 清单模式：2 条目、带空格与 UTF-8 文件名、无参 + 从别的目录双击（T9/T11/T12）
- 静音输入（`-map 0:a?` 回归，T10）；**纯音频输入必须被 `check_isvideo` 拦下**（T13，期望 rc=3）
- AV1 NVENC（T14，需 RTX 40 系及以后的 N 卡）
- AV1 QSV（T15，**先探测硬件再断言**：核显没有 AV1 编码器时记 `[SKIP]`，绝不 FAIL；
  探测日志单独落 `smoke_logs/T15_av1_qsv_probe.txt`）
- 全局卫生检查：任何日志都不得出现 `is not recognized`（cp65001 守卫标记泄漏回归）与 lib 调试输出

夹具全部由 lavfi 现场生成，**不依赖仓库里的媒体文件**（那些文件未纳入版本管理）。
可选参数：`smoke_ffmpeg_bat.bat [repo_path] [LIST]`，第二个参数为 `LIST` 时只跑清单用例。

## .sh 族（Linux / Cygwin / MSYS2）

```bash
bash test/sh/smoke_sh.sh            # 全部 22 用例（默认）
bash test/sh/smoke_sh.sh arg        # 只跑一段: arg | stdin | list | guard | stdinleak
```

环境开关：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `REPO` | 脚本上两级目录 | 仓库根 |
| `WORK` | `${TMPDIR:-/tmp}/ffmpeg_bat_smoke_sh` | 工作/日志目录，`summary.txt` 在其中 |
| `FIXTURE` | `$WORK/fixture.mp4` | 源片；不存在时用 lavfi 自动生成（720p30 5s H.264+AAC） |
| `EXPECT_AV1_QSV` | `fail` | 本机核显有没有 AV1 硬编：Gen9.5 等填 `fail`，Arrow Lake 填 `ok` |

覆盖范围：11 个编码入口（VAAPI / QSV / 软编 / NVENC / Cygwin 变体）的参数模式、交互模式
（含码率覆盖）、清单模式（LF/CRLF + UTF-8 BOM、含空格文件名）、cp65001 守卫、
以及 `</dev/null` 的 stdin 泄漏回归（`done < "$list"` 的 fd 被 ffmpeg 继承后啃掉下一条首字符）。

## 实测状态（截至 2026-09-16）

| 套件 | 机器 | 结果 |
| --- | --- | --- |
| `.bat` | B 机 i9-13900HX + RTX 4080 Laptop / Win11 | T1–T14 PASS、T15 SKIP（Raptor Lake 核显无 AV1 编码）、卫生检查 PASS |
| `.sh` | A 机 i7-9700T / UHD630 / Ubuntu 22.04 | PASS=22 / FAIL=0（distro 优先与 `/opt` master 优先各一轮） |
| `.sh` | C 机 Ultra 7 265K / Arrow Lake / Ubuntu 22.04 | PASS=22 / FAIL=0（`EXPECT_AV1_QSV=ok`，`ffmpeg_av1_qsv.sh` 真产出 AV1） |

机器 × 平台 × ffmpeg 来源的完整矩阵见仓库根 `environment_matrix.md`。

## 与「探针」的区别

环境勘察探针（`probe_*.sh`，逐台机器取证硬件/驱动/构建指纹用）属一次性取证脚本，**不入库**；
这里放的是可重复运行的**回归套件**。
