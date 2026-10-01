# DVD 菜单盘制作笔记（2026-10-01 实测，素材 ZP001）

从零做出一张「播菜单 → 方向键选按钮 → 进正片 → 播完回菜单」的 DVD-Video ISO 时
踩出来的坑。对应工具：

| 工具 | 作用 |
|---|---|
| `tools/dvd_menu_build.sh` | 主线：多段源 → 统一音频 → 菜单（按钮）→ `dvdauthor` → ISO |
| `tools/dvd_aud_gap.sh` | 音频洞体检（逐包量 PTS 间隔） |
| `tools/dvd_find_split.sh` | 按 I 帧找能落刀的切分点 |
| `tools/dvd_restore.sh` | 最后一步打包（补 `AUDIO_TS`、`-dvd-video` 排序、结构校验） |

---

## 1. 方向键选不动按钮 —— spumux 的 `highlight`/`select` 是文件名，不是颜色

最坑的一条，症状是「播放器里菜单正常显示，但按方向键没反应」，很容易误判成
「VLC 不支持菜单」。

`spumux.xml` 里这几个属性：

```xml
<spu image="btn_normal.png" highlight="btn_hilite.png" select="btn_select.png"
     transparent="black">
```

`image` / `highlight` / `select` 是**三张 PNG 的文件名**，只有 `transparent` 才是颜色
（dvdauthor 源码 `subgen-parse-xml.c`：`spu_highlight` → `localize_filename`）。

写成颜色名的后果是**不报错、静默失败**：

```
INFO: PNG had 2 colors
ERR:  Unable to open file white          ← highlight="white" 被当文件名打开
INFO: 0 subtitles added, 1 subtitles skipped
```

产物与输入**字节数一模一样**（实测 `menu_spu.mpg` = `menu.mpg`）。没有子图就没有
PCI 里的 BTN_GRP，方向键自然没反应。

判据写进脚本了，两条都对上才算成功：

1. 日志里是 `N subtitles added` 且 `N > 0`；
2. `menu_spu.mpg` 字节数必须**大于** `menu.mpg`。

三态子图只画边框不填充，底图里的缩略图才看得见：

| 状态 | 颜色 | 线宽 |
|---|---|---|
| 未选中 | `0x555555` 深灰 | 6 |
| 选中（高亮） | `0xFFFFFF` 白 | 8 |
| 按下 | `0xFFD200` 黄 | 8 |

三张 PNG 尺寸必须一致（PAL `720x576` / NTSC `720x480`）。

## 2. 音频洞：根因是 LPCM，修法是 `aresample`

表现：播放时有规律的小爆音/静音；`dvdauthor` 满屏 `Discontinuity ... please remultiplex`。
但**文件能播、时长也对**，看 `ffprobe` 的 stream 信息完全看不出来。

同一份素材逐段量：

- 源为 LPCM 的段：`seg_1` 有 196 个 2 帧洞；
- 源为 AC3 的段：`seg_2` 0 个。

LPCM 每包样本数不规则，解码出来时间戳抖，AC3 编码器原样带走 → 成品里约 4% 的音频
帧跳 2 帧（64ms）。

修法：重编码音频时按时间轴补偿

```
-af "aresample=48000:async=1:first_pts=0"
```

实测同一素材前 90 秒：2 帧洞 **4802 → 0**。

对照（都试过）：直接 AC3→AC3 重编码无效；`asetpts=N/SR/TB` 也压不平，只有
`aresample` 的 `async=1` 按时间轴补才干净。

体检口径：AC3 一帧 = 1536/48000 = 32ms，相邻 PTS 间隔明显大于它就是洞。

## 3. `-muxrate` 只能加在“逐段统一音频”那一步

| 步骤 | 加不加 |
|---|---|
| 逐段转 AC3（`-f dvd`） | **加** `-muxrate 10080000`（DVD 规范上限） |
| concat 重封装 | 不加 |
| 切 title | 不加 |
| 音频抹平重编码 | 不加（实测不加也过） |

