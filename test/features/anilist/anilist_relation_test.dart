import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

void main() {
  Map<String, dynamic> edge(
    String type, {
    int id = 1,
    String? english,
    String? romaji,
    String? nodeType,
    String? format,
    int? year,
  }) =>
      {
        'relationType': type,
        'node': {
          'id': id,
          'type': nodeType,
          'format': format,
          'seasonYear': year,
          'title': {'english': english, 'romaji': romaji},
          'coverImage': {'large': 'https://img/$id.jpg'},
        },
      };

  group('parsing', () {
    test('reads a real AniList edge', () {
      // The shape verified live against graphql.anilist.co for Naruto.
      final r = AnilistRelation.fromEdge(
        edge('SEQUEL',
            id: 1735,
            english: 'Naruto: Shippuden',
            romaji: 'NARUTO: Shippuuden',
            nodeType: 'ANIME',
            format: 'TV',
            year: 2007),
      );
      expect(r.id, 1735);
      expect(r.relationType, 'SEQUEL');
      expect(r.title, 'Naruto: Shippuden');
      expect(r.type, 'ANIME');
      expect(r.format, 'TV');
      expect(r.year, 2007);
      expect(r.coverImage, 'https://img/1735.jpg');
    });

    test('falls back to romaji when there is no English title', () {
      // Common for anything that never got a licensed release.
      final r = AnilistRelation.fromEdge(edge('SIDE_STORY', romaji: 'Kizumonogatari'));
      expect(r.title, 'Kizumonogatari');
    });

    test('an empty English title does not win over a real romaji one', () {
      // AniList returns "" rather than null often enough that a null check
      // alone leaves cards with no name on them.
      final r = AnilistRelation.fromEdge(edge('SEQUEL', english: '', romaji: 'Bakemonogatari'));
      expect(r.title, 'Bakemonogatari');
    });

    test('missing fields do not throw', () {
      final r = AnilistRelation.fromEdge({'relationType': 'OTHER', 'node': {}});
      expect(r.id, 0);
      expect(r.title, '');
      expect(r.year, isNull);
      expect(r.coverImage, isNull);
    });

    test('a missing relation type reads as OTHER', () {
      final r = AnilistRelation.fromEdge({'node': {'id': 5}});
      expect(r.relationType, 'OTHER');
    });

    test('the relation type is upper-cased', () {
      expect(AnilistRelation.fromEdge(edge('sequel')).relationType, 'SEQUEL');
    });
  });

  group('ordering', () {
    test('a sequel outranks everything', () {
      // The question this tab exists to answer is "I finished it, what is
      // next" — so the sequel cannot sit under nine side stories.
      final sequel = AnilistRelation.fromEdge(edge('SEQUEL'));
      for (final other in ['SIDE_STORY', 'ADAPTATION', 'SOURCE', 'CHARACTER', 'OTHER']) {
        expect(
          sequel.rank,
          lessThan(AnilistRelation.fromEdge(edge(other)).rank),
          reason: 'SEQUEL must outrank $other',
        );
      }
    });

    test('the source manga sorts below the watchable relations', () {
      // Interesting, and almost never the next thing somebody opens here.
      final source = AnilistRelation.fromEdge(edge('SOURCE'));
      final side = AnilistRelation.fromEdge(edge('SIDE_STORY'));
      expect(side.rank, lessThan(source.rank));
    });

    test('an unknown relation type sorts last rather than vanishing', () {
      // A value added upstream should still show the title it points at.
      final unknown = AnilistRelation.fromEdge(edge('NEWLY_INVENTED'));
      final other = AnilistRelation.fromEdge(edge('OTHER'));
      expect(unknown.rank, greaterThanOrEqualTo(other.rank));
    });

    test('every listed type has a distinct rank', () {
      final ranks = [
        for (final t in AnilistRelation.order)
          AnilistRelation.fromEdge(edge(t)).rank,
      ];
      expect(ranks.toSet().length, ranks.length);
    });
  });
}
