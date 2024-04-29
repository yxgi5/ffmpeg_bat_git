# 基于ffmpeg的软件参数查看

## 根据进程名查找命令参数
```
wmic process where caption="ffmpeg.exe" get caption,commandline /value
```
## 根据所有命令行参数进行筛选
可以用于formatfactory、ShanaEncoder等
```
wmic process get caption,commandline /value | findstr "ffmpeg"
wmic process get caption,commandline /value | findstr ".mp4"
```

## 查看命令所在位置
```
where ffmpeg
C:\Program Files\ffmpeg\bin\ffmpeg.exe
```

# ffmpeg基础命令

## 查看版本
```
ffmpeg -version
```

## 去掉banner信息
```
ffmpeg -hide_banner
```
## 查看codecs(解码器)
```
ffmpeg -hide_banner -codecs
```
### 查询所需的特定编解码器
```
ffmpeg -hide_banner -codecs | grep nvenc    (bash)
ffmpeg -hide_banner -codecs | findstr nvenc (cmd)
ffmpeg -hide_banner -codecs | sls nvenc     (power shell 的 sls 命令相当于 linux 的 grep 命令)
```

## 查看硬件加速方式
```
ffmpeg -hide_banner -hwaccels
```

## 查看支持的解码器
```
ffmpeg -hide_banner -decoders
ffmpeg -hide_banner -decoders | findstr h264
ffmpeg -hide_banner -decoders | findstr hevc
```

## 查看支持的编码器
```
ffmpeg -hide_banner -encoders
ffmpeg -hide_banner -encoders | findstr hevc
ffmpeg -hide_banner -encoders | findstr qsv
ffmpeg -hide_banner -encoders | findstr nvenc
ffmpeg -hide_banner -encoders | findstr amf
```

## 查看hevc_qsv编码器选项
```
ffmpeg -hide_banner -h encoder=hevc_qsv

Encoder hevc_qsv [HEVC (Intel Quick Sync Video acceleration)]:
    General capabilities: delay hybrid
    Threading capabilities: none
    Supported hardware devices: qsv qsv qsv
    Supported pixel formats: nv12 p010le p012le yuyv422 y210le qsv bgra x2rgb10le vuyx xv30le
hevc_qsv encoder AVOptions:
  -async_depth       <int>        E..V....... Maximum processing parallelism (from 1 to INT_MAX) (default 4)
  -preset            <int>        E..V....... (from 0 to 7) (default 0)
     veryfast        7            E..V.......
     faster          6            E..V.......
     fast            5            E..V.......
     medium          4            E..V.......
     slow            3            E..V.......
     slower          2            E..V.......
     veryslow        1            E..V.......
  -forced_idr        <boolean>    E..V....... Forcing I frames as IDR frames (default false)
  -low_power         <boolean>    E..V....... enable low power mode(experimental: many limitations by mfx version, BRC modes, etc.) (default auto)
  -rdo               <int>        E..V....... Enable rate distortion optimization (from -1 to 1) (default -1)
  -max_frame_size    <int>        E..V....... Maximum encoded frame size in bytes (from -1 to INT_MAX) (default -1)
  -max_frame_size_i  <int>        E..V....... Maximum encoded I frame size in bytes (from -1 to INT_MAX) (default -1)
  -max_frame_size_p  <int>        E..V....... Maximum encoded P frame size in bytes (from -1 to INT_MAX) (default -1)
  -max_slice_size    <int>        E..V....... Maximum encoded slice size in bytes (from -1 to INT_MAX) (default -1)
  -mbbrc             <int>        E..V....... MB level bitrate control (from -1 to 1) (default -1)
  -extbrc            <int>        E..V....... Extended bitrate control (from -1 to 1) (default -1)
  -p_strategy        <int>        E..V....... Enable P-pyramid: 0-default 1-simple 2-pyramid(bf need to be set to 0). (from 0 to 2) (default 0)
  -b_strategy        <int>        E..V....... Strategy to choose between I/P/B-frames (from -1 to 1) (default -1)
  -dblk_idc          <int>        E..V....... This option disable deblocking. It has value in range 0~2. (from 0 to 2) (default 0)
  -low_delay_brc     <boolean>    E..V....... Allow to strictly obey avg frame size (default auto)
  -max_qp_i          <int>        E..V....... Maximum video quantizer scale for I frame (from -1 to 51) (default -1)
  -min_qp_i          <int>        E..V....... Minimum video quantizer scale for I frame (from -1 to 51) (default -1)
  -max_qp_p          <int>        E..V....... Maximum video quantizer scale for P frame (from -1 to 51) (default -1)
  -min_qp_p          <int>        E..V....... Minimum video quantizer scale for P frame (from -1 to 51) (default -1)
  -max_qp_b          <int>        E..V....... Maximum video quantizer scale for B frame (from -1 to 51) (default -1)
  -min_qp_b          <int>        E..V....... Minimum video quantizer scale for B frame (from -1 to 51) (default -1)
  -adaptive_i        <int>        E..V....... Adaptive I-frame placement (from -1 to 1) (default -1)
  -adaptive_b        <int>        E..V....... Adaptive B-frame placement (from -1 to 1) (default -1)
  -scenario          <int>        E..V....... A hint to encoder about the scenario for the encoding session (from 0 to 8) (default unknown)
     unknown         0            E..V.......
     displayremoting 1            E..V.......
     videoconference 2            E..V.......
     archive         3            E..V.......
     livestreaming   4            E..V.......
     cameracapture   5            E..V.......
     videosurveillance 6            E..V.......
     gamestreaming   7            E..V.......
     remotegaming    8            E..V.......
  -avbr_accuracy     <int>        E..V....... Accuracy of the AVBR ratecontrol (unit of tenth of percent) (from 0 to 65535) (default 0)
  -avbr_convergence  <int>        E..V....... Convergence of the AVBR ratecontrol (unit of 100 frames) (from 0 to 65535) (default 0)
  -skip_frame        <int>        E..V....... Allow frame skipping (from 0 to 3) (default no_skip)
     no_skip         0            E..V....... Frame skipping is disabled
     insert_dummy    1            E..V....... Encoder inserts into bitstream frame where all macroblocks are encoded as skipped
     insert_nothing  2            E..V....... Encoder inserts nothing into bitstream
     brc_only        3            E..V....... skip_frame metadata indicates the number of missed frames before the current frame
  -dual_gfx          <int>        E..V....... Prefer processing on both iGfx and dGfx simultaneously (from 0 to 2) (default off)
     off             0            E..V....... Disable HyperEncode mode
     on              1            E..V....... Enable HyperEncode mode and return error if incompatible parameters during initialization
     adaptive        2            E..V....... Enable HyperEncode mode or fallback to single GPU if incompatible parameters during initialization
  -idr_interval      <int>        E..V....... Distance (in I-frames) between IDR frames (from -1 to INT_MAX) (default 0)
     begin_only      -1           E..V....... Output an IDR-frame only at the beginning of the stream
  -load_plugin       <int>        E..V....... A user plugin to load in an internal session (from 0 to 2) (default hevc_hw)
     none            0            E..V.......
     hevc_sw         1            E..V.......
     hevc_hw         2            E..V.......
  -load_plugins      <string>     E..V....... A :-separate list of hexadecimal plugin UIDs to load in an internal session (default "")
  -look_ahead_depth  <int>        E..V....... Depth of look ahead in number frames, available when extbrc option is enabled (from 0 to 100) (default 0)
  -profile           <int>        E..V....... (from 0 to INT_MAX) (default unknown)
     unknown         0            E..V.......
     main            1            E..V.......
     main10          2            E..V.......
     mainsp          3            E..V.......
     rext            4            E..V.......
     scc             9            E..V.......
  -tier              <int>        E..V....... Set the encoding tier (only level >= 4 can support high tier) (from 0 to 256) (default high)
     main            0            E..V.......
     high            256          E..V.......
  -gpb               <boolean>    E..V....... 1: GPB (generalized P/B frame); 0: regular P frame (default true)
  -tile_cols         <int>        E..V....... Number of columns for tiled encoding (from 0 to 65535) (default 0)
  -tile_rows         <int>        E..V....... Number of rows for tiled encoding (from 0 to 65535) (default 0)
  -recovery_point_sei <int>        E..V....... Insert recovery point SEI messages (from -1 to 1) (default -1)
  -aud               <boolean>    E..V....... Insert the Access Unit Delimiter NAL (default false)
  -pic_timing_sei    <boolean>    E..V....... Insert picture timing SEI with pic_struct_syntax element (default true)
  -transform_skip    <int>        E..V....... Turn this option ON to enable transformskip (from -1 to 1) (default -1)
  -int_ref_type      <int>        E..V....... Intra refresh type. B frames should be set to 0 (from -1 to 65535) (default -1)
     none            0            E..V.......
     vertical        1            E..V.......
     horizontal      2            E..V.......
     slice           3            E..V.......
  -int_ref_cycle_size <int>        E..V....... Number of frames in the intra refresh cycle (from -1 to 65535) (default -1)
  -int_ref_qp_delta  <int>        E..V....... QP difference for the refresh MBs (from -32768 to 32767) (default -32768)
  -int_ref_cycle_dist <int>        E..V....... Distance between the beginnings of the intra-refresh cycles in frames (from -1 to 32767) (default -1)
```

## 查看libx265编码器选项
```
ffmpeg -hide_banner -h encoder=libx265

Encoder libx265 [libx265 H.265 / HEVC]:
    General capabilities: dr1 delay threads
    Threading capabilities: other
    Supported pixel formats: yuv420p yuvj420p yuv422p yuvj422p yuv444p yuvj444p gbrp yuv420p10le yuv422p10le yuv444p10le gbrp10le yuv420p12le yuv422p12le yuv444p12le gbrp12le gray gray10le gray12le
libx265 AVOptions:
  -crf               <float>      E..V....... set the x265 crf (from -1 to FLT_MAX) (default -1)
  -qp                <int>        E..V....... set the x265 qp (from -1 to INT_MAX) (default -1)
  -forced-idr        <boolean>    E..V....... if forcing keyframes, force them as IDR frames (default false)
  -preset            <string>     E..V....... set the x265 preset
  -tune              <string>     E..V....... set the x265 tune parameter
  -profile           <string>     E..V....... set the x265 profile
  -udu_sei           <boolean>    E..V....... Use user data unregistered SEI if available (default false)
  -a53cc             <boolean>    E..V....... Use A53 Closed Captions (if available) (default true)
  -x265-params       <dictionary> E..V....... set the x265 configuration using a :-separated list of key=value parameters
```

