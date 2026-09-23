import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:soplay/core/preview/mpv_frame_preview.dart';

// Temporary: checks that a vo=null libmpv hands back frames. Not shipped.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('probe')))));
  final b = MpvFramePreview();
  const url = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
  final sw = Stopwatch()..start();
  final ok = await b.invoke('open', {'url': url, 'headers': <String, String>{}});
  debugPrint('MPVPROBE open=$ok in ${sw.elapsedMilliseconds}ms');
  for (final ms in [5000, 60000, 300000, 61000]) {
    sw.reset();
    final bytes = await b.invoke('frame', {'posMs': ms});
    debugPrint('MPVPROBE pos=$ms bytes=${(bytes as dynamic)?.length} in ${sw.elapsedMilliseconds}ms');
  }
  debugPrint('MPVPROBE done');
}
