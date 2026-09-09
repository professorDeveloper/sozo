import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/data/aniskip_service.dart';
import 'package:soplay/features/detail/domain/playback/skip_offers.dart';

SkipInterval op({int startS = 60, int endS = 150}) => SkipInterval(
      type: 'op',
      start: Duration(seconds: startS),
      end: Duration(seconds: endS),
    );

SkipInterval ed({int startS = 1300, int endS = 1400}) => SkipInterval(
      type: 'ed',
      start: Duration(seconds: startS),
      end: Duration(seconds: endS),
    );

Duration at(int seconds) => Duration(seconds: seconds);

void main() {
  group('when an offer appears', () {
    test('inside the interval, from its first second', () {
      final s = SkipOffers()..load([op()]);
      expect(s.offerAt(at(59)), isNull);
      expect(s.offerAt(at(60))?.type, 'op');
      expect(s.offerAt(at(65))?.type, 'op');
    });

    test('and never after the interval ends', () {
      final s = SkipOffers()..load([op(startS: 60, endS: 150)]);
      expect(s.offerAt(at(150)), isNull);
    });

    test('the ending is offered on its own terms', () {
      final s = SkipOffers()..load([op(), ed()]);
      expect(s.offerAt(at(1305))?.type, 'ed');
    });

    test('nothing is offered between intervals', () {
      final s = SkipOffers()..load([op(), ed()]);
      expect(s.offerAt(at(600)), isNull);
    });
  });

  group('watching past the window is a decision', () {
    test('the offer expires ten seconds in', () {
      // A Skip button that hangs about for the whole opening is worse than
      // none: it stops being an offer and becomes furniture.
      final s = SkipOffers()..load([op(startS: 60, endS: 150)]);
      expect(s.offerAt(at(70)), isNotNull, reason: 'exactly at the window');
      expect(s.offerAt(at(71)), isNull, reason: 'one second past it');
    });

    test('and does not come back later in the same interval', () {
      final s = SkipOffers()..load([op(startS: 60, endS: 150)]);
      expect(s.offerAt(at(120)), isNull);
    });
  });

  group('an interval taken never returns', () {
    test('even when the viewer seeks back into it', () {
      final s = SkipOffers()..load([op()]);
      final offer = s.offerAt(at(62))!;
      s.take(offer);
      expect(s.offerAt(at(62)), isNull);
      expect(s.wasTaken(offer), isTrue);
    });

    test('taking the opening leaves the ending alone', () {
      final s = SkipOffers()..load([op(), ed()]);
      s.take(s.offerAt(at(62))!);
      expect(s.offerAt(at(1305))?.type, 'ed');
    });
  });

  group('bad submissions', () {
    test('a two-second interval is dropped, not offered', () {
      // AniSkip is crowd-sourced. A Skip button that jumps two seconds looks
      // broken, so these never reach the offer logic at all.
      final s = SkipOffers()..load([op(startS: 60, endS: 62)]);
      expect(s.intervals, isEmpty);
      expect(s.offerAt(at(61)), isNull);
    });

    test('a five-second interval is the shortest that counts', () {
      final s = SkipOffers()..load([op(startS: 60, endS: 65)]);
      expect(s.intervals, hasLength(1));
    });
  });

  group('a new episode', () {
    test('forgets what was taken', () {
      final s = SkipOffers()..load([op()]);
      s.take(s.offerAt(at(62))!);
      s.load([op()]);
      expect(s.offerAt(at(62)), isNotNull);
    });

    test('clear leaves nothing to offer', () {
      final s = SkipOffers()..load([op()]);
      s.clear();
      expect(s.intervals, isEmpty);
      expect(s.offerAt(at(62)), isNull);
    });
  });

  test('skipping lands at the end of the interval, not a fixed jump', () {
    // Openings differ in length; ninety seconds either lands mid-opening or
    // well into the episode.
    final s = SkipOffers()..load([op(startS: 60, endS: 150)]);
    expect(s.targetFor(s.offerAt(at(62))!), at(150));
  });

  test('no intervals at all is quiet, not a crash', () {
    final s = SkipOffers();
    expect(s.offerAt(at(62)), isNull);
    expect(s.intervals, isEmpty);
  });
}