## 查看libx264编码器选项
```
ffmpeg -hide_banner -h encoder=libx264

Encoder libx264 [libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10]:
    General capabilities: dr1 delay threads
    Threading capabilities: other
    Supported pixel formats: yuv420p yuvj420p yuv422p yuvj422p yuv444p yuvj444p nv12 nv16 nv21 yuv420p10le yuv422p10le yuv444p10le nv20le gray gray10le
libx264 AVOptions:
  -preset            <string>     E..V....... Set the encoding preset (cf. x264 --fullhelp) (default "medium")
  -tune              <string>     E..V....... Tune the encoding params (cf. x264 --fullhelp)
  -profile           <string>     E..V....... Set profile restrictions (cf. x264 --fullhelp)
  -fastfirstpass     <boolean>    E..V....... Use fast settings when encoding first pass (default true)
  -level             <string>     E..V....... Specify level (as defined by Annex A)
  -passlogfile       <string>     E..V....... Filename for 2 pass stats
  -wpredp            <string>     E..V....... Weighted prediction for P-frames
  -a53cc             <boolean>    E..V....... Use A53 Closed Captions (if available) (default true)
  -x264opts          <string>     E..V....... x264 options
  -crf               <float>      E..V....... Select the quality for constant quality mode (from -1 to FLT_MAX) (default -1)
  -crf_max           <float>      E..V....... In CRF mode, prevents VBV from lowering quality beyond this point. (from -1 to FLT_MAX) (default -1)
  -qp                <int>        E..V....... Constant quantization parameter rate control method (from -1 to INT_MAX) (default -1)
  -aq-mode           <int>        E..V....... AQ method (from -1 to INT_MAX) (default -1)
     none            0            E..V.......
     variance        1            E..V....... Variance AQ (complexity mask)
     autovariance    2            E..V....... Auto-variance AQ
     autovariance-biased 3            E..V....... Auto-variance AQ with bias to dark scenes
  -aq-strength       <float>      E..V....... AQ strength. Reduces blocking and blurring in flat and textured areas. (from -1 to FLT_MAX) (default -1)
  -psy               <boolean>    E..V....... Use psychovisual optimizations. (default auto)
  -psy-rd            <string>     E..V....... Strength of psychovisual optimization, in <psy-rd>:<psy-trellis> format.
  -rc-lookahead      <int>        E..V....... Number of frames to look ahead for frametype and ratecontrol (from -1 to INT_MAX) (default -1)
  -weightb           <boolean>    E..V....... Weighted prediction for B-frames. (default auto)
  -weightp           <int>        E..V....... Weighted prediction analysis method. (from -1 to INT_MAX) (default -1)
     none            0            E..V.......
     simple          1            E..V.......
     smart           2            E..V.......
  -ssim              <boolean>    E..V....... Calculate and print SSIM stats. (default auto)
  -intra-refresh     <boolean>    E..V....... Use Periodic Intra Refresh instead of IDR frames. (default auto)
  -bluray-compat     <boolean>    E..V....... Bluray compatibility workarounds. (default auto)
  -b-bias            <int>        E..V....... Influences how often B-frames are used (from INT_MIN to INT_MAX) (default INT_MIN)
  -b-pyramid         <int>        E..V....... Keep some B-frames as references. (from -1 to INT_MAX) (default -1)
     none            0            E..V.......
     strict          1            E..V....... Strictly hierarchical pyramid
     normal          2            E..V....... Non-strict (not Blu-ray compatible)
  -mixed-refs        <boolean>    E..V....... One reference per partition, as opposed to one reference per macroblock (default auto)
  -8x8dct            <boolean>    E..V....... High profile 8x8 transform. (default auto)
  -fast-pskip        <boolean>    E..V....... (default auto)
  -aud               <boolean>    E..V....... Use access unit delimiters. (default auto)
  -mbtree            <boolean>    E..V....... Use macroblock tree ratecontrol. (default auto)
  -deblock           <string>     E..V....... Loop filter parameters, in <alpha:beta> form.
  -cplxblur          <float>      E..V....... Reduce fluctuations in QP (before curve compression) (from -1 to FLT_MAX) (default -1)
  -partitions        <string>     E..V....... A comma-separated list of partitions to consider. Possible values: p8x8, p4x4, b8x8, i8x8, i4x4, none, all
  -direct-pred       <int>        E..V....... Direct MV prediction mode (from -1 to INT_MAX) (default -1)
     none            0            E..V.......
     spatial         1            E..V.......
     temporal        2            E..V.......
     auto            3            E..V.......
  -slice-max-size    <int>        E..V....... Limit the size of each slice in bytes (from -1 to INT_MAX) (default -1)
  -stats             <string>     E..V....... Filename for 2 pass stats
  -nal-hrd           <int>        E..V....... Signal HRD information (requires vbv-bufsize; cbr not allowed in .mp4) (from -1 to INT_MAX) (default -1)
     none            0            E..V.......
     vbr             1            E..V.......
     cbr             2            E..V.......
  -avcintra-class    <int>        E..V....... AVC-Intra class 50/100/200/300/480 (from -1 to 480) (default -1)
  -me_method         <int>        E..V....... Set motion estimation method (from -1 to 4) (default -1)
     dia             0            E..V.......
     hex             1            E..V.......
     umh             2            E..V.......
     esa             3            E..V.......
     tesa            4            E..V.......
  -motion-est        <int>        E..V....... Set motion estimation method (from -1 to 4) (default -1)
     dia             0            E..V.......
     hex             1            E..V.......
     umh             2            E..V.......
     esa             3            E..V.......
     tesa            4            E..V.......
  -forced-idr        <boolean>    E..V....... If forcing keyframes, force them as IDR frames. (default false)
  -coder             <int>        E..V....... Coder type (from -1 to 1) (default default)
     default         -1           E..V.......
     cavlc           0            E..V.......
     cabac           1            E..V.......
     vlc             0            E..V.......
     ac              1            E..V.......
  -b_strategy        <int>        E..V....... Strategy to choose between I/P/B-frames (from -1 to 2) (default -1)
  -chromaoffset      <int>        E..V....... QP difference between chroma and luma (from INT_MIN to INT_MAX) (default 0)
  -sc_threshold      <int>        E..V....... Scene change threshold (from INT_MIN to INT_MAX) (default -1)
  -noise_reduction   <int>        E..V....... Noise reduction (from INT_MIN to INT_MAX) (default -1)
  -udu_sei           <boolean>    E..V....... Use user data unregistered SEI if available (default false)
  -x264-params       <dictionary> E..V....... Override the x264 configuration using a :-separated list of key=value parameters
  -mb_info           <boolean>    E..V....... Set mb_info data through AVSideData, only useful when used from the API (default false)
```

## 查看hevc_nvenc编码器选项
```
ffmpeg -hide_banner -h encoder=hevc_nvenc

Encoder hevc_nvenc [NVIDIA NVENC hevc encoder]:
    General capabilities: dr1 delay hardware
    Threading capabilities: none
    Supported hardware devices: cuda cuda d3d11va d3d11va
    Supported pixel formats: yuv420p nv12 p010le yuv444p p016le yuv444p16le bgr0 bgra rgb0 rgba x2rgb10le x2bgr10le gbrp gbrp16le cuda d3d11
hevc_nvenc AVOptions:
  -preset            <int>        E..V....... Set the encoding preset (from 0 to 18) (default p4)
     default         0            E..V.......
     slow            1            E..V....... hq 2 passes
     medium          2            E..V....... hq 1 pass
     fast            3            E..V....... hp 1 pass
     hp              4            E..V.......
     hq              5            E..V.......
     bd              6            E..V.......
     ll              7            E..V....... low latency
     llhq            8            E..V....... low latency hq
     llhp            9            E..V....... low latency hp
     lossless        10           E..V....... lossless
     losslesshp      11           E..V....... lossless hp
     p1              12           E..V....... fastest (lowest quality)
     p2              13           E..V....... faster (lower quality)
     p3              14           E..V....... fast (low quality)
     p4              15           E..V....... medium (default)
     p5              16           E..V....... slow (good quality)
     p6              17           E..V....... slower (better quality)
     p7              18           E..V....... slowest (best quality)
  -tune              <int>        E..V....... Set the encoding tuning info (from 1 to 4) (default hq)
     hq              1            E..V....... High quality
     ll              2            E..V....... Low latency
     ull             3            E..V....... Ultra low latency
     lossless        4            E..V....... Lossless
  -profile           <int>        E..V....... Set the encoding profile (from 0 to 4) (default main)
     main            0            E..V.......
     main10          1            E..V.......
     rext            2            E..V.......
  -level             <int>        E..V....... Set the encoding level restriction (from 0 to 186) (default auto)
     auto            0            E..V.......
     1               30           E..V.......
     1.0             30           E..V.......
     2               60           E..V.......
     2.0             60           E..V.......
     2.1             63           E..V.......
     3               90           E..V.......
     3.0             90           E..V.......
     3.1             93           E..V.......
     4               120          E..V.......
     4.0             120          E..V.......
     4.1             123          E..V.......
     5               150          E..V.......
     5.0             150          E..V.......
     5.1             153          E..V.......
     5.2             156          E..V.......
     6               180          E..V.......
     6.0             180          E..V.......
     6.1             183          E..V.......
     6.2             186          E..V.......
  -tier              <int>        E..V....... Set the encoding tier (from 0 to 1) (default main)
     main            0            E..V.......
     high            1            E..V.......
  -rc                <int>        E..V....... Override the preset rate-control (from -1 to INT_MAX) (default -1)
     constqp         0            E..V....... Constant QP mode
     vbr             1            E..V....... Variable bitrate mode
     cbr             2            E..V....... Constant bitrate mode
     vbr_minqp       8388609      E..V....... Variable bitrate mode with MinQP (deprecated)
     ll_2pass_quality 8388609      E..V....... Multi-pass optimized for image quality (deprecated)
     ll_2pass_size   8388610      E..V....... Multi-pass optimized for constant frame size (deprecated)
     vbr_2pass       8388609      E..V....... Multi-pass variable bitrate mode (deprecated)
     cbr_ld_hq       8388610      E..V....... Constant bitrate low delay high quality mode
     cbr_hq          8388610      E..V....... Constant bitrate high quality mode
     vbr_hq          8388609      E..V....... Variable bitrate high quality mode
  -rc-lookahead      <int>        E..V....... Number of frames to look ahead for rate-control (from 0 to INT_MAX) (default 0)
  -surfaces          <int>        E..V....... Number of concurrent surfaces (from 0 to 64) (default 0)
  -cbr               <boolean>    E..V....... Use cbr encoding mode (default false)
  -2pass             <boolean>    E..V....... Use 2pass encoding mode (default auto)
  -gpu               <int>        E..V....... Selects which NVENC capable GPU to use. First GPU is 0, second is 1, and so on. (from -2 to INT_MAX) (default any)
     any             -1           E..V....... Pick the first device available
     list            -2           E..V....... List the available devices
  -rgb_mode          <int>        E..V....... Configure how nvenc handles packed RGB input. (from 0 to INT_MAX) (default yuv420)
     yuv420          1            E..V....... Convert to yuv420
     yuv444          2            E..V....... Convert to yuv444
     disabled        0            E..V....... Disables support, throws an error.
  -delay             <int>        E..V....... Delay frame output by the given amount of frames (from 0 to INT_MAX) (default INT_MAX)
  -no-scenecut       <boolean>    E..V....... When lookahead is enabled, set this to 1 to disable adaptive I-frame insertion at scene cuts (default false)
  -forced-idr        <boolean>    E..V....... If forcing keyframes, force them as IDR frames. (default false)
  -spatial_aq        <boolean>    E..V....... set to 1 to enable Spatial AQ (default false)
  -spatial-aq        <boolean>    E..V....... set to 1 to enable Spatial AQ (default false)
  -temporal_aq       <boolean>    E..V....... set to 1 to enable Temporal AQ (default false)
  -temporal-aq       <boolean>    E..V....... set to 1 to enable Temporal AQ (default false)
  -zerolatency       <boolean>    E..V....... Set 1 to indicate zero latency operation (no reordering delay) (default false)
  -nonref_p          <boolean>    E..V....... Set this to 1 to enable automatic insertion of non-reference P-frames (default false)
  -strict_gop        <boolean>    E..V....... Set 1 to minimize GOP-to-GOP rate fluctuations (default false)
  -aq-strength       <int>        E..V....... When Spatial AQ is enabled, this field is used to specify AQ strength. AQ strength scale is from 1 (low) - 15 (aggressive) (from 1 to 15) (default 8)
  -cq                <float>      E..V....... Set target quality level (0 to 51, 0 means automatic) for constant quality mode in VBR rate control (from 0 to 51) (default 0)
  -aud               <boolean>    E..V....... Use access unit delimiters (default false)
  -bluray-compat     <boolean>    E..V....... Bluray compatibility workarounds (default false)
  -init_qpP          <int>        E..V....... Initial QP value for P frame (from -1 to 51) (default -1)
  -init_qpB          <int>        E..V....... Initial QP value for B frame (from -1 to 51) (default -1)
  -init_qpI          <int>        E..V....... Initial QP value for I frame (from -1 to 51) (default -1)
  -qp                <int>        E..V....... Constant quantization parameter rate control method (from -1 to 51) (default -1)
  -qp_cb_offset      <int>        E..V....... Quantization parameter offset for cb channel (from -12 to 12) (default 0)
  -qp_cr_offset      <int>        E..V....... Quantization parameter offset for cr channel (from -12 to 12) (default 0)
  -weighted_pred     <int>        E..V....... Set 1 to enable weighted prediction (from 0 to 1) (default 0)
  -b_ref_mode        <int>        E..V....... Use B frames as references (from -1 to 2) (default -1)
     disabled        0            E..V....... B frames will not be used for reference
     each            1            E..V....... Each B frame will be used for reference
     middle          2            E..V....... Only (number of B frames)/2 will be used for reference
  -a53cc             <boolean>    E..V....... Use A53 Closed Captions (if available) (default true)
  -s12m_tc           <boolean>    E..V....... Use timecode (if available) (default true)
  -dpb_size          <int>        E..V....... Specifies the DPB size used for encoding (0 means automatic) (from 0 to INT_MAX) (default 0)
  -multipass         <int>        E..V....... Set the multipass encoding (from 0 to 2) (default disabled)
     disabled        0            E..V....... Single Pass
     qres            1            E..V....... Two Pass encoding is enabled where first Pass is quarter resolution
     fullres         2            E..V....... Two Pass encoding is enabled where first Pass is full resolution
  -ldkfs             <int>        E..V....... Low delay key frame scale; Specifies the Scene Change frame size increase allowed in case of single frame VBV and CBR (from 0 to 255) (default 0)
  -extra_sei         <boolean>    E..V....... Pass on extra SEI data (e.g. a53 cc) to be included in the bitstream (default true)
  -udu_sei           <boolean>    E..V....... Pass on user data unregistered SEI if available (default false)
  -intra-refresh     <boolean>    E..V....... Use Periodic Intra Refresh instead of IDR frames (default false)
  -single-slice-intra-refresh <boolean>    E..V....... Use single slice intra refresh (default false)
  -max_slice_size    <int>        E..V....... Maximum encoded slice size in bytes (from 0 to INT_MAX) (default 0)
  -constrained-encoding <boolean>    E..V....... Enable constrainedFrame encoding where each slice in the constrained picture is independent of other slices (default false)
```

