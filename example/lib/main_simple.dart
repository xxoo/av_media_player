import 'package:flutter/material.dart';
import 'package:av_media_player/index.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AVMediaPlayer? _controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Lite Video Player example app'),
          ),
          body: AspectRatio(
            aspectRatio: _controller?.mediaInfo.value == null
                ? 16 / 9
                : _controller!.mediaInfo.value!.width /
                    _controller!.mediaInfo.value!.height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AVMediaView(
                  initSource:
                      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
                  initLooping: true,
                  initAutoPlay: true,
                  onCreated: (controller) {
                    _controller = controller;
                    controller.mediaInfo.addListener(_update);
                    controller.loading.addListener(_update);
                  },
                ),
                if (_controller?.loading.value ?? true)
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );

  void _update() => setState(() {});
}
