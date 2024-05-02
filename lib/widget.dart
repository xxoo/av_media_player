import 'package:flutter/widgets.dart';
import 'player.dart';
import 'utils.dart';

/// This type is used by [AVMediaView], for sizing the video.
enum SizingMode { free, keepAspectRatio, originalSize }

/// The widget to display video for [AVMediaPlayer].
class AVMediaView extends StatefulWidget {
  final AVMediaPlayer? initPlayer;
  final void Function(AVMediaPlayer player)? onCreated;
  final Color? backgroundColor;
  final SizingMode sizingMode;
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
  /// [sizingMode] indicates how to size the video.
  /// This parameter can be changed by updating the widget.
  ///
  /// Other parameters only take efferts at the time the widget is mounted.
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
    this.sizingMode = SizingMode.keepAspectRatio,
  });

  @override
  State<AVMediaView> createState() => _AVMediaState();
}

class _AVMediaState extends State<AVMediaView> with SetStateAsync {
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
        _player!.seekTo(widget.initPosition!);
      }
    }
    if (widget.onCreated != null) {
      widget.onCreated!(_player!);
    }
    _player!.videoSize.addListener(_update);
  }

  @override
  void didUpdateWidget(AVMediaView oldWidget) {
    if (widget.sizingMode != oldWidget.sizingMode ||
        widget.backgroundColor != oldWidget.backgroundColor) {
      super.didUpdateWidget(oldWidget);
    }
  }

  @override
  void dispose() {
    if (_foreignPlayer) {
      try {
        _player?.videoSize.removeListener(_update);
      } catch (_) {}
    } else {
      _player?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_player!.videoSize.value != Size.zero) {
      final texture = Texture(textureId: _player!.id.value!);
      if (widget.sizingMode == SizingMode.keepAspectRatio) {
        return AspectRatio(
          aspectRatio:
              _player!.videoSize.value.width / _player!.videoSize.value.height,
          child: texture,
        );
      } else if (widget.sizingMode == SizingMode.originalSize) {
        return SizedBox(
          width: _player!.videoSize.value.width,
          height: _player!.videoSize.value.height,
          child: texture,
        );
      } else {
        return texture;
      }
    } else {
      return Container(color: widget.backgroundColor);
    }
  }

  void _update() => setState(() {});
}
