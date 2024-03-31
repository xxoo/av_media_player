import 'dart:io';

import 'package:flutter/services.dart';

enum VideoSourceType { asset, network, local }

class ExampleVideoSource {
  String path;
  VideoSourceType type;

  ExampleVideoSource({
    required this.path,
    required this.type,
  });
}

final videoSources = [
  ExampleVideoSource(path: 'assets/01.mp4', type: VideoSourceType.asset),
  ExampleVideoSource(path: 'assets/02.mp4', type: VideoSourceType.asset),
  ExampleVideoSource(path: 'assets/03.mp4', type: VideoSourceType.asset),
  ExampleVideoSource(path: 'assets/04.mp4', type: VideoSourceType.asset),
  ExampleVideoSource(path: 'assets/05.mp4', type: VideoSourceType.asset),
  ExampleVideoSource(path: 'assets/06.mp4', type: VideoSourceType.asset),
  ExampleVideoSource(
    path: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    type: VideoSourceType.network,
  ),
  ExampleVideoSource(
    path:
        'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4',
    type: VideoSourceType.network,
  ),
  ExampleVideoSource(
    path: 'https://download.samplelib.com/mp3/sample-3s.mp3',
    type: VideoSourceType.network,
  ),
];

Future<String> loadAssetFile(String assetPath) async {
  final cacheDirectory = Directory.systemTemp;
  final cachedFilePath = '${cacheDirectory.path}/$assetPath';
  final cachedFile = File(cachedFilePath);
  if (cachedFile.existsSync()) return cachedFilePath;

  // Create intermediate directories
  final cachedFileDirectoryPath = cachedFile.parent.path;
  final cachedFileDirectory = Directory(cachedFileDirectoryPath);
  if (!cachedFileDirectory.existsSync()) {
    cachedFileDirectory.createSync(recursive: true);
  }

  cachedFile.createSync();
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  cachedFile.writeAsBytesSync(bytes);

  return cachedFilePath;
}
