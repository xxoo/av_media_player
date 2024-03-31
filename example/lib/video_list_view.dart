import 'package:flutter/material.dart';
import 'package:av_media_player/index.dart';
import 'package:inview_notifier_list/inview_notifier_list.dart';
import 'defines.dart';

class VideoListView extends StatefulWidget {
  const VideoListView({super.key});

  @override
  State<StatefulWidget> createState() => _VideoListView();
}

class _VideoListView extends State<VideoListView> {
  final _players = <AVMediaPlayer>[];
  @override
  void initState() {
    super.initState();

    for (var i = 0; i < videoSources.length; i++) {
      final player = AVMediaPlayer(initLooping: true);
      player.mediaInfo.addListener(() => setState(() {}));
      player.loading.addListener(() => setState(() {}));
      _players.add(player);
    }
  }

  @override
  void dispose() {
    //you should dispose all the players. cause they are managed by the user.
    for (final player in _players) {
      player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InViewNotifierList(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 200),
        isInViewPortCondition:
            (double deltaTop, double deltaBottom, double viewPortDimension) {
          return deltaTop < (0.5 * viewPortDimension) &&
              deltaBottom > (0.5 * viewPortDimension);
        },
        builder: (context, index) => InViewNotifierWidget(
          id: '$index',
          child: Container(
            margin: index == _players.length - 1
                ? null
                : const EdgeInsets.only(bottom: 16),
            child: AspectRatio(
              aspectRatio: _players[index].mediaInfo.value == null ||
                      _players[index].mediaInfo.value!.width == 0 ||
                      _players[index].mediaInfo.value!.height == 0
                  ? 16 / 9
                  : _players[index].mediaInfo.value!.width /
                      _players[index].mediaInfo.value!.height,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _players[index].mediaInfo.value != null &&
                          (_players[index].mediaInfo.value!.width == 0 ||
                              _players[index].mediaInfo.value!.height == 0)
                      ? const Text(
                          'Audio only',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 24,
                          ),
                        )
                      : AVMediaView(initPlayer: _players[index]),
                  if (_players[index].loading.value)
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
          builder: (context, isInView, child) {
            if (!isInView) {
              _players[index].pause();
              _players[index].setAutoPlay(false);
            } else if (_players[index].mediaInfo.value != null) {
              _players[index].play();
            } else {
              if (!_players[index].loading.value) {
                _players[index].open(videoSources[index].path);
              }
              _players[index].setAutoPlay(true);
            }
            return child!;
          },
        ),
        itemCount: _players.length,
      );

  //some opreation may trigger the builder while building is in process.
  //in this situation, we just queue a new frame to update the state.
  @override
  void setState(void Function() fn) {
    try {
      super.setState(fn);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) => super.setState(fn));
    }
  }
}
