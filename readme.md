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
tools/dvd_restore.sh      解压出来的 VIDEO_TS 反向还原成可刻录的 DVD-Video ISO
tools/dvd_repair.sh       补齐解压盘里缺失的 IFO / BUP(缺哪个都行, 整组丢了就用 dvdauthor 重建)
tools/dvd_make_sample.sh  用本机 ffmpeg 合成 DVD 合规的 MPEG-2 PS, 做成一张已知参数的测试盘
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
test/bat/check_env.bat     Windows 侧能力报告（双击快查，`/probe` 深测）
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
| `ffmpeg_copy_to_mp4.bat` | 不重编码 | 仅换容器，已是 mp4 则直接退出；**moov 前置**（`-movflags +faststart`，边下边播可用） |
| `ffmpeg_dvd_hevc.bat` | HEVC（默认 `nvenc`→`qsv`→`libx265` 自动挑） | **DVD-Video** 专用：ISO / `VIDEO_TS` 目录 / 光驱 → HEVC MKV。需带 `libdvdread`+`libdvdnav` 的 ffmpeg（有 `dvdvideo` 解复用器），否则脚本直接报错退出。`VENC=` 可显式指定（含 `h264_qsv` / `av1_qsv` 等），见后文 |

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

## DVD-Video 转 HEVC（`ffmpeg_dvd_hevc.bat` / `.sh`）

普通视频脚本**不能**直接拿来压 DVD，四个坑（均为实测）：

1. 裸 `-i` 喂 ISO **不报错**——ffmpeg 把 UDF 镜像当 MPEG-PS 糊乱解开，实测只得到 ~130s / 110504 帧的废品（正片其实 55 分钟）。必须 `-f dvdvideo -title N`
2. `-c:s mov_text` 遇到 DVD 位图字幕必然失败：`Subtitle encoding currently possible only from text to text or bitmap to bitmap`
3. 就算改成 `copy`，**mp4 也只保留 1 条**字幕（实测 300s 片段：mkv 2 条、mp4 1 条）→ 要全留必须 MKV
4. DVD 大量内容是 3:2 pulldown 的 23.976p，按 29.97 编码白扔 20% 码率 → 默认做 IVTC

```
ffmpeg_dvd_hevc.bat <源> [输出目录] [title号]

  源        ISO 镜像 / 含 VIDEO_TS 的目录 / 光驱(如 E:；.sh 侧为 /dev/sr0)
  输出目录  省略 = <源所在目录>\HEVC_OUT
  title号   给了这个就等价于 MODE=TITLE，只处理这一条
```

```
ffmpeg_dvd_hevc.bat "D:\xxx.ISO"                  :: 每个 title 各出一个文件(默认 MODE=ALL)
ffmpeg_dvd_hevc.bat "D:\xxx.ISO" D:\out 5         :: 指定输出目录 + 只压 title 5
set MODE=AUTO && ffmpeg_dvd_hevc.bat "D:\xxx.ISO" :: 只挑时长最长的那条当正片
set SPLIT_CHAPTER=7 && ffmpeg_dvd_hevc.bat "D:\x.ISO" :: 按第 7 章切成两段(前編/後編)
```

`.sh` 侧开关是同名环境变量（`MODE=AUTO ./ffmpeg_dvd_hevc.sh ...`），`VENC=libx265` 走软编、
`VENC=h264_qsv` 走 QSV，与 `.bat` 侧一致。

### 参数说明

开关写在**调用脚本之前**（脚本内部按固定配置读一次）。cmd 不区分大小写，`set` / `SET` 均可。

| 开关 | 取值 | 默认 | 作用 |
| --- | --- | --- | --- |
| `MODE` | `ALL` / `AUTO` / `TITLE` | `ALL` | `ALL` 每个 title 各出一个文件（**默认**）；`AUTO` 扫描全部 title、取**时长最长**的那条当正片；`TITLE` 只处理 `DVD_TITLE` |
| `DVD_TITLE` | title 号 | 命令行第 3 参 | 要处理的 title；一给就自动切到 `MODE=TITLE` |
| `EXT` | `mkv` / `mp4` | `mkv` | **建议保持 `mkv`**：mp4 装不下第 2 条 DVD 位图字幕（实测只剩 1 条），且 AC3 必须重编码 |
| `FILT` | `AUTO` / `IVTC` / `BWDIF` / `NONE` | `AUTO` | `AUTO`＝**按源制式选**（见下）：NTSC 29.97i→`IVTC`，PAL 25i→`BWDIF`，源已 23.976p→不加滤镜；`IVTC`＝3:2 pulldown 还原 23.976p；`BWDIF`＝只去交错、**保留原帧率**；`NONE`＝原样编码 |
| `VFILT_EXTRA` | 滤镜串 | 空 | 追加到滤镜链末尾。**默认不改 SAR、不裁边**；确要修填 `setsar=32:27` / `crop=704:480:8:0,setsar=40:33` |
| `AUDIO` | `copy` / `aac` / `flac` | `copy` | `copy`＝原样保留 AC3 / DTS / MP2（零损失、最快），**唯一例外**：源音轨是 LPCM 时自动转 AAC（见下）；`aac`＝强制重编码 192k；`flac`＝强制重编码，无损，体积约为 LPCM 的一半；mp4 下强制 `aac` |
| `SPLIT_CHAPTER` | 章号 / `0` | `0` | 按第 N 章切成两段：第 1 段＝第 1…N−1 章，第 2 段＝第 N 章…结尾。`0`＝不切 |
| `EXTRA_TITLES` | 空格分隔的 title 号 | 空 | 正片之外额外再导出的 title，例 `1 4 5` |
| `VBITRATE` | 裸数字（bit/s） | 空 | 空＝查表再把结果 `/2`（推荐，用哪张表由 `VENC` 定，见下）；填了就覆盖。**单位是 bit/s，别写 `636k`**——会被当成 636 Mbps 把编码器顶回去 |
| `VENC` | 见下 | `auto` | 编码器。空 / `auto`＝依次探测 `hevc_nvenc`→`hevc_qsv`→`libx265` 取第一个能编的；显式填名字就用那个 |

