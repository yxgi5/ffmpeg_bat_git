# 存档视频压缩码率

根据分辨率给出较低的码率来转换视频为 h265 格式的 mp4 文件

码率选取曲线见《bitrate_calc.xlsx》

如果要输出中等质量码率, 修改一下查表输出，不除2。

## 设置 cmd 环境
opencmd.bat

## 批量转换
不带参数, 默认从 list.txt 文件读取
```
.\convert_from_list.bat
```
带参数, 可以指定 list 文件
```
.\convert_from_list.bat list0.txt
```

## 单独执行文件转换

不带参数，需要交互输入文件名，根据提示进行输入，其中码率和输出文件名可以为空
```
.\ffmpeg_hevc_qsv.bat
```


带参数, 只传递文件名，码率和输出文件名采用默认
```
.\ffmpeg_hevc_qsv.bat  "D:\....\xxx.mov"
```

<https://en.wikipedia.org/wiki/Intel_Quick_Sync_Video#Hardware_decoding_and_encoding>




## linux 下通用的版本

convert_from_list.sh + ffmpeg_lib265.sh

必须加参数
```
./convert_from_list.sh list.txt
```


单独用和前面类似, 可以加一个文件名参数或者不加参数
```
./ffmpeg_libx265.sh  "/dss/xxx/xxx.mov"
```
```
./ffmpeg_libx265.sh
```


### linux 下硬件加速
查询显卡
```
lspci -vnn | grep -i VGA -A 12
```

查询软件支持的的硬件加速
```
$ ffmpeg -hide_banner -hwaccels shows
Hardware acceleration methods:
vdpau
vaapi
drm

$ ffmpeg -hide_banner -init_hw_device list
Supported hardware device types:
vdpau
vaapi
drm

```

hevc_vaapi、h264_vaapi 测试ok。 

查询软件支持的编码器和解码器
```
ffmpeg -hide_banner -encoders | grep hevc
ffmpeg -hide_banner -decoders | grep hevc
```

