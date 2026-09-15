# ffmpeg_bat_git 代码质量分析报告

**仓库路径:** `D:\repos\ffmpeg_bat_git`
**分析日期:** 2026-08-14
**代码语言:** Bash / Windows Batch
**文件数量:** 25 个脚本文件 (13 .sh + 12 .bat) + 文档/数据文件

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

### 4.4 码率查找表应该是数据而非代码

94 个硬编码的 `if-elif` 分支本质上是一张像素数→码率的查找表，数据来源于 `bitrate_calc.xlsx`。应将其提取为外部数据文件（CSV/JSON），用脚本读取，而非硬编码在源码中。

### 4.5 `list.txt` 包含个人文件路径（隐私风险）

工作目录中的 `list.txt` 包含真实的个人文件路径，虽然 git 跟踪的是示例内容，但工作目录中的实际内容如果误提交会泄露隐私。

---

## 五、改进建议

### 5.1 架构重构（最高优先级）

**目标：消除代码重复，实现"一次修改，处处生效"。**

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
├── bitrate_table.csv      # 码率数据（从 xlsx 导出）
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

将 94 分支 if-elif 替换为读取 CSV 文件：

```bash
# bitrate_table.csv 格式:
# max_pixels,bitrate
# 12288,95892
# 19200,135504
# ...

lookup_bitrate() {
    local pixels="$1"
    awk -F',' -v p="$pixels" '
        NR>1 && p<=$1 { print $2; exit }
        END { exit 2 }
    ' "$(dirname "$0")/bitrate_table.csv"
}
```

### 5.3 消除 eval — 使用数组

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

将所有 .sh 文件中重复的 9 个函数提取到 `lib/common.sh`，各脚本 `source` 引用即可。

### 5.8 合并 nvenc 和 nvenc_cygwin

两个文件仅 hwaccel 行不同，应通过参数或平台检测合并为一个脚本。

---

## 六、量化评估

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

**综合评分：3.5 / 10**

---

## 七、优先级排序的改进路线图

| 优先级 | 改进项                                 | 预期收益                    |
|:---:| ----------------------------------- | ----------------------- |
| P0  | 添加 .gitignore                       | 防止大文件误入库                |
| P0  | 修复 `TARGET_BITRATE =` 语法错误          | 交互输入码率功能恢复              |
| P1  | 提取公共函数到 lib/common.sh               | 减少 ~60% 重复代码            |
| P1  | 码率查找表改为 CSV 数据驱动                    | 94 分支→1 个函数，修改码率只需改 CSV |
| P1  | 合并 nvenc/nvenc_cygwin/libx265 为统一脚本 | 11 个文件→1 个脚本+参数         |
| P2  | 消除 eval，改用数组                        | 安全性提升                   |
| P2  | 修复变量引号和文件名空格处理                      | 健壮性提升                   |
| P2  | .bat 临时文件改用 for /f                  | 消除竞争风险                  |
| P3  | 清理死代码和调试标记                          | 可读性提升                   |
| P3  | 修正拼写错误                              | 专业性提升                   |
| P3  | 规范 git commit message               | 可追溯性提升                  |
