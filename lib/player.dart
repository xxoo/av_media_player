import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'types.dart';

class AVMediaPlayer {
  static const _methodChannel = MethodChannel('avMediaPlayer');

  final id = ValueNotifier<int?>(null);
  final mediaInfo = ValueNotifier<MediaInfo?>(null);
  final position = ValueNotifier(0);
  final error = ValueNotifier<String?>(null);
  final loading = ValueNotifier(false);
  final playbackState = ValueNotifier(PlaybackState.closed);
  final volume = ValueNotifier(1.0);
  final speed = ValueNotifier(1.0);
  final looping = ValueNotifier(false);
  final autoPlay = ValueNotifier(false);
  final finishedTimes = ValueNotifier(0);
  final bufferRange = ValueNotifier(BufferRange.empty);

  // event channel is much more efficient than method channel
  // we'd better use it to hanel playback events especially for position
  StreamSubscription? _eventSubscription;

  String? _source;
  int? _position;

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

  void open(String source) {
    _source = source;
    loading.value = true;
    if (id.value != null) {
      error.value = null;
      mediaInfo.value = null;
      position.value = 0;
      bufferRange.value = BufferRange.empty;
      finishedTimes.value = 0;
      playbackState.value = PlaybackState.closed;
      _methodChannel.invokeMethod('open', {'id': id.value, 'value': source});
    }
  }

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

  bool seekTo(int pos) {
    if (id.value != null &&
        mediaInfo.value != null &&
        pos >= 0 &&
        pos <= mediaInfo.value!.duration) {
      _methodChannel.invokeMethod('seekTo', {'id': id.value, 'value': pos});
      loading.value = true;
      return true;
    }
    return false;
  }

  bool setVolume(double vol) {
    if (volume.value != vol && vol >= 0 && vol <= 1) {
      _methodChannel.invokeMethod('setVolume', {'id': id.value, 'value': vol});
      volume.value = vol;
      return true;
    }
    return false;
  }

  bool setSpeed(double spd) {
    if (spd >= 0.5 && spd <= 2) {
      if (id.value != null) {
        _methodChannel.invokeMethod('setSpeed', {'id': id.value, 'value': spd});
      }
      speed.value = spd;
      return true;
    }
    return false;
  }

  void setLooping(bool loop) {
    if (id.value != null) {
      _methodChannel
          .invokeMethod('setLooping', {'id': id.value, 'value': loop});
    }
    looping.value = loop;
  }

  void setAutoPlay(bool auto) {
    autoPlay.value = auto;
  }
}
