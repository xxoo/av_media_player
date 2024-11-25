// This example shows how to use the AvMediaView widget to play a video from a URL.
// Which is a very basic way to use av_media_player package.
// For more advanced usage, see main_advanced.dart.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:av_media_player/widget.dart';
import 'dart:io';

void main() async {
  final client = HttpClient();
  final server = await HttpServer.bind('127.0.0.1', 8080);
  server.listen((request) async {
    final url = request.uri.path.substring(1);
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    request.response.statusCode = res.statusCode;
    debugPrint('url: $url, statusCode: ${res.statusCode}');
    if (url.endsWith('.m3u8')) {
      final content = await res.transform(const Utf8Decoder()).join();
      final newContent =
          content.replaceAll('https://', 'http://127.0.0.1:8080/https://');
      request.response.headers
          .add('content-type', 'application/vnd.apple.mpegurl');
      request.response.write(newContent);
      await request.response.close();
    } else {
      request.response.contentLength = res.headers.contentLength - 148;
      request.response.headers.add('content-type', 'video/mp2t');
      var i = 0;
      res.listen(
        (data) {
          if (i < 148) {
            final j = i;
            i += data.length;
            if (i > 148) {
              request.response.add(data.sublist(148 - j));
            }
          } else {
            request.response.add(data);
          }
        },
        onDone: () => request.response.close(),
      );
    }
  });
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _loading = true;
  @override
  Widget build(BuildContext context) => Stack(
        textDirection: TextDirection.ltr,
        alignment: Alignment.center,
        children: [
          AvMediaView(
            initSource:
                'http://127.0.0.1:8080/http://yun.366day.site/mp4hls/dmhls/dianwanka1.m3u8',
            initLooping: true,
            initAutoPlay: true,
            onCreated: (player) => player.loading.addListener(
                () => setState(() => _loading = player.loading.value)),
          ),
          if (_loading) const CircularProgressIndicator(),
        ],
      );
}
