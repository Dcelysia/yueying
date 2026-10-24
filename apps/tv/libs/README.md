# bv-libs
存放为 [bv](https://github.com/aaa1115910/bv) 编译/修改过的依赖


## av1Decoder
Media 3 AV1 解码器

打包自 [Media3 1.0.0-beta03](https://github.com/androidx/media/tree/c2cbb6370a265efc93661b659e70b2679506e995/libraries/decoder_av1)


## ffmpegDecoder
Media 3 FFmpeg 音频解码器 (flac mp3 aac ac3 eac3)

打包自 [Media3 1.5.0](https://github.com/androidx/media/tree/1.5.0)


## libVLC
去掉了 UserAgent 末尾强制加上的 `LibVLC/xxx`，并修改了加载 native lib 的路径

打包自 [VLC-Android](https://code.videolan.org/videolan/vlc-android/-/tree/a0f588afd3626fa1e97de81603c2589a9c62b004)

依赖版本 `3.6.0-ep05`，`LibVLC` 版本 `3.0.18`


## media3Container

打包自 [Media3 f9fb71b](https://github.com/androidx/media/tree/f9fb71bdd5ec1c385c2db77f0cb88d2e753fb7a0)