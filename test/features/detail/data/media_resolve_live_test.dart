import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';

void main() {
  test('a resolve marked live says so; anything else is a file', () {
    final live = MediaResolveModel.fromJson({
      'videoUrl': 'https://cdn.example/ch/index.m3u8',
      'type': 'hls',
      'live': true,
    });
    expect(live.live, isTrue);
    expect(live.type, 'hls', reason: 'the format stays HLS for the engine');

    final file = MediaResolveModel.fromJson({
      'videoUrl': 'https://cdn.example/v.mp4',
      'type': 'mp4',
    });
    expect(file.live, isFalse);
    expect(
      MediaResolveModel.fromJson({'videoUrl': 'x', 'live': 'yes'}).live,
      isFalse,
    );
  });
}
