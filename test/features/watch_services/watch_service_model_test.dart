// What TMDB sends, and what the app must not assume about it.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/watch_services/data/models/watch_region_model.dart';
import 'package:soplay/features/watch_services/data/models/watch_service_model.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';

void main() {
  group('a service', () {
    test('reads what the backend sends', () {
      final s = WatchServiceModel.fromJson(const {
        'id': 8,
        'slug': 'netflix',
        'name': 'Netflix',
        'logo': 'https://image.tmdb.org/t/p/w300/x.png',
        'priority': 0,
        'types': ['movie', 'tv'],
      });
      expect(s.id, 8);
      expect(s.name, 'Netflix');
      expect(s.priority, 0);
      expect(s.hasMovies, isTrue);
      expect(s.hasSeries, isTrue);
    });

    test('a missing logo is null, not an empty url', () {
      // An empty string draws a broken image; null draws the initials.
      expect(
        WatchServiceModel.fromJson(const {'id': 1, 'name': 'X'}).logo,
        isNull,
      );
      expect(
        WatchServiceModel.fromJson(const {
          'id': 1,
          'name': 'X',
          'logo': '  ',
        }).logo,
        isNull,
      );
    });

    test('an unknown media type is dropped, not guessed', () {
      final s = WatchServiceModel.fromJson(const {
        'id': 1,
        'name': 'X',
        'types': ['movie', 'audiobook', null],
      });
      expect(s.types, [WatchServiceMedia.movie]);
    });

    test('a service with no priority sorts last, not first', () {
      // Zero is a real priority — Netflix has it in the US — so an absent one
      // must not default to it.
      expect(
        WatchServiceModel.fromJson(const {'id': 1, 'name': 'X'}).priority,
        9999,
      );
    });
  });

  group('initials, for a service with no mark', () {
    // Never a generic icon: a row of identical glyphs says nothing, where "MX"
    // is recognisable and is what the name says anyway.
    WatchServiceEntity named(String name) =>
        WatchServiceEntity(id: 1, name: name);

    test('two words give two letters', () {
      expect(named('Amazon Prime').initials, 'AP');
      expect(named('Apple TV Plus').initials, 'AT');
    });

    test('one word gives its first two', () {
      expect(named('Netflix').initials, 'NE');
      expect(named('MX').initials, 'MX');
      expect(named('A').initials, 'A');
    });

    test('and nothing at all is still something', () {
      expect(named('').initials, '?');
      expect(named('   ').initials, '?');
    });
  });

  group('a region', () {
    test('is upper-cased, because every request takes it that way', () {
      expect(
        WatchRegionModel.fromJson(const {
          'code': 'uz',
          'name': 'Uzbekistan',
        }).code,
        'UZ',
      );
    });

    test('with no name falls back to its code rather than vanishing', () {
      // A country you can still pick beats one dropped from the list.
      expect(WatchRegionModel.fromJson(const {'code': 'AQ'}).name, 'AQ');
    });
  });
}
