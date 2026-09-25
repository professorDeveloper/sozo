import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/quality_preference.dart';
import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_style.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

VideoSourceEntity src(String quality, {bool isDefault = false}) =>
    VideoSourceEntity(
      quality: quality,
      videoUrl: 'https://cdn.test/$quality',
      isDefault: isDefault,
      accessible: true,
    );

void main() {
  group('pick', () {
    const ladder = [1080, 720, 480, 360];

    test('Auto pins nothing', () {
      expect(QualityPreference.pick(ladder, QualityPreference.auto), isNull);
    });

    test('an exact match wins', () {
      expect(QualityPreference.pick(ladder, 720), 720);
    });

    test('the closest height at or below the preference', () {
      expect(QualityPreference.pick([1080, 480, 360], 720), 480);
      expect(QualityPreference.pick(ladder, 2160), 1080);
    });

    test('the lowest above when everything is above', () {
      expect(QualityPreference.pick([1080, 720], 480), 720);
    });

    test('data saver takes the smallest', () {
      expect(QualityPreference.pick(ladder, QualityPreference.dataSaver), 360);
    });

    test('nothing to pick from stays adaptive', () {
      expect(QualityPreference.pick(const [], 720), isNull);
      expect(QualityPreference.pick(const [0], 720), isNull);
    });

    test('an unknown stored value reads as Auto', () {
      expect(QualityPreference.normalize(999), QualityPreference.auto);
      expect(QualityPreference.normalize('720'), QualityPreference.auto);
      expect(QualityPreference.normalize(480), 480);
      expect(QualityPreference.normalize(-1), QualityPreference.dataSaver);
    });
  });

  group('shouldExpand', () {
    bool expand(
      String label,
      String url, {
      String? type,
      List<String> siblings = const [],
    }) => QualityPreference.shouldExpand(
      label: label,
      url: url,
      type: type,
      siblingLabels: siblings,
    );

    test('a lone adaptive HLS source is expanded', () {
      expect(expand('auto', 'https://cdn.test/master.m3u8'), isTrue);
      expect(expand('Server 1', 'https://cdn.test/play', type: 'hls'), isTrue);
    });

    test('a label with a resolution is the provider\'s own and is kept', () {
      expect(expand('1080p', 'https://cdn.test/master.m3u8'), isFalse);
    });

    test('a progressive file has no master to read', () {
      expect(expand('auto', 'https://cdn.test/film.mp4', type: 'mp4'), isFalse);
      expect(expand('auto', ''), isFalse);
    });

    test('not twice once its rows are in the list', () {
      expect(
        expand(
          'auto',
          'https://cdn.test/master.m3u8',
          siblings: ['auto · 1080p', 'auto · 720p'],
        ),
        isFalse,
      );
      // Another server's rows say nothing about this one.
      expect(
        expand(
          'auto',
          'https://cdn.test/master.m3u8',
          siblings: ['Server 2 · 720p'],
        ),
        isTrue,
      );
    });
  });

  group('displayHeight', () {
    test('names the picture the way players do', () {
      expect(QualityPreference.displayHeight(1920, 1080), 1080);
      expect(QualityPreference.displayHeight(1920, 800), 1080);
      expect(QualityPreference.displayHeight(1280, 720), 720);
      expect(QualityPreference.displayHeight(1080, 1920), 1080);
      expect(QualityPreference.displayHeight(0, 0), isNull);
    });
  });

  group('SourceLadder with a preferred height', () {
    test('picks the preferred height over the provider default', () {
      final sources = [src('1080p', isDefault: true), src('720p'), src('480p')];
      final ladder = SourceLadder(
        sources: sources,
        hasDirective: false,
        preferredHeight: 720,
      );
      expect(ladder.initialPick(), 1);
    });

    test('Auto keeps the old order', () {
      final sources = [src('480p'), src('1080p', isDefault: true)];
      expect(
        SourceLadder(sources: sources, hasDirective: false).initialPick(),
        1,
      );
    });

    test('a remembered label still wins', () {
      final sources = [src('1080p'), src('720p'), src('480p')];
      final ladder = SourceLadder(
        sources: sources,
        hasDirective: false,
        rememberedQuality: '1080p',
        preferredHeight: QualityPreference.dataSaver,
      );
      expect(ladder.initialPick(), 0);
    });

    test('never trades the default server for another host', () {
      final sources = [src('Voe', isDefault: true), src('Filemoon · 720p')];
      final ladder = SourceLadder(
        sources: sources,
        hasDirective: false,
        preferredHeight: 720,
      );
      expect(ladder.initialPick(), 0);
    });
  });

  group('subtitle size', () {
    test('steps stay in range and land on whole points', () {
      expect(SubtitleStyle.stepFontSize(17.4, 2), 19);
      expect(SubtitleStyle.stepFontSize(39, 2), SubtitleStyle.maxFontSize);
      expect(SubtitleStyle.stepFontSize(13, -2), SubtitleStyle.minFontSize);
    });

    test('the default size is the Medium preset', () {
      expect(
        SubtitleSizePreset.of(SubtitleStyle.defaults().fontSize),
        SubtitleSizePreset.medium,
      );
      expect(SubtitleSizePreset.of(19), isNull);
    });
  });

  test('no expansion when the server already lists resolutions', () {
    expect(
      QualityPreference.shouldExpand(
        label: 'Auto',
        url: 'https://cdn.example/master.m3u8',
        type: 'hls',
        siblingLabels: ['Auto', '1080p', '720p'],
      ),
      isFalse,
    );
    expect(
      QualityPreference.shouldExpand(
        label: 'Server 1',
        url: 'https://cdn.example/master.m3u8',
        type: 'hls',
        siblingLabels: ['Server 1', 'Server 2 · 1080p'],
      ),
      isTrue,
    );
  });
}
