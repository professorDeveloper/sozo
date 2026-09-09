import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

/// The ladder is the answer to "which mirror plays, and what comes next". Each
/// test below pins a case the player used to get wrong.
VideoSourceEntity src(
  String quality, {
  String? url,
  bool isDefault = false,
  bool accessible = true,
  String? type,
  String? codec,
}) =>
    VideoSourceEntity(
      quality: quality,
      videoUrl: url ?? 'https://cdn.test/$quality',
      isDefault: isDefault,
      accessible: accessible,
      type: type,
      codec: codec,
    );

void main() {
  group('isPlayable', () {
    test('an unreachable mirror is never offered', () {
      // The backend already probed it. Trying anyway costs a spinner and a
      // failure the viewer has to sit through.
      expect(
        SourceLadder.isPlayable(src('1080p', accessible: false),
            hasDirective: false),
        isFalse,
      );
    });

    test('an iframe entry is a page, not a stream, unless a sniff is coming',
        () {
      // Some providers push {type: 'iframe'} first for every server, so
      // sources[0] was an HTML document handed to a video decoder.
      final embed = src('1080p', type: 'iframe');
      expect(SourceLadder.isPlayable(embed, hasDirective: false), isFalse);
      expect(SourceLadder.isPlayable(embed, hasDirective: true), isTrue);
    });

    test('an empty url is not a candidate', () {
      expect(
        SourceLadder.isPlayable(src('1080p', url: ''), hasDirective: true),
        isFalse,
      );
    });
  });

  group('ordering', () {
    test('the remembered quality wins over the source default', () {
      final ladder = SourceLadder(
        sources: [src('480p', isDefault: true), src('720p'), src('1080p')],
        hasDirective: false,
        rememberedQuality: '1080p',
      );
      expect(ladder.next(), 2);
    });

    test('without a remembered choice the default leads', () {
      final ladder = SourceLadder(
        sources: [src('480p'), src('1080p', isDefault: true), src('720p')],
        hasDirective: false,
      );
      expect(ladder.next(), 1);
    });

    test('with neither, the backend order stands', () {
      // The list arrives ranked. Absent a reason, do not reorder it.
      final ladder = SourceLadder(
        sources: [src('720p'), src('1080p'), src('480p')],
        hasDirective: false,
      );
      expect(ladder.ordered(), [0, 1, 2]);
    });

    test('a remembered label that matches nothing is ignored, not fatal', () {
      // The title was watched at a quality this provider no longer serves.
      final ladder = SourceLadder(
        sources: [src('720p'), src('1080p', isDefault: true)],
        hasDirective: false,
        rememberedQuality: '2160p',
      );
      expect(ladder.next(), 1);
    });

    test('unplayable mirrors are dropped from the order entirely', () {
      final ladder = SourceLadder(
        sources: [
          src('1080p', type: 'iframe'),
          src('720p', accessible: false),
          src('480p'),
        ],
        hasDirective: false,
      );
      expect(ladder.ordered(), [2]);
    });
  });

  group('walking the ladder', () {
    test('every mirror is tried before anything gives up', () {
      // The old retry advanced one index and latched a bool, so mirrors three
      // onward were never reached.
      final sources = [src('1080p'), src('720p'), src('480p')];
      final tried = <String>{};
      final visited = <int>[];

      for (;;) {
        final idx = SourceLadder(
          sources: sources,
          hasDirective: false,
          triedUrls: tried,
        ).next();
        if (idx == null) break;
        visited.add(idx);
        tried.add(sources[idx].videoUrl);
      }

      expect(visited, [0, 1, 2]);
    });

    test('null only once nothing is left — that is the error condition', () {
      final sources = [src('1080p')];
      expect(
        SourceLadder(
          sources: sources,
          hasDirective: false,
          triedUrls: {sources.first.videoUrl},
        ).next(),
        isNull,
      );
    });

    test('a re-resolve that returns new urls does not restart the walk', () {
      // Indices are meaningless across a re-resolve because the list is
      // rebuilt; urls are what survive it.
      final tried = {'https://cdn.test/1080p'};
      final ladder = SourceLadder(
        sources: [src('1080p'), src('720p')],
        hasDirective: false,
        triedUrls: tried,
      );
      expect(ladder.next(), 1);
    });

    test('an empty source list yields nothing rather than throwing', () {
      expect(
        const SourceLadder(sources: [], hasDirective: false).next(),
        isNull,
      );
    });
  });

  group('initialPick — the first mirror, never "none"', () {
    test('takes the ranked choice when there is one', () {
      final ladder = SourceLadder(
        sources: [src('480p'), src('1080p', isDefault: true)],
        hasDirective: false,
      );
      expect(ladder.initialPick(), 1);
    });

    test('falls back to the first source when nothing qualifies', () {
      // next() is strict and returns null here. Starting with no index left
      // _currentQuality null, which left the current server null, which made
      // the Quality panel list every mirror across every host — pressing
      // Quality showed servers. Play something instead.
      final ladder = SourceLadder(
        sources: [src('1080p', type: 'iframe'), src('720p', accessible: false)],
        hasDirective: false,
      );
      expect(ladder.next(), isNull);
      expect(ladder.initialPick(), 0);
    });

    test('still null when there genuinely are no sources', () {
      const ladder = SourceLadder(sources: [], hasDirective: false);
      expect(ladder.initialPick(), isNull);
    });

    test('the walk stays strict — initialPick does not loosen next()', () {
      final sources = [src('1080p')];
      final ladder = SourceLadder(
        sources: sources,
        hasDirective: false,
        triedUrls: {sources.first.videoUrl},
      );
      expect(ladder.next(), isNull, reason: 'exhausted means exhausted');
    });
  });

  group('codec demotion after a decoder failure', () {
    test('same-codec mirrors sink below the rest', () {
      final ladder = SourceLadder(
        sources: [
          src('1080p', codec: 'h265'),
          src('720p', codec: 'h264'),
        ],
        hasDirective: false,
        avoidCodec: 'h265',
      );
      expect(ladder.next(), 1);
    });

    test('demoted, never dropped — an h265-only title still plays', () {
      // Filtering instead of demoting would take a title from "plays after one
      // retry" to "no sources".
      final ladder = SourceLadder(
        sources: [src('1080p', codec: 'h265'), src('720p', codec: 'h265')],
        hasDirective: false,
        avoidCodec: 'h265',
      );
      expect(ladder.ordered(), [0, 1]);
    });

    test('demotion outranks even the remembered quality', () {
      // The viewer's remembered pick is the codec that just failed to decode.
      final ladder = SourceLadder(
        sources: [
          src('1080p', codec: 'h265'),
          src('720p', codec: 'h264'),
        ],
        hasDirective: false,
        rememberedQuality: '1080p',
        avoidCodec: 'h265',
      );
      expect(ladder.next(), 1);
    });

    test('codec matching ignores case', () {
      final ladder = SourceLadder(
        sources: [src('1080p', codec: 'H265'), src('720p', codec: 'h264')],
        hasDirective: false,
        avoidCodec: 'h265',
      );
      expect(ladder.next(), 1);
    });
  });
}
