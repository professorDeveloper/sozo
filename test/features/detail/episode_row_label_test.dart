import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/presentation/pages/episodes_page.dart';

/// Sources routinely name every entry after its own number — "Episode 12",
/// "12-qism", "Серия 12" — so the row read "12  Episode 12": the same fact
/// twice, in a list where vertical space is the scarce thing.
///
/// The regex is duplicated here rather than exported, because what is being
/// pinned down is the RULE, and a test that imports the implementation of the
/// rule cannot catch the rule changing.
final RegExp redundant = RegExp(
  // Two orders, because languages differ on which comes first:
  //   "Episode 12", "Серия 12", "حلقة 12"   — word then number
  //   "12-qism", "12-bo'lim", "12 серия"     — number then word
  r'^\s*(?:'
  r'(?:episode|episodio|ep|серия|серія|qism|bo[ʻ’\x27]?lim|فصل|حلقة)'
  r'\s*[.:\-]?\s*0*(\d+)'
  r'|'
  r'0*(\d+)\s*[.:\-]?\s*'
  r'(?:episode|episodio|ep|серия|серія|qism|bo[ʻ’\x27]?lim|فصل|حلقة)'
  r')\s*$',
  caseSensitive: false,
);

bool isRedundant(String label, int episode) {
  final m = redundant.firstMatch(label.trim());
  if (m == null) return false;
  return int.tryParse(m.group(1) ?? m.group(2) ?? '') == episode;
}

EpisodeEntity ep(String label, int number) =>
    EpisodeEntity(episode: number, label: label, mediaRef: 'x');

void main() {
  group('the page itself applies the rule', () {
    // The rule had these tests and the page still crashed on half of them:
    // the regex has one group per alternative, and the page read only the
    // first with a `!`. A label like "12-qism" therefore threw during build,
    // which takes the whole episode list down rather than one row's title —
    // reported from idub as a blank screen.
    for (final label in ['12-qism', '12 серия', '12 Episode', "12-bo'lim"]) {
      test('"\$label" is dropped without throwing', () {
        expect(episodeRowTitle(ep(label, 12)), '');
      });
    }

    test('a real title survives', () {
      expect(episodeRowTitle(ep('Marineford', 12)), 'Marineford');
    });

    test('a label naming another number survives', () {
      expect(episodeRowTitle(ep('12-qism', 3)), '12-qism');
    });

    test('an empty label is empty', () {
      expect(episodeRowTitle(ep('   ', 1)), '');
    });
  });

  group('a label that only repeats the number is dropped', () {
    for (final label in [
      'Episode 12', 'episode 12', 'EPISODE 12', 'Ep 12', 'Ep. 12', 'Ep: 12',
      'Episode 012', '12-qism', "12-bo'lim", '12-boʻlim', 'Серия 12',
      'Episodio 12', 'حلقة 12', '12 серия', '12 Episode', '12. qism',
    ]) {
      test('"$label"', () => expect(isRedundant(label, 12), isTrue));
    }
  });

  group('a real title is kept', () {
    for (final label in [
      'Episode 12: Marineford',
      'Marineford',
      'The One Where They Fight',
      'Episode 12 - The End',
      '12 Angry Men',
    ]) {
      test('"$label"', () => expect(isRedundant(label, 12), isFalse));
    }
  });

  test('a label naming a DIFFERENT number is kept', () {
    // "Episode 3" on row 12 is a numbering mismatch worth seeing, not noise.
    expect(isRedundant('Episode 3', 12), isFalse);
  });

  test('an empty label is not matched by the rule', () {
    // It is handled before the rule runs; the rule itself must not claim it.
    expect(redundant.hasMatch(''), isFalse);
  });
}
