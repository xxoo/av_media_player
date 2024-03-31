import 'package:flutter/material.dart';
import 'package:av_media_player/index.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AVMediaPlayer? _player;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('AV Media Player example app'),
          ),
          body: AspectRatio(
            aspectRatio: _player?.mediaInfo.value == null
                ? 16 / 9
                : _player!.mediaInfo.value!.width /
                    _player!.mediaInfo.value!.height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AVMediaView(
                  initSource:
                      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
                  initLooping: true,
                  initAutoPlay: true,
                  onCreated: (player) {
                    _player = player;
                    player.mediaInfo.addListener(() => setState(() {}));
                    player.loading.addListener(() => setState(() {}));
                  },
                ),
                if (_player?.loading.value ?? true)
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
}
