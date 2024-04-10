import 'dart:core';
import 'package:flutter/material.dart';
import 'video_list_view.dart';
import 'video_player_view.dart';
import 'defines.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final n in videoSources) {
    if (n.type == VideoSourceType.asset) {
      n.path = await loadAssetFile(n.path);
      n.type = VideoSourceType.local;
    }
  }
  runApp(const AppView());
}

enum AppRoute {
  videoPlayer,
  videoList,
}

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  var _appRoute = AppRoute.videoPlayer;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('AV Media Player example app'),
          ),
          body: _buildBodyView(),
          bottomNavigationBar: BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.smart_display),
                label: 'Video Player',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.view_stream),
                label: 'Video List',
              ),
            ],
            currentIndex: _appRoute.index,
            onTap: (index) =>
                setState(() => _appRoute = AppRoute.values[index]),
          ),
        ),
      );

  Widget _buildBodyView() {
    switch (_appRoute) {
      case AppRoute.videoPlayer:
        return const VideoPlayerView();
      case AppRoute.videoList:
        return const VideoListView();
    }
  }
}
