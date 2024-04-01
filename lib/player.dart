import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'types.dart';

/// The class to create and control [AVMediaPlayer] instance.
///
/// Do NOT modify properties directly, use the corresponding methods instead.
class AVMediaPlayer {
  static const _methodChannel = MethodChannel('avMediaPlayer');

  /// The id of the player. It's null before the player is initialized.
  /// After the player is initialized it will be unique and never change again.
  final id = ValueNotifier<int?>(null);

  /// The information of the current media. It's null before the media is opened.
  final mediaInfo = ValueNotifier<MediaInfo?>(null);

  /// The position of the current media in milliseconds. It's 0 before the media is opened.
  final position = ValueNotifier(0);

  /// The error message of the player. It's null before an error occurs.
  final error = ValueNotifier<String?>(null);

  /// The loading state of the player. It's false before opening a media.
  final loading = ValueNotifier(false);

  /// The playback state of the player. It's [PlaybackState.closed] berore a media is opened.
  final playbackState = ValueNotifier(PlaybackState.closed);

  /// The volume of the player. It's between 0 and 1, and defaults to 1.
  final volume = ValueNotifier(1.0);

  /// The speed of the player. It's between 0.5 and 2, and defaults to 1.
  final speed = ValueNotifier(1.0);

  /// Whether the player should loop the media. It's false by default.
  final looping = ValueNotifier(false);

  /// Whether the player should play the media automatically. It's false by default.
  final autoPlay = ValueNotifier(false);

  /// How many times the player has finished playing the current media. It will be reset to 0 when the media is closed.
  final finishedTimes = ValueNotifier(0);

  /// The current buffer status of the player. It is only reported for network media.
  final bufferRange = ValueNotifier(BufferRange.empty);

  // Event channel is much more efficient than method channel
  // We'd better use it to hanel playback events especially for position
  StreamSubscription? _eventSubscription;
  String? _source;
  int? _position;

  /// All the parameters are optional, and can be changed later by calling the corresponding methods.
  AVMediaPlayer({
    String? initSource,
    double? initVolume,
    double? initSpeed,
    bool? initLooping,
    bool? initAutoPlay,
    int? initPosition,
  }) {
    _methodChannel.invokeMethod('create').then((value) {
      id.value = value as int;
      _eventSubscription = EventChannel('avMediaPlayer/${id.value}')
          .receiveBroadcastStream()
          .listen((event) {
        final e = event as Map;
        if (e['event'] == 'mediaInfo') {
          if (_source == e['source']) {
            loading.value = false;
            playbackState.value = PlaybackState.paused;
            mediaInfo.value = MediaInfo(
              e['width'],
              e['height'],
              e['duration'],
              _source!,
            );
            if (autoPlay.value) {
              play();
            }
            if (_position != null) {
              seekTo(_position!);
              _position = null;
            }
          }
        } else if (e['event'] == 'position') {
          if (mediaInfo.value != null) {
            position.value = e['value'] > mediaInfo.value!.duration
                ? mediaInfo.value!.duration
                : e['value'] < 0
                    ? 0
                    : e['value'];
          }
        } else if (e['event'] == 'bufferChange') {
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
            position.value = 0;
            bufferRange.value = BufferRange.empty;
            finishedTimes.value = 0;
            loading.value = false;
            playbackState.value = PlaybackState.closed;
          }
        } else if (e['event'] == 'loading') {
          loading.value = e['value'];
        } else if (e['event'] == 'seekEnd') {
          loading.value = false;
        } else if (e['event'] == 'finished') {
          if (!looping.value) {
            position.value = 0;
            bufferRange.value = BufferRange.empty;
            playbackState.value = PlaybackState.paused;
          }
          finishedTimes.value += 1;
        }
      });
      if (_source != null) {
        open(_source!);
      }
      if (volume.value != 1) {
        setVolume(volume.value);
      }
      if (speed.value != 1) {
        setSpeed(speed.value);
      }
      if (looping.value) {
        setLooping(true);
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
    _methodChannel.invokeMethod('dispose', id.value);
    _eventSubscription?.cancel();
    id.dispose();
    mediaInfo.dispose();
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

  /// Open a media file
  ///
  /// source: The url or local path of the media file
  void open(String source) {
    _source = source;
    if (id.value != null) {
      error.value = null;
      mediaInfo.value = null;
      position.value = 0;
      bufferRange.value = BufferRange.empty;
      finishedTimes.value = 0;
      playbackState.value = PlaybackState.closed;
      _methodChannel.invokeMethod('open', {'id': id.value, 'value': source});
    }
    loading.value = true;
  }

  /// Close or stop opening the media file.
  void close() {
    _source = null;
    if (id.value != null &&
        (playbackState.value != PlaybackState.closed || loading.value)) {
      _methodChannel.invokeMethod('close', id.value);
      mediaInfo.value = null;
      position.value = 0;
      bufferRange.value = BufferRange.empty;
      finishedTimes.value = 0;
      playbackState.value = PlaybackState.closed;
    }
    loading.value = false;
  }

  /// Play the current media file.
  ///
  /// If the the player is opening a media file, calling this method will set autoplay to true
  bool play() {
    if (speed.value > 0) {
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
  bool pause() {
    if (id.value != null && playbackState.value == PlaybackState.playing) {
      _methodChannel.invokeMethod('pause', id.value);
      loading.value = false;
      playbackState.value = PlaybackState.paused;
      return true;
    } else if (autoPlay.value &&
        playbackState.value == PlaybackState.closed &&
        _source != null) {
      setAutoPlay(false);
      return true;
    }
    return false;
  }

  /// Seek to a specific position.
  ///
  /// position: The position to seek to in milliseconds.
  bool seekTo(int position) {
    if (id.value != null &&
        mediaInfo.value != null &&
        position >= 0 &&
        position <= mediaInfo.value!.duration) {
      _methodChannel
          .invokeMethod('seekTo', {'id': id.value, 'value': position});
      loading.value = true;
      return true;
    }
    return false;
  }

  /// Set the volume of the player.
  ///
  /// volume: The volume to set between 0 and 1.
  bool setVolume(double volume) {
    if (this.volume.value != volume && volume >= 0 && volume <= 1) {
      _methodChannel
          .invokeMethod('setVolume', {'id': id.value, 'value': volume});
      this.volume.value = volume;
      return true;
    }
    return false;
  }

  /// Set playback speed of the player.
  ///
  /// speed: The speed to set between 0.5 and 2.
  bool setSpeed(double speed) {
    if (speed >= 0.5 && speed <= 2) {
      if (id.value != null) {
        _methodChannel
            .invokeMethod('setSpeed', {'id': id.value, 'value': speed});
      }
      this.speed.value = speed;
      return true;
    }
    return false;
  }

  /// Set whether the player should loop the media.
  void setLooping(bool looping) {
    if (id.value != null) {
      _methodChannel
          .invokeMethod('setLooping', {'id': id.value, 'value': looping});
    }
    this.looping.value = looping;
  }

  /// Set whether the player should play the media automatically.
  void setAutoPlay(bool autoPlay) {
    this.autoPlay.value = autoPlay;
  }
}
