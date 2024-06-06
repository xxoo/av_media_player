## About AvMediaPlayer

A lightweight media player for flutter that builds on system components. Video rendering in Texture widget.
For api documentation please check [here](https://pub.dev/documentation/av_media_player/latest/index/index-library.html).

| Platform | Version | Backend                                                                                 |
| -------- | ------- | --------------------------------------------------------------------------------------- |
| iOS      | 12+     | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)            |
| macOS    | 11+     | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)            |
| Android  | 8+      | [MediaPlayer](https://developer.android.com/reference/kotlin/android/media/MediaPlayer) |
| Windows  | 10+     | [MediaPlayer](https://learn.microsoft.com/uwp/api/windows.media.playback.mediaplayer)   |

## Supported media formats

The full list depends on the platform's native components. But the following formats are generally supported:

| Type              | Formats              |
| ----------------- | -------------------- |
| Video Codec       | H.264, H.265(HEVC)\* |
| Audio Codec       | AAC, MP3             |
| Container Format  | MP4, TS              |
| Transfer Protocol | HTTP, HLS            |

---

\* Windows user may need to install a free decoder for H.265(HEVC) from [Microsoft Store](https://apps.microsoft.com/detail/9n4wgh0z6vhq).
