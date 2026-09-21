// A Japanese title has to be able to match itself.
//
// `normalize()` kept Latin, Cyrillic and Arabic and deleted everything else, so
// a Japanese, Korean, Chinese, Thai, Greek or Hebrew title became the EMPTY
// STRING and scored zero against itself. On an app whose catalogue is largely
// Japanese that is not a ranking quirk — it is three separate failures:
//
//   * such a title sorts last in every search;
//   * `looksUnsearched` reads the zero as "the source ignored the query" and
//     DELETES the whole page;
//   * the weak-results banner is stapled over answers that were right.
//
// And the same whitelist in `normalizedTitleKey` produced an empty merge key,
// which the all-source merge skips outright — so those rows vanished from the
// list while the count still included them, and the page said "N results" over
// nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/search_relevance.dart';

MovieEntity movie(String title) => MovieEntity(
  externalId: title,
  title: title,
  description: '',
  slug: title,
  url: 'https://x/$title',
  provider: 'p',
  thumbnail: null,
  year: null,
  rating: null,
  qualities: null,
  category: 'anime',
);

ProviderSearchResult leg(String id, List<MovieEntity> items) =>
    ProviderSearchResult(
      provider: ProviderRef(
        id: id,
        name: id.toUpperCase(),
        kind: ProviderKind.server,
      ),
      items: items,
      status: ProviderSearchStatus.ok,
    );

void main() {
  const scripts = {
    'japanese': 'ナルト',
    'korean': '나루토',
    'chinese': '火影忍者',
    'greek': 'Νάρουτο',
    'hebrew': 'נארוטו',
    'thai': 'นารูโตะ',
  };

  group('a title survives normalisation', () {
    for (final entry in scripts.entries) {
      test('${entry.key} does not normalise to nothing', () {
        expect(SearchRelevance.normalize(entry.value), isNotEmpty);
      });
    }

    test('and scores 1.0 against itself', () {
      for (final title in scripts.values) {
        expect(
          SearchRelevance.score(title, title),
          1.0,
          reason: '$title could not match itself',
        );
      }
    });

    test('punctuation still goes', () {
      expect(SearchRelevance.normalize('ナルト！ (2002)'), 'ナルト 2002');
      expect(SearchRelevance.normalize('。。。'), '');
    });

    test('Latin behaviour is unchanged', () {
      expect(SearchRelevance.normalize('Attack on Titan!'), 'attack on titan');
      expect(SearchRelevance.score('Naruto', 'naruto'), 1.0);
    });
  });

  group('a page is only thrown away on evidence', () {
    final katakana = [for (var i = 0; i < 8; i++) movie('ナルト 第$i話')];

    test('a romaji query against native titles is not a dump', () {
      // Zero here means the two are written differently, not that the source
      // ignored the question. Sources routinely answer a romaji query with
      // native titles.
      expect(SearchRelevance.looksUnsearched(katakana, 'naruto'), isFalse);
    });

    test('and a native query against romaji titles is not either', () {
      final romaji = [for (var i = 0; i < 8; i++) movie('Bleach Episode $i')];
      expect(SearchRelevance.looksUnsearched(romaji, 'ナルト'), isFalse);
    });

    test('but a real catalogue dump still is', () {
      // Same script, nothing matching: that zero means something.
      final dump = [for (var i = 0; i < 8; i++) movie('Latest Upload $i')];
      expect(SearchRelevance.looksUnsearched(dump, 'naruto'), isTrue);
    });

    test('and a same-script page that DOES match is kept', () {
      final hit = [
        movie('Naruto Shippuden'),
        for (var i = 0; i < 7; i++) movie('Filler $i'),
      ];
      expect(SearchRelevance.looksUnsearched(hit, 'naruto'), isFalse);
    });

    test('a page of native titles for a native query is judged normally', () {
      final other = [for (var i = 0; i < 8; i++) movie('ブリーチ 第$i話')];
      expect(SearchRelevance.looksUnsearched(other, 'ナルト'), isTrue);
    });
  });

  group('scripts', () {
    test('are recognised apart', () {
      expect(SearchRelevance.scriptsOf('ナルト'), contains('kana'));
      expect(SearchRelevance.scriptsOf('火影忍者'), contains('han'));
      expect(SearchRelevance.scriptsOf('나루토'), contains('hangul'));
      expect(SearchRelevance.scriptsOf('Naruto'), contains('latin'));
      expect(SearchRelevance.scriptsOf('Наруто'), contains('cyrillic'));
    });

    test('and a mixed title carries both', () {
      // Common in the wild: "ナルト Naruto".
      final s = SearchRelevance.scriptsOf('ナルト Naruto');
      expect(s, containsAll(['kana', 'latin']));
    });

    test('digits and punctuation are not a script', () {
      expect(SearchRelevance.scriptsOf('2002 !!'), isEmpty);
    });
  });

  group('the all-source merge keeps them', () {
    test('a native title produces a usable key', () {
      expect(normalizedTitleKey('ナルト'), isNotEmpty);
      expect(normalizedTitleKey('나루토 (2002)'), isNotEmpty);
    });

    test('and the same title from two sources still merges into one row', () {
      final merged = mergeSearchResults([
        leg('a', [movie('ナルト')]),
        leg('b', [movie('ナルト')]),
      ]);
      expect(merged, hasLength(1));
      expect(merged.first.hits, hasLength(2));
    });

    test('a title that is only punctuation falls back to its raw text', () {
      // A row the viewer cannot see is worse than one that failed to merge.
      final merged = mergeSearchResults([
        leg('a', [movie('!!!')]),
      ]);
      expect(merged, hasLength(1));
    });
  });
}
