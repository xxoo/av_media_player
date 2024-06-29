import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// This type is used by [AvMediaPlayer], for showing current playback state.
enum PlaybackState { playing, paused, closed }

/// This type is used by [AvMediaPlayer], for showing current buffer status.
class BufferRange {
  static const empty = BufferRange(0, 0);

  final int begin;
  final int end;
  const BufferRange(this.begin, this.end);
}

/// This type is used by [AvMediaPlayer], for showing current media info.
/// If duration is 0, it means the media is a realtime stream
class MediaInfo {
  final int duration;
  final String source;
  const MediaInfo(this.duration, this.source);
}

/// The class to create and control [AvMediaPlayer] instance.
///
/// Do NOT modify properties directly, use the corresponding methods instead.
class AvMediaPlayer {
  static const _methodChannel = MethodChannel('av_media_player');
  static var _detectorStarted = false;

  /// Whether the player is disposed.
  var disposed = false;

  /// The id of the player. It's null before the player is initialized.
  /// After the player is initialized it will be unique and never change again.
  final id = ValueNotifier<int?>(null);

  /// The information of the current media.
  /// It's null before the media is opened.
  final mediaInfo = ValueNotifier<MediaInfo?>(null);

  /// The size of the current video.
  /// This value is Size.zero by default, and may change during playback.
  final videoSize = ValueNotifier<Size>(Size.zero);

  /// The position of the current media in milliseconds.
  /// It's 0 before the media is opened.
  final position = ValueNotifier(0);

  /// The error message of the player.
  /// It's null before an error occurs.
  final error = ValueNotifier<String?>(null);

  /// The loading state of the player.
  /// It's false before opening a media.
  final loading = ValueNotifier(false);

  /// The playback state of the player.
  /// It's [PlaybackState.closed] berore a media is opened.
  final playbackState = ValueNotifier(PlaybackState.closed);

  /// The volume of the player.
  /// It's between 0 and 1, and defaults to 1.
  final volume = ValueNotifier(1.0);

  /// The speed of the player.
  /// It's between 0.5 and 2, and defaults to 1.
  final speed = ValueNotifier(1.0);

  /// Whether the player should loop the media.
  /// It's false by default.
  final looping = ValueNotifier(false);

  /// Whether the player should play the media automatically.
  /// It's false by default.
  final autoPlay = ValueNotifier(false);

  /// How many times the player has finished playing the current media.
  /// It will be reset to 0 when the media is closed.
  final finishedTimes = ValueNotifier(0);

  /// The current buffer status of the player.
  /// It is only reported for network media.
  final bufferRange = ValueNotifier(BufferRange.empty);

  // Event channel is much more efficient than method channel
  // We'd better use it to hanel playback events especially for position
  StreamSubscription? _eventSubscription;
  String? _source;
  int? _position;
  var _seeked = false;

