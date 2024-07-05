## About AvMediaPlayer

A lightweight media player for flutter that builds on system or app level components. Video rendering in Texture widget.
For api documentation please check [here](https://pub.dev/documentation/av_media_player/latest/index/index-library.html).

| **Platform** | **Version** | **Backend**                                                                           |
| ------------ | ----------- | ------------------------------------------------------------------------------------- |
| iOS          | 12+         | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)          |
| macOS        | 11+         | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)          |
| Android      | 5+          | [ExoPlayer](https://developer.android.com/media/media3/exoplayer)                     |
| Windows      | 10+         | [MediaPlayer](https://learn.microsoft.com/uwp/api/windows.media.playback.mediaplayer) |
| Linux        | N/A         | [libmpv](https://github.com/mpv-player/mpv/tree/master/libmpv)[^libmpv]               |

## Supported media formats

The full list depends on the platform's native components. But the following formats are generally supported:

| **Type**          | **Formats**               |
| ----------------- | ------------------------- |
| Video Codec       | H.264, H.265(HEVC)[^h265] |
| Audio Codec       | AAC, MP3                  |
| Container Format  | MP4, TS                   |
| Transfer Protocol | HTTP, HLS, LL-HLS         |

[^libmpv]: Linux backend requires `libmpv`(aka `mpv-libs`) to work. For developer who needs to integrate this plugin on linux, please install `libmpv-dev`(aka `mpv-libs-devel`) instead. If none of these packages are available in your package manager, you may need to build `libmpv` from source. For more information, please refer to [mpv-build](https://github.com/mpv-player/mpv-build).
[^h265]: Windows user may need to install a free decoder for H.265(HEVC) from [Microsoft Store](https://apps.microsoft.com/detail/9n4wgh0z6vhq).
