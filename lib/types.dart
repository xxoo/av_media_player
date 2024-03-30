class BufferRange {
  static const empty = BufferRange(0, 0);

  final int begin;
  final int end;
  const BufferRange(this.begin, this.end);
}

class MediaInfo {
  final int width;
  final int height;
  final int duration;
  final String source;
  const MediaInfo(this.width, this.height, this.duration, this.source);
}

enum PlaybackState { playing, paused, closed }
