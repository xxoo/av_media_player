import 'package:flutter/widgets.dart';
import 'player.dart';

/// The widget to display video for [AVMediaPlayer].
class AVMediaView extends StatefulWidget {
  final AVMediaPlayer? initPlayer;
  final void Function(AVMediaPlayer player)? onCreated;
  final Color? backgroundColor;
  final bool keepAspectRatio;
  final String? initSource;
  final bool? initAutoPlay;
  final bool? initLooping;
  final double? initVolume;
  final double? initSpeed;
  final int? initPosition;

  /// Create a new [AVMediaView] widget.
  /// If [initPlayer] is null, a new player will be created.
  /// You can get the player from [onCreated] callback.
  ///
  /// [backgroundColor] is the color to display when there is no video.
  /// This parameter can be changed by updating the widget.
  ///
  /// [keepAspectRatio] indicates whether the video should keep its original aspect ratio.
  /// This parameter can be changed by updating the widget.
  ///
  /// Other parameters only take efferts at the time the widget is created.
  /// To changed them later, you need to call the corresponding methods of the player.
  const AVMediaView({
    super.key,
    this.initPlayer,
    this.initSource,
    this.initAutoPlay,
    this.initLooping,
    this.initVolume,
    this.initSpeed,
    this.initPosition,
    this.onCreated,
    this.backgroundColor,
    this.keepAspectRatio = true,
  });

  @override
  State<AVMediaView> createState() => _AVMediaState();
}

class _AVMediaState extends State<AVMediaView> {
  bool _foreignPlayer = false;
  AVMediaPlayer? _player;

  @override
  void initState() {
    super.initState();
    if (widget.initPlayer == null) {
      _player = AVMediaPlayer(
        initSource: widget.initSource,
        initAutoPlay: widget.initAutoPlay,
        initLooping: widget.initLooping,
        initVolume: widget.initVolume,
        initSpeed: widget.initSpeed,
        initPosition: widget.initPosition,
      );
    } else {
      _player = widget.initPlayer!;
      _foreignPlayer = true;
      if (widget.initSource != null) {
        _player!.open(widget.initSource!);
      }
      if (widget.initAutoPlay != null) {
        _player!.setAutoPlay(widget.initAutoPlay!);
      }
      if (widget.initLooping != null) {
        _player!.setLooping(widget.initLooping!);
      }
      if (widget.initVolume != null) {
        _player!.setVolume(widget.initVolume!);
      }
      if (widget.initSpeed != null) {
        _player!.setSpeed(widget.initSpeed!);
      }
      if (widget.initPosition != null) {
        if (_player!.mediaInfo.value == null) {
          _player!.mediaInfo.addListener(_initPosition);
        } else {
          _player!.seekTo(widget.initPosition!);
        }
      }
    }
    if (widget.onCreated != null) {
      widget.onCreated!(_player!);
    }
    _player!.mediaInfo.addListener(_update);
  }

  @override
  void didUpdateWidget(AVMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keepAspectRatio != oldWidget.keepAspectRatio ||
        widget.backgroundColor != oldWidget.backgroundColor) {
      _update();
    }
  }

  @override
  void dispose() {
    if (_foreignPlayer) {
      try {
        _player?.mediaInfo.removeListener(_update);
        //maybe the player will be reused by the user.
        //but at least it should be closed to prevent texture link error if there is an open video.
        if (_checkVideo()) {
          _player!.close();
        }
      } catch (_) {}
    } else {
      _player?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkVideo()) {
      final texture = Texture(textureId: _player!.id.value!);
      return widget.keepAspectRatio
          ? AspectRatio(
              aspectRatio: _player!.mediaInfo.value!.width /
                  _player!.mediaInfo.value!.height,
              child: texture,
            )
          : texture;
    } else {
      return Container(color: widget.backgroundColor);
    }
  }

  void _initPosition() {
    _player?.mediaInfo.removeListener(_initPosition);
    if (widget.initPosition != null) {
      _player?.seekTo(widget.initPosition!);
    }
  }

  bool _checkVideo() =>
      _player?.mediaInfo.value != null &&
      _player!.mediaInfo.value!.width > 0 &&
      _player!.mediaInfo.value!.height > 0 &&
      _player!.mediaInfo.value!.duration > 0;

  void _update() {
    try {
      setState(() {});
    } catch (e) {
      //some opreation may trigger the builder while building is in process.
      //in this situation, we just queue a new frame to update the state.
      if (e is FlutterError &&
          e.message.substring(0, 51) ==
              'setState() or markNeedsBuild() called during build.') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            //maybe the widget is disposed.
            setState(() {});
          } catch (_) {}
        });
      } else {
        rethrow;
      }
    }
  }
}
