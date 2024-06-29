## About AvMediaPlayer

A lightweight media player for flutter that builds on system components. Video rendering in Texture widget.
For api documentation please check [here](https://pub.dev/documentation/av_media_player/latest/index/index-library.html).

| Platform | Version | Backend                                                                                 |
| -------- | ------- | --------------------------------------------------------------------------------------- |
| iOS      | 12+     | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)            |
| macOS    | 11+     | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)            |
| Android  | 8+      | [MediaPlayer](https://developer.android.com/reference/kotlin/android/media/MediaPlayer) |
| Windows  | 10+     | [MediaPlayer](https://learn.microsoft.com/uwp/api/windows.media.playback.mediaplayer)   |
| Linux    | N/A     | [libmpv](https://github.com/mpv-player/mpv/tree/master/libmpv)[^1]                      |

## Supported media formats

The full list depends on the platform's native components. But the following formats are generally supported:

| Type              | Formats                |
| ----------------- | ---------------------- |
| Video Codec       | H.264, H.265(HEVC)[^2] |
| Audio Codec       | AAC, MP3               |
| Container Format  | MP4, TS                |
| Transfer Protocol | HTTP, HLS              |

[^1] Linux backend requires `libmpv`(aka `mpv-libs`) to run. For developer who needs to build the plugin from source, please install `libmpv-dev`(aka `mpv-libs-devel`). If none of these packages are available in your package manager, you may need to build `libmpv` from source. For more information, please check [mpv repo](https://github.com/mpv-player/mpv?tab=readme-ov-file#compilation).

[^2] Windows user may need to install a free decoder for H.265(HEVC) from [Microsoft Store](https://apps.microsoft.com/detail/9n4wgh0z6vhq).