## 查看h264_qsv解码器选项
```
ffmpeg -hide_banner -h decoder=h264_qsv

Decoder h264_qsv [H264 video (Intel Quick Sync Video acceleration)]:
    General capabilities: dr1 delay avoidprobe hybrid
    Threading capabilities: none
    Supported hardware devices: qsv
    Supported pixel formats: nv12 p010le p012le yuyv422 y210le y212le vuyx xv30le xv36le qsv
h264_qsv AVOptions:
  -async_depth       <int>        .D.V....... Internal parallelization depth, the higher the value the higher the latency. (from 1 to INT_MAX) (default 4)
  -gpu_copy          <int>        .D.V....... A GPU-accelerated copy between video and system memory (from 0 to 2) (default default)
     default         0            .D.V.......
     on              1            .D.V.......
     off             2            .D.V.......
```

# formatfactory调用ffmpeg参数确定过程

## 确定1：默认关闭cfr/cq
```
CommandLine="C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V.mp4" -c:v:0 libx265 -b:v 14.40M -aspect 16:9 -c:a aac -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 "D:\FFOutput\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V~1.mp4"
```

## 实际上音频不需要转
不过有些文件还是不能直接copy音频，所以这个copy音频不通用
```
CommandLine="C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V.mp4" -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\V.mp4
```
另外换个源文件
```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\magarin02_4k.ts" -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\magarin02_4k.mp4
```
我操，目标视频比特率还是-b:v 14.40M

## formatfactory调用ffmpeg的banner信息
```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"
ffmpeg (Format Factory Revision)version N-110064-gcbcc817353 Copyright (c) 2000-2023 the FFmpeg developers
  built with gcc 8.3.0 (Rev2, Built by MSYS2 project)
  configuration: --prefix=/mingw64 --arch=x86_64 --disable-static --enable-shared --enable-small --disable-debug --extra-cflags='-ID:\CodeLib\Video_Codec_SDK_10.0.26\include -I/mingw64/include/mfx -O2' --extra-ldflags='-LD:\CodeLib\Video_Codec_SDK_10.0.26\Lib\x64' --enable-gpl --enable-version3 --enable-nonfree --enable-cuda --enable-cuvid --enable-dxva2 --enable-nvenc --enable-frei0r --enable-amf --enable-libmfx --enable-encoder=h264_qsv --enable-decoder=h264_qsv --enable-encoder=hevc_qsv --enable-libass --enable-libzvbi --enable-fontconfig --enable-iconv --enable-libbs2b --enable-libfreetype --enable-libgsm --enable-libilbc --enable-libmp3lame --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopenjpeg --enable-libopus --enable-libspeex --enable-libtheora --enable-libtwolame --enable-libvidstab --enable-libvo-amrwbenc --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxvid --enable-libaom --enable-bzlib --enable-lzma --enable-zlib --extra-libs='-static-libgcc -static-libstdc++ -lstdc++ -lgcc_eh -lpthread -lintl -liconv'
  libavutil      58.  5.100 / 58.  5.100
  libavcodec     60.  6.101 / 60.  6.101
  libavformat    60.  4.100 / 60.  4.100
  libavdevice    60.  2.100 / 60.  2.100
  libavfilter     9.  4.100 /  9.  4.100
  libswscale      7.  2.100 /  7.  2.100
  libswresample   4. 11.100 /  4. 11.100
  libpostproc    57.  2.100 / 57.  2.100
```

## 嗨格式压缩大师调用ffmpeg的banner信息
```
"C:\Program Files (x86)\Auntec\嗨格式压缩大师\ffmpeg.exe"
ffmpeg version 4.2 Copyright (c) 2000-2019 the FFmpeg developers
  built with gcc 9.1.1 (GCC) 20190807
  configuration: --enable-gpl --enable-version3 --enable-sdl2 --enable-fontconfig --enable-gnutls --enable-iconv --enable-libass --enable-libdav1d --enable-libbluray --enable-libfreetype --enable-libmp3lame --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopenjpeg --enable-libopus --enable-libshine --enable-libsnappy --enable-libsoxr --enable-libtheora --enable-libtwolame --enable-libvpx --enable-libwavpack --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxml2 --enable-libzimg --enable-lzma --enable-zlib --enable-gmp --enable-libvidstab --enable-libvorbis --enable-libvo-amrwbenc --enable-libmysofa --enable-libspeex --enable-libxvid --enable-libaom --enable-libmfx --enable-amf --enable-ffnvcodec --enable-cuvid --enable-d3d11va --enable-nvenc --enable-nvdec --enable-dxva2 --enable-avisynth --enable-libopenmpt
  libavutil      56. 31.100 / 56. 31.100
  libavcodec     58. 54.100 / 58. 54.100
  libavformat    58. 29.100 / 58. 29.100
  libavdevice    58.  8.100 / 58.  8.100
  libavfilter     7. 57.100 /  7. 57.100
  libswscale      5.  5.100 /  5.  5.100
  libswresample   3.  5.100 /  3.  5.100
  libpostproc    55.  5.100 / 55.  5.100
```

## Any Video Converter Professional调用ffmpeg的banner信息
```
"C:\Program Files (x86)\Anvsoft\Any Video Converter Professional\gnu\ffmpeg.exe"
FFmpeg version SVN-r25456-Sherpya, Copyright (c) 2000-2010 the FFmpeg developers
  built on Oct 14 2010 16:46:15 with gcc 4.2.5 20090330 (prerelease) [Sherpya]
  libavutil     50.32. 3 / 50.32. 3
  libavcore      0. 9. 1 /  0. 9. 1
  libavcodec    52.92. 0 / 52.92. 0
  libavformat   52.81. 0 / 52.81. 0
  libavdevice   52. 2. 2 / 52. 2. 2
  libavfilter    1.51. 1 /  1.51. 1
  libswscale     0.12. 0 /  0.12. 0
  libpostproc   51. 2. 0 / 51. 2. 0
```

## 最新的ffmpeg的banner信息
```
"C:\Program Files\ffmpeg\bin\ffmpeg.exe"
ffmpeg version 2024-01-14-git-34a47b97de-full_build-www.gyan.dev Copyright (c) 2000-2024 the FFmpeg developers
  built with gcc 12.2.0 (Rev10, Built by MSYS2 project)
  configuration: --enable-gpl --enable-version3 --enable-static --pkg-config=pkgconf --disable-w32threads --disable-autodetect --enable-fontconfig --enable-iconv --enable-gnutls --enable-libxml2 --enable-gmp --enable-bzlib --enable-lzma --enable-libsnappy --enable-zlib --enable-librist --enable-libsrt --enable-libssh --enable-libzmq --enable-avisynth --enable-libbluray --enable-libcaca --enable-sdl2 --enable-libaribb24 --enable-libaribcaption --enable-libdav1d --enable-libdavs2 --enable-libuavs3d --enable-libzvbi --enable-librav1e --enable-libsvtav1 --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxavs2 --enable-libxvid --enable-libaom --enable-libjxl --enable-libopenjpeg --enable-libvpx --enable-mediafoundation --enable-libass --enable-frei0r --enable-libfreetype --enable-libfribidi --enable-libharfbuzz --enable-liblensfun --enable-libvidstab --enable-libvmaf --enable-libzimg --enable-amf --enable-cuda-llvm --enable-cuvid --enable-ffnvcodec --enable-nvdec --enable-nvenc --enable-dxva2 --enable-d3d11va --enable-libvpl --enable-libshaderc --enable-vulkan --enable-libplacebo --enable-opencl --enable-libcdio --enable-libgme --enable-libmodplug --enable-libopenmpt --enable-libopencore-amrwb --enable-libmp3lame --enable-libshine --enable-libtheora --enable-libtwolame --enable-libvo-amrwbenc --enable-libcodec2 --enable-libilbc --enable-libgsm --enable-libopencore-amrnb --enable-libopus --enable-libspeex --enable-libvorbis --enable-ladspa --enable-libbs2b --enable-libflite --enable-libmysofa --enable-librubberband --enable-libsoxr --enable-chromaprint
  libavutil      58. 36.101 / 58. 36.101
  libavcodec     60. 37.100 / 60. 37.100
  libavformat    60. 20.100 / 60. 20.100
  libavdevice    60.  4.100 / 60.  4.100
  libavfilter     9. 17.100 /  9. 17.100
  libswscale      7.  6.100 /  7.  6.100
  libswresample   4. 13.100 /  4. 13.100
  libpostproc    57.  4.100 / 57.  4.10
```

## 测试formatfactory和最新版本的ffmpeg输出的结果

```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V.mp4" -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\V.mp4

"C:\Program Files\ffmpeg\bin\ffmpeg.exe" -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V.mp4" -c:v:0 hevc_qsv -b:v 14.40M  -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\V~1.mp4
```
后者的大小稍大，但是流畅性更好

## formatfactory默认的crf参数是给libx265编码器的
```
CommandLine="C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V.mp4" -c:v:0 libx265 -crf 16 -aspect 16:9 -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\V~2.mp4
```
libx265实际上可以给 `-threads 16` 之类的参数，不给也没关系，formatfactory默认也会把一半线程用起来。

## formatfactory改造
那么简单，把formatfactory的ffmpeg.exe替换了就好了。最好还是用命令行！

## formatfactory的参数目标比特率-b:v参数是根据"屏幕大小"这个玩意来定的
```
RES             H265/AV1    H264
XVGA-1024x768   2.28M       3.42M
SVGA-800x600    1.55M       2.33M
VGA-640x480     1.09M       1.64M
QVGA-320x240    379K        568K
QQVGA-160x120   128K        192K
CIF-352x228     471K        706K
QCIF-176x144    159K        239K
SubQCIF-128x96  100K        136K
960x540         1.65M       2.47M
856x480         1.37M       2.05M
720x408         1.05M       1.58M
640x360         895K        1.31M
480x360         714K        1.05M
480x272         570K/574K   856K/861K 
480x320         652K        977K
400x240         451K        677K
320x240         379K        568K
8K-7680x4320    42.57M      63.86M
BD-4096x2160    15.14M      22.72M
BD-3840x2160    14.40M      21.60M
HD-2560x1440    7.64M       11.46M
HD-1920x1080    4.87M       7.31M
HD-1280x720     2.58M       3.88M
HD-800x480      1.30M       1.95M
HD-720x576      1.38M       2.08M
HD-720x480      1.20M       1.80M
```