#### `VENC`：编码器怎么选

名字一律用 **ffmpeg 原生编码器名**（不另起一套别名）：

| 填这个 | 出什么 | 查哪张码率表 | 参数（与仓库同名入口同口径） |
| --- | --- | --- | --- |
| `hevc_nvenc` | HEVC（N 卡） | `bitrate_table_hevc.csv` | `-profile:v main -preset p4 -tune:v hq -rc cbr` |
| `hevc_qsv` | HEVC（Intel QSV） | `bitrate_table_hevc.csv` | `-profile:v main -preset veryfast` |
| `libx265` | HEVC（软编） | `bitrate_table_hevc.csv` | `-profile:v main -preset fast` |
| `h264_nvenc` | AVC（N 卡） | `bitrate_table_avc.csv` | `-profile:v high -preset p4 -tune:v hq -rc cbr` |
| `h264_qsv` | AVC（Intel QSV） | `bitrate_table_avc.csv` | `-profile:v main -preset veryfast` |
| `libx264` | AVC（软编） | `bitrate_table_avc.csv` | `-profile:v high -preset fast` |
| `av1_nvenc` | AV1（N 卡，Ada 起） | `bitrate_table_av1.csv` | `-preset p4 -tune:v hq -rc cbr` |
| `av1_qsv` | AV1（Intel QSV） | `bitrate_table_av1.csv` | `-profile:v main -preset fast` |
| `libsvtav1` | AV1（软编） | `bitrate_table_av1.csv` | `-preset 8` |

三张表都是「查表值 `/2`」，与仓库其余入口同口径——所以 AVC 的码率会比 HEVC 高一截（AV1 更低），这不是 bug。
`-b:v` 由脚本按上述结果追加，不用自己填。

- 连字符写法也认：`hevc-nvenc` ≡ `hevc_nvenc`；`avc_nvenc` / `avc_qsv` 会自动翻成 `h264_nvenc` / `h264_qsv`（ffmpeg 里没有 `avc_*` 这个编码器名）。
- **空 / `auto`：依次真跑探测 `hevc_nvenc` → `hevc_qsv` → `libx265`，取第一个能编的。**
  探测是「真编码一次 320×240 小片段」，**不是**看 `ffmpeg -encoders` 列表——本机（2026-09-29 实测）三个 nvenc
  都挂在列表里，真跑却在 `cuInit(0) failed` 处失败（没 N 卡），只看列表会把不可用判成可用。
- 显式指定的那个探测通不过 → **报错退出**，并打印本机实测可用的编码器，不静默降级（免得跑了 40 分钟才发现
  其实在软编）。要换就自己改 `VENC`，或让它自己挑：`VENC=auto`。

```
本机实测（2026-09-29，Intel iGPU，无 N 卡）:
  hevc_nvenc / h264_nvenc / av1_nvenc   列表里有，真编失败(cuInit)  -> auto 会跳过
  hevc_qsv / h264_qsv / av1_qsv         可用                        -> auto 落在 hevc_qsv
  libx265 / libx264 / libsvtav1         可用
```

#### `FILT=AUTO`：按源制式选滤镜

| 源帧率 | 判定 | 用的滤镜 | 出片 |
| --- | --- | --- | --- |
| `30000/1001` | NTSC 29.97i | `fieldmatch+yadif+decimate` | 23.976p（IVTC） |
| `25/1` | PAL 25i | `bwdif=mode=0` | 25p |
| `24000/1001` | NTSC 23.976p | 无 | 23.976p |
| 读不到帧率 | 按高度猜：`576`/`288`＝PAL，`480`/`240`＝NTSC | 同上 | 同上 |

**为什么不能一律 IVTC**：PAL 没有 3:2 pulldown，硬套上去会掉到 **20fps** —— 本机实测两张
720×576 PAL 盘跑 IVTC 出来 `r_frame_rate=20/1`（`decimate` 每 5 帧扔 1 帧），白扔 20% 的帧。

