import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/comments/domain/spoiler_rules.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

SpoilerVisibility _v({
  bool spoiler = false,
  bool isOwn = false,
  bool revealed = false,
  bool hideUnwatched = true,
  String? episodeKey = 'e3',
  bool episodeFinished = false,
  int? atSec,
  int? playheadSec,
}) => SpoilerRules.visibility(
  spoiler: spoiler,
  isOwn: isOwn,
  revealed: revealed,
  hideUnwatched: hideUnwatched,
  episodeKey: episodeKey,
  episodeFinished: episodeFinished,
  atSec: atSec,
  playheadSec: playheadSec,
);

HistoryItem _row(int episode, {int pos = 0, int dur = 1000}) => HistoryItem(
  contentUrl: 'show',
  provider: 'p',
  title: 'Show',
  isSerial: true,
  episodeNumber: episode,
  positionMs: pos,
  durationMs: dur,
  watchedAt: 1,
);

void main() {
  group('visibility', () {
    test('a flagged spoiler is blurred even on a finished episode', () {
      expect(
        _v(spoiler: true, episodeFinished: true),
        SpoilerVisibility.spoiler,
      );
      expect(
        _v(spoiler: true, episodeKey: null, hideUnwatched: false),
        SpoilerVisibility.spoiler,
      );
    });

    test('own comments and revealed ones always show', () {
      expect(_v(spoiler: true, isOwn: true), SpoilerVisibility.visible);
      expect(_v(spoiler: true, revealed: true), SpoilerVisibility.visible);
      expect(_v(revealed: true), SpoilerVisibility.visible);
    });

    test('an unfinished episode hides its thread while the setting is on', () {
      expect(_v(), SpoilerVisibility.unwatched);
      expect(_v(hideUnwatched: false), SpoilerVisibility.visible);
      expect(_v(episodeFinished: true), SpoilerVisibility.visible);
    });

    test('title-level comments are never hidden as unwatched', () {
      expect(_v(episodeKey: null), SpoilerVisibility.visible);
    });

    test('while watching, only comments past the playhead stay hidden', () {
      expect(_v(playheadSec: 300, atSec: 120), SpoilerVisibility.visible);
      expect(_v(playheadSec: 300, atSec: 300), SpoilerVisibility.visible);
      expect(_v(playheadSec: 300, atSec: 301), SpoilerVisibility.unwatched);
      expect(_v(playheadSec: 300), SpoilerVisibility.visible);
    });
  });

  group('episodeFinished', () {
    test('watched past the tracker threshold', () {
      expect(
        SpoilerRules.episodeFinished('e3', 'show', [_row(3, pos: 900)]),
        isTrue,
      );
      expect(
        SpoilerRules.episodeFinished('e3', 'show', [_row(3, pos: 500)]),
        isFalse,
      );
    });

    test('moving on to a later episode counts', () {
      expect(SpoilerRules.episodeFinished('e3', 'show', [_row(5)]), isTrue);
      expect(SpoilerRules.episodeFinished('e3', 'show', [_row(2)]), isFalse);
    });

    test('another title does not count, and nothing watched is unfinished',
        () {
      final other = HistoryItem(
        contentUrl: 'other',
        provider: 'p',
        title: 'Other',
        isSerial: true,
        episodeNumber: 9,
        positionMs: 1000,
        durationMs: 1000,
        watchedAt: 1,
      );
      expect(SpoilerRules.episodeFinished('e3', 'show', [other]), isFalse);
      expect(SpoilerRules.episodeFinished('e3', 'show', const []), isFalse);
    });

    test('a key that is not an episode is treated as finished', () {
      expect(SpoilerRules.episodeFinished(null, 'show', const []), isTrue);
    });
  });
}