默认的最优质量和大小(屏幕大小<1080p,-b:v 4.87M，<720p -b:v 2.58M)
```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\magarin02_4k.ts" -s 1920x1080 -c:v:0 hevc_qsv -b:v 4.87M -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\magarin02_4k.mp4
```
修改(屏幕大小为"默认",-b:v 14.40M, 实际上并不稳定，有时候会自己变成2.58M)
```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\magarin02_4k.ts" -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\magarin02_4k~1.mp4
CommandLine=findstr  "ffmpeg"
```
默认音频采样率和比特率  -c:a aac
```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\magarin02_4k.ts" -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -c:a aac -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\magarin02_4k~2.mp4
```
“最优质量和大小” 给出的音频参数  -ar 44100 -b:a 128k -c:a aac -ac 2 
```
"C:\Program Files (x86)\FormatFactory\ffmpeg.exe"  -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\magarin02_4k.ts" -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\magarin02_4k.mp4
```

那么可以确定formatfactory的hevc_qsv是根据平均码率来进行编码的, 影响因素最大的就是"屏幕大小"，


# 改进编码方式的尝试

批量还是借鉴formatfactory，只控制目标文件bitrate

还可以用-global_quality控制质量，-global_quality 22 以下合适？

## hevc_qsv编码控制质量尝试
```
"C:\Users\dengl\Desktop\ShanaEncoder\tools\x64\ShanaEncoder.sha"  -threads 0 -thread_type frame -hwaccel dxva2 -gui_hwnd 15992268 -hide_msg -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\011.[DCP-snaps] May Vol.1 [98P+1V／785MB]\011.[DCP-snaps]_May_Vol.1__001.mp4"  -threads 0 -f mp4 -c:v hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -c:a libfdk_aac -cutoff 20k -b:a 192k -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -map 0:0 -map 0:1 "D:\\[SHANA]011.[DCP-snaps]_May_Vol.1__001.mp4"

"C:\Users\dengl\Desktop\ShanaEncoder\tools\x64\ShanaEncoder.sha"  -threads 0 -thread_type frame -hwaccel dxva2 -gui_hwnd 15992268 -hide_msg -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\011.[DCP-snaps] May Vol.1 [98P+1V／785MB]\011.[DCP-snaps]_May_Vol.1__001.mp4"   -threads 0 -f mp4 -c:v hevc_qsv -fps_mode cfr -profile:v main  -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -c:a copy -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -map 0:0 -map 0:1 "D:\\[SHANA]011.[DCP-snaps]_May_Vol.1__001.mp4"

"C:\Users\dengl\Desktop\ShanaEncoder\tools\x64\ShanaEncoder.sha"  -threads 0 -thread_type frame -gui_hwnd 15992268 -hide_msg -y -i "D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv"  -af "aresample=48000:resampler=soxr"  -threads 0 -f mp4 -c:v hevc_qsv -fps_mode cfr -profile:v main  -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -c:a libfdk_aac -cutoff 20k -ac 2 -b:a 192k -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -map 0:1 -map 0:0 "D:\\[SHANA]丝袜足交.mp4"

ffmpeg.exe -y -i "D:\BaiduNetdiskDownload\tmp\from\20240118\135.[Bimilstory] Magarin Vol.02 - The essence of Lingerie[2V-3.03G]\V.mp4" -c:v:0 hevc_qsv -b:v 14.40M -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\V~1.mp4

ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv -c:v:0 hevc_qsv -b:v 2.58M -aspect 16:9 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\丝袜足交~1.mp4

ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv -c:v:0 hevc_qsv -b:v 14.40M -aspect 16:9 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\丝袜足交~3.mp4


ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv -map 0 -c copy -c:v:0 hevc_qsv -preset slow -global_quality 22 -look_ahead 1 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\丝袜足交~3.mp4

ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv -threads 0 -f mp4 -c:v hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -c:a aac -cutoff 20k -b:a 192k -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -map 0:0 -map 0:1 "D:\FFOutput\丝袜足交~4.mp4"

ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv -c:v:0 hevc_qsv -fps_mode cfr -preset veryfast -global_quality:v 16 -g 250 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\丝袜足交~5.mp4

ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.wmv -c:v:0 hevc_qsv -fps_mode cfr -preset veryfast -global_quality:v 16 -g 250 -c:a aac -cutoff 20k -ac 2 -b:a 192k -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\丝袜足交~6.mp4


ffmpeg.exe -y -i D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.mp4 -threads 0 -f mp4 -c:v hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -c:a copy -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -map 0:0 -map 0:1 "D:\FFOutput\丝袜足交~7.mp4"

ffmpeg.exe -y -i "D:\BaiduNetdiskDownload\[丝雨]\丝袜足交.mp4" -c:v:0 hevc_qsv -fps_mode cfr -preset veryfast -global_quality:v 16 -g 250 -c:a copy -map 0:v -map 0:a -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\丝袜足交~8.mp4
```
一般hevc_qsv先这样编码试试，可以尝试global_quality不同值测试看看输出的码率
```
ffmpeg.exe -y -i input.xxx -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 output.mp4

ffmpeg.exe -y -i "input.xxx" -c:v:0 hevc_qsv -fps_mode cfr -preset veryfast -global_quality:v 16？ -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"


ffmpeg -hide_banner -v warning -stats -hwaccel dxva2 -i "input.xxx" -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset fast -global_quality:v 16 -qmin 10 -qmax 31 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"

ffmpeg -hide_banner -v warning -stats -hwaccel dxva2 -i "input.xxx" -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset fast -global_quality:v 16  -g 250 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -max_muxing_queue_size 1024 "output.mp4"
---
这样设置下加不加-qmax -qmin没有区别
ffmpeg -hide_banner -v warning -stats -hwaccel dxva2 -i "input.xxx" -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset fast -global_quality:v 16 -qmin 10 -qmax 31 -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -map 0:1 -map 0:0 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"
```

## 读输入文件其实也可以进行硬件加速解码
```
ffmpeg -hwaccel cuvid -c:v h264_cuvid -i input.mp4 -c:v h264_nvenc -b:v 2048k output.mp4
```

hwaccel有qsv，auto，dxva2，cuda等，可能需要设置hwaccel_output_format, 比如 `-hwaccel qsv` 应配合 `-hwaccel_output_format qsv`

非标分辨率 例如 `-s 8192x540` 应该用 `-hwaccel auto`

### Intel QSV 加速解码

1、硬件解码H264 + 硬件编码H264，=>速率1.7x
```
ffmpeg -hwaccel qsv -c:v h264_qsv -i input.mp4 -c:v h264_qsv -global_quality 23 output.mp4
```
2、软件解码H264 + 硬件编码H264，=>速率0.9x
```
ffmpeg -i input.mp4 -c:v h264_qsv -global_quality 23 output.mp4
```
3、硬件解码H264 + 硬件编码H265，=>速率0.41x
```
ffmpeg -hwaccel qsv -c:v h264_qsv -i input.mp4 -c:v hevc_qsv -global_quality 28 output.mp4
```
4、软件解码H264 + 硬件编码H265，=>速率0.45x
```
ffmpeg -i input.mp4 -c:v hevc_qsv -global_quality 28 output.mp4
```

也就是说，解码也有点影响编码速度，不过已经差别不大了。

### cuda 加速解码
```
ffmpeg -vsync 0 -hwaccel cuvid -hwaccel_output_format cuda -c:v hevc_cuvid -noautorotate -hide_banner -i 源文件.mov -c:v h264_nvenc -vf scale_cuda=1280:720 -map_metadata 0 -preset slow -cq 40 输出文件.mp4
 
-hwaccel cuvid -hwaccel_output_format cuda -c:v hevc_cuvid # 指定使用gpu硬件解码。
-noautorotate # 不加这个，对于竖着拍摄的视频，转码将报错。
-c:v h264_nvenc # 位于源文件之后，指定使用gpu硬件编码器。
-vf scale_cuda=1280:720 # 指定使用gpu运算来缩放视频尺寸至720p。
-map_metadata 0 # 保留元数据。
-preset slow -cq 40 # 控制转码质量。cq可以根据实际需求取值（0~51，越小质量越好、码率越高，0为自动）。
```

## win10，批量转码
transcode_h265-to-h264.bat
```
mode con cols=100 lines=3
for %%a in ("\\nas\*.MOV") do "ffmpeg.exe" -vsync 0 -hwaccel cuvid -hwaccel_output_format cuda -c:v hevc_cuvid -noautorotate -hide_banner -i "%%a" -c:v h264_nvenc -vf scale_cuda=1280:720 -map_metadata 0 -preset slow -cq 40 "\\nas\transcoded\%%~na_720p_h264_cq=40.mp4"
```
<https%3A//developer.nvidia.com/blog/nvidia-ffmpeg-transcoding-guide/>



## 可以使用以下命令获得源视频参数
```
ffprobe -show_streams -i input.xxx >input.txt
```


# 视频压缩

## 控制质量方法
质量优先级高的, 先尝试控制q, 具体到hevc_qsv也就是-global_quality:v <q值这里一般用16>
```hevc_qsv
ffmpeg -hide_banner -threads 0 -hwaccel auto?qsv?dxva2? -i "input.xxx"? -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -global_quality:v 16 -g 250 -keyint_min 25 -pix_fmt nv12? -sws_flags bicubic  -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"?
```
```hevc_nvenc（默认是vbr文件会大一点）最快,接近3倍上面qsv设置
ffmpeg -hide_banner -threads 0 -hwaccel cuda -i "input.xxx" -c:v hevc_nvenc -global_quality 22 -g 250 -keyint_min 25 -profile:v main -preset p4 -tune:v hq -rc cbr -fps_mode cfr -pix_fmt yuv420p? -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"?
```
```av1_nvenc（默认是vbr文件会大一点）超过两倍上面qsv设置
ffmpeg -hide_banner -threads 0 -hwaccel cuda -i "input.xxx" -c:v av1_nvenc -global_quality 22 -g 250 -keyint_min 25 -preset p4 -tune:v hq -rc cbr -pix_fmt yuv420p? -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"?
```

## 控制比特率方法

一般情况下, 直接控制比特率, 也就是-b:v <比特率>, 比特率可以根据目标大小来定，也可以根据q=16时候的比特率来估计

后续根据formatfactory的目标bitrate做拟合, 拟合出一个合适的函数，来得出目标文件bitrate
```hevc_qsv
ffmpeg -hide_banner -threads 0 -hwaccel auto?qsv?dxva2? -i "input.xxx"? -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -b:v 10M? -g 250 -keyint_min 25 -pix_fmt nv12? -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"?
```
```hevc_nvenc（默认是vbr文件会大一点）最快,接近3倍上面qsv设置
ffmpeg -hide_banner -threads 0 -hwaccel cuda -i "input.xxx"? -c:v hevc_nvenc -b:v 2.58M？ -g 250 -keyint_min 25 -profile:v main -preset p4 -tune:v hq -rc cbr -fps_mode cfr -pix_fmt yuv420p? -sws_flags bicubic  -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"?
```
```av1_nvenc（默认是vbr文件会大一点）超过两倍上面qsv设置
ffmpeg -hide_banner -threads 0 -hwaccel cuda -i "input.xxx"? -c:v av1_nvenc -b:v 2.58M？ -g 250 -keyint_min 25 -preset p4 -tune:v hq -rc cbr -pix_fmt yuv420p? -sws_flags bicubic -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"?
```

