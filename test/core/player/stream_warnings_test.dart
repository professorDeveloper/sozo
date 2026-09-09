import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/stream_warnings.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

/// A source page routinely offers the same film as a 17 GB 2160p Dolby Vision
/// remux and as a 3 GB 1080p H.264 copy. The first is the better file and the
/// worse choice on a phone — and every way it fails looks like the app being
/// broken rather than the file being wrong for the device.
void main() {
  // No localisation setup: nothing here reads `message`, which is the only
  // member that resolves a translation. Ranking and recognition are what this
  // covers, and both are pure.

  VideoSourceEntity source(List<String> warnings) => VideoSourceEntity(
    quality: '2160p',
    videoUrl: 'https://x/y.mkv',
    isDefault: false,
    accessible: true,
    warnings: warnings,
  );

  test('a clean source has nothing to say', () {
    expect(StreamWarning.forSource(source(const [])), isEmpty);
    expect(StreamWarning.worst(source(const [])), isNull);
  });

  test('what stops playback outranks what merely costs data', () {
    // The order is the whole point of `worst`: a 4K Dolby Vision remux carries
    // four warnings, and the one worth the single line under the row is the
    // one that means it will not play.
    final worst = StreamWarning.worst(
      source(const ['4k', 'large-file', 'dolby-vision', 'atmos-audio']),
    );
    expect(worst, isNotNull);
    expect(worst!.risk, StreamRisk.blocking);
    expect(worst.code, 'dolby_vision');
  });

  test('the three blocking kinds are all blocking', () {
    for (final code in ['dolby-vision', 'atmos-audio', 'indirect-host']) {
      expect(
        StreamWarning.worst(source([code]))!.risk,
        StreamRisk.blocking,
        reason: '$code should block',
      );
    }
  });

  test('size and resolution are cautions, not blockers', () {
    for (final code in ['4k', 'large-file']) {
      expect(StreamWarning.worst(source([code]))!.risk, StreamRisk.caution);
    }
  });

  test('an unreachable link is recognised whatever status it carries', () {
    // The backend appends the HTTP code, so this is a family rather than a
    // fixed string.
    for (final code in ['unreachable-404', 'unreachable-503', 'unreachable-error']) {
      final w = StreamWarning.worst(source([code]));
      expect(w, isNotNull, reason: code);
      expect(w!.risk, StreamRisk.blocking);
    }
  });

  test('a code the app does not know is dropped, not printed raw', () {
    // The backend may add one before the app has a string for it, and an
    // untranslated `some-new-code` on screen is worse than one fewer line.
    expect(StreamWarning.forSource(source(const ['not-a-real-code'])), isEmpty);
    // And it must not hide the ones alongside it.
    final mixed = StreamWarning.forSource(source(const ['not-a-real-code', '4k']));
    expect(mixed.length, 1);
    expect(mixed.single.code, 'uhd');
  });

  group('size', () {
    test('reads in the units the labels use', () {
      expect(formatStreamSize(2890000000), '2.9 GB');
      expect(formatStreamSize(17440000000), '17.4 GB');
      expect(formatStreamSize(924000000), '924 MB');
    });

    test('a missing or nonsense size is no size', () {
      expect(formatStreamSize(null), isNull);
      expect(formatStreamSize(0), isNull);
      expect(formatStreamSize(-1), isNull);
    });
  });
}
