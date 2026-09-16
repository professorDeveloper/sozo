/// One place for "what language is this source, and does the user want it".
///
/// The four extension ecosystems each tag their sources with a language and
/// each then threw that away in its own manner: the Kotlin hosts and
/// [MangayomiBridge] collapsed same-named sources down to one entry with a
/// hard-coded `English → all → anything else` ranking, and the picker never
/// parsed the field at all. The result was that a French user could install a
/// repo carrying fourteen French anime sources and be shown none of them.
///
/// Nothing here enumerates the world's languages. The codes come from whatever
/// the installed repos actually publish, which is the only list that is ever
/// correct — a repo that adds Kazakh tomorrow needs no app change. [labelFor]
/// is a display courtesy, not a gate: an unknown code renders as itself.
library;

import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

/// A source tagged with this belongs to every language selection rather than
/// to none. Both Tachiyomi-family ecosystems use the literal string.
const String kAllLanguages = 'all';

/// `pt-BR`, `pt-br` and ` PT-BR ` are one language.
String normalizeLang(String lang) => lang.trim().toLowerCase();

/// Whether a source tagged [lang] should be shown to someone who selected
/// [selected].
///
/// An empty selection means "no preference", and no-preference shows
/// everything — this is the shipped default, so a user who never opens the
/// filter sees exactly the list they saw before it existed.
bool langMatches(String lang, List<String> selected) {
  if (selected.isEmpty) return true;
  final key = normalizeLang(lang);
  // `all` and untagged both pass. Untagged is not a claim that the source is
  // in no language, it is the ecosystem declining to say — CloudStream's lazy
  // metadata carries no language — and hiding those would empty the list for
  // the users most likely to be filtering.
  if (key.isEmpty || key == kAllLanguages) return true;
  return selected.any((s) => normalizeLang(s) == key);
}

/// Sort key for choosing ONE source when several share a name.
///
/// Lower wins. The user's own order is honoured first — a user who lists
/// `fr, en` gets the French MangaDex, one who lists `en, fr` gets the English
/// one — then `all`, then everything else. With no selection this reproduces
/// the previous hard-coded behaviour exactly, English first, which is what
/// keeps existing installs looking unchanged.
int langRank(String lang, List<String> preferred) {
  final key = normalizeLang(lang);
  for (var i = 0; i < preferred.length; i++) {
    if (normalizeLang(preferred[i]) == key) return i;
  }
  final base = preferred.length;
  if (preferred.isEmpty && key == 'en') return base;
  if (key == kAllLanguages) return base + 1;
  return base + 2;
}

/// Every language present in [langs], ordered the way the filter row shows
/// them: the user's selections first in their own order, then `all`, then the
/// rest alphabetically.
///
/// Built from the data on purpose. The alternative — a fixed list of "supported
/// languages" — is wrong the moment a repo ships a language it does not contain
/// and misleading the moment one drops a language it does.
List<String> orderedLanguages(Iterable<String> langs, List<String> preferred) {
  final seen = <String>{};
  for (final l in langs) {
    final key = normalizeLang(l);
    if (key.isNotEmpty) seen.add(key);
  }
  final out = <String>[];
  for (final p in preferred) {
    final key = normalizeLang(p);
    // Kept even when nothing installed carries it any more, so a selection the
    // user made cannot silently vanish from the row it lives in.
    if (key.isNotEmpty && !out.contains(key)) out.add(key);
  }
  if (seen.remove(kAllLanguages) && !out.contains(kAllLanguages)) {
    out.add(kAllLanguages);
  }
  final rest = seen.where((l) => !out.contains(l)).toList()..sort();
  return [...out, ...rest];
}

/// English names for the codes the extension repos actually publish today.
///
/// A lookup, not a whitelist: [labelFor] falls back to the code in upper case,
/// so an unlisted language is merely less pretty and never missing. Endonyms
/// are deliberately avoided — the row is scanned, not read, and a user hunting
/// for French finds "French" faster next to "Spanish" than "Français" next to
/// "Español" in a UI that is otherwise in Uzbek.
const Map<String, String> _names = {
  kAllLanguages: 'All languages',
  'ar': 'Arabic',
  'bn': 'Bengali',
  'ca': 'Catalan',
  'cs': 'Czech',
  'de': 'German',
  'el': 'Greek',
  'en': 'English',
  'es': 'Spanish',
  'es-419': 'Spanish (LatAm)',
  'fa': 'Persian',
  'fi': 'Finnish',
  'fil': 'Filipino',
  'fr': 'French',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hu': 'Hungarian',
  'id': 'Indonesian',
  'it': 'Italian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'ml': 'Malayalam',
  'mr': 'Marathi',
  'ms': 'Malay',
  'my': 'Burmese',
  'nl': 'Dutch',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'pt-br': 'Portuguese (BR)',
  'ro': 'Romanian',
  'ru': 'Russian',
  'sq': 'Albanian',
  'sr': 'Serbian',
  'sv': 'Swedish',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'uz': 'Uzbek',
  'vi': 'Vietnamese',
  'zh': 'Chinese',
  'zh-hans': 'Chinese (Simplified)',
  'zh-hant': 'Chinese (Traditional)',
};

String labelFor(String lang) {
  final key = normalizeLang(lang);
  if (key.isEmpty) return '';
  return _names[key] ?? key.toUpperCase();
}

/// Short form for the chip drawn on a source's row — `FR`, `PT-BR`, `ALL`.
String shortLabelFor(String lang) => normalizeLang(lang).toUpperCase();