控制码率方法其他可用命令
```
ffmpeg.exe -y -i input.xxx -c:v:0 hevc_qsv -b:v 2.58M? -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 output.mp4

ffmpeg.exe -hide_banner -v warning -stats -i "input.xxx" -c:v:0 hevc_qsv -preset veryfast -b:v 10M? -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"

ffmpeg -hide_banner -v warning -stats -hwaccel dxva2 -i "input.xxx" -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -b:v 10M -maxrate 10M -bufsize 5M -g 250 -ar 44100 -b:a 128k -c:a aac -ac 2 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 "output.mp4"
```
一般 bufsize 控制比 maxrate 小大概 1/3 ~ 1/2 即可。后来发现, -maxrate配合-b:v不起作用，不需要加。


### 快速设置比特率
```
4k 5M~7.20M~10M
1080p 2.58M~4.87M
```

## 关于硬件加速解码

hwaccel有qsv，auto，dxva2，cuda等，可能需要设置hwaccel_output_format, 比如 `-hwaccel qsv` 应配合 `-hwaccel_output_format qsv`

非标分辨率 例如 `-s 8192x540` 应该用 `-hwaccel auto`

Windows 环境下，在 AMD、Intel、Nvidia 的 GPU 上用 dxva2 和 d3d11va 来解码，再使用厂商提供的编码器编码的例子
```
ffmpeg -hwaccel dxva2 -hwaccel_output_format dxva2_vld -i <video> -c:v h264_amf -b:v 2M -y out.mp4
ffmpeg -hwaccel d3d11va -hwaccel_output_format d3d11 -i <video> -c:v h264_amf -b:v 2M -y out.mp4

ffmpeg -hwaccel dxva2 -hwaccel_output_format dxva2_vld -i <video> -c:v h264_qsv -vf hwmap=derive_device=qsv,format=qsv -b:v 2M -y out.mp4
ffmpeg -hwaccel d3d11va -hwaccel_output_format d3d11 -i <video> -c:v h264_qsv -vf hwmap=derive_device=qsv,format=qsv -b:v 2M -y out.mp4

ffmpeg -hwaccel d3d11va -hwaccel_output_format d3d11 -i <video> -c:v h264_nvenc -b:v 2M -y out.mp4
```

## 不能拖动进度的目标文件修复
之前formatfactory制作的h265格式mp4无法拖动, 可以先ffprob源mp4的video stream的bitrate，填入-b:v, -maxrate, -bufsize
```
ffmpeg -hide_banner -v warning -stats -threads 0 -thread_type frame -hwaccel dxva2 -i "input.xxx" -c:v:0 hevc_qsv -fps_mode cfr -profile:v main -preset veryfast -b:v 10M? -maxrate 10M? -bufsize 10M? -g 250 -keyint_min 25 -ar 44100 -b:a 128k -c:a aac -ac 2 -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 "output.mp4"
```
后来发现, -maxrate配合-b:v不起作用，不需要加。

# av1编码  
libsvtav1软件编码很慢(稍微堪用, 0.28x以下), librav1e比较慢(0.0xx), libaom-av1更慢一百倍(0x.00xx), intel-12代并不支持硬件av1_qsv编码，nv显卡可以用av1_nvenc
```
ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -r 24000/1001 -c:v libsvtav1 -b:v 7674k -preset 8 -g 250 -keyint_min 25 -filter_complex "[0:v]yadif=0:0:0[out]" -map "[out]" -c:a aac -ar 48k -b:a 192k -map a:0 -pix_fmt yuv420p -sws_flags bicubic -svtav1-params "enable-force-key-frames=0" -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_0.mp4"

ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -r 24000/1001 -c:v libsvtav1 -b:v 7674k -preset 8 -g 250 -keyint_min 25 -map v:0 -c:a aac -ar 48k -b:a 192k -map a:0 -ac 2 -pix_fmt yuv420p -sws_flags bicubic -svtav1-params "enable-force-key-frames=0" -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_1.mp4"

ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -af "aresample=48000:resampler=soxr" -r 24000/1001 -c:v libaom-av1 -cpu-used 2 -threads 4 -b:v 7674k -g 250 -keyint_min 25 -c:a aac -ar 48k -b:a 192k -ac 2  -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_2.mp4"

ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -af "aresample=48000:resampler=soxr" -r 24000/1001 -c:v libaom-av1 -threads 0 -b:v 7674k -g 250 -keyint_min 25 -c:a aac -ar 48k -b:a 192k -ac 2  -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_3.mp4"

ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -af "aresample=48000:resampler=soxr" -r 24000/1001 -c:v librav1e -threads 0 -b:v 7674k -g 250 -keyint_min 25 -c:a aac -ar 48k -b:a 192k -ac 2  -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_4.mp4"

ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -r 24000/1001 -c:v libsvtav1 -b:v 9600k -preset 8 -g 250 -keyint_min 25 -filter_complex "[0:v]yadif=0:0:0[out]" -map "[out]" -c:a aac -ar 48k -b:a 192k -map a:0 -pix_fmt yuv420p -sws_flags bicubic -svtav1-params "enable-force-key-frames=0" -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_5.mp4"
是比hevc少一些130M->100M

CRF35 -svtav1-params "enable-force-key-frames=0:rc=0"

ffmpeg -hide_banner -threads 0 -hwaccel auto -i "D:\BaiduNetdiskDownload\ffmpeg\v1.mp4" -r 24000/1001 -c:v libsvtav1 -crf 30 -preset 8 -g 250 -keyint_min 25 -filter_complex "[0:v]yadif=0:0:0[out]" -map "[out]" -c:a aac -ar 48k -b:a 192k -map a:0 -pix_fmt yuv420p -sws_flags bicubic -svtav1-params "enable-force-key-frames=0" -map_metadata -1 -map_chapters -1 -strict -2 -rtbufsize 120m -max_muxing_queue_size 1024 -y "D:\BaiduNetdiskDownload\ffmpeg\v1_av1_6.mp4"
```

ref

<https://trac.ffmpeg.org/wiki/Encode/AV1/>
<https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/svt-av1_encoder_user_guide.md>
<https://www.ffmpeg.org/ffmpeg-all.html#libsvtav1>
<https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Parameters.md>


record

```
ffmpeg -hide_banner -threads 0 -hwaccel qsv -i "D:\BaiduNetdiskDownload\ffmpeg\v0.wmv" -c:v av1_qsv "D:\BaiduNetdiskDownload\ffmpeg\v0_av1qsv_0.mp4" 不支持

ffmpeg.exe -y -i C:\Users\dengl\Desktop\pcie演示视频.mp4 -c:v:0 libaom-av1 -cpu-used 2 -threads 4 -b:v 1.33M -aspect 16:9 -c:a aac -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 "output.mp4"
ffmpeg.exe -y -i C:\Users\dengl\Desktop\pcie演示视频.mp4 -c:v:0 libaom-av1 -cpu-used 2 -threads 4 -crf 16 -aspect 16:9 -c:a aac -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\pcie演示视频~1.mp4

ffmpeg.exe -y -i C:\Users\dengl\Desktop\pcie演示视频.mp4 -c:v:0 libaom-av1 -aom-params lossless=1 -cpu-used 2 -threads 4 -crf 16 -aspect 16:9 -c:a aac -strict -2 -rtbufsize 30m -max_muxing_queue_size 1024 D:\FFOutput\pcie演示视频~1.mp4

"C:\Program Files\ShanaEncoder\tools\x64\ShanaEncoder.sha"  -threads 0 -thread_type frame -hwaccel dxva2 -gui_hwnd 4793176 -hide_msg -y -i "C:\Users\dengl\Desktop\pcie演示视频.mp4"  -af "aresample=48000:resampler=soxr"  -threads 0 -f mp4 -c:v libaom-av1 -b:v 2000k -g 300 -keyint_min 30 -c:a libfdk_aac -cutoff 20k -ac 2 -b:a 192k -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -strict experimental -map 0:0 -map 0:1 "D:\\[SHANA]pcie演示视频 (1).mp4"
 -f mp4
 -c:v libaom-av1 -b:v 2000k -shanakeyframe 10
 -c:a libfdk_aac -ac 2 -b:a 192k
 -sn -map_metadata -1 -map_chapters -1

"C:\Program Files\ShanaEncoder\tools\x64\ShanaEncoder.sha"  -threads 0 -thread_type frame -hwaccel dxva2 -gui_hwnd 4793176 -hide_msg -y -i "C:\Users\dengl\Desktop\pcie演示视频.mp4"  -af "aresample=48000:resampler=soxr"  -threads 0 -f mp4 -c:v libaom-av1 -b:v 2000k -g 300 -keyint_min 30 -fps_mode cfr -c:a libfdk_aac -cutoff 20k -ac 2 -b:a 192k -sn -map_metadata -1 -map_chapters -1 -pix_fmt yuv420p -strict experimental -map 0:0 -map 0:1 "D:\\[SHANA]pcie演示视频 (2).mp4"
 -f mp4
 -c:v libaom-av1 -b:v 2000k -shanakeyframe 10 -fps_mode cfr
 -c:a libfdk_aac -ac 2 -b:a 192k
 -sn -map_metadata -1 -map_chapters -1
```



# ffmpeg 进阶使用
## 常见选项含义
```
-y :  若输出档案已存在时覆盖输出文件
ffmpeg -hide_banner -h | findstr "\-y"
-y                  overwrite output files


-f fmt  ：强制设置输出格式
-c codec = -codec codec ：编解码器名称， ，CODEC =ENCode （编码） + DECode（解码）
-fs 固定大小(fixed size)，超过指定的档案大小时则结束转换。
-ss 从指定时间开始转换。
-t 录制时间
-title 设定标题。
-timestamp 设定时间戳。
-vsync 增减Frame使影音同步。


-map_metadata 0 : 保留元数据
-map_metadata outfile[,metadata]:infile[,metadata]  从infile设置outfile的元数据信息
ffmpeg -hide_banner -h full | findstr "\-map"

-i 输入文件名: 设置输入文件名
-b <int64>: 设定影像流量，默认为200Kbit
-q <数值> == -qscale <数值> 以<数值>质量为基础的VBR，取值0.01-255，越小质量越好。较新版本中修改为 -q:v <数值>. 
-q:v 0 == -qscale:v 0 指定输出与输入是相同的quality.
-qmin <数值> 设定最小质量，与-qmax（设定最大质量）共用，比如-qmin 10 -qmax 31
-r rate：设置帧速率（Hz值，分数或缩写）例如 –r 25  或 者例如 -vf fps=25
-s size ：设置帧大小（W x H或缩写）
-aspect aspect：设置纵横比（4：3,16：9或1.3333,1.77777）
-vn：禁用视频
-vcodec codec：强制视频编解码器（'复制’复制流）,未设定时则使用与输入档案相同之编解码器。
-c:v <codec>: 较新版本中修改为**-c:v <编解码器名>**。例如 -c:v libx264 指定编解码器为libx264.
-vf filter_graph：设置视频过滤器

-b bitrate：视频比特率（请使用-b:v）
-dn：禁用数据

-ab bitrate：音频比特率（请使用-b:a）
-aq quality ：设置音频质量（特定于编解码器）
-ar rate：设置音频采样率（Hz）
-ac channels ：设置音频通道数
-an：禁用音频
-acodec codec：强制音频编解码器（'复制’到复制流）
-c:a <codec>: 指定音频编解码器
-af filter_graph：设置音频过滤器


-sn：禁用字幕
-scodec codec ：强制字幕编解码器（'复制’复制流）
-fix_sub_duration：修复字幕持续时间
-canvas_size size：设置画布大小（W x H或缩写）
-spre preset：将字幕选项设置为指定的预设
```

## 术语
```
容器(Container) ：容器就是一种文件格式，比如flv，mkv等。包含下面5种流(Stream)以及文件头信息。

流(Stream)：是一种视频数据信息的传输方式，5种流：音频，视频，字幕，附件，数据。

帧(Frame)：帧代表一幅静止的图像，分为I帧，P帧，B帧。

编解码器(Codec)：是对视频进行压缩或者解压缩，CODEC =COde （编码） +DECode（解码）

复用/解复用(mux/demux)：把不同的流按照某种容器的规则放入容器，这种行为叫做复用（mux）；把不同的流从某种容器中解析出来，这种行为叫做解复用(demux).

过滤器(Filter)：在多媒体处理中，filter的意思是被编码到输出文件之前用来修改输入文件内容的一个软件工具。如：视频翻转，旋转，缩放等。
```

