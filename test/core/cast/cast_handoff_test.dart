import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/cast/cast_handoff.dart';

void main() {
  group('subtitle format', () {
    test('comes from the path extension', () {
      expect(CastHandoff.subtitleFormatFor('https://x/a.srt'), 'srt');
      expect(CastHandoff.subtitleFormatFor('https://x/a.vtt'), 'vtt');
      expect(CastHandoff.subtitleFormatFor('https://X/A.SRT'), 'srt');
    });

    test('a signed url keeps the format of its file, not of its token', () {
      // The check this replaces was `contains('.srt')`, so any token with those
      // four characters in it turned a WebVTT track into a SubRip one.
      expect(
        CastHandoff.subtitleFormatFor('https://x/a.vtt?t=abc.srtdef'),
        'vtt',
      );
      expect(CastHandoff.subtitleFormatFor('https://x/a.srt?t=1'), 'srt');
      expect(CastHandoff.subtitleFormatFor('https://x/a.vtt#.srt'), 'vtt');
    });

    test('a host that merely contains srt does not decide the format', () {
      // https://cdn.srt-host.net/track.vtt was announced as SubRip. A WebVTT
      // file parsed as SubRip yields nothing, and nothing is what the
      // television shows — with no error anywhere.
      expect(
        CastHandoff.subtitleFormatFor('https://cdn.srt-host.net/track.vtt'),
        'vtt',
      );
    });

    test('an extension that only starts with srt is not srt', () {
      expect(CastHandoff.subtitleFormatFor('https://x/a.srtx'), 'vtt');
    });

    test('no extension at all falls back to what Chromecast requires', () {
      expect(CastHandoff.subtitleFormatFor('https://x/subtitle'), 'vtt');
      expect(CastHandoff.subtitleFormatFor(''), 'vtt');
    });
  });

  group('which tracks are sent', () {
    test('a track with no file is not', () {
      // Listed but never fetched. Sending it gives the receiver a url it cannot
      // load and the viewer an option that does nothing.
      expect(CastHandoff.isSendable(''), isFalse);
      expect(CastHandoff.isSendable('   '), isFalse);
      expect(CastHandoff.isSendable('https://x/a.vtt'), isTrue);
    });
  });

  group('where the receiver starts', () {
    test('at the viewer\'s position, because they were mid-episode', () {
      expect(
        CastHandoff.startPositionFor(
          isLive: false,
          position: const Duration(minutes: 12),
        ),
        const Duration(minutes: 12),
      );
    });

    test('nowhere on a live channel', () {
      // No seekable timeline to start into; a receiver told to seek on one
      // either ignores it or drops the stream.
      expect(
        CastHandoff.startPositionFor(
          isLive: true,
          position: const Duration(minutes: 12),
        ),
        isNull,
      );
    });

    test('and nowhere at the very beginning, which is the same as unset', () {
      expect(
        CastHandoff.startPositionFor(isLive: false, position: Duration.zero),
        isNull,
      );
      expect(
        CastHandoff.startPositionFor(isLive: false, position: null),
        isNull,
      );
      expect(
        CastHandoff.startPositionFor(
          isLive: false,
          position: const Duration(seconds: -3),
        ),
        isNull,
      );
    });
  });
}