  /// All the parameters are optional, and can be changed later by calling the corresponding methods.
  AvMediaPlayer({
    String? initSource,
    double? initVolume,
    double? initSpeed,
    bool? initLooping,
    bool? initAutoPlay,
    int? initPosition,
  }) {
    if (kDebugMode && !_detectorStarted) {
      _detectorStarted = true;
      final receivePort = ReceivePort();
      receivePort.listen((_) => _methodChannel.invokeMethod('dispose'));
      Isolate.spawn(
        (_) {},
        null,
        paused: true,
        onExit: receivePort.sendPort,
        debugName: 'AvMediaPlayer restart detector',
      );
    }
    _methodChannel.invokeMethod('create').then((value) {
      if (disposed) {
        _methodChannel.invokeMethod('dispose', value);
      } else {
        id.value = value as int;
        _eventSubscription = EventChannel('av_media_player/${id.value}')
            .receiveBroadcastStream()
            .listen((event) {
          final e = event as Map;
          if (e['event'] == 'mediaInfo') {
            if (_source == e['source']) {
              loading.value = false;
              playbackState.value = PlaybackState.paused;
              mediaInfo.value = MediaInfo(e['duration'], _source!);
              if (autoPlay.value) {
                play();
              }
              if (_position != null) {
                seekTo(_position!);
                _position = null;
              }
            }
          } else if (e['event'] == 'videoSize') {
            if (playbackState.value != PlaybackState.closed || loading.value) {
              final width = e['width'] as double;
              final height = e['height'] as double;
              if (width != videoSize.value.width ||
                  height != videoSize.value.height) {
                videoSize.value = width > 0 && height > 0
                    ? Size(e['width'], e['height'])
                    : Size.zero;
              }
            }
          } else if (e['event'] == 'playbackState') {
            playbackState.value = e['value'] == 'playing'
                ? PlaybackState.playing
                : e['value'] == 'paused'
                    ? PlaybackState.paused
                    : PlaybackState.closed;
          } else if (e['event'] == 'position') {
            if (mediaInfo.value != null) {
              position.value = e['value'] > mediaInfo.value!.duration
                  ? mediaInfo.value!.duration
                  : e['value'] < 0
                      ? 0
                      : e['value'];
            }
          } else if (e['event'] == 'buffer') {
            if (mediaInfo.value != null) {
              final begin = e['begin'] as int;
              final end = e['end'] as int;
              bufferRange.value = begin == 0 && end == 0
                  ? BufferRange.empty
                  : BufferRange(begin, end);
            }
          } else if (e['event'] == 'error') {
            //ignore errors when player is closed
            if (playbackState.value != PlaybackState.closed || loading.value) {
              _source = null;
              error.value = e['value'];
              mediaInfo.value = null;
              videoSize.value = Size.zero;
              position.value = 0;
              bufferRange.value = BufferRange.empty;
              finishedTimes.value = 0;
              loading.value = false;
              playbackState.value = PlaybackState.closed;
            }
          } else if (e['event'] == 'loading') {
            if (mediaInfo.value != null) {
              loading.value = e['value'];
            }
          } else if (e['event'] == 'seekEnd') {
            if (mediaInfo.value != null) {
              _seeked = false;
              loading.value = false;
            }
          } else if (e['event'] == 'finished') {
            if (mediaInfo.value != null) {
              if (!looping.value && mediaInfo.value!.duration != 0) {
                playbackState.value = PlaybackState.paused;
              }
              finishedTimes.value += 1;
              if (mediaInfo.value!.duration == 0) {
                playbackState.value = PlaybackState.closed;
              }
            }
          }
        });
        if (_source != null) {
          open(_source!);
        }
        if (volume.value != 1) {
          _methodChannel.invokeMethod('setVolume', {
            'id': value,
            'value': volume.value,
          });
        }
        if (speed.value != 1) {
          _methodChannel.invokeMethod('setSpeed', {
            'id': value,
            'value': speed.value,
          });
        }
        if (looping.value) {
          _methodChannel.invokeMethod('setLooping', {
            'id': value,
            'value': true,
          });
        }
      }
    });
    _position = initPosition;
    if (initSource != null) {
      open(initSource);
    }
    if (initVolume != null) {
      setVolume(initVolume);
    }
    if (initSpeed != null) {
      setSpeed(initSpeed);
    }
    if (initLooping != null) {
      setLooping(initLooping);
    }
    if (initAutoPlay != null) {
      setAutoPlay(initAutoPlay);
    }
  }

  /// Dispose the player
  void dispose() {
    if (!disposed) {
      disposed = true;
      _eventSubscription?.cancel();
      if (id.value != null) {
        _methodChannel.invokeMethod('dispose', id.value);
      }
      id.dispose();
      mediaInfo.dispose();
      videoSize.dispose();
      position.dispose();
      error.dispose();
      loading.dispose();
      playbackState.dispose();
      volume.dispose();
      speed.dispose();
      looping.dispose();
      autoPlay.dispose();
      finishedTimes.dispose();
    }
  }

  /// Open a media file
  ///
  /// source: The url or local path of the media file
  void open(String source) {
    if (!disposed) {
      _source = source;
      if (id.value != null) {
        error.value = null;
        mediaInfo.value = null;
        videoSize.value = Size.zero;
        position.value = 0;
        bufferRange.value = BufferRange.empty;
        finishedTimes.value = 0;
        playbackState.value = PlaybackState.closed;
        _methodChannel.invokeMethod('open', {
          'id': id.value,
          'value': source,
        });
      }
      loading.value = true;
    }
  }