- 不加的后果：`dvd` muxer 默认码率不够交错音频 → 满屏 `buffer underflow` +
  `dvdauthor` 报 `Discontinuity ... please remultiplex`。
- **反过来加错的后果更硬**：静态/末尾 padding 会造出「只有填充没有音视频」的 VOBU，
  `dvdauthor` 直接 `ERR: Cannot infer pts for VOBU ...` 退出，整条线中断。

## 4. 切分点必须落在 I 帧 / VOBU 起点

- 从非 I 帧切开：第二段开头花屏/卡几帧（B/P 帧缺参考）。
- DVD-Video 每个 VOBU 以 NAV 包开头，家用机靠它跳转和返回菜单。切在 VOBU 内部，
  `dvdauthor` 要么报 `Cannot infer pts for VOBU`，要么造出章节点错位的盘 —— 而文件
  本身能播，很容易误判成「刻坏了」。

实测：目标 1823s 时最近 I 帧是 `1823.1063`，用后者切一次过。

找 NAV 包（VOBU 起点）可以直接问 ffprobe 的 data 流，不用猜字节模式：

```
ffprobe -select_streams d -show_entries packet=pos -of csv=p=0 all.vob
```

NAV 包的特征：14 字节 pack header 后是 `00 00 01 bf`。

## 5. 多段源的两条硬约束

1. **一个 PGC 只能声明一种音频格式**。4 段源里 1/3 段是 `pcm_dvd`、2/4 段是 `ac3`，
   必须先统一（本仓库统一成 AC3 448k，视频全程 copy）。
2. **本机 ffmpeg 没有 `pcm_dvd` 编码器**，LPCM 流复制一律 `sample rate not set`
   （`dvd` / `vob` / `mpeg` 三个 muxer 都试过）→ 只能往 AC3 统一。

另外各段 PTS 都从 0 开始，**直接 `cat` 出来的时间轴是断的**，必须用 concat 解复用器
重封装成连续时间轴，之后 `-t` / `-ss` 才对得上。

## 6. 菜单循环与返回：`post` 指令

```xml
<!-- 菜单：播完跳回自己 = 循环 -->
<pgc>
  <vob file="menu_spu.mpg" />
  <button>jump title 1;</button>
  <button>jump title 2;</button>
  <post>jump vmgm menu 1;</post>
</pgc>

<!-- 正片：播完回菜单 -->
<pgc>
  <vob file="title1.mpg" />
  <post>call vmgm menu 1;</post>
</pgc>
```

按钮个数必须等于 title 个数，`jump title N;` 里的 N 从 1 开始。

## 7. 脚本层的两个自杀式写法

1. **ffmpeg/ffprobe 会从 stdin 读键盘命令**。非交互环境下 stdin 是不关的管道 → 卡死
   几小时（真踩过）。ffmpeg 全部 `-nostdin`，其余全部 `</dev/null`。
2. **`ffprobe ... | head -N`**。`head` 拿够就关管道，`ffprobe` 收 SIGPIPE 返回 141，
   配合 `set -o pipefail` 直接把脚本干掉。要少解一点就让 ffprobe 自己只解前 N 秒：
   `-read_intervals "%+90"`。

## 8. 顺带记下的零散经验

- 菜单底图用一张图 + 静音即可：`-loop 1 -framerate 25 -i bg.jpg` 配
  `-f lavfi -i anullsrc=r=48000:cl=stereo -t 30 -target pal-dvd`。
- 输出 ISO **不能落在源目录里面**（`mkisofs` 边扫边写，会把正在写的 ISO 也扫进去）。
  `dvd_restore.sh` 已经拦这一条。
- 成品结构可以直接从 IFO 里 od 出来核对，不用装专门的解析工具（大端读偏移）：
  - `VIDEO_TS.IFO` +196 → VMG 的 title 数；+200 → VMG 菜单 PGC 数；
  - `VTS_01_0.IFO` +204 → 该标题集的 PGC 数；偏移值要 `×2048`。
- `dvdauthor` 的日志里 `Discontinuity` / `moves backwards` 按数值分档统计比数条数有用：
  <5 ticks 基本无害，≥1000 才需要回头重封装。
