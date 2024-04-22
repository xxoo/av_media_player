import 'package:flutter/material.dart';
import 'package:av_media_player/widget.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _loading = true;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          AVMediaView(
            initSource:
                'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
            initLooping: true,
            initAutoPlay: true,
            onCreated: (player) => player.loading.addListener(
                () => setState(() => _loading = player.loading.value)),
          ),
          if (_loading) const CircularProgressIndicator(),
        ],
      );
}
