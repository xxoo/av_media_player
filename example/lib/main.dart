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
          body: Stack(
            alignment: Alignment.center,
            children: [
              AVMediaView(
                initSource:
                    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
                initLooping: true,
                initAutoPlay: true,
                onCreated: (player) {
                  _player = player;
                  player.loading.addListener(() => setState(() {}));
                },
              ),
              if (_player?.loading.value ?? true)
                const CircularProgressIndicator(),
            ],
          ),
        ),
      );
}
