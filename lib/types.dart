import 'package:flutter/widgets.dart';

/// This mixin is used by [AVMediaView] to avoid [setState] issues.
///
/// It is recommended to add this mixin with [State] in your [StatefulWidget]
/// while using [AVMediaPlayer] or [AVMediaView].
mixin SetStateSafely<T extends StatefulWidget> on State<T> {
  @override
  void setState(VoidCallback fn) {
    try {
      super.setState(fn);
    } catch (e) {
      //some opreation may trigger the builder while building is in process.
      //in this situation, we just queue a new frame to update the state.
      if (e is FlutterError &&
          e.message.substring(0, 38) ==
              'setState() or markNeedsBuild() called ') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          //check if the widget is still mounted before updating.
          if (mounted) {
            setState(fn);
          }
        });
      } else {
        rethrow;
      }
    }
  }
}

/// This type is used by [AVMediaPlayer], for showing current buffer status.
class BufferRange {
  static const empty = BufferRange(0, 0);

  final int begin;
  final int end;
  const BufferRange(this.begin, this.end);
}

/// This type is used by [AVMediaPlayer], for showing current media info.
class MediaInfo {
  final int width;
  final int height;
  final int duration;
  final String source;
  const MediaInfo(this.width, this.height, this.duration, this.source);
}

/// This type is used by [AVMediaPlayer], for showing current playback state.
enum PlaybackState { playing, paused, closed }

/// This type is used by [AVMediaView], for sizing the video.
enum SizingMode { free, keepAspectRatio, originalSize }