**注意 `bwdif=mode=1` 帧率翻倍**：`mode=1` 是 send_field，实测 25i→**50p**，帧数翻倍会把既定码率
摊薄一倍，所以档位里用 `mode=0`（send_frame，保留原帧率）。真想要 50p / 59.94p 的平滑感，就
`FILT=NONE` + `VFILT_EXTRA=bwdif=mode=1`。

#### `AUDIO=copy` 的 LPCM 例外

Matroska 装不下 DVD 的 LPCM 音轨（`pcm_dvd`），一写头就失败：

```
[matroska] No wav codec tag found for codec pcm_dvd
[out#0/matroska] Could not write header (incorrect codec parameters ?): Invalid argument
```

所以 `AUDIO=copy`（默认）下探测到 LPCM 会**自动转 AAC 192k** 并打印一行提示；AC3 / DTS / MP2 继续
原样直通。要无损就 `AUDIO=flac`（体积约为 LPCM 的一半）。

不"一律强制转 AAC"的理由：AC3→AAC 是**有损重编码**（448k→192k），而直通是零损失且最快；只有装不下
时才转。真要统一成 AAC 自己设 `AUDIO=aac` 即可（mp4 下本来就是强制 AAC）。

两个刻意的设计：**不动 SAR、不裁边**（DVD 宽高比要同时看 IFO 与 MPEG-2 序列头，同一张盘两者都可能不一致，没有通用写法，故让 ffmpeg 透传原始 SAR）；**不猜测分界章号**（每张盘不同，默认 `SPLIT_CHAPTER=0` 不切）。

### 输出包含原盘的哪些段？

以实测的那张盘（`人妻かすみさん` 前編+後編，`MODE=AUTO`）为例：

| | 内容 |
| --- | --- |
| **进入成片的** | title 3 —— 全盘最长的 PGC（3304s）＝ **视频全部** ＋ **2 条 AC3 立体声全部** ＋ **2 条 DVD 位图字幕全部** ＋ **16 个章节标记全部** |
| **没有进入成片的** | title 1(84s) / 4(66s) / 5(30s) / 6(70s) / 7(130s)——探针显示均为「1 视频 + 1 AC3、无字幕」的短片（菜单/警告/予告类）；以及菜单域(VMGM)与 `IFO`/`BUP`/`NAV PACK` 等 DVD 导航结构本身 |

要点：

- **一条 title 出一个文件**，`MODE=AUTO` 只挑一条，其余 title 默认丢弃——想要就 `MODE=ALL` 或 `EXTRA_TITLES`。
- **章节不会丢**：`-map_chapters 0` 把 title 的章节点原样写进 MKV（实测 16 个，与源盘 15 个 cell 边界逐一对得上）。所以「前編/後編」这类分段信息仍在文件里，`SPLIT_CHAPTER` 只是**按它切文件**。该盘实测分界在**第 7 章**（第 1–6 章＝前編，第 7–16 章＝後編，各约 27.5 分钟；边界处 1640–1651s 画面全黑、1652s 起换篇），即 `SPLIT_CHAPTER=7`。
- **分辨率与 SAR 透传**，不裁边、不改宽高比，字幕/音轨条数不变。
- 成片时间轴相对源盘**整体缩到 1000/1001（0.1%）**，这是 `dvdvideo` 的 DVD 时钟换算；实测**每一章都按同一比值 0.999001 缩放**，所以是均匀缩放、**不是丢段**。
- 该盘 title 3 的**音频本身止于 3241.8s**：末尾约 60s 只有画面没有音轨。因为音频是 `-c:a copy` 原样拷贝（ffmpeg 不会平白丢掉 60s 的包），且这段画面实测平均亮度 YAVG≈25（正片同口径是 163），属**源盘自身的极暗收尾画面**，不是转码造成的。

### 已知现象（不是错误）

- `[dvdvideo @ ...] libdvdnav: Unable to open device file <路径>.ISO.` —— **误报**：libdvdnav 先按物理光驱试开、失败后才落到 ISO 文件读取。看到它而产物完整即正常。
- 进度行末尾的 `time=` 可能**冻住不动**（同时 `frame=`/`size=` 正常增长）—— ffmpeg 的显示瑕疵。判定完整性请看 `ffprobe` 输出，勿信这一格（详见 `environment_matrix.md` 第 49 条）。

`.bat` 侧另有四个坑，只有真机跑才暴露（2026-09-22 首轮实跑修复，详见 `environment_matrix.md` 第 48 条）：

- **`set /p` 配 `^<` 不是重定向**：`^` 会把 `<` 转成字面量参数，`set /p` 随即退化成「从键盘读一行」，表现是打印完「源」再无输出、脚本静默卡住等按键。**读探针临时文件一律用 `for /f "usebackq"`**（本仓库真机验证过的写法，见 `lib/common.bat`）
- **`call :ENC` 的前缀必须加双引号**：源文件名常带空格与小括号（如 `[DVDISO](18禁アニメ) ...`），不包住会被按空格切成好几个参数，输出名与章节号全部错位
- **`MODE=ALL` 要先拿 title 1 定码率档位**：直接跳进编码循环会整段跳过码率计算，`-b:v` 是空值，每个 title 都在 ffmpeg 处失败
- **`title` 编号不连续**：DVD 的 title 号会缺号（实测那张盘缺 title 2），扫描循环不能「读不到就收尾」，否则只压到某个短特典而跳过正片，**而产物看起来完全正常**

