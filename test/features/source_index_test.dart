import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/sources/domain/source_index.dart';

void main() {
  _sortingTests();

  group('indexLetterOf', () {
    test('uppercases the first Latin letter', () {
      expect(indexLetterOf('animepahe'), 'A');
      expect(indexLetterOf('KissKH'), 'K');
    });

    test('leading whitespace does not decide the bucket', () {
      expect(indexLetterOf('  Zoro'), 'Z');
    });

    test('anything outside A-Z shares one bucket', () {
      // Digits, punctuation and every non-Latin script. A chip per script is
      // longer than the list it indexes.
      expect(indexLetterOf('4KHDHub'), '#');
      expect(indexLetterOf('.hack'), '#');
      expect(indexLetterOf('Аниме'), '#');
      expect(indexLetterOf('アニメ'), '#');
      expect(indexLetterOf(''), '#');
      expect(indexLetterOf('   '), '#');
    });
  });

  group('indexLetters', () {
    test('one chip per run, in the list order', () {
      expect(
        indexLetters(['A', 'A', 'B', 'C', 'C', 'C']),
        ['A', 'B', 'C'],
      );
    });

    test('a letter that comes back later gets its own chip', () {
      // Not a set: these lists are sorted by the ecosystem, not by us, and a
      // set would merge the two runs into one chip that jumps to the first.
      expect(indexLetters(['A', 'B', 'A']), ['A', 'B', 'A']);
    });

    test('empty in, empty out', () {
      expect(indexLetters(const []), isEmpty);
    });
  });
}

void _sortingTests() {
  group('compareForIndex', () {
    test('sorts A–Z, case-insensitively', () {
      final names = ['Zoro', 'animepahe', 'MangaDex', 'bato'];
      names.sort(compareForIndex);
      expect(names, ['animepahe', 'bato', 'MangaDex', 'Zoro']);
    });

    test('files everything outside A–Z last, as one block', () {
      final names = ['360资源', 'Zoro', '9kMovies', 'Anime'];
      names.sort(compareForIndex);
      expect(names.first, 'Anime');
      expect(names[1], 'Zoro');
      expect(names.sublist(2).toSet(), {'360资源', '9kMovies'});
    });

    test('a sorted list collapses to one chip per letter', () {
      final names = ['Anime', 'AsilMedia', 'Bato', 'Zoro'];
      names.sort(compareForIndex);
      expect(indexLetters(names.map(indexLetterOf)), ['A', 'B', 'Z']);
    });
  });
}
