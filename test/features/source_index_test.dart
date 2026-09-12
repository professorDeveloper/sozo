import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/sources/domain/source_index.dart';

void main() {
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
