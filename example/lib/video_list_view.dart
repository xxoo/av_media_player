import 'package:flutter/material.dart';
import 'package:av_media_player/player.dart';
import 'package:av_media_player/utils.dart';
import 'package:inview_notifier_list/inview_notifier_list.dart';
import 'defines.dart';

class VideoListView extends StatefulWidget {
  const VideoListView({super.key});

  @override
  State<StatefulWidget> createState() => _VideoListView();
}

class _VideoListView extends State<VideoListView> with SetStateAsync {
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
    //We should dispose all the players. cause they are managed by the user.
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
              aspectRatio: 16 / 9,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // We can use Texture widget instead of AVPlayerView to display video.
                  // But we have to make sure the player is initialized before doing that. (_players[index].id.value != null)
                  // In this case we check _players[index].mediaInfo.value != null which also guarantees that the player is initialized.
                  _players[index].mediaInfo.value == null ||
                          _players[index].mediaInfo.value!.width == 0 ||
                          _players[index].mediaInfo.value!.height == 0
                      ? Container(color: Colors.black)
                      : Texture(textureId: _players[index].id.value!),
                  if (_players[index].mediaInfo.value != null &&
                      (_players[index].mediaInfo.value!.width == 0 ||
                          _players[index].mediaInfo.value!.height == 0))
                    const Text(
                      'Audio only',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
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
}
