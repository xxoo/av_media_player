import 'package:flutter/material.dart';
import 'package:av_media_player/index.dart';
import 'sources.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> with SetStateAsync {
  final AVMediaPlayer _player = AVMediaPlayer();

  @override
  initState() {
    super.initState();
    _player.playbackState.addListener(() => setState(() {}));
    _player.position.addListener(() => setState(() {}));
    _player.speed.addListener(() => setState(() {}));
    _player.volume.addListener(() => setState(() {}));
    _player.mediaInfo.addListener(() => setState(() {}));
    _player.videoSize.addListener(() => setState(() {}));
    _player.loading.addListener(() => setState(() {}));
    _player.looping.addListener(() => setState(() {}));
    _player.autoPlay.addListener(() => setState(() {}));
    _player.error.addListener(() {
      if (_player.error.value != null) {
        debugPrint('Error: ${_player.error.value}');
      }
    });
    _player.bufferRange.addListener(() {
      if (_player.bufferRange.value != BufferRange.empty) {
        debugPrint(
            'pos: ${_player.position.value} buffer begin: ${_player.bufferRange.value.begin} buffer end: ${_player.bufferRange.value.end}');
      }
    });
  }

  @override
  void dispose() {
    //We should dispose this player. cause it's managed by the user.
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _player.autoPlay.value,
                        onChanged: (value) =>
                            _player.setAutoPlay(value ?? false),
                      ),
                      const Text('Autoplay'),
                      const Spacer(),
                      Checkbox(
                        value: _player.looping.value,
                        onChanged: (value) =>
                            _player.setLooping(value ?? false),
                      ),
                      const Text('Playback loop'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AVMediaView(
                          initPlayer: _player,
                          backgroundColor: Colors.black,
                          initSource: videoSources.first,
                        ),
                        if (_player.mediaInfo.value != null &&
                            _player.videoSize.value == Size.zero)
                          const Text(
                            'Audio only',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          ),
                        if (_player.loading.value)
                          const CircularProgressIndicator(),
                      ],
                    ),
                  ),
                  Slider(
                    // min: 0,
                    max: (_player.mediaInfo.value?.duration ?? 0).toDouble(),
                    value: _player.position.value.toDouble(),
                    onChanged: (value) => _player.seekTo(value.toInt()),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatDuration(
                            Duration(milliseconds: _player.position.value)),
                      ),
                      const Spacer(),
                      Text(
                        _formatDuration(Duration(
                            milliseconds:
                                _player.mediaInfo.value?.duration ?? 0)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _player.play(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.pause),
                        onPressed: () => _player.pause(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop),
                        onPressed: () => _player.close(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.fast_rewind),
                        onPressed: () =>
                            _player.seekTo(_player.position.value - 5000),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fast_forward),
                        onPressed: () =>
                            _player.seekTo(_player.position.value + 5000),
                      ),
                      const Spacer(),
                      _buildPlaybackStatusView(),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                          'Volume: ${_player.volume.value.toStringAsFixed(2)}'),
                      Expanded(
                        child: Slider(
                          value: _player.volume.value,
                          onChanged: (value) => _player.setVolume(value),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Speed: ${_player.speed.value.toStringAsFixed(2)}'),
                      Expanded(
                        child: Slider(
                          value: _player.speed.value,
                          onChanged: (value) => _player.setSpeed(value),
                          min: 0.5,
                          max: 2,
                          divisions: (2 - 0.25) ~/ 0.25,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: videoSources.length,
                itemBuilder: (context, index) => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: GestureDetector(
                    onTap: () => _player.open(videoSources[index]),
                    child: AVMediaView(
                      initSource: videoSources[index],
                      backgroundColor: Colors.black,
                      sizingMode: SizingMode.free,
                    ),
                  ),
                ),
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 8),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );

  Widget _buildPlaybackStatusView() {
    const size = 16.0;
    const color = Color(0x80000000);
    switch (_player.playbackState.value) {
      case PlaybackState.playing:
        return const Icon(
          Icons.play_arrow,
          size: size,
          color: color,
        );
      case PlaybackState.paused:
        return const Icon(
          Icons.pause,
          size: size,
          color: color,
        );
      case PlaybackState.closed:
        return const Icon(
          Icons.stop,
          size: size,
          color: color,
        );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$twoDigitMinutes:$twoDigitSeconds';
  }
}