## 造测试素材（`tools/dvd_make_sample.sh`）

本机 ffmpeg 合成一段 DVD 合规的 MPEG-2 PS，顺手做成 `VIDEO_TS` 和 ISO —— 给上面几个脚本
当输入。用真盘测的话，读出来 1682s 你也不知道对不对；自己造一张，几条 title、多长、章节
落在哪几个时间点全是已知的。

```
./tools/dvd_make_sample.sh [输出目录] [输出ISO]
  输出目录  默认 ./dvd_sample（dvdauthor 在它下面生成 VIDEO_TS / AUDIO_TS）
  输出ISO   默认 <输出目录旁边>/<目录名>.iso
```

```
./tools/dvd_make_sample.sh                                  # 5 分钟 PAL, 4:3, 一条 title
DURATION=120 SCENE_LEN=30 TITLES=2 ./tools/dvd_make_sample.sh /tmp/e2e
FORMAT=ntsc ASPECT=16:9 VBITRATE=2000k ./tools/dvd_make_sample.sh /tmp/ntsc
NO_VIDEOTS=1 ./tools/dvd_make_sample.sh /tmp/only_mpg        # 只要 MPEG-2 PS
NO_ISO=1 ./tools/dvd_make_sample.sh /tmp/ts                  # 出 VIDEO_TS 就停
```

| 开关 | 默认 | 意思 |
|---|---|---|
| `DURATION=300` | 300 | 每条 title 的时长（秒） |
| `TITLES=1` | 1 | 几条 title（每条一个标题集，音调频率错开，耳朵能分出来） |
| `SCENE_LEN=30` | 30 | 每几秒切一次画面。切点即章节点，也是场景检测的期望值 |
| `FORMAT=pal\|ntsc` | pal | pal = 720x576@25；ntsc = 720x480@30000/1001 |
| `ASPECT=4:3\|16:9` | 4:3 | DVD 只认这两种 |
| `VBITRATE` / `ABITRATE` | 4000k / 192k | 默认压低过：60s 素材用 `-target` 的默认值要 49 MB |
| `LABEL=1` | 开 | 画面上叠「scene N」和时间码。没有 drawtext 或找不到字体就自动关 |
| `NO_VIDEOTS=1` / `NO_ISO=1` | 关 | 半路停下，只出 mpg / 出到 `VIDEO_TS` |
| `KEEP_WORK=1` | 关 | 保留工作目录（生成的 mpg 与 dvdauthor 的 XML、日志） |

画面是 6 种合成源轮着切（testsrc2 / 纯白 / 彩条 / 纯黑 / rgbtestsrc / 深蓝）。纯色段是
故意的：白↔黑跳变的场景分数拉满，切点一定检得出来，正好拿来测 `dvd_repair` 的
`CHAPTERS=auto`（阈值 0.40 命中 4 个里的 3 个，放到 0.10 全中）。

跑完自己回读一遍 ISO 核对：几条 title、每条多长、几个章节。三个实测出来的点：

- **`-target pal-dvd` 不管 SAR**：实测给的是 `SAR=1:1 → DAR=5:4`，既不 4:3 也不 16:9，不是
  合规盘。必须显式 `-aspect`，加了之后 SAR 变 `16:15` / DAR `4:3`。NTSC 同理。
- **`-target` 默认码率约 6.5M**：60s 素材就 49 MB，做测试素材太浪费，所以默认压到 4000k。
- **校验章节数不能问 ffprobe**：它的 `dvdvideo` 解复用器会漏 —— IFO 里 6 个章节它只报 5 个，
  只有 2 个时干脆报 0 个；`mplayer -identify` 读出来和 IFO 一致。所以脚本直接读
  `VTS_xx_0.IFO` 里 PGC 的 `nr_of_programs`。

依赖：ffmpeg（带 `mpeg2video` + `ac3` 编码器，`LABEL` 还要 `drawtext`）+ `dvdauthor` +
`tools/dvd_restore.sh`（打 ISO 那一步）。同样没人会调它，它是这一串的起点：
`dvd_make_sample → dvd_restore`，产出的目录再交给 `dvd_repair` / `dvd_shrink` 去测。

## 还原 DVD-Video（`tools/dvd_restore.sh`）

`ffmpeg_dvd_hevc` 是把 DVD 拆成视频文件，**这个工具是反向的**：手里有一份解压出来的
`VIDEO_TS`（+ `AUDIO_TS`），把它还原成一张能刻盘、能在家用 DVD 机上播的 DVD-Video ISO。

```
./tools/dvd_restore.sh <源目录> [输出ISO]
  源目录   含 VIDEO_TS 的 DVD 根目录；直接指到 VIDEO_TS 目录本身也行
  输出ISO  默认 <源目录名>.iso，写在源目录**旁边**（不能写在源目录里面）
```

