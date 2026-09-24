import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/home/domain/home_rail.dart';

void main() {
  group('ids', () {
    test('are unique and stable-looking', () {
      final ids = HomeRail.values.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id), isTrue, reason: id);
      }
    });

    test('the defaults cover every rail exactly once', () {
      // A rail missing from the defaults would never appear on a fresh
      // install, and one listed twice would render twice.
      expect(HomeRail.defaults.toSet(), HomeRail.values.toSet());
      expect(HomeRail.defaults.length, HomeRail.values.length);
    });

    test('the defaults are the order Home has always had', () {
      expect(HomeRail.defaults.map((r) => r.id).toList(), [
        'hero',
        'resume',
        'new_releases',
        'picked_for_you',
        'genres',
        'live_tv',
        'watch_services',
        'catalogue',
      ]);
    });
  });

  group('default visibility', () {
    test('streaming services are enabled by default', () {
      expect(HomeRail.watchServices.isOptIn, isFalse);
      expect(HomeRail.catalogue.isOptIn, isFalse);
      expect(HomeRail.liveTv.isOptIn, isFalse);
    });

    test('the default home includes streaming services', () {
      final shown = visibleRails(HomeRail.defaults, HomeRail.optIn);
      expect(shown.contains(HomeRail.watchServices), isTrue);
      expect(shown.contains(HomeRail.catalogue), isTrue);
    });

    test('and it shows once it is taken out of the hidden set', () {
      final shown = visibleRails(HomeRail.defaults, const {});
      expect(shown.contains(HomeRail.watchServices), isTrue);
    });
  });

  group('placing a band where it was offered', () {
    test('an accepted band lands under the one it was offered beneath', () {
      // The card sits after Genres. Taking it up used to drop the band
      // wherever the defaults put it — three rails further down — so the thing
      // you just agreed to appeared somewhere you were not looking.
      final out = placeRailAfter(
        ['hero', 'resume', 'genres', 'live_tv', 'watch_services', 'catalogue'],
        'watch_services',
        'genres',
      );
      expect(out, [
        'hero',
        'resume',
        'genres',
        'watch_services',
        'live_tv',
        'catalogue',
      ]);
    });

    test('and moving it backwards works the same way', () {
      expect(placeRailAfter(['a', 'b', 'c'], 'a', 'c'), ['b', 'c', 'a']);
    });

    test('an id that is already there is left alone', () {
      expect(
        placeRailAfter(
          ['hero', 'genres', 'watch_services'],
          'watch_services',
          'genres',
        ),
        ['hero', 'genres', 'watch_services'],
      );
    });

    test('and an unknown id changes nothing', () {
      // A stored order can name a band this version has dropped. Re-ordering
      // around it must not quietly delete it.
      expect(placeRailAfter(['a', 'b'], 'zzz', 'a'), ['a', 'b']);
      expect(placeRailAfter(['a', 'b'], 'a', 'zzz'), ['a', 'b']);
      expect(placeRailAfter(['a', 'b'], 'a', 'a'), ['a', 'b']);
    });
  });

  group('repairing a stored order', () {
    test('nothing stored gives the defaults', () {
      expect(sanitizeRailOrder(const []), HomeRail.defaults);
    });

    test('a stored order is kept', () {
      final out = sanitizeRailOrder([
        'catalogue',
        'resume',
        'hero',
        'genres',
        'live_tv',
      ]);
      expect(out.map((r) => r.id).toList(), [
        'catalogue',
        'resume',
        // Newer than this stored order too, but anchored beside Continue
        // Watching rather than buried at the end.
        'new_releases',
        'hero',
        'genres',
        'live_tv',
        // Appended, because they are newer than this stored order. Being in
        // the order is not being on Home: each still decides for itself
        // whether it has anything to show.
        'picked_for_you',
        'watch_services',
      ]);
    });

    test('an id this build does not know is dropped', () {
      // A rail removed in a later version. Keeping it would be a null in the
      // render loop.
      final out = sanitizeRailOrder(['hero', 'shorts_rail', 'catalogue']);
      expect(out.contains(HomeRail.hero), isTrue);
      expect(
        out.length,
        HomeRail.values.length,
        reason: 'the rest is appended',
      );
    });

    test('a duplicate is dropped', () {
      // A rail in two places would render twice, and the second copy would be
      // the one nobody can explain.
      final out = sanitizeRailOrder(['hero', 'hero', 'catalogue']);
      expect(out.where((r) => r == HomeRail.hero).length, 1);
    });

    test('a rail added since the order was written is appended', () {
      // The upgrade case. Without this a new rail is invisible until somebody
      // happens to open the customizer.
      final out = sanitizeRailOrder(['catalogue', 'hero']);
      expect(out.first, HomeRail.catalogue);
      expect(out.toSet(), HomeRail.values.toSet());
    });

    test('an order of nothing but junk falls back whole', () {
      // A home screen with no bands is not a preference, it is a broken
      // screen.
      expect(
        sanitizeRailOrder(['nonsense', 'more_nonsense']),
        HomeRail.defaults,
      );
    });
  });

  group('hiding', () {
    test('a hidden rail is left out', () {
      final out = visibleRails(HomeRail.defaults, {'genres', 'live_tv'});
      expect(out.contains(HomeRail.genres), isFalse);
      expect(out.contains(HomeRail.liveTv), isFalse);
      expect(out.contains(HomeRail.catalogue), isTrue);
    });

    test('the order survives hiding', () {
      // A hidden rail keeps its place, so switching it back on puts it where
      // it was rather than at the end.
      final order = [HomeRail.catalogue, HomeRail.hero, HomeRail.resume];
      final out = visibleRails(order, {'hero'});
      expect(out.map((r) => r.id).toList(), ['catalogue', 'resume']);
    });

    test('hiding everything still leaves something to look at', () {
      // The dead end this guards: a blank screen whose only way back is a
      // customizer nobody who just blanked their home screen would think to
      // open.
      final out = visibleRails(HomeRail.defaults, {
        for (final r in HomeRail.values) r.id,
      });
      expect(out, isNotEmpty);
      expect(out.single, HomeRail.catalogue);
    });

    test('hiding nothing shows everything', () {
      expect(visibleRails(HomeRail.defaults, const {}), HomeRail.defaults);
    });
  });

  group('labels', () {
    test('every rail names a key under home_rails.', () {
      for (final r in HomeRail.values) {
        expect(r.labelKey.startsWith('home_rails.'), isTrue, reason: r.id);
      }
    });
  });
}
