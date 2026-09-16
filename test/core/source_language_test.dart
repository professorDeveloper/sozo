import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/extensions/source_language.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

ProviderEntity _p({
  String id = 'x',
  String name = 'X',
  String url = '',
  String lang = '',
}) => ProviderEntity(
  id: id,
  name: name,
  image: '',
  url: url,
  description: '',
  domains: const [],
  lang: lang,
);

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

  group('inferLang', () {
    test('a declaration is never second-guessed', () {
      // The whole point of the backend declaring `lang`: whatever the name or
      // the host suggests, the source's own answer is the answer.
      expect(
        inferLang(lang: 'en', name: 'VidAPI', id: 'vidapi', url: 'https://vidapi.ru'),
        'en',
      );
      expect(
        inferLang(lang: 'uz', name: 'Russian Dubs', id: 'x', url: 'https://x.fr'),
        'uz',
      );
      expect(
        inferLang(lang: ' PT-BR ', name: '', id: '', url: ''),
        'pt-br',
      );
    });

    test('a Sozo provider is never labelled by its domain', () {
      // vidapi.ru serves English and was called Russian in every source list
      // in the app. If a declaration ever goes missing the honest answer is
      // "we do not know", not the registrar's country: these providers can be
      // asked, so a guess about them is a guess nobody had to make.
      expect(
        inferLang(lang: '', name: 'VidAPI', id: 'vidapi', url: 'https://vidapi.ru'),
        null,
      );
      expect(
        inferLang(lang: '', name: 'Uzmovi', id: 'uzmovi', url: 'https://uzmovi.net'),
        null,
      );
    });

    test('an extension source on the same domain still is', () {
      // Nobody can go and ask a source in somebody else's repo, so the host is
      // the best evidence there is and it is better than nothing.
      expect(
        inferLang(lang: '', name: 'Anime', id: 'cs:12345', url: 'https://anime.ru'),
        'ru',
      );
      expect(
        inferLang(lang: '', name: 'Dizi', id: 'an:9', url: 'https://dizi.com.tr'),
        'tr',
      );
    });

    test('a name hint beats the host it is served from', () {
      // A French source on a .ru host is French. The name is the site telling
      // you; the TLD is where it happens to be hosted.
      expect(
        inferLang(lang: '', name: 'AnimeFrench', id: 'cs:1', url: 'https://a.ru'),
        'fr',
      );
      // Ordered longest-first so `hindisub` is not read as a bare `hi`.
      expect(
        inferLang(lang: '', name: 'HindiSubAnime', id: 'cs:2', url: 'https://a.de'),
        'hi',
      );
    });

    test('`all` is a declaration, not a language to infer past', () {
      // It must not be treated as an answer here — displayLang keeps it — but
      // it must not become a French source either just because of the host.
      expect(
        inferLang(lang: 'all', name: 'KissKH', id: 'kisskh', url: 'https://kisskh.co'),
        null,
      );
      // The case that actually bites: an extension source, which is the one
      // kind this function will guess about from a domain, declaring `all` on
      // a host the TLD table knows. Tachiyomi and Aniyomi repos ship `all`
      // constantly, so this is VidAPI-on-vidapi.ru one ecosystem over — badge
      // a multi-language catalogue `RU` because of where it is hosted.
      expect(
        inferLang(lang: 'all', name: 'Anime', id: 'cs:12345', url: 'https://anime.ru'),
        null,
      );
      // The name is not allowed to overrule it either. `all` is the source
      // telling you about its own contents; the word in its title is not.
      expect(
        inferLang(lang: 'ALL ', name: 'AnimeFrench', id: 'an:9', url: 'https://a.io'),
        null,
      );
    });

    test('nothing to go on returns null, and null is an answer', () {
      // Those sources are grouped under a heading that admits the gap rather
      // than hidden: guessing wrong and hiding is worse than saying so.
      expect(
        inferLang(lang: '', name: 'Streamer', id: 'cs:7', url: 'https://streamer.io'),
        null,
      );
      expect(inferLang(lang: '', name: '', id: '', url: ''), null);
    });
  });

  group('displayLang', () {
    // The one answer the providers page badges, the sources hub subtitles and
    // both of their filters test. They each had their own before, so a source
    // could be blank in one list, RU in the next and English in the third.
    test('is what the row shows and what the filter hides by', () {
      final vidapi = _p(id: 'vidapi', name: 'VidAPI', url: 'https://vidapi.ru', lang: 'en');
      expect(vidapi.displayLang, 'en');
      expect(langMatches(vidapi.displayLang, const ['ru']), false);
      expect(langMatches(vidapi.displayLang, const ['en']), true);
    });

    test('`all` survives as itself rather than being narrowed', () {
      // A catalogue that says it has no one language is not overruled by its
      // own name or host, and it belongs to every selection.
      final kisskh = _p(id: 'kisskh', name: 'KissKH', url: 'https://kisskh.co', lang: 'all');
      expect(kisskh.displayLang, kAllLanguages);
      expect(langMatches(kisskh.displayLang, const ['fr']), true);
    });

    test('empty when there is nothing to go on, which still passes a filter', () {
      final unknown = _p(id: 'cs:7', name: 'Streamer', url: 'https://streamer.io');
      expect(unknown.displayLang, '');
      expect(langMatches(unknown.displayLang, const ['fr']), true);
    });

    test('the four kinds of source each get one answer, everywhere', () {
      // The providers page badge, the sources hub subtitle and the quick
      // switch row all read this one getter now. The quick switch used to call
      // inferLang itself, and the `all` row below is where the two answers
      // parted company: `RU` in the sheet, `ALL` in the other two lists.
      final cloud = _p(id: 'vidapi', name: 'VidAPI', url: 'https://vidapi.ru', lang: 'en');
      final declared = _p(id: 'an:1', name: 'AnimeSama', url: 'https://anime-sama.fr', lang: 'fr');
      final everything = _p(id: 'cs:2', name: 'Anime', url: 'https://anime.ru', lang: 'all');
      final silent = _p(id: 'cs:3', name: 'Dizi', url: 'https://dizi.com.tr');

      expect(cloud.displayLang, 'en');
      expect(declared.displayLang, 'fr');
      expect(everything.displayLang, kAllLanguages);
      // Nobody can go and ask a source in somebody else's repo, so an
      // undeclared one is still guessed at from its host.
      expect(silent.displayLang, 'tr');

      // And the badge a row shows is the value its filter hides it by — the
      // property that makes the filter believable.
      for (final p in [cloud, declared, everything, silent]) {
        expect(langMatches(p.displayLang, const []), true, reason: p.id);
        expect(
          langMatches(p.displayLang, [p.displayLang]),
          true,
          reason: p.id,
        );
      }
      expect(langMatches(everything.displayLang, const ['ru']), true);
      expect(langMatches(cloud.displayLang, const ['ru']), false);
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