## 选择媒体流
一些多媒体容器比如AVI，mkv，mp4等，可以包含不同种类的多个流，如何从容器中抽取各种流呢？

语法：
```
-map file_number:stream_type[:stream_number]
```

一些特别流符号的说明：后面“##选择媒体流##”
```
1、-map 0 选择第一个文件的所有流
2、-map i:v 从文件序号i(index)中获取所有视频流， -map i:a 获取所有音频流，-map i:s 获取所有字幕流等等。
3、特殊参数-an,-vn,-sn分别排除所有的音频，视频，字幕流。
```

## 常用capabilities查询
```
可用的bit流过滤器 ：ffmpeg -hide_banner -bsfs         参考  ffmpeg -hide_banner -h | findstr "\-bsfs"
可用的编解码器：ffmpeg -hide_banner -codecs
可用的解码器：ffmpeg -hide_banner -decoders
可用的编码器：ffmpeg -hide_banner -encoders
可用的过滤器：ffmpeg -hide_banner -filters
可用的视频格式：ffmpeg -hide_banner -formats
可用的声道布局：ffmpeg -hide_banner -layouts
可用的license：ffmpeg -hide_banner -L
可用的像素格式：ffmpeg -hide_banner -pix_fmts
可用的协议：ffmpeg -hide_banner -protocals
```

## basic help

`ffmpeg -?`   ==  `ffmpeg -h`

## extended help
```
ffmpeg -h long
ffmpeg -h full
ffmpeg -hide_banner -h full
```
## help for selected item
```
ffmpeg -? topic   ==  ffmpeg -h topic
```
eg.
```
ffmpeg -hide_banner -h decoder=decoder_name
ffmpeg -hide_banner -h encoder=encoder_name
ffmpeg -hide_banner -h demuxer=demuxer_name
ffmpeg -hide_banner -h muxer=muxer_name
ffmpeg -hide_banner -h decoder=decoder_name
ffmpeg -hide_banner -h format=format_name
```
这些名称可以不加-h来查询
```
ffmpeg -hide_banner -encoders
ffmpeg -hide_banner -decoders
ffmpeg -hide_banner -codecs
ffmpeg -hide_banner -formats
ffmpeg -hide_banner -filters
ffmpeg -hide_banner -muxers
ffmpeg -hide_banner -demuxers
```


## 将MPEG-1影片转换成MPEG-4格式之范例
```
ffmpeg -i inputfile.mpg -f mp4 -acodec libfaac -vcodec mpeg4 -b 256k -ab 64k outputfile.mp4
```
## 将MP3声音转换成MPEG-4格式之范例
```
ffmpeg -i inputfile.mp3 -f mp4 -acodec libaac -vn -ab 64k outputfile.mp4
```
## 将DVD的VOB档转换成VideoCD格式的MPEG-1档之范例
```
ffmpeg -i inputfile.vob -f mpeg -acodec mp2 -vcodec mpeg1video -s 352x240 -b 1152k -ab 128k outputfile.mpg
```
## 将AVI影片转换成H.264格式的M4V档之范例
```
ffmpeg -i inputfile.avi -f mp4　-acodec libfaac -vcodec libx264 -b 512k -ab 320k outputfile.m4v
```
## 把两个视频文件合并成一个
简单地使用 concat demuxer，示例：
```
$ cat mylist.txt
file '/path/to/file1'
file '/path/to/file2'
file '/path/to/file3'
$ ffmpeg -f concat -i mylist.txt -c copy output
```
更多时候，由于输入文件的多样性，需要转成中间格式再合成：
```
ffmpeg -i input1.avi -qscale:v 1 intermediate1.mpg
ffmpeg -i input2.avi -qscale:v 1 intermediate2.mpg
cat intermediate1.mpg intermediate2.mpg > intermediate_all.mpg
ffmpeg -i intermediate_all.mpg -qscale:v 2 output.avi
```

## 合并连接复数的AVI影片档之范例
在此范例中须一度暂时将AVI档转换成MPEG-1档(MPEG-1, MPEG-2 PSDV格式亦可连接)
```
ffmpeg -i input1.avi -sameq inputfile_01.mpg
ffmpeg -i input2.avi -sameq inputfile_02.mpg
cat inputfile_01.mpg inputfile_02.mpg > inputfile_all.mpg
ffmpeg -i inputfile_all.mpg -sameq outputfile.avi
```
## 合并连接复数的AVI影片档
-sameq 表示 相同的质量,可能新版本已经没有这个了
```
ffmpeg -i input1.avi -sameq inputfile_01.mpg -r 20
ffmpeg -i input2.avi -sameq inputfile_02.mpg -r 20
cat inputfile_01.mpg inputfile_02.mpg > inputfile_all.mpg
ffmpeg -i inputfile_all.mpg -sameq outputfile.avi
```

## 查看视频格式信息
```
ffprobe input.avi
```
## 查看视频有多少帧
注意不是所有格式都可以用这种方法，这需要container支持, 比如mp4。
```
ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=nokey=1:noprint_wrappers=1 input.mp4
```
## 获取视频时间长度duration
```
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i a.flv
```
编写一个python函数：
```
import subprocess as sp

def get_video_duration(filename):
    cmd = "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i %s" % filename
    p = sp.Popen(cmd, stdout=sp.PIPE, stderr=sp.PIPE)
    p.wait()
    strout, strerr = p.communicate() # 去掉最后的回车
    ret = strout.decode("utf-8").split("\n")[0]
    return ret
```

## 将视频video.avi 和音频 audio.mp3 合并成output.avi
```
ffmpeg -i video.avi -vcodec copy -an video2.avi
ffmpeg -i video2.avi -i audio.mp3 -vcodec copy -acodec copy output.avi
```

## 从视频里提取视频或图片

### 第8秒处 截一张灰度图
```
ffmpeg -i test.avi -f image2 -ss 8 -t 0.001 -s 350x240 -vf format=gray test.jpg         
```
### 拆分剪切视频文件
```
ffmpeg -i [filename] -ss [starttime] -t [length] -c copy [newfilename]
ffmpeg -i ./in.mp4  -vcodec copy -acodec copy -ss 00:00:20 -to 00:05:30 ./out.mp4
-i 为需要裁剪的文件
-ss 为裁剪开始时间
-t 为裁剪结束时间或者长度
-to为结束时间。
```
用 Python 写一个调用：
```
import subprocess as sp

def cut_video(filename, outfile, start, length=90):
    cmd = "ffmpeg -i %s -ss %d -t %d -c copy %s" % (filename, start, length, outfile)
    p = sp.Popen(cmd, shell=True)
    p.wait()
    return
```

### 从第3分35秒片截取15秒的视频
```
ffmpeg -i test.avi -ss 3:35 -t 15 out.mp4
```

## 图片转成视频
```
ffmpeg -r 60 -f image2 -s 1920x1080 -start_number 1 -i pic%04d.png -vframes 1000 -vcodec libx264 -crf 25 -pix_fmt yuv420p test.mp4
ffmpeg -i pic%04d.png -vcodec libx264 -preset veryslow -crf 0 output.avi # lossless compression
```
## 删除视频中的音频(提取视频或者叫做删除音频)
```
ffmpeg -i Life.of.Pi.has.subtitles.mkv -vcodec copy –an  videoNoAudioSubtitle.mp4
ffmpeg -i output.mp4 -c:v copy -an input-no-audio.mp4
ffmpeg -i example.mkv -c copy -an example-nosound.mkv
ffmpeg  -i in.mp4 -map 0:0  -vcodec copy -acodec copy out.mp4   通过ffprobe命令，可以查看所有的通道，例子中的0:0就是视频通道
```
## 为无声的视频添加音频
```
ffmpeg -i ../out/4in1.mp4  -i ./3.aac  -vcodec copy -acodec copy output.mp4
```
## 视频调整为两倍速
```
ffmpeg -i input.mkv -filter:v “setpts=0.5*PTS” output.mkv
```

## 设置帧率
```
用 -r 参数设置帧率
ffmpeg –i input –r fps output
用fps filter设置帧率
ffmpeg -i clip.mpg -vf fps=fps=25 clip.webm
```
### 设置帧率为29.97fps
```
ffmpeg -i input.avi -r 29.97 output.mpg
==
ffmpeg -i input.avi -r 30000/1001 output.mpg
==
ffmpeg -i input.avi -r netsc output.mpg
```

## 设置码率 –b 参数
```
ffmpeg -i film.avi -b 1.5M film.mp4
```
### 音频：-b:a 视频： - b:v

设置视频码率为1500kbps
```
ffmpeg -i input.avi -b:v 1500k output.mp4
```

## 控制输出文件大小-fs (file size首字母缩写)
其实就是剪切了前19M、1024K的视频内容
```
ffmpeg -i input.avi -fs 1024K output.mp4
ffmpeg -i ./sea.mp4 -fs 19M output.mp4
```

## 改变分辨率（高分辨率向低分辨率的转化）

### 将输入视频的分辨率改成640x480
```
ffmpeg -hide_banner -i input.avi -vf scale=640:480 output_half_width.avi
```
### 在未知视频的分辨率时，保证调整的分辨率与源视频有相同的横纵比。宽度固定400，高度成比例：
```
ffmpeg -hide_banner -i input.avi -vf scale=400:400/a
ffmpeg -hide_banner -i input.avi -vf scale=400:-1
```
### 将输入视频的分辨率减半
```
ffmpeg -hide_banner -i input.avi -vf scale = iw/2:ih/2 output_half_width.avi
```
### 设置视频的宽高比
```
ffmpeg -i video_320x180.mp4 -vf scale=320:240,setdar=4:3 video_320x240.mp4 -hide_banner
```
### 视频倒放，无音频
```
ffmpeg -i in.mp4 -filter_complex [0:v]reverse[v] -map [v] -preset superfast out.mp4
```
### 视频倒放，音频不变
```
ffmpeg -i in.mp4 -vf reverse out.mp4
```
### 音频倒放，视频不变
```
ffmpeg -i in.mp4 -map 0 -c:v copy -af "areverse" out.mp4
```
### 音视频同时倒放
```
ffmpeg -i in.mp4 -vf reverse -af areverse -preset superfast out.mp4
```
## 提取音频
```
ffmpeg -i 3.mp4 -vn -y -acodec copy 3.aac
ffmpeg -i 3.mp4 -vn -y -acodec copy 3.m4a
```
## 裁剪视频crop filter