```
./tools/dvd_restore.sh ~/Downloads/tmp/KB059-Nessy-KB4
BURN=/dev/sr0 ./tools/dvd_restore.sh ~/Downloads/tmp/KB059-Nessy-KB4   # 打好立刻刻
FIX=1 ./tools/dvd_restore.sh ...                                       # 缺/坏的 BUP 用 IFO 补
DEEP=1 ./tools/dvd_restore.sh ...                                      # 解开镜像逐字节比对
ALLOW_GAP=1 ./tools/dvd_restore.sh ...                                 # VOB 断号也照样出镜像(默认拦下)
```

三个关键点（都是实测，脚本头部注释有原始数据）：

- **必须 `mkisofs -dvd-video`**：它会按 DVD-Video 的规矩排序文件并补 padding；不加这个参数
  出来的镜像在电脑上看着正常，家用机却会挑盘/跳帧。
- **文件名必须全大写**：mkisofs 手册写明 `-dvd-video` 的排序只对大写名生效，小写名不报错、
  只是**悄悄不排序**，于是掉进上一条。
- **输出 ISO 不能落在源目录里面**：mkisofs 边扫目录树边写镜像，会把正在写的 ISO 自己卷进去。

打包前会先体检：必备文件、大小写、2048 字节对齐、单文件 ≤ 1 GiB、IFO/BUP 是否成对、
`AUDIO_TS` 是否存在（缺了自动补空目录）、容量能不能塞进 DVD-5 / DVD-9；
打包后校验 UDF 卷识别序列（`BEA01`/`NSR02`/`TEA01`）并逐个比对文件清单与大小。
其中 **VOB 编号断号默认拦下**：那一整段的音视频真没了，任何工具都补不出来，镜像看着正常、
校验也过，播到缺的那段才断 —— 而那时盘已经刻完了。报错里直接给出 `ALLOW_GAP=1 ...` 那条
「带着缺口继续」的命令（`CHECK=0` 则连其它结构检查一起跳过）。

依赖：`genisoimage`（必需，提供 `mkisofs -dvd-video`）；`xorriso` 或 `7z`（校验，二选一）；
`growisofs` / `wodim`（仅 `BURN=` 刻录时需要）。

## 补齐缺失的 IFO / BUP（`tools/dvd_repair.sh`）

抓盘/解压出来的目录常常缺文件。这个工具先体检再补齐，默认**只读预览**，加 `APPLY=1` 才动盘。

体检也可以单独要：`CHECK_ONLY=1` 只打印缺失清单、**一个字节都不改**，结论走退出码
（`0` 完好 / `1` 有缺失但都能补 / `2` 有补不出来的）—— `dvd_shrink.sh` 与
`dvd_to_data_iso.sh` 就是拿它当「体检门」用（见下面「谁会调它」）。

```
./tools/dvd_repair.sh <源目录> [输出ISO]
  源目录   含 VIDEO_TS 的 DVD 根目录；直接指到 VIDEO_TS 也行
  输出ISO  给了就接着调 dvd_restore.sh 打包，不给就只修不打
```

```
./tools/dvd_repair.sh ~/Downloads/tmp/DVD001      # 先看看缺什么（只读，不动盘）
APPLY=1 ./tools/dvd_repair.sh ~/Downloads/tmp/DVD001 ~/out.iso   # 修完直接打 ISO
APPLY=1 ./tools/dvd_repair.sh ~/Downloads/tmp/DVD001             # 只修，不打
CHAPTERS=none APPLY=1 ...                          # 重建时不要章节（省一次全片解码）
KEEPMENU=0 APPLY=1 ...                             # 重建时连菜单也不要（孤儿 VOB 会被挪走）
FORMAT=pal APPLY=1 ...                             # 强制制式（默认按 VOB 分辨率判）
```

常用开关（都是环境变量，写在命令前面）：

| 开关 | 默认 | 意思 |
|---|---|---|
| `APPLY=1` | 关 | 不加就是只读预览，只打印"缺什么、打算怎么补" |
| `CHAPTERS=auto\|none` | `auto` | 重建时用 ffmpeg 场景检测重打章节（代价：一次全片解码） |
| `SCENE_TH` / `MIN_GAP` / `MAX_CH` | `0.40` / `30` / `60` | 场景检测阈值 / 相邻章节最小间隔 / 章节上限 |
| `KEEPMENU=1` | 开 | 重建时把原 `VTS_xx_0.VOB`（菜单）一起喂给 `dvdauthor`，保住菜单 |
| `FORMAT=pal\|ntsc` | 自动 | 按 VOB 分辨率判（576/288 = PAL）；判错时手动指定 |
| `FORCE=1` | 关 | 本盘 IFO/BUP 本就不一致时，也照样用 BUP 顶 IFO |
| `KEEP_WORK=1` | 关 | 保留工作目录（`dvdauthor` 的中间产物与日志） |

被替换掉的原件不会凭空消失，一律先 `mv` 到 DVD 根**旁边**的
`.dvd_repair_backup_<名字>/`（同分区 `mv` 不占额外空间）；工作目录是旁边的
`.dvd_repair_<名字>/`，跑完自动删（`KEEP_WORK=1` 保留）。两者都刻意放在根目录外面，
否则会被 `dvd_restore.sh` 当成夹带物警告，也会被 `mkisofs` 一起卷进镜像。

