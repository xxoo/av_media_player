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
