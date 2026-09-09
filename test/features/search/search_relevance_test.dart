import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/domain/services/search_relevance.dart';

/// Every fixture in this file is a real response from the app's own backend,
/// captured while chasing "search doesn't work". The junk is not invented.
MovieEntity _m(String title, {int? year}) => MovieEntity(
      externalId: '${title.hashCode}',
      title: title,
      description: '',
      slug: '',
      url: 'https://example.test/${title.hashCode}',
      provider: 'p',
      thumbnail: null,
      year: year,
      rating: null,
      qualities: null,
      category: 'movie',
    );

List<MovieEntity> _all(List<String> titles) => [for (final t in titles) _m(t)];

void main() {
  group('score', () {
    test('the exact title wins outright', () {
      expect(SearchRelevance.score('Naruto', 'naruto'), 1.0);
      expect(SearchRelevance.score('naruto', 'Naruto'), 1.0);
    });

    test('punctuation and spacing do not change the answer', () {
      // Sources disagree about colons and macrons on the same show.
      expect(SearchRelevance.score('Naruto: Shippuden', 'naruto shippuden'), 1.0);
    });

    test('a title that starts with the query beats one that merely contains it',
        () {
      final starts = SearchRelevance.score('Naruto Shippuden', 'naruto');
      final contains =
          SearchRelevance.score('Boruto: Naruto Next Generations', 'naruto');
      expect(starts, greaterThan(contains));
      expect(contains, greaterThan(0));
    });

    test('scattered words score below a contiguous match', () {
      final contiguous = SearchRelevance.score('Attack on Titan', 'attack on titan');
      final scattered =
          SearchRelevance.score('Titan Attack Squad Recruits', 'attack on titan');
      expect(contiguous, greaterThan(scattered));
      expect(scattered, greaterThan(0));
    });

    test('a short query is not allowed to match inside a word', () {
      // "aot" returned 18 unrelated Uzbek films from the live backend, because
      // three letters land inside ordinary words in every language. Whatever
      // the source matched on, the title says nothing.
      expect(SearchRelevance.score("Bo'zqir", 'aot'), 0);
      expect(SearchRelevance.score('Moxir oshpaz', 'aot'), 0);
      // As a whole word it is a real match and still counts.
      expect(SearchRelevance.score('AOT Chronicles', 'aot'), greaterThan(0));
    });

    test('a longer query may match inside a word', () {
      // Four letters is enough evidence to be worth something, but less than a
      // whole-word hit.
      final inside = SearchRelevance.score('Narutopedia Guide', 'naruto');
      expect(inside, greaterThan(0));
    });

    test('an unrelated title scores nothing', () {
      expect(SearchRelevance.score('Learn To Draw APK', 'naruto'), 0);
    });

    test('a title in another alphabet is comparable, not discarded', () {
      expect(SearchRelevance.score('Бэтмен', 'бэтмен'), 1.0);
    });
  });

  group('rank', () {
    test('the real match comes first even when it arrived last', () {
      // anikai's live response for "naruto": spin-offs and films ahead of the
      // show itself.
      final ranked = SearchRelevance.rank(
        _all([
          'Naruto the Movie 2: Legend of the Stone of Gelel',
          'Boruto: Naruto Next Generations',
          'Naruto',
        ]),
        'naruto',
      );
      expect(ranked.first.title, 'Naruto');
    });

    test('junk sinks but is never dropped', () {
      // "Van Pis" is the Uzbek dub of One Piece and shares not one letter with
      // the query. It scores zero and is the best result in the set — which is
      // exactly why ranking must not become filtering.
      final ranked = SearchRelevance.rank(
        _all(['Learn To Draw APK', 'Van Pis', 'One Piece']),
        'one piece',
      );
      expect(ranked.first.title, 'One Piece');
      expect(ranked.map((m) => m.title), containsAll(['Van Pis', 'Learn To Draw APK']));
      expect(ranked, hasLength(3));
    });

    test('equal scores keep the source order', () {
      // These lists repaint as other legs land. A comparator that broke ties
      // arbitrarily would move a card out from under a finger already on its
      // way down to it.
      final titles = ['Naruto A', 'Naruto B', 'Naruto C'];
      final ranked = SearchRelevance.rank(_all(titles), 'naruto');
      expect(ranked.map((m) => m.title).toList(), titles);
    });

    test('browsing with no query is left exactly as the source ordered it', () {
      final titles = ['Third', 'First', 'Second'];
      final ranked = SearchRelevance.rank(_all(titles), '');
      expect(ranked.map((m) => m.title).toList(), titles);
    });
  });

  group('looksUnsearched', () {
    test('a full page with nothing matching is a catalogue dump', () {
      // The live response for "naruto" from the uzmovi provider.
      expect(
        SearchRelevance.looksUnsearched(
          _all([
            'Narkoz',
            'Hech narsa tasodif emas',
            "Hayotda hamma narsa bo'ladi",
            'Million dollarlik tuzoq',
            "Senga bo'lgan muhabbat",
            'Choson nikoh agentligi',
            'Yolg\'on hayot',
            'Qora qish',
          ]),
          'naruto',
        ),
        isTrue,
      );
    });

    test('one aliased match is not a dump', () {
      // The distinction the whole guard rests on: a source that searched and
      // found a differently-titled match returns one or two rows, never a full
      // page. Dropping these would delete the best answers in the app.
      expect(SearchRelevance.looksUnsearched(_all(['Van Pis']), 'one piece'),
          isFalse);
      expect(
        SearchRelevance.looksUnsearched(
          _all(['Van Pis', 'Learn To Draw APK']),
          'one piece',
        ),
        isFalse,
      );
    });

    test('a page that does match is left alone', () {
      // "batman" legitimately fills a page on the same provider that dumps its
      // catalogue for "naruto". Size alone must never be the trigger.
      expect(
        SearchRelevance.looksUnsearched(
          _all([
            'Batman: The Enemy Within',
            'Batman: Jimjitlik HD 2019',
            'Бэтмен (2022)',
            'Betmen: Batman Supermenga qarshi',
            'Batman Begins',
            'The Batman',
          ]),
          'batman',
        ),
        isFalse,
      );
    });

    test('a query with no scoreable words disables the guard', () {
      // Nothing can be scored, so the source's own order is a better answer
      // than rejecting everything it returned.
      expect(
        SearchRelevance.looksUnsearched(
          _all(['A', 'B', 'C', 'D', 'E', 'F', 'G']),
          '。。。',
        ),
        isFalse,
      );
    });

    test('an empty result is not a dump', () {
      expect(SearchRelevance.looksUnsearched(const [], 'naruto'), isFalse);
    });
  });
}