| 情形 | 怎么补 | 代价 |
|---|---|---|
| 缺 `.BUP`（`.IFO` 在） | 直接 `cp`。规范要求 BUP 是 IFO 的逐字节备份 | 无 |
| 缺 `.IFO`（`.BUP` 在） | 反方向 `cp`。补之前先核对本盘其余 IFO/BUP 对是否真的一致 | 无 |
| `.IFO` 与 `.BUP` 都没了 | `dvdauthor` 从该标题集自己的 VOB 重建（**不重编码**）+ `dvdauthor -T` 重生成 VMG | 该组 VOB 重写一遍；菜单可保，章节用场景检测重打（是近似值，不是原盘的） |
| 缺 VOB（编号断号） | 补不出来，只报告是哪一段 | — |

三个实测出来的坑（脚本头部有原始数据）：

- **缺 `.IFO` 看着没坏，其实打不出 ISO**：`ffprobe` 还读得出 title，是因为 `libdvdread`
  会自动退回 BUP；`mkisofs -dvd-video` 没这待遇，直接 `Failed to open VTS info`。
- **只换掉坏的那组不够，VMG 必须跟着重生成**：留着原来的 `VIDEO_TS.IFO`，正片会少读一大截
  （实测 1682s 只剩 1119s，正好是第一个 VOB 的量）。
- **重建后没有菜单时，原来的 `VTS_xx_0.VOB` 成了孤儿**，`mkisofs -dvd-video` 会失败
  （`Either VIDEO_TS.IFO or VIDEO_TS.VOB is not of correct size`）。默认 `KEEPMENU=1` 把菜单
  一起喂给 `dvdauthor` 保住它。

章节（`CHAPTERS=auto`，默认）用 ffmpeg 场景检测重新打点，代价是一次全片解码。`dvdauthor`
在这里有个很坑的脾气：**`chapters` 必须每个 `<vob>` 各写一份、时间是相对该 VOB 自己的开头**，
只写在第一个 VOB 上会把整条 PGC 的时长元数据截成"第一个 VOB 的长度"（1681.76s → 1119.04s，
而内容其实还是完整的）。所以脚本每建一次都复核时长，发现被截断就自动降级重写。

依赖：前两档只要 `cp`；第三档要 `dvdauthor` + `ffmpeg`/`ffprobe`。

### 谁会调它、它调谁（顺序别搞反）

```
dvd_repair.sh  ──(只在给了输出ISO时)──>  dvd_restore.sh      修完直接打包
dvd_shrink.sh  ──(CHECK_ONLY=1, 只体检)──>  dvd_repair.sh    先体检, 有缺失就停下
dvd_shrink.sh  ─────────────────────>  dvd_restore.sh      瘦身完打包
dvd_to_data_iso.sh ──(CHECK_ONLY=1, 只体检)──> dvd_repair.sh  DVD 目录 + 要压时才体检
dvd_make_sample.sh ─────────────────>  dvd_restore.sh      造完素材打包
dvd_to_data_iso.sh ──(ENCODE=1, 先压)──>  ffmpeg_dvd_hevc.sh
```

- **`dvd_shrink.sh` / `dvd_to_data_iso.sh` 只调 `dvd_repair.sh` 的体检模式**（`CHECK_ONLY=1`，
  只读）：有缺失就停下来，把「缺什么 + 该跑的那条 `APPLY=1 ...` 命令」打给你。
  **仍然没有脚本会替你改盘** —— 修是 `dvd_repair.sh` 的事，而它默认也是只读预览。
- `dvd_repair.sh` 自己只在一个地方自动往下走：你给了「输出 ISO」参数时，修完自己调
  `dvd_restore.sh` 打包。反过来 `dvd_restore.sh` **不**调 `dvd_repair.sh`（它只指路），
  否则「修完打包」会变成互相调用的死循环。
- 瘦身（`dvd_shrink.sh`）靠 `ffprobe -f dvdvideo` 读源盘，而 libdvdread 会自动退回 BUP，
  所以「缺 IFO 或 BUP 中的一个」对它毫无影响（实测缺哪个都照样读出 1682s / 2068s）。
- 但**整组 `.IFO` + `.BUP` 全丢时那条 title 根本读不出来**（`DVDOpenFilePath:
  findDVDFile /VIDEO_TS/VTS_01_0.IFO failed`）——`dvd_shrink.sh` 只会静默跳过它，`MODE=ALL`
  做出来的盘就少一条正片，`MODE=AUTO` 则可能挑中另一条。所以顺序是：
  **先 `dvd_repair.sh` 修，再 `dvd_shrink.sh` 瘦**。
- 顺带一提：`dvd_shrink.sh` 每条 title 只生成一个 mpg（一个 `<vob>`），所以不会撞上
  上面那个「`chapters` 写在多 VOB 上会被截断」的坑。

## 重制 DVD-Video（压缩到目标容量）（`tools/dvd_shrink.sh`）

