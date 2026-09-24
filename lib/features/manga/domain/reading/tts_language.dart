/// Which language to read a chapter in.
///
/// The source's declared language first, unless the text is plainly in a
/// script that language does not use: plenty of sources are tagged by the site
/// and serve a translation. Then the script on its own. Latin text with no
/// declaration is read as English, which is what an undeclared Latin novel
/// source almost always carries — the app's own locale is a worse guess there,
/// since an Uzbek or Turkish UI says nothing about the book.
String resolveTtsLanguage({required String? declared, required String sample}) {
  final lang = _base(declared);
  final script = detectScriptLanguage(sample);
  if (script == null) {
    return lang != null && !_nonLatin.containsKey(lang) ? lang : 'en';
  }
  if (script == 'ja') return 'ja';
  if (lang != null && _nonLatin[lang] == _nonLatin[script]) return lang;
  return script;
}

/// The language a non-Latin script most likely means, or null for Latin text
/// (and for text too short to say).
String? detectScriptLanguage(String sample) {
  final counts = <String, int>{};
  var letters = 0;
  for (final rune in sample.runes) {
    final s = _scriptOf(rune);
    if (s == null) continue;
    letters++;
    counts[s] = (counts[s] ?? 0) + 1;
    if (letters >= 600) break;
  }
  if (letters == 0) return null;
  // Kana anywhere means Japanese, even when Han characters outnumber it.
  if ((counts['ja'] ?? 0) > letters * 0.05) return 'ja';
  final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  if (top.key == 'latin' || top.value < letters * 0.3) return null;
  return top.key;
}

/// Whether a voice with [locale] (as the engine reports it: `en-US`, `en_US`,
/// `yue-HK`) speaks [lang].
bool voiceSpeaks(String locale, String lang) {
  final l = locale.toLowerCase().replaceAll('_', '-');
  final want = lang.toLowerCase();
  if (want == 'yue') {
    return l.startsWith('yue') || l == 'zh-hk' || l.startsWith('zh-hant-hk');
  }
  if (want == 'zh') {
    return (l == 'zh' || l.startsWith('zh-') || l.startsWith('cmn')) &&
        !l.contains('hk');
  }
  if (want == 'id' && (l == 'in' || l.startsWith('in-'))) return true;
  if (want == 'he' && (l == 'iw' || l.startsWith('iw-'))) return true;
  return l == want || l.startsWith('$want-');
}

String? _base(String? declared) {
  final d = declared?.trim().toLowerCase() ?? '';
  if (d.isEmpty || d == 'all' || d == 'multi') return null;
  if (d == 'zh-hk' || d == 'yue') return 'yue';
  return d.split(RegExp('[-_]')).first;
}

/// Non-Latin languages mapped to the script family they are written in.
const Map<String, String> _nonLatin = {
  'ru': 'cyr',
  'uk': 'cyr',
  'be': 'cyr',
  'bg': 'cyr',
  'sr': 'cyr',
  'mk': 'cyr',
  'kk': 'cyr',
  'ky': 'cyr',
  'mn': 'cyr',
  'tg': 'cyr',
  'ar': 'arab',
  'fa': 'arab',
  'ur': 'arab',
  'ps': 'arab',
  'zh': 'han',
  'yue': 'han',
  'ja': 'han',
  'ko': 'hang',
  'th': 'thai',
  'hi': 'deva',
  'mr': 'deva',
  'ne': 'deva',
  'he': 'hebr',
  'el': 'grek',
};

String? _scriptOf(int r) {
  if ((r >= 0x41 && r <= 0x5A) ||
      (r >= 0x61 && r <= 0x7A) ||
      (r >= 0xC0 && r <= 0x24F) ||
      (r >= 0x1E00 && r <= 0x1EFF)) {
    return 'latin';
  }
  if (r >= 0x0400 && r <= 0x052F) return 'ru';
  if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) {
    return 'ar';
  }
  if (r >= 0x3040 && r <= 0x30FF) return 'ja';
  if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) {
    return 'zh';
  }
  if ((r >= 0xAC00 && r <= 0xD7AF) || (r >= 0x1100 && r <= 0x11FF)) {
    return 'ko';
  }
  if (r >= 0x0E00 && r <= 0x0E7F) return 'th';
  if (r >= 0x0900 && r <= 0x097F) return 'hi';
  if (r >= 0x0590 && r <= 0x05FF) return 'he';
  if (r >= 0x0370 && r <= 0x03FF) return 'el';
  return null;
}