  /// Close or stop opening the media file.
  void close() {
    if (!disposed) {
      _source = null;
      if (id.value != null &&
          (playbackState.value != PlaybackState.closed || loading.value)) {
        _methodChannel.invokeMethod('close', id.value);
        mediaInfo.value = null;
        videoSize.value = Size.zero;
        position.value = 0;
        bufferRange.value = BufferRange.empty;
        finishedTimes.value = 0;
        playbackState.value = PlaybackState.closed;
      }
      loading.value = false;
    }
  }

  /// Play the current media file.
  ///
  /// If the the player is opening a media file, calling this method will set autoplay to true
  bool play() {
    if (!disposed) {
      if (id.value != null && playbackState.value == PlaybackState.paused) {
        _methodChannel.invokeMethod('play', id.value);
        playbackState.value = PlaybackState.playing;
        return true;
      } else if (!autoPlay.value &&
          playbackState.value == PlaybackState.closed &&
          _source != null) {
        setAutoPlay(true);
        return true;
      }
    }
    return false;
  }

  /// Pause the current media file.
  ///
  /// If the the player is opening a media file, calling this method will set autoplay to false
  bool pause() {
    if (!disposed) {
      if (id.value != null && playbackState.value == PlaybackState.playing) {
        _methodChannel.invokeMethod('pause', id.value);
        playbackState.value = PlaybackState.paused;
        if (!_seeked) {
          loading.value = false;
        }
        return true;
      } else if (autoPlay.value &&
          playbackState.value == PlaybackState.closed &&
          _source != null) {
        setAutoPlay(false);
        return true;
      }
    }
    return false;
  }

  /// Seek to a specific position.
  ///
  /// position: The position to seek to in milliseconds.
  bool seekTo(int position) {
    if (!disposed && id.value != null) {
      if (mediaInfo.value != null) {
        if (position < 0) {
          position = 0;
        } else if (position > mediaInfo.value!.duration) {
          position = mediaInfo.value!.duration;
        }
        _methodChannel.invokeMethod('seekTo', {
          'id': id.value,
          'value': position,
        });
        loading.value = true;
        _seeked = true;
        return true;
      } else if (loading.value) {
        _position = position;
        return true;
      }
    }
    return false;
  }

  /// Set the volume of the player.
  ///
  /// volume: The volume to set between 0 and 1.
  bool setVolume(double volume) {
    if (!disposed) {
      if (volume < 0) {
        volume = 0;
      } else if (volume > 1) {
        volume = 1;
      }
      if (this.volume.value != volume) {
        _methodChannel.invokeMethod('setVolume', {
          'id': id.value,
          'value': volume,
        });
        this.volume.value = volume;
        return true;
      }
    }
    return false;
  }

  /// Set playback speed of the player.
  ///
  /// speed: The speed to set between 0.5 and 2.
  bool setSpeed(double speed) {
    if (!disposed) {
      if (speed < 0.5) {
        speed = 0.5;
      } else if (speed > 2) {
        speed = 2;
      }
      if (this.speed.value != speed) {
        if (id.value != null) {
          _methodChannel.invokeMethod('setSpeed', {
            'id': id.value,
            'value': speed,
          });
        }
        this.speed.value = speed;
        return true;
      }
    }
    return false;
  }

  /// Set whether the player should loop the media.
  bool setLooping(bool looping) {
    if (!disposed && looping != this.looping.value) {
      if (id.value != null) {
        _methodChannel.invokeMethod('setLooping', {
          'id': id.value,
          'value': looping,
        });
      }
      this.looping.value = looping;
      return true;
    }
    return false;
  }

  /// Set whether the player should play the media automatically.
  bool setAutoPlay(bool autoPlay) {
    if (!disposed && autoPlay != this.autoPlay.value) {
      this.autoPlay.value = autoPlay;
      return true;
    }
    return false;
  }
}