/// The language a source is in, when it did not say.
///
/// Roughly half the sources in a Watch tab declare nothing — CloudStream's lazy
/// metadata carries no language. Filtering by language was letting all of those
/// through, so picking English barely shortened the list; the filter looked
/// broken because it had nothing to match against.
///
/// Sozo's own cloud providers used to be in that half and no longer are: the
/// backend declares `lang` per provider now, so they take the first line below
/// and never reach the guessing at all. That is the arrangement this function
/// wants — every guess here is a source nobody could ask.
///
/// Most of them do say, just not in the field: `HindiSubAnime`, `animefr`,
/// `.ru`, `.com.tr`. This reads the name, the id and the host. It returns null
/// when there is genuinely nothing to go on, and null is an answer — those
/// sources are grouped rather than hidden, because guessing wrong and hiding is
/// worse than admitting the gap.
String? inferLang({
  required String lang,
  required String name,
  required String id,
  required String url,
}) {
  final declared = normalizeLang(lang);
  if (declared.isNotEmpty) {
    // `all` is a declaration too, and the guesses below would overrule it: an
    // `all` catalogue served from a `.ru` domain is not a Russian source, and
    // one called `AnimeFrench` is not a French one. Tachiyomi and Aniyomi repos
    // hand `all` out freely, so falling through to the guessing here was the
    // VidAPI bug waiting in a second ecosystem. It is not a language to hand
    // back either — this function answers "which language", and the honest
    // answer for a catalogue that says it has no one language is the same null
    // it returns when it will not guess. [ProviderLanguage.displayLang], which
    // is how every screen asks, keeps `all` as itself.
    return declared == kAllLanguages ? null : declared;
  }

  final haystack = '$name $id'.toLowerCase();
  for (final entry in _nameHints.entries) {
    if (haystack.contains(entry.key)) return entry.value;
  }

  // A domain says where a site is hosted, not what it speaks. For the
  // extension ecosystems it is still the best guess there is, and the only one:
  // an `an:`/`cs:`/`mn:` id is a source in somebody else's repo that nobody
  // here can go and ask. Sozo's own providers can be asked, and were guessed at
  // wrongly for as long as they were not — VidAPI on vidapi.ru serves English
  // and was labelled Russian — so their bare ids are excluded from the guess
  // even if a declaration ever goes missing.
  if (id.contains(':')) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    for (final entry in _tldHints.entries) {
      if (host.endsWith(entry.key)) return entry.value;
    }
  }
  return null;
}

/// Words that appear in source names and mean a language. Ordered longest-first
/// where one contains another, so `hindisub` is not read as `hi`.
const Map<String, String> _nameHints = {
  'portugu': 'pt',
  'brasil': 'pt',
  'espanol': 'es',
  'español': 'es',
  'spanish': 'es',
  'castellano': 'es',
  'latino': 'es',
  'french': 'fr',
  'francais': 'fr',
  'français': 'fr',
  'german': 'de',
  'deutsch': 'de',
  'italian': 'it',
  'italiano': 'it',
  'russian': 'ru',
  'russkij': 'ru',
  'turkce': 'tr',
  'türkçe': 'tr',
  'turkish': 'tr',
  'arabic': 'ar',
  'عربي': 'ar',
  'hindi': 'hi',
  'indone': 'id',
  'vietnam': 'vi',
  'thai': 'th',
  'chinese': 'zh',
  'japan': 'ja',
  'korean': 'ko',
  'polski': 'pl',
  'polish': 'pl',
  'persian': 'fa',
  'farsi': 'fa',
  'uzbek': 'uz',
};

/// A host that ends in one of these is almost always in that language. Only
/// codes where the mapping is unambiguous: `.tv` and `.io` say nothing, and
/// `.ar` is Argentina rather than Arabic.
const Map<String, String> _tldHints = {
  '.ru': 'ru',
  '.ua': 'ru',
  '.tr': 'tr',
  '.fr': 'fr',
  '.es': 'es',
  '.mx': 'es',
  '.it': 'it',
  '.de': 'de',
  '.br': 'pt',
  '.pt': 'pt',
  '.pl': 'pl',
  '.uz': 'uz',
  '.id': 'id',
  '.vn': 'vi',
  '.th': 'th',
  '.cn': 'zh',
  '.jp': 'ja',
  '.kr': 'ko',
  '.ir': 'fa',
};

/// The one language answer every screen shows, counts and filters on.
///
/// Three screens used to answer the question three different ways: the
/// providers page badged the raw `lang`, the sources hub put the raw `lang` in
/// a row's subtitle, and the quick switcher ran [inferLang]. So one source
/// could be unlabelled in one list, `RU` in the next and English in the third,
/// and — worse — the providers page hid rows by a value it never displayed. A
/// filter is only believable when the label it hides a row by is the label the
/// row was showing.
extension ProviderLanguage on ProviderEntity {
  /// Empty when there is nothing to go on at all, which is the same thing an
  /// undeclared language has always meant here: the chip, the badge and the
  /// tally all skip it, and [langMatches] lets it through rather than hiding a
  /// source nobody can vouch for.
  ///
  /// `all` survives as itself. It is a declaration — this catalogue has no one
  /// language — and inferring a narrower answer from the name or the host would
  /// be overruling the source about its own contents.
  String get displayLang => isAllLanguages
      ? kAllLanguages
      : inferLang(lang: lang, name: name, id: id, url: url) ?? '';
}