要「变小」**又仍然能在家用 DVD 机上播**，只有这一条路：重编码成低码率 MPEG-2，再用
`dvdauthor` 重新生成 `VIDEO_TS`。DVD-Video 规范只认 MPEG-1 / MPEG-2 视频 + AC-3 / MP2 /
LPCM / DTS 音频，把 HEVC 塞进 VOB 里能出 ISO 也能刻盘，但没有任何一台 DVD 机解得了。

```
./tools/dvd_shrink.sh <源> [输出ISO] [title号]
  源  ISO 镜像 / 含 VIDEO_TS 的目录 / 光驱(如 /dev/sr0)
```

```
./tools/dvd_shrink.sh ~/Downloads/tmp/LD016春春裸足电影3      # 挑最长的正片, 目标 DVD-5
TARGET_MB=8000 ./tools/dvd_shrink.sh ...                     # 目标改成 DVD-9 双层
MODE=ALL ./tools/dvd_shrink.sh ...                           # 每个 title 各做一个标题集
ALLOW_GAP=1 ./tools/dvd_shrink.sh ...                        # 断号/标题数对不上也继续(默认拦下)
VBITRATE=2500k ./tools/dvd_shrink.sh ...                     # 直接指定视频码率
AUDIO=ac3 ./tools/dvd_shrink.sh ...                          # dvdauthor 报音频断续时改重编
```

- 码率按「目标容量 ÷ 总时长 − 音频」反推（实测 20 分钟正片 + 目标 300 MiB → 1818 kbps，
  预估 302 MiB、实出 306 MiB）。给很高的目标时 `mpeg2video` 会撞 `qmin=2` 编不到那么多，
  实测 8500k 与 5839k 出一样大 —— 所以估算在高目标是上界。
- 代价说在前面：**重编码必然掉画质**、**原盘菜单会丢**（IFO 由 `dvdauthor` 重生成，菜单
  只存在于原盘的 VOB 里）。脚本发现「反推出的码率不低于原盘」会先劝退。
- 章节从源盘带过来；**不做 IVTC** —— DVD 只认 25（PAL）/ 29.97（NTSC）两种帧率。
- **源盘缺文件会先被拦下**（源是**目录**时）：开跑前请 `dvd_repair.sh` 只读体一次检，
  有缺失就停下并把 `APPLY=1 bash tools/dvd_repair.sh <源>` 打给你（`CHECK=0` 跳过这道门）。
  补不出来的那种（VOB 断号）同理拦下，确实要带着缺口继续就 `ALLOW_GAP=1`。
  本脚本**不会替你改源盘**。源是 ISO / 光驱时做不了体检（`dvd_repair.sh` 只认目录），跳过不拦。
- 另外 `MODE=ALL` 下会对一次账：盘上有几个 `VTS_*_0.IFO`，就该读出几条 title；
  对不上说明有标题集读不出来（多半是整组 IFO/BUP 丢了），不再静默少一条正片。

产物仍由 `dvd_restore.sh` 打包与校验（UDF 卷识别序列 + 文件清单），等于「重制 + 还原」一条龙。
依赖：`dvdauthor` + 带 `dvdvideo` 与 `mpeg2video` 的 `ffmpeg` + `genisoimage`。

## HEVC 归档 → 数据 ISO（`tools/dvd_to_data_iso.sh`）

不在乎 DVD 机、只在乎体积与长期保存时走这条：先把 DVD 压成 HEVC（复用 `ffmpeg_dvd_hevc.sh`），
再打成 UDF 数据盘。

```
./tools/dvd_to_data_iso.sh <目录|DVD源> [输出ISO]
```

```
./tools/dvd_to_data_iso.sh ~/Downloads/tmp/LD026-VIV裸足电影1  # DVD -> HEVC MKV -> 数据 ISO
./tools/dvd_to_data_iso.sh ~/HEVC_OUT                          # 已有文件, 直接打包
VENC=hevc_nvenc ./tools/dvd_to_data_iso.sh ...                 # 有 N 卡时走硬编(默认 libx265)
KEEP_STAGE=1 ./tools/dvd_to_data_iso.sh ...                    # 保留中间那份 MKV
CHECK=0 ./tools/dvd_to_data_iso.sh ...                         # 跳过源盘体检
ALLOW_GAP=1 ./tools/dvd_to_data_iso.sh ...                     # 断号也照样压(默认拦下)
```

- 源是 **DVD 目录且真要读它**（`ENCODE=1`）时，开跑前同样先过一遍 `dvd_repair.sh` 的只读体检：
  有缺失就停下并给出修复命令；断号（`ALLOW_GAP=1` 放行）与「补不出来」同上。
  源是 ISO / 光驱、或只是普通文件目录时不做体检。

实测 1.05 GiB 的 DVD → 136 MiB 数据 ISO（约 1/8）。**这是数据盘，不是 DVD-Video**：没有
`VIDEO_TS`、没有菜单，PC 直接播，传统 DVD 机读不了；部分电视 / 蓝光机的数据盘功能能读。

