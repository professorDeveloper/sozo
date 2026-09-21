// Which country's line-ups to show, and what the flag is.
//
// The stored region starts EMPTY rather than at a default, and that is the
// whole design: an unchosen region follows the device, so a phone carried
// across a border keeps up instead of being frozen on wherever it first
// launched.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/watch_region.dart';

void main() {
  const known = [
    WatchRegionEntity(code: 'US', name: 'United States'),
    WatchRegionEntity(code: 'UZ', name: 'Uzbekistan'),
    WatchRegionEntity(code: 'GB', name: 'United Kingdom'),
  ];

  group('which region to browse', () {
    test('a stored choice wins', () {
      expect(resolveRegion('UZ', known, deviceCountry: 'US'), 'UZ');
    });

    test('the device is followed until somebody chooses', () {
      expect(resolveRegion('', known, deviceCountry: 'UZ'), 'UZ');
    });

    test(
      'a stored region TMDB has dropped falls back rather than sticking',
      () {
        // A screen of nothing under a flag is worse than a screen of somewhere
        // else's films.
        expect(resolveRegion('XX', known, deviceCountry: 'GB'), 'GB');
      },
    );

    test('and US only when there is nothing else to go on', () {
      expect(resolveRegion('', known, deviceCountry: ''), 'US');
      expect(resolveRegion('', known, deviceCountry: 'XX'), 'US');
      expect(resolveRegion('', const [], deviceCountry: ''), 'US');
    });

    test('an unknown list cannot contradict a stored choice', () {
      // On the first load the region list has not been fetched. An empty list
      // must not be read as "TMDB lists nothing", or every start would reset
      // the viewer's own choice.
      expect(resolveRegion('UZ', const [], deviceCountry: 'US'), 'UZ');
    });

    test('case and spacing do not change the answer', () {
      expect(resolveRegion(' uz ', known, deviceCountry: ''), 'UZ');
      expect(resolveRegion('', known, deviceCountry: 'uz'), 'UZ');
    });
  });

  group('the flag', () {
    test('two letters become regional indicators', () {
      expect(regionFlag('UZ'), '\u{1F1FA}\u{1F1FF}');
      expect(regionFlag('us'), '\u{1F1FA}\u{1F1F8}');
    });

    test('anything else is nothing at all', () {
      // Never a placeholder glyph: a box where a flag should be reads as a
      // broken app, where no flag just reads as a name.
      expect(regionFlag('USA'), '');
      expect(regionFlag('U'), '');
      expect(regionFlag('12'), '');
      expect(regionFlag(''), '');
      expect(regionFlag('U1'), '');
    });
  });
}
