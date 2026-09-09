import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/extensions/source_language.dart';

void main() {
  group('langMatches', () {
    test('no selection shows everything — the shipped default', () {
      // The one case that must not regress: a user who never opens the filter
      // has to see the list exactly as it was before the filter existed.
      for (final lang in ['en', 'fr', 'all', '', 'pt-BR']) {
        expect(langMatches(lang, const []), true, reason: lang);
      }
    });

    test('a selection keeps its own languages', () {
      expect(langMatches('fr', const ['fr']), true);
      expect(langMatches('en', const ['fr']), false);
      expect(langMatches('es', const ['fr', 'es']), true);
    });

    test('case and padding do not make a different language', () {
      expect(langMatches(' PT-BR ', const ['pt-br']), true);
      expect(langMatches('pt-br', const ['PT-BR']), true);
    });

    test('`all` and untagged always pass', () {
      // `all` is a source that is not language-specific. Untagged is the
      // ecosystem declining to say — CloudStream repos that omit `language` —
      // and hiding those would empty the list for the users most likely to
      // be filtering.
      expect(langMatches('all', const ['fr']), true);
      expect(langMatches('', const ['fr']), true);
    });
  });

  group('langRank', () {
    test('with no preference the old hard-coded order is reproduced', () {
      // en → all → rest, which is what every host did before the preference
      // existed. Existing installs must not see their picker reshuffle.
      expect(langRank('en', const []) < langRank('all', const []), true);
      expect(langRank('all', const []) < langRank('fr', const []), true);
    });

    test('the user order wins, and it is an order not a set', () {
      expect(langRank('fr', const ['fr', 'en']) < langRank('en', const ['fr', 'en']), true);
      expect(langRank('en', const ['en', 'fr']) < langRank('fr', const ['en', 'fr']), true);
    });

    test('a selected language beats `all`, which beats an unselected one', () {
      const prefs = ['fr'];
      expect(langRank('fr', prefs) < langRank('all', prefs), true);
      expect(langRank('all', prefs) < langRank('de', prefs), true);
    });

    test('English is not privileged once the user has said otherwise', () {
      // The whole point. A French user asked for French MangaDex; before this
      // the English entry held the name and every other language was dropped.
      const prefs = ['fr'];
      expect(langRank('fr', prefs) < langRank('en', prefs), true);
    });
  });

  group('orderedLanguages', () {
    test('selections first in their own order, then all, then alphabetical', () {
      final out = orderedLanguages(
        const ['en', 'fr', 'all', 'de', 'es'],
        const ['fr', 'es'],
      );
      expect(out, ['fr', 'es', 'all', 'de', 'en']);
    });

    test('a selected language survives even with nothing installed for it', () {
      // Otherwise the chip the user just tapped vanishes from the row it lives
      // in the moment it empties the list, and there is no way back.
      expect(orderedLanguages(const ['en'], const ['fr']), ['fr', 'en']);
    });

    test('duplicates and casing collapse, blanks are dropped', () {
      expect(
        orderedLanguages(const ['EN', 'en', ' en ', '', 'fr'], const []),
        ['en', 'fr'],
      );
    });
  });

  group('labels', () {
    test('known codes get a name, unknown ones get themselves', () {
      expect(labelFor('fr'), 'French');
      expect(labelFor('pt-BR'), 'Portuguese (BR)');
      // A lookup, not a whitelist: a language nobody listed is merely less
      // pretty, never missing.
      expect(labelFor('kk'), 'KK');
      expect(labelFor(''), '');
    });

    test('the row badge is the bare code', () {
      expect(shortLabelFor('pt-br'), 'PT-BR');
      expect(shortLabelFor('fr'), 'FR');
    });
  });
}