打包用 `-udf -iso-level 3 -J -r`：UDF 桥让单文件不被 ISO9660 的 2 GiB 卡住，Joliet + Rock Ridge
保证 Windows / macOS / Linux 都读得到（别加 `-dvd-video`，那个是给有 `VIDEO_TS` 的源用的）。

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
| 块内参数里的裸 `)` | 多行 `( ... )` 块中，**参数文本里未转义的 `)` 会提前关闭该块**（`^( ^)` 转义、全角 `（）`、`[1]`、双引号内、`for %%A in (...)`、`\|\| ( ... )` 均安全）。后果极隐蔽：紧跟其后的语句脱离块、变成**无条件执行**的顶层语句 —— `ffmpeg_dvd_hevc.bat` 首跑就是这样静默 `exit /b 1` 的（打印两行后直接回提示符、零报错）。静态由 **L23** 拦截，实验记录见 `environment_matrix.md` 第 49 条 |

## 验证状态

测试体系分三层，先用 1 秒的静态检查过滤低层次问题，再跑数分钟的冒烟套件：

| 层 | 命令 | 本机最近一轮（2026-09-20，Win11 + MSYS2 + RTX） |
|----|------|--------------------------------------------|
| ① 静态 + 对等 | `python3 test/lint/lint.py` | `30 PASS / 0 FAIL / 5 WARN`，退出码 0 |
| ① 检查器自测 | `python3 test/lint/selftest.py` | `40 cases / 0 FAIL` |
| ② sh 冒烟 | `bash test/sh/smoke_all.sh` | `PASS=22 FAIL=0 SKIP=4`，`rc=0` |
| ③ 能力报告 | `bash test/sh/check_env.sh [--probe]` | 列出本机可用入口与原因 |

2026-09-22 新增 `ffmpeg_dvd_hevc.{bat,sh}` 后重跑：静态层 `31 PASS / 0 FAIL / 5 WARN`、
检查器自测 `49 cases / 0 FAIL`（新增 L23 + 9 条用例）。该条目在 lint 的 L16（流映射统一性）上被
登记为**部分豁免**：只豁免 `-c:s mov_text` 一项，理由是 DVD 字幕是位图流、ffmpeg 根本拒绝转换
（见上文），其余 5 项 token 全部保留。豁免表 `STREAM_MAP_EXEMPT` 写在 `test/lint/lint.py` 里并
注明"不得扩展到文本字幕条目"。

`.sh` 侧已在本机 Git Bash 实跑通过（30s 的 title 5，IVTC 后 727 帧 / 23.976p，SAR 原样透传，
AC3 无损保留）。

`.bat` 侧**已改为真机等价实跑**：开发沙箱现在可以用
`python 造一个 stdin 脚本 → cmd < script.txt > log.txt` 驱动 `cmd.exe` 交互模式执行批处理，
控制流与双击完全一致（只有输出编码受限于无真实控制台）。`ffmpeg_dvd_hevc.bat` 因此完成了
**两次完整实跑**：title 5（30s，727 帧、8.3 倍速）与 **MODE=AUTO 全片**（自动跳过缺失的
title 2、选中 3304s 的 title 3、输出约 1 Mbps 的 MKV）。首次真机运行的静默退出正是靠这条
通路定位的（根因见 `environment_matrix.md` 第 49 条）。

用户随后在**自己的机器上双击实跑**同一条命令并成功（rc=0）：产物
`HEVC_OUT\….mkv` 为 **401 754 057 字节，与沙箱实跑逐字节同尺寸** —— NVENC 在固定参数下
是确定性的，可用来交叉比对两次运行是否等价。

> **冒烟为什么是"数分钟"**：墙钟时间 ≈ 入口调用次数 × 单次入口成本，与片长几乎无关。
> 2026-09-17 把 `lib/common.sh` 的源探测从「7 个 helper 各起一条 ffprobe」（一次入口
> 8 个 ffprobe 进程，每条还套一个 `tr` 管道）合并为**一次 `-of flat` 探测 + 按文件路径缓存**，
> 解析全部改 bash 内建：单次入口 **9.7s → 5.6s**、5 条目清单用例 **51.1s → 30.5s**，
> 而 7 个 helper 的对外行为逐条不变（56 组合等价性对比；同日修复了顺带发现的
> 「`$?` 判的是管道末尾 `tr`」假判据，探测失败现在真正报错）。
> 详见 `test/README.md` §3.6。**`.bat` 侧已同步**（`lib/common.bat` 新增 `:probe_source`，
> 7 个编码入口的 6 段探测合并为 1 次 ffprobe；待真机双击验证）。

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
  `0 成功 / 1 参数与文件错误（含编码失败、找不到 ffmpeg）/ 2 查表越界 / 3 无视频流 / 5 码率异常`；
  「失败必须传回非零」由 lint **L15**、流映射一致性由 **L16**、moov 前置由 **L17** 静态钉住
  （`.bat` 入口历史上曾无条件 `exit /b 0` 吞掉失败；而 Windows 版 ffmpeg 的**负**退出码
  `-40/-22/-2` 会让 `if errorlevel 1` 静默失手，故 L15 现在要求 `if not "%FB_RC%"=="0"` 这种负数安全写法）。
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
