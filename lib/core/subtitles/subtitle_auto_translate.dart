/// Whether to translate this episode's subtitles without being asked, and what
/// to reach for first.
///
/// Settings → Player has carried an "Auto translate" switch for some time. It
/// was written to Hive and read back by the settings screen, and nothing else
/// ever read it: the player only translated when somebody tapped the menu
/// entry. A switch that persists its own state and changes nothing is worse
/// than a missing feature — the viewer believes they have turned something on.
///
/// ## Ready first, quota second
///
/// Two different things can satisfy "give me this in my language":
///
///   * a translation somebody has already published for this episode, which is
///     a download and costs nothing;
///   * a fresh one, which spends a slice of the account's daily allowance.
///
/// So the first is tried whether or not the switch is on — it is free, and a
/// viewer with no subtitles in their language is unambiguously better off with
/// one. Spending the allowance is what the switch actually authorises. Getting
/// that order wrong burns somebody's daily limit on an episode that was already
/// translated and sitting there.
///
/// Pure: flags and labels in, a decision out. No Flutter, no getIt, no I/O.
library;

/// What the player should do about subtitles for the episode just loaded.
enum AutoTranslateAction {
  /// Leave it alone — already suitable, unsupported, or already handled.
  none,

  /// Load a translation somebody else has already published. Free.
  loadReady,

  /// Translate it now, against the account's daily allowance.
  translateNow,
}

abstract final class SubtitleAutoTranslate {
  /// What to do, given what is on hand.
  ///
  /// [alreadyRan] is per episode, not per session: an episode whose auto
  /// attempt failed must not be retried on every subtitle reload, and one that
  /// succeeded must not be translated twice — but the next episode is a fresh
  /// question.
  static AutoTranslateAction decide({
    required bool enabled,
    required bool isLive,
    required bool alreadyRan,
    required bool hasTargetTrack,
    required bool hasReadyTranslation,
  }) {
    if (alreadyRan) return AutoTranslateAction.none;
    // A live channel has no fixed subtitle file to translate — there is nothing
    // to send and nothing to cache against.
    if (isLive) return AutoTranslateAction.none;
    // Already readable. Translating over the top would replace a human
    // subtitle with a machine one, which is a downgrade, not a service.
    if (hasTargetTrack) return AutoTranslateAction.none;
    if (hasReadyTranslation) return AutoTranslateAction.loadReady;
    return enabled ? AutoTranslateAction.translateNow : AutoTranslateAction.none;
  }

  /// Whether a subtitle track already reads in [code].
  ///
  /// Tracks arrive labelled by whoever published them: `English`, `eng`,
  /// `en-US`, `O'zbekcha [AI]`, `Русский (forced)`. There is no code on the
  /// entity to compare, only that label, so this matches the label against both
  /// the code and the language's own name — and anchors on word boundaries,
  /// because a substring test makes `Indonesian` match `id` and `Korean` match
  /// `ko` in half the titles that carry either.
  static bool labelMatchesLanguage(String label, String code) {
    final needle = code.trim().toLowerCase();
    if (needle.isEmpty) return false;
    final hay = label.toLowerCase();

    for (final word in _wordsOf(hay)) {
      if (word == needle) return true;
      // `en-US`, `pt_BR`: the region is a variant of the same language.
      final dash = word.indexOf(RegExp('[-_]'));
      if (dash > 0 && word.substring(0, dash) == needle) return true;
      final three = _threeLetter[word];
      if (three != null && three == needle) return true;
    }

    final native = _nativeNames[needle];
    if (native != null) {
      for (final name in native) {
        if (hay.contains(name)) return true;
      }
    }
    return false;
  }

  /// Whether any of [labels] already reads in [code].
  static bool anyMatches(Iterable<String> labels, String code) {
    for (final l in labels) {
      if (labelMatchesLanguage(l, code)) return true;
    }
    return false;
  }

  static Iterable<String> _wordsOf(String s) =>
      s.split(RegExp(r'[^a-z0-9_-]+')).where((w) => w.isNotEmpty);

  /// The three-letter codes subtitle sites use, mapped to two-letter ones.
  static const Map<String, String> _threeLetter = {
    'eng': 'en', 'rus': 'ru', 'spa': 'es', 'fra': 'fr', 'fre': 'fr',
    'deu': 'de', 'ger': 'de', 'ita': 'it', 'por': 'pt', 'jpn': 'ja',
    'kor': 'ko', 'zho': 'zh', 'chi': 'zh', 'ara': 'ar', 'tur': 'tr',
    'ukr': 'uk', 'nld': 'nl', 'dut': 'nl', 'pol': 'pl', 'ind': 'id',
    'uzb': 'uz',
  };

  /// What each language is called, in English and in itself. Lower-case, and
  /// matched as a substring — these are names, not codes, so a label like
  /// `Brazilian Portuguese` should still count as Portuguese.
  static const Map<String, List<String>> _nativeNames = {
    'uz': ["o'zbek", 'ozbek', 'uzbek', 'узбек'],
    'ru': ['русск', 'russian'],
    'en': ['english', 'английск'],
    'tr': ['türkçe', 'turkce', 'turkish'],
    'ar': ['العربية', 'arabic'],
    'de': ['deutsch', 'german'],
    'fr': ['français', 'francais', 'french'],
    'es': ['español', 'espanol', 'spanish'],
    'it': ['italiano', 'italian'],
    'pt': ['português', 'portugues', 'portuguese'],
    'nl': ['nederlands', 'dutch'],
    'pl': ['polski', 'polish'],
    'uk': ['українськ', 'ukrainian'],
    'id': ['indonesia', 'indonesian'],
    'ja': ['日本語', 'japanese'],
    'ko': ['한국어', 'korean'],
    'zh': ['中文', 'chinese'],
  };
}
