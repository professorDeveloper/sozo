import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/matching/title_match.dart';

/// One row of the real ranking a source switcher produced.
///
/// [score] is asserted to three decimal places on purpose. The band alone
/// would let the numbers drift until the next accident sits one thousandth
/// under [TitleMatch.floor], and the numbers are what this file is for: every
/// figure in `title_match.dart`'s documentation is checked here, so the prose
/// cannot quietly become a description of something else.
class _Row {
  const _Row(this.candidate, this.score, this.confidence, {this.usable = true});

  final String candidate;
  final double score;
  final TitleConfidence confidence;

  /// Whether the app would show this row at all.
  final bool usable;
}

void _expectRows(String query, List<_Row> rows) {
  for (final row in rows) {
    final m = TitleMatch.of(query: query, candidate: row.candidate);
    expect(
      double.parse(m.score.toStringAsFixed(3)),
      row.score,
      reason: '"$query" vs "${row.candidate}"',
    );
    expect(
      m.confidence,
      row.confidence,
      reason: '"$query" vs "${row.candidate}" scored ${m.score}',
    );
    expect(
      m.isUsable,
      row.usable,
      reason: '"$query" vs "${row.candidate}" scored ${m.score}',
    );
  }
}

void main() {
  group('the screenshot', () {
    // Six sources answered "Return of the Blossoming Blade". Four of them
    // answered with a different show, and the old formula put three of those
    // above 0.6 because it divided by the shorter title.
    test('only the real answers survive', () {
      _expectRows('Return of the Blossoming Blade', const [
        _Row(
          'Return of the Blossoming Blade',
          1.000,
          TitleConfidence.exact,
        ),
        _Row('Return', 0.316, TitleConfidence.weak, usable: false),
        _Row(
          'Blade of the Immortal',
          0.223,
          TitleConfidence.weak,
          usable: false,
        ),
        _Row('K: Return of Kings', 0.277, TitleConfidence.weak, usable: false),
        _Row(
          'Aladdin The Return of Jafar (1994) Movie Hindi Dubbed Download',
          0.245,
          TitleConfidence.weak,
          usable: false,
        ),
        _Row(
          'The Lord of the Rings: The Return of the King',
          0.259,
          TitleConfidence.weak,
          usable: false,
        ),
      ]);
    });

    test('a source that drops the subtitle is still the same show', () {
      _expectRows('Return of the Blossoming Blade', const [
        _Row('Blossoming Blade', 0.684, TitleConfidence.strong),
      ]);
    });
  });

  group('the matches that must not be lost', () {
    test('an Uzbek listing answers an English query', () {
      // The noise list is the whole reason this works; without it the two
      // titles share one word out of five.
      expect(
        TitleMatch.normalise('Naruto Shippuden (Uzbek tilida) barcha qismlar'),
        'naruto shippuden',
      );
      _expectRows('Naruto', const [
        _Row(
          'Naruto Shippuden Uzbek tilida barcha qismlar',
          0.829,
          TitleConfidence.strong,
        ),
      ]);
    });

    test('a season suffix is strong, and deliberately not exact', () {
      _expectRows('Jujutsu Kaisen', const [
        _Row('Jujutsu Kaisen 2nd Season', 0.94, TitleConfidence.strong),
      ]);
      _expectRows('Solo Leveling', const [
        _Row(
          'Solo Leveling Season 2: Arise from the Shadow',
          0.940,
          TitleConfidence.strong,
        ),
      ]);
    });

    test('spacing is not a difference', () {
      _expectRows('Dandadan', const [
        _Row('Dan Da Dan', 1.000, TitleConfidence.exact),
      ]);
    });

    test('a title made only of small words does not collapse to zero', () {
      _expectRows('The Who', const [
        _Row('The Who', 1.000, TitleConfidence.exact),
      ]);
    });

    test('a missing article is the same title', () {
      _expectRows('The Lord of the Rings', const [
        _Row('Lord of the Rings', 1.000, TitleConfidence.exact),
      ]);
    });

    test('a bracketed year is decoration, not a word', () {
      _expectRows('IT', const [_Row('IT (2017)', 1.000, TitleConfidence.exact)]);
    });

    test('a respelt word is the same word', () {
      // The reason character similarity survives at all, and the only place it
      // is allowed to act.
      _expectRows('Naruto Shippuden', const [
        _Row('Naruto Shippuuden', 0.855, TitleConfidence.strong),
      ]);
    });

    test('a non-Latin title can match itself', () {
      // It could not before: the normaliser kept Latin and Cyrillic and deleted
      // everything else, so both sides became the empty string.
      _expectRows('進撃の巨人', const [
        _Row('進撃の巨人', 1.000, TitleConfidence.exact),
      ]);
    });
  });

  group('a catalogue name against a source name', () {
    // The direction the app actually runs in, and the one the first version of
    // this scorer got backwards. AniList and TMDB hand over the long canonical
    // title; a source carries the short one. Scored against the whole query
    // these all fell under the floor and were thrown away — which turned one
    // wrong list into an empty page saying no source has the title.
    test('a source that carries only the head is the same show', () {
      _expectRows('Bleach: Thousand-Year Blood War', const [
        _Row('Bleach', 0.940, TitleConfidence.strong),
      ]);
      _expectRows('Spider-Man: Across the Spider-Verse', const [
        _Row('Spider-Man', 0.940, TitleConfidence.strong),
      ]);
      _expectRows('Demon Slayer: Kimetsu no Yaiba', const [
        _Row('Demon Slayer', 0.940, TitleConfidence.strong),
      ]);
      _expectRows('Fate/stay night: Unlimited Blade Works', const [
        _Row('Fate stay night', 0.940, TitleConfidence.strong),
      ]);
    });

    test('matching the head is never called exact', () {
      // It got there by dropping a subtitle, and a dropped subtitle is how
      // somebody who has finished a show is opened into its first episode.
      final m = TitleMatch.of(
        query: 'Attack on Titan: Final Season',
        candidate: 'Attack on Titan',
      );
      expect(m.confidence, TitleConfidence.strong);
      expect(m.score, lessThan(TitleMatch.exactAt));
    });

    test('the head only exists where a separator does', () {
      // The guarantee that this cannot resurrect the screenshot. "Return of the
      // Blossoming Blade" has no colon, so "Return" is still measured against
      // the whole title and still rejected.
      _expectRows('Return of the Blossoming Blade', const [
        _Row('Return', 0.316, TitleConfidence.weak, usable: false),
      ]);
    });

    test('a tail word is not a head', () {
      _expectRows('Bleach: Thousand-Year Blood War', const [
        _Row('Blood', 0.192, TitleConfidence.weak, usable: false),
        _Row('Naruto', 0.000, TitleConfidence.weak, usable: false),
      ]);
    });
  });

  group('words that are only sometimes decoration', () {
    // Stripping these as whole words from both sides scored two different
    // films as a perfect match, which is worse than scoring them badly: exact
    // is the band the app acts on without asking anyone.
    test('a season word without a number stays in the title', () {
      _expectRows('Season of the Witch', const [
        _Row('The Witch', 0.459, TitleConfidence.weak),
      ]);
      _expectRows('Sub Zero', const [
        _Row('Zero', 0.571, TitleConfidence.weak),
      ]);
    });

    test('a season word with a number is decoration', () {
      expect(
        TitleMatch.normalise('Jujutsu Kaisen 2nd Season'),
        'jujutsu kaisen',
      );
      expect(TitleMatch.normalise('Solo Leveling Season 2'), 'solo leveling');
    });
  });

  group('the near misses that must be rejected', () {
    test('a shared common word is not a match', () {
      _expectRows('One Piece', const [
        _Row('One Punch Man', 0.293, TitleConfidence.weak, usable: false),
        _Row('One Piece', 1.000, TitleConfidence.exact),
      ]);
    });

    test('an unrelated show shares nothing', () {
      _expectRows('Frieren', const [
        _Row('Bleach', 0.000, TitleConfidence.weak, usable: false),
      ]);
    });

    test('two seasons of one show are offered, not trusted', () {
      _expectRows('Naruto 2', const [
        _Row('Naruto 3', 0.528, TitleConfidence.weak),
      ]);
    });
  });

  group('the year', () {
    test('a year that disagrees caps the match at weak', () {
      final m = TitleMatch.of(
        query: 'Hunter x Hunter',
        candidate: 'Hunter x Hunter',
        queryYear: 1999,
        candidateYear: 2011,
      );
      expect(m.confidence, TitleConfidence.weak);
      // Demoted below every agreeing match, and no further. Halving it deleted
      // correct answers outright: anything under 0.80 fell through the floor,
      // which is not the cap this is meant to be.
      expect(m.score, lessThan(TitleMatch.strongAt));
      expect(m.isUsable, isTrue, reason: 'a disagreeing year must not delete it');
      expect(m.isTrustworthy, isFalse);
    });

    test('a year that agrees nudges the score and leaves the band alone', () {
      final m = TitleMatch.of(
        query: 'Jujutsu Kaisen',
        candidate: 'Jujutsu Kaisen 2nd Season',
        queryYear: 2020,
        candidateYear: 2020,
      );
      // Strong rather than exact: the two titles are only identical once a
      // season number has been taken off one of them, and two seasons of one
      // show are not the same title.
      expect(m.confidence, TitleConfidence.strong);
      // The agreeing year still nudges the score for ordering — that is its
      // whole job — so this asserts the BAND, which the nudge must not move.
      expect(m.score, greaterThan(TitleMatch.strongAt));
    });

    test('a year is read from the candidate title when it carries one', () {
      expect(TitleMatch.yearIn('Aladdin The Return of Jafar (1994)'), 1994);
      // Not a release year — part of the name.
      expect(TitleMatch.yearIn('Blade Runner 2049'), isNull);
    });
  });

  group('best', () {
    test('picks the highest and rejects a field of near misses', () {
      const rows = ['Return', 'K: Return of Kings', 'Blade of the Immortal'];
      expect(
        TitleMatch.best(
          rows,
          query: 'Return of the Blossoming Blade',
          titleOf: (r) => r,
        ),
        isNull,
      );
      final picked = TitleMatch.best(
        [...rows, 'Return of the Blossoming Blade'],
        query: 'Return of the Blossoming Blade',
        titleOf: (r) => r,
      );
      expect(picked?.$1, 'Return of the Blossoming Blade');
      expect(picked?.$2.confidence, TitleConfidence.exact);
    });

    test('a tie keeps the first row', () {
      final picked = TitleMatch.best(
        const ['Frieren', 'Frieren'],
        query: 'Frieren',
        titleOf: (r) => r,
      );
      expect(identical(picked?.$1, 'Frieren'), isTrue);
    });

    test('an empty field and an empty query are null, not a crash', () {
      expect(
        TitleMatch.best(const <String>[], query: 'Frieren', titleOf: (r) => r),
        isNull,
      );
      expect(
        TitleMatch.of(query: '   ', candidate: 'Frieren').score,
        TitleMatch.none.score,
      );
    });
  });

  group('normalise', () {
    test('noise words go as whole words, never as substrings', () {
      // The substring version turned "Subaru" into "aru".
      expect(TitleMatch.normalise('Subaru'), 'subaru');
      // And a whole-word list is still too blunt for words that are only
      // sometimes decoration: stripping "Serial" scored Serial Experiments Lain
      // against "Lain Experiments" as a perfect match, and stripping "Season"
      // did the same to Season of the Witch against The Witch.
      expect(
        TitleMatch.normalise('Serial Experiments Lain'),
        'serial experiments lain',
      );
      expect(TitleMatch.normalise('Season of the Witch'), 'season of the witch');
      // A season NUMBER is decoration in every title that carries one.
      expect(TitleMatch.normalise('Jujutsu Kaisen 2nd Season'), 'jujutsu kaisen');
      expect(TitleMatch.normalise('Solo Leveling Season 2'), 'solo leveling');
    });

    test('a title that is entirely decoration keeps its words', () {
      expect(TitleMatch.normalise('Dubbed'), 'dubbed');
    });

    test("o'zbekcha and ozbekcha are one word", () {
      expect(TitleMatch.normalise("Naruto (O'zbekcha tarjima)"), 'naruto');
    });
  });
}
