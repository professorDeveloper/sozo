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
