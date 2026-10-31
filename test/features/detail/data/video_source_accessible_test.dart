import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/video_source_model.dart';

/// `accessible` says a probe refused the source. Providers do not probe, so it
/// is usually absent, and reading absent as false left the ladder with nothing:
/// the first mirror played and its failure ended on the error screen, with the
/// others untried.
void main() {
  Map<String, dynamic> source(String name, {bool? accessible, String? type}) =>
      {
        'quality': name,
        'videoUrl': 'https://cdn.test/$name.m3u8',
        'type': ?type,
        'accessible': ?accessible,
      };

  test('a source that does not say is one the player may try', () {
    expect(VideoSourceModel.fromJson(source('a')).accessible, isTrue);
  });

  test('a source a probe refused stays refused', () {
    expect(
      VideoSourceModel.fromJson(source('a', accessible: false)).accessible,
      isFalse,
    );
  });

  test('a resolve with no flags can be walked past its first mirror', () {
    final media = MediaResolveModel.fromJson({
      'videoUrl': 'https://cdn.test/a.m3u8',
      'videoSources': [source('a'), source('b'), source('c')],
    });
    final ladder = SourceLadder(
      sources: media.videoSources,
      hasDirective: false,
    );
    expect(ladder.ordered(), hasLength(3));

    final afterFirst = SourceLadder(
      sources: media.videoSources,
      hasDirective: false,
      triedUrls: {media.videoSources.first.videoUrl},
    );
    expect(afterFirst.next(), isNotNull);
  });

  test('an embed is walked only when a directive says it will be sniffed', () {
    final sources = [
      VideoSourceModel.fromJson(source('direct', type: 'hls')),
      VideoSourceModel.fromJson(source('embed', type: 'iframe')),
    ];
    expect(
      SourceLadder(sources: sources, hasDirective: false).ordered(),
      hasLength(1),
    );
    expect(
      SourceLadder(sources: sources, hasDirective: true).ordered(),
      hasLength(2),
    );
  });
}