从输入文件中选取你想要的矩形区域到输出文件中,常见用来去视频黑边。(x,y以左上角为零点）

语法：`crop:ow[:oh[:x[:y:[:keep_aspect]]]]`
```
比如有一个竖向的视频 1080 x 1920，如果指向保留中间 1080×1080 部分，可以使用下面的命令：
ffmpeg -i input.mp4 -strict -2 -vf crop=1080:1080:0:420 out.mp4

具体含义是 crop=width:height:x:y，其中 width 和 height 表示裁剪后的尺寸，x:y 表示裁剪区域的左上角坐标
只需要保留中间部分，所以x=0,y=(1920-1080)/2=420

视频缩放和裁剪是可以同时进行的，如下命令则为将视频缩小至 853×480，然后裁剪保留横向中间部分：
ffmpeg -i input.mp4 -strict -2 -vf scale=853:480,crop=480:480:186:0 out.mp4
```


### 比较裁剪后的视频和源视频比较
```
ffplay -i jidu.mp4 -vf split[a][b];[a]drawbox=x=(iw-300)/2:(ih-300)/2:w=300:h=300:c=yellow[A];[A]pad=2iw[C];[b]crop=300:300:(iw-300)/2:(ih-300)/2[B];[C][B]overlay=w2.4:40
```
### 自动检测裁剪区域

cropdetect filter 自动检测黑边区域，然后把检测出来的参数填入crop filter
```
ffplay jidu.mp4 -vf cropdetect
```
## 填充视频(pad)

在视频帧上增加一快额外额区域，经常用在播放的时候显示不同的横纵比

语法：`pad=width[:height:[:x[:y:[:color]]]]`

#### 创建一个30个像素的粉色宽度来包围一个SVGA尺寸的图片：
```
ffmpeg -i photo.jpg -vf pad=860:660:30:30:pink framed_photo.jpg
```
#### 同理可以制作testsrc视频用30个像素粉色包围视频
```
ffplay -f lavfi -i testsrc -vf pad=iw+60:ih+60:30:30:pink
```
#### 添加黑色上下边界
```
ffmpeg -i <input> -vf "pad=1920:1080:(ow-iw)/2:(oh-ih)/2" <output>
```
## 翻转

### 水平翻转
语法 `-vf hflip`
```
ffplay -f lavfi -i testsrc -vf hflip
```
### 垂直翻转
语法 `-vf vflip`
```
ffplay -f lavfi -i testsrc -vf vflip
```
### 旋转
语法 `transpose={0,1,2,3}`
```
0:逆时针旋转90°然后垂直翻转

1:顺时针旋转90°

ffplay -f lavfi -i testsrc -vf transpose=1

2:逆时针旋转90°

3:顺时针旋转90°然后水平翻转
```

## 模糊

语法：`boxblur=luma_r:luma_p[:chroma_r:chram_p[:alpha_r:alpha_p]]`
```
ffplay -f lavfi -i testsrc -vf boxblur=1:10:4:10
```
注意：luma_r和alpha_r半径取值范围是0~min(w,h)/2, chroma_r半径的取值范围是0~min(cw/ch)/2

## 锐化
语法：`-vf unsharp=l_msize_x:l_msize_y:l_amount:c_msize_x:c_msize_y:c_amount`
所有的参数是可选的，默认值是5:5:1.0:5:5:0.0
```
l_msize_x:水平亮度矩阵，取值范围3-13，默认值为5

l_msize_y:垂直亮度矩阵，取值范围3-13，默认值为5

l_amount:亮度强度，取值范围-2.0-5.0，负数为模糊效果，默认值1.0

c_msize_x:水平色彩矩阵，取值范围3-13，默认值5

c_msize_y:垂直色彩矩阵，取值范围3-13，默认值5

c_amount:色彩强度，取值范围-2.0-5.0，负数为模糊效果，默认值0.0
```
举例
```
– 使用默认值，亮度矩阵为5x5和亮度值为1.0

ffmpeg -i input -vf unsharp output.mp4

– 高斯模糊效果(比较强的模糊)：

ffplay -f lavfi -i testsrc -vf unsharp=13:13:-2
```


## 覆盖（画中画）

### 覆盖

语法：`overlay[=x[:y]`

所有的参数都是可选，默认值都是0

举例
```
– Logo在左上角

ffmpeg -i pair.mp4 -i logo.png -filter_complex overlay pair1.mp4

– 右上角：

ffmpeg -i pair.mp4 -i logo.png -filter_complex overlay=W-w pair2.mp4

– 左下角：

ffmpeg -i pair.mp4 -i logo.png -filter_complex overlay=0:H-h pair2.mp4

– 右下角：

ffmpeg -i pair.mp4 -i logo.png -filter_complex overlay=W-w:H-h pair2.mp4
```

## 删除logo

语法：`-vf delogo=x:y:w:h[:t[:show]]`
```
x:y 离左上角的坐标

w:h logo的宽和高

t: 矩形边缘的厚度默认值4

show：若设置为1有一个绿色的矩形，默认值0.
```
```
ffplay -i jidu.mp4 -vf delogo=50:51:60:600
```

## 添加文本

语法：
```
drawtext=fontfile=font_f:text=text1[:p3=v3[:p4=v4[…]]]
```
常用的参数值
```
x：离左上角的横坐标

y: 离左上角的纵坐标

fontcolor：字体颜色

fontsize：字体大小

text:文本内容

textfile:文本文件

t：时间戳，单位秒

n:帧数开始位置为0

draw/enable:控制文件显示，若值为0不显示，1显示，可以使用函数
```
简单用法
```
在左上角添加Welcome文字

ffplay -f lavfi -i color=c=white -vf drawtext=fontfile=arial.ttf:text=Welcom

在中央添加Good day

ffplay -f lavfi -i color=c=white -vf drawtext=“fontfile=arial.ttf:text=‘Goodday’:x=(w-tw)/2:y=(h-th)/2”

设置字体颜色和大小

ffplay -f lavfi -i color=c=white -vf drawtext=“fontfile=arial.ttf:text=‘Happy Holidays’:x=(w-tw)/2:y=(h-th)/2:fontcolor=green:fontsize=30”
```
动态文本
```
用 t (时间秒)变量实现动态文本

顶部水平滚动

ffplay -i jidu.mp4 -vf drawtext=“fontfile=arial.ttf:text=‘Dynamic RTL text’:x=w-t*50:fontcolor=darkorange:fontsize=30”

底部水平滚动

ffplay -i jidu.mp4 -vf drawtext=“fontfile=arial.ttf:textfile=textfile.txt:x=w-t*50:y=h-th:fontcolor=darkorange:fontsize=30”

垂直从下往上滚动

ffplay jidu.mp4 -vf drawtext="textfile=textfile:fontfile=arial.ttf:x=(w-tw)/2:y=h-t*100:fontcolor=white:fontsize=30“

想实现右上角显示当前时间？

在右上角显示当前时间 localtime

ffplay jidu.mp4 -vf drawtext="fontfile=arial.ttf:x=w-tw:fontcolor=white:fontsize=30:text=’%{localtime:%H\:%M\:%S}’“

每隔3秒显示一次当前时间

ffplay jidu.mp4 -vf drawtext=“fontfile=arial.ttf:x=w-tw:fontcolor=white:fontsize=30:text=’%{localtime:%H\:%M\:%S}’:enable=lt(mod(t,3),1)”
```


## 色彩平衡
```
ffplay -i jidu.mp4 -vf curves=vintage
```
## 色彩变幻
```
ffplay -i jidu.mp4 -vf hue="H=2PIt: s=sin(2PIt)+1“
```
## 彩色转换黑白
```
ffplay -i jidu.mp4 -vf lutyuv=“u=128:v=128”
```

## 设置音频视频播放速度
```
3倍视频播放视频

ffplay -i jidu.mp4 -vf setpts=PTS/3

3/4速度播放视频

ffplay -i jidu.mp4 -vf setpts=PTS/(3/4)

2倍速度播放音频

ffplay -i speech.mp3 -af atempo=2

50%原始速度

ffplay p629100.mp3 -af atempo=0.5
```

## 截图
```
每隔一秒截一张图

ffmpeg -i input.flv -f image2 -vf fps=fps=1 out%d.png

每隔20秒截一张图

ffmpeg -i input.flv -f image2 -vf fps=fps=1/20 out%d.png

多张截图合并到一个文件里（2x3） ?每隔一千帧(秒数=1000/fps25)即40s截一张图

ffmpeg? -i jidu.mp4 -frames 3 -vf “select=not(mod(n,1000)),scale=320:240,tile=2x3” out.png
```

## 马赛克视频
```
用多个输入文件创建一个马赛克视频：

ffmpeg -i jidu.mp4 -i jidu.flv -i “Day By Day SBS.mp4” -i “Dangerous.mp4” -filter_complex “nullsrc=size=640x480 [base]; [0:v] setpts=PTS-STARTPTS, scale=320x240 [upperleft]; [1:v] setpts=PTS-STARTPTS, scale=320x240 [upperright]; [2:v] setpts=PTS-STARTPTS, scale=320x240 [lowerleft]; [3:v] setpts=PTS-STARTPTS, scale=320x240 [lowerright]; [base][upperleft] overlay=shortest=1 [tmp1]; [tmp1][upperright] overlay=shortest=1:x=320 [tmp2]; [tmp2][lowerleft] overlay=shortest=1:y=240 [tmp3]; [tmp3][lowerright] overlay=shortest=1:x=320:y=240” -c:v libx264 output.mkv
```


## 图像拼接

两张图像im0.png (30像素高）和im1.jpg (20像素高）上下拼接：
```
ffmpeg -i im0.png -i im1.jpg -filter_complex “[0:v] pad=iw:50 [top]; [1:v] copy [down]; [top][down] overlay=0:30” im3.png
```
## 视频拼接

需要将需要拼接的视频文件按以下格式保存在一个列表 list.txt 中：
```
file ‘/path/to/file1’

file ‘/path/to/file2’

file ‘/path/to/file3’

相应的命令为：

ffmpeg -f concat -i list.txt -c copy output.mp4

```

## 视频同步播放

将下面这行保存为ffplay2.bat，运行时输入：ffplay2 video1.mp4 video2.mp4，即可实现左右同步播放。
```
ffplay -f lavfi “movie=%1,scale=iw/2:ih[v0];movie=%2,scale=iw/2:ih[v1];[v0][v1] hstack”
```
还可以输入更多的参数，比如缩小系数、堆叠方式。例如：ffplay2 video1.mp4 video2.mp4 2 vstack 可以将两个视频缩小2倍、竖起方向堆叠同步播放。
```
ffplay -f lavfi “movie=%1,scale=iw/%3:ih/%3[v0];movie=%2,scale=iw/%3:ih/%3[v1];[v0][v1] %4”
```

## Logo动态移动

2秒后logo从左到右移动：
```
ffplay -i jidu.mp4 -vf movie=logo.png[logo];[in][logo]overlay=x=‘if(gte(t,2),((t-2)*80)-w,NAN)’:y=0
```
2秒后logo从左到右移动后停止在左上角
```
ffplay -i jidu.mp4 -vf movie=logo.png[logo];[in][logo]overlay=x=‘if(gte(((t-2)*80)-w,W),0,((t-2)*80)-w)’:y=0
```
每隔10秒交替出现logo。
```
ffmpeg -y -t 60 -i jidu.mp4 -i logo.png -i logo2.png -filter_complex “overlay=x=if(lt(mod(t,20),10),10,NAN ):y=10,overlay=x=if(gt(mod(t,20),10),W-w-10,NAN ) :y=10” overlay.mp4
```

##屏幕录像

linux
```
ffmpeg -f x11grab -s xga -r 10 -i :0.0+0+0 wheer.avi

ffmpeg -f x11grab -s 320x240 -r 10 -i :0.0+100+200 wheer.avi
```
```
:0:0 表示屏幕（个人理解，因为系统变量$DISPLAY值就是:0.0） 而100,表示距左端100象素，200表示距上端200

-r 10 设置频率

ffmpeg -f x11grab -s xga -qscale 5 -r 10 -i :0.0+0+0 wheer.avi

-qscale 8 设定画面质量，值越小越好
```

## 压缩mp3文件

如果你觉得mp3 文件 有点大，想变小一点那么可以通过-ab 选项改变音频的比特率 （bitrate）
```
ffmpeg -i input.mp3 -ab 128 output.mp3 //这里将比特率设为128
```
你可以用file 命令查看一下源文件 的信息


## 录音

（要有可用的麦克风，并且如果用alsa 的话，好像得安alsa-oss，重启）
```
ffmpeg -f oss -i /dev/dsp out.avi (should hava oss or alsa-oss)

ffmpeg -f alsa -ac 2 -i hw:0, 0 out.avi (should )

ffmpeg -f alsa -ac 2 -i pulse (should hava PulseAudio)
```
在alsa 体系中声卡（也可能是麦克风）叫hw:0,0 而在oss 体系中叫/dev/dsp (用词可能不太专业) 。Linux在安装了声卡后，会有一些设备文件生成，采集数字样本的/dev/dsp文件，针对混音器的/dev/mixer文件，用于音序器的/dev/sequencer，/dev/audio文件一个基于兼容性考虑的声音设备文件。只要向/dev/audio中输入wav文件就能发出声音。而对/dev/dsp文件读取就能得到WAV文件格式的声音文件。



## 过滤器链（Filterchain）
Filterchain = 逗号分隔的一组filter

语法：
```
“filter1,filter2,filter3,…filterN-2,filterN-1,filterN”
```
顺时针旋转90度并水平翻转
```
ffplay -f lavfi -i testsrc -vf transpose=1,hflip
```
水平翻转视频和源视频进行比较

第一步： 源视频宽度扩大两倍。
```
ffmpeg -i jidu.mp4 -t 10 -vf pad=2*iw output.mp4
```
第二步：源视频水平翻转
```
ffmpeg -i jidu.mp4 -t 10 -vf hflip output2.mp4
```
第三步：水平翻转视频覆盖output.mp4
```
ffmpeg -i output.mp4 -i output2.mp4 -filter_complex overlay=w compare.mp4
```

## 过滤器图（Filtergraph）
Filtergraph = 分号分隔的一组filterchain

语法: 
```
“filterchain1;filterchain2;…filterchainN-1;filterchainN”
```

Filtergraph的分类
```
1、简单(simple) 一对一
2、复杂(complex）多对一， 多对多. 复杂过滤器图比简单过滤器图少2个步骤，效率比简单高，ffmpeg建议尽量使用复杂过滤器图。
```
实现水平翻转视频和源视频进行比较:

用ffplay直接观看结果：
```
ffplay -f lavfi -i testsrc -vf split[a][b];[a]pad=2*iw[1];[b]hflip[2];[1][2]overlay=w
```
```
F1: split过滤器创建两个输入文件的拷贝并标记为[a],[b]
F2: [a]作为pad过滤器的输入，pad过滤器产生2倍宽度并输出到[1].
F3: [b]作为hflip过滤器的输入，vflip过滤器水平翻转视频并输出到[2].
F4: 用overlay过滤器把 [2]覆盖到[1]的旁边.1];[b]hflip[2];[1][2]overlay=w
```

## 选择媒体流
一些多媒体容器比如AVI，mkv，mp4等，可以包含不同种类的多个流，如何从容器中抽取各种流呢？

语法：`-map file_number:stream_type[:stream_number]`

特别流符号：
```
1、-map 0 选择第一个文件的所有流
2、-map i:v 从文件序号i(index)中获取所有视频流， -map i:a 获取所有音频流，-map i:s 获取所有字幕流等等。
3、特殊参数-an,-vn,-sn分别排除所有的音频，视频，字幕流。
```
eg.
```
file1 streams   specifier
1st video       0:v:0
2nd video       0:v:1
1st audio       0:a:0
2nd audio       0:a:1
1st subtitle    0:s:0
2nd subtitle    0:s:1
3rd subtitle    0:s:2

file2 streams   specifier
1st video       1:v:0
1st audio       1:a:0
1st subtitle    1:s:0

a) all stream from both files
-map 0 -map 1

b) file1: 3rd subtitle, file2: 1st video, 1st audio
-map 0:s:2 -map 1:v:0 -map 1:a:0

c) file1: 2nd video, file2: 1st subtitle, no audio
-map 0:v:1 -map 1:s:0 -an

d) all streams except 1st video and 2nd audio in file1
-map 0 -map 1 -map -0:v:0 -map -0:a:1

e) 1st video from a.mov, audio from b.mov 1st subtitle from c.mov
ffmpeg -i a.mov -i b.mov -i c.mov -map 0:v:0 -map 1:a:0 -map 2:s:0 clip.mov
```
ref

<http%3A//ffmpeg.org/documentation.html>


## profile preset tune 配置 模板 调优
具体每个编码器怎么用没啥研究，大概列一些，一般libx264,libx265的有

profile     baseline、main、high、high10、high422、high444

preset 模板   ultrafast、superfast、veryfast、faster、fast、medium、slow、slower、veryslow、placebo

tune 调优类型的模板     film、animation、grain、stillimage、psnr、ssim、fastdecode、zerolatency

多尝试看看
```
ffmpeg -i ~/Movies/Test/ToS-4k-1920.mov -pix_fmt yuv420p -vcodec libx264 -nal-hrd cbr -tune zerolatency -preset superfast -maxrate 900k -minrate 890k -bufsize 300k -x264opts "open-gop=1" output.ts
ffmpeg -i input.mkv -x264opts "bframes=2:b-adapt=0" -r:v 30 -g 60 -sc_threshold 0 -vf "scale=1280:720" output.mkv
```


# ffprobe获取视频分辨率、编码等信息
## 显示分辨率
```
ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x 1.mp4
```
## 分行显示分辨率
```
ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -print_format flat -select_streams v:0 -show_entries stream=width,height  -of default=noprint_wrappers=1:nokey=1 1.mp4
```

## 显示视频编码
```
ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=codec_name -of csv=p=0:s=x  1.mp4
```
## 显示音频编码
```
ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -select_streams a:0 -show_entries stream=codec_name -of csv=p=0:s=x  1.mp4
```
## 显示文件大小
```
ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 1.mp4

ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 input.mp4
```
## 显示时长
```
ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -print_format ini -select_streams v:0 -show_entries stream=duration -of csv=p=0:s=x   1.mp4

ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 1.mp4

ffprobe -show_entries format=duration -v quiet -of csv="p=0"  1.mp4
```

## 视频码率
```
ffprobe -v error -hide_banner -of default=noprint_wrappers=0  -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0:s=x  1.mp4

ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -print_format flat  -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0:s=x  1.mp4
```
什么是码率？很简单： 
```
bitrate = file size / duration 
```
比如一个文件20.8M，时长1分钟，那么，码率就是： 
```
biterate = 20.8M bit/60s = 20.8*1024*1024*8 bit/60s= 2831Kbps 
```
## 像素格式
```
ffprobe -v error -hide_banner -of default=noprint_wrappers=0 -select_streams v:0 -show_entries stream=pix_fmt  -of csv=p=0:s=x  1.mp4
```
## 视频总帧数
```
ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=nokey=1:noprint_wrappers=1 1.mp4
```
## 视频帧率
```
ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate input.mp4

ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate 1.mp4

ffprobe -v 0 -of csv="p=0" -select_streams V:0 -show_entries stream=r_frame_rate 1.mp4
```
## 视觉停留

人类的眼睛所看画面的帧率高于16的时候，就会认为是连贯的，此现象称之为视觉停留


#bash循环调用ffmpeg例子
```
for i in *.mp4; do ffmpeg -i "$i" -c:v libx265 -c:a copy -x265-params crf=25 $(dirname "$i")/new-$(basename "$i"); done
```





# 图片压缩
看起来效果差不多的设置
```
Caesium Image Compressor 92%
heic 58~60% ffmpeg 一般还不支持，heic可以用heic_tools的heif-convert.exe转换
avif crf 4~5
```

# 图像转换

## jpg转avif
可以用chrome浏览器查看
```
ffmpeg -i 0001.jpg -c:v libaom-av1 -still-picture 1 0001.avif
ffmpeg -i 0001.jpg -frames:v 1 -c:v libaom-av1 -still-picture 1 0001.avif
ffmpeg -i 0001.jpg -frames:v 1 -c:v libaom-av1 -crf 30 -still-picture 1 0001.avif       默认crf是32, 控制在38以下, 0是无损
ffmpeg -i 0001.jpg -frames:v 1 -c:v libaom-av1 -aom-params lossless=1:threads=4 -still-picture 1 0001.avif
ffmpeg -i 0001.jpg -frames:v 1 -c:v libaom-av1 -crf 0 -still-picture 1 0001.avif        这个也是无损转换
```
无损编码设置很像 `-libx265` 时候的 `-x265-params lossless=1`
<https://trac.ffmpeg.org/wiki/Encode/AV1>

## 转出heic文件（ffmpeg不能）
```
sudo apt-get install libheif1 libheif-examples libheif-dev
heif-enc -q 50 example.png
```
## heic文件转jpg等
```
for file in *.heic; do heif-convert $file ${file/%.heic/.jpg}; done
```
## webp转jpg
```
ffmpeg -i in.webp out.jpg
for %i in (*.webp) do ffmpeg -i "%i" "%~ni.jpg"
```
## webp转换成png
```
ffmpeg -i in.webp out.png
```
## jpg转换成png
```
ffmpeg -i in.jpg out.png
```
## jpg转换成webp
```
ffmpeg -i in.jpg out.webp
```
## png转换成webp
```
ffmpeg -i in.png out.webp
```
## png转换成jpg
```
ffmpeg -i in.png out.jpg
```
## gif专项(ffmpeg+gifski+gifsicle)
```
ffmpeg -y -i file.mp4 -pix_fmt rgb24 -r 10 -s 320x480 file.gif
magick  out.gif -fuzz 30% -layers Optimize result.gif

gifsicle -O3 --lossy=35 -o lossy-compressed.gif input.gif

ffmpeg -y -i file.mp4 -vf palettegen palette.png
ffmpeg -y -i file.mp4 -i palette.png -filter_complex paletteuse -r 10 -s 320x480 file.gif
ffmpeg -y -i file.mp4 -filter_complex "paletteuse,scale=iw*.2:ih*.2" palettegen palette.png
ffmpeg -y -i input.mp4 -filter_complex "fps=5,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=32[p];[s1][p]paletteuse=dither=bayer" output.gif
ffmpeg -i input.mp4 -filter_complex "[0:v]fps=10,scale=-1:90:flags=lanczos,split [a][b];[a] palettegen [p];[b][p] paletteuse" -y output.gif


```
#!/bin/sh

palette="/tmp/palette.png"

filters="fps=15,scale=320:-1:flags=lanczos"

ffmpeg -v warning -i $1 -vf "$filters,palettegen=stats_mode=diff" -y $palette

ffmpeg -i $1 -i $palette -lavfi "$filters,paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y $2
```

ffmpeg -i foo.gif -c:v libx264 -crf 22 foo.mp4
ffmpeg -i input.gif -pix_fmt yuv420p output.mp4
ffmpeg -i input.gif -ss 00:00:00 -to 00:00:03 -c copy output.gif
ffmpeg -i input.gif -vf "scale=iw/2:ih/2" output.gif
ffmpeg -i my-animation.gif -c vp9 -b:v 0 -crf 41 my-animation.webm



ffmpeg -i input.mp4 -c:v libx264 -tune zerolatency -preset ultrafast -crf 40 -c:a aac -b:a 32k output.mp4
for %F in (*.mp4) do (If not Exist "%~nF" MkDir "%~nF" ffmpeg -i %F -r 1 -qscale:v 2 %~nF\%~nF-%3d.jpg)


ffmpeg -i input.gif -c:v libx265 -preset veryslow -qp 0 output.mkv
ffmpeg -i image-%06.png -o output.mkv will create a video from a list of images image-000000.png, image-000001.png etc.

sudo apt install gifsicle
curl -O https://deved-images.nyc3.cdn.digitaloceanspaces.com/gif-cli/app-platform.webm
ffprobe app-platform.webm
ffmpeg -ss 00:00:09 -to 00:00:12 -i app-platform.webm -c copy clip.webm
ls -lh clip.webm
ffmpeg -filter_complex "[0:v] fps=12,scale=w=540:h=-1,split [a][b];[a] palettegen [p];[b][p] paletteuse" -i clip.webm ffmpeg-sample.gif
ls -lh ffmpeg-sample.gif
gifski --fps 12 --width 540 -o gifski-sample.gif clip.webm
ls -lh gifski-sample.gif
gifski --fps 25 --width 1080 -o gifski-high.gif clip.webm
ls -lh gifski-high.gif
gifsicle -O3 --lossy=80 --colors 256 gifski-sample.gif -o optimized.gif
ls -lh optimized.gif
gifsicle --explode optimized.gif
ls -lh optimized*
gifsicle --rotate-90 optimized.gif -o rotated.gif
```







