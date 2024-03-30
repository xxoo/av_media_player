import 'package:flutter/widgets.dart';
import 'player.dart';

class AVMediaView extends StatefulWidget {
  final AVMediaPlayer? initPlayer;
  final String? initSource;
  final bool? initAutoPlay;
  final bool? initLooping;
  final double? initVolume;
  final double? initSpeed;
  final int? initPosition;
  final void Function(AVMediaPlayer player)? onCreated;

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
      _foreignPlayer = true;
      _player = widget.initPlayer!;
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
    if (_player!.id.value == null) {
      _player!.id.addListener(_update);
    }
  }

  @override
  void dispose() {
    if (_foreignPlayer) {
      try {
        //maybe the player will be reused by the user.
        //but at least it should be closed to prevent texture link error if there is an open video.
        if (_player?.mediaInfo.value != null &&
            _player!.mediaInfo.value!.width > 0 &&
            _player!.mediaInfo.value!.height > 0) {
          _player!.close();
        }
      } catch (_) {}
    } else {
      _player?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _player?.id.value == null
      ? Container()
      : Texture(textureId: _player!.id.value!);

  void _initPosition() {
    _player?.mediaInfo.removeListener(_initPosition);
    if (widget.initPosition != null) {
      _player?.seekTo(widget.initPosition!);
    }
  }

  void _update() {
    _player?.id.removeListener(_update);
    setState(() {});
  }
}
