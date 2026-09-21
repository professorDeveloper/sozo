// A six-hundred-chapter list is a scrollbar and a guess.
//
// The reader's chapter sheet was flat: six hundred identical rows, and the only
// way to reach chapter 300 was to drag until the numbers looked right. Grouping
// gives it a spine — but only where the source's own labels support one, and
// never by renumbering anything.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/manga/domain/reading/chapter_groups.dart';

EpisodeEntity ch(String label, [int number = 0]) =>
    EpisodeEntity(episode: number, label: label, mediaRef: label);

void main() {
  group('reading a volume out of a label', () {
    test('the spellings sources actually use', () {
      expect(volumeOf('Vol. 4 Ch. 31'), 4);
      expect(volumeOf('Volume 12, Chapter 3'), 12);
      expect(volumeOf('vol 7 - the descent'), 7);
      expect(volumeOf('Tome 2 Chapitre 9'), 2);
    });

    test('and nothing else', () {
      // A looser pattern reads the "2" out of these and invents volumes
      // nobody wrote, which is worse than no grouping at all.
      expect(volumeOf('Chapter 31'), isNull);
      expect(volumeOf('Season 2 Episode 4'), isNull);
      expect(volumeOf('2 Broke Girls'), isNull);
      expect(volumeOf('Revolution 9'), isNull);
    });
  });

  group('grouping', () {
    test('a short list is left alone, with no heading', () {
      final groups = groupChapters([
        for (var i = 1; i <= 12; i++) ch('Ch $i', i),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.label, '');
      expect(groups.single.indices, hasLength(12));
    });

    test('a long list with volumes groups by volume', () {
      final chapters = [
        for (var v = 1; v <= 5; v++)
          for (var c = 1; c <= 10; c++) ch('Vol. $v Ch. ${(v - 1) * 10 + c}'),
      ];
      final groups = groupChapters(chapters);
      expect(groups.map((g) => g.volume).toList(), [1, 2, 3, 4, 5]);
      expect(groups.first.indices, hasLength(10));
      // The identity everything else in the reader is keyed on.
      expect(groups.last.indices.last, chapters.length - 1);
    });

    test('and a handful of volume labels is not a volume list', () {
      // A quarter of the chapters naming a volume means the list is not
      // organised by volume; grouping on it would put nearly everything in
      // one nameless bucket.
      final chapters = [
        for (var i = 1; i <= 50; i++) ch('Chapter $i', i),
        for (var i = 51; i <= 60; i++) ch('Vol. 1 Ch. $i', i),
      ];
      final groups = groupChapters(chapters);
      expect(groups.every((g) => g.volume == null), isTrue);
      expect(groups.length, greaterThan(1), reason: 'it fell back to ranges');
    });

    test('an unnumbered chapter gets its own heading, at the end', () {
      final chapters = [
        for (var v = 1; v <= 5; v++)
          for (var c = 1; c <= 10; c++) ch('Vol. $v Ch. $c'),
        ch('Extras'),
        ch('Omake'),
      ];
      final groups = groupChapters(chapters);
      expect(groups.last.volume, isNull);
      expect(groups.last.indices, hasLength(2));
    });

    test('a long list without volumes groups by range, named by number', () {
      final groups = groupChapters([
        for (var i = 1; i <= 120; i++) ch('Chapter $i', i),
      ]);
      expect(groups, hasLength(3));
      expect(groups[0].label, '1 – 50');
      expect(groups[1].label, '51 – 100');
      expect(groups[2].label, '101 – 120');
    });

    test('and every chapter lands in exactly one group', () {
      // The property that matters: grouping is a view, not an edit.
      final chapters = [for (var i = 1; i <= 237; i++) ch('Chapter $i', i)];
      final seen = <int>[];
      for (final g in groupChapters(chapters)) {
        seen.addAll(g.indices);
      }
      seen.sort();
      expect(seen, [for (var i = 0; i < 237; i++) i]);
    });

    test('a source that numbers nothing still gets readable headings', () {
      final groups = groupChapters([
        for (var i = 1; i <= 60; i++) ch('Chapter $i'),
      ]);
      expect(groups.first.label, '1 – 50');
    });
  });
}
