import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_index.dart';

void main() {
  _sortingTests();
  _ecosystemTests();

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
  });
}

void _ecosystemTests() {
  group('SourceEcosystem', () {
    test('reads the runtime off the provider id', () {
      expect(SourceEcosystem.of('cs:HDHub4U'), SourceEcosystem.cloudstream);
      expect(SourceEcosystem.of('an:9163675745699695675'), SourceEcosystem.aniyomi);
      expect(SourceEcosystem.of('mn:2499283573021220255'), SourceEcosystem.manga);
      expect(SourceEcosystem.of('my:abc'), SourceEcosystem.mangayomi);
    });

    test('anything without a prefix is one of ours', () {
      expect(SourceEcosystem.of('vidapi'), SourceEcosystem.sozo);
      expect(SourceEcosystem.of('anilibria'), SourceEcosystem.sozo);
      expect(SourceEcosystem.of(''), SourceEcosystem.sozo);
    });

    test('a name that merely contains a prefix is not matched', () {
      // The prefix has to start the id. "answers" begins with "an" but not
      // with "an:", and filing it under Aniyomi would hide one of ours.
      expect(SourceEcosystem.of('answers'), SourceEcosystem.sozo);
      expect(SourceEcosystem.of('mycima'), SourceEcosystem.sozo);
    });
  });
}
