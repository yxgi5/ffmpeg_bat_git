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
bitrate_calc.xlsx          码率曲线拟合原始表
code_review_report.md      多轮代码评审与冒烟记录
environment_matrix.md      机器 × 平台 × ffmpeg 来源 实测矩阵与待验证清单
```

## 码率怎么来的

码率表是「像素总数 → 参考码率」的分档表，曲线拟合见 `bitrate_calc.xlsx`。
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
| `ffmpeg_hevc_nvenc.bat` | HEVC NVENC | NVIDIA 显卡（cuvid 全硬解链路） |
| `ffmpeg_libx265.bat` | HEVC 软编 | 无硬件要求（保底方案） |
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

./convert_from_list_qsv.sh              # 不带参数默认 list.txt
./convert_from_list_qsv.sh list0.txt
./convert_from_list_cuda.sh | _libx265.sh | repack_from_list.sh
```

平台差异（实测见 `environment_matrix.md`）：

- **Cygwin**：ffmpeg 的 QSV 会话初始化失败，且未编入 libx265 → 请用 `convert_from_list_cuda.sh` 或改在 MSYS2 / Linux 下跑
- **发行版自带 ffmpeg 偏旧**：对 Arrow Lake 等新核显的 `hevc_vaapi` / AV1 支持不全；`av1_qsv.sh`、`hevc_vaapi.sh`、`av1_nvenc.sh` 对 `/opt/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin` 有**软偏好**（存在即前置 PATH，不存在则回退发行版）。**装了这个目录不会改变整机默认**（`which ffmpeg` 仍是 `/usr/bin/ffmpeg`），只有上面 3 个脚本会切到它
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

- **`.bat` 家族**：仓库外探针 `smoke_all.bat` 一键串跑 T1–T13 回归套件 + 元字符矩阵，最近一轮从 **cp936 窗口**启动全绿（4 编码器 × 三种用法、静音输入、纯音频拦截 rc=3、list 三测 2/2、banner/debug 卫生检查、A 18+1SKIP / C 3/3 / B 6/6）
- **`.sh` 家族**：仓库外套件 `smoke_all.sh` 18 用例断言，**PASS=18 / FAIL=0**；15 个入口脚本已在 Ubuntu 22.04 全量实测
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
