import 'dart:ui' show Locale;

/// Where a voice search session stands. The dialog renders one of these and
/// never closes on a failure: every failure phase has something to say.
enum VoicePhase {
  starting,
  listening,

  /// Ended with a transcript; the dialog pops with [VoiceSearchState.words].
  done,
  noSpeech,
  permissionDenied,
  unavailable,
  network,
  recognizer,
}

class VoiceSearchState {
  const VoiceSearchState(this.phase, {this.words = '', this.lastError});

  static const VoiceSearchState initial = VoiceSearchState(VoicePhase.starting);

  final VoicePhase phase;
  final String words;

  /// A non-permanent error seen mid-session, used to explain an empty ending.
  final String? lastError;

  bool get isActive =>
      phase == VoicePhase.starting || phase == VoicePhase.listening;

  bool get isFailure => !isActive && phase != VoicePhase.done;

  /// Retrying cannot fix a device with no recogniser.
  bool get canRetry => isFailure && phase != VoicePhase.unavailable;

  @override
  bool operator ==(Object other) =>
      other is VoiceSearchState &&
      other.phase == phase &&
      other.words == words &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(phase, words, lastError);

  @override
  String toString() => 'VoiceSearchState($phase, "$words", $lastError)';
}

/// The session's transitions, kept free of the plugin so they can be tested.
abstract final class VoiceSearchMachine {
  static VoiceSearchState retry() => VoiceSearchState.initial;

  static VoiceSearchState initFailed({required bool hasPermission}) =>
      VoiceSearchState(
        hasPermission ? VoicePhase.unavailable : VoicePhase.permissionDenied,
      );

  static VoiceSearchState listenFailed({required bool hasPermission}) =>
      VoiceSearchState(
        hasPermission ? VoicePhase.recognizer : VoicePhase.permissionDenied,
      );

  static VoiceSearchState listeningStarted(VoiceSearchState s) =>
      s.phase == VoicePhase.starting
      ? VoiceSearchState(VoicePhase.listening, words: s.words)
      : s;

  static VoiceSearchState heard(
    VoiceSearchState s,
    String words, {
    bool isFinal = false,
  }) {
    if (!s.isActive) return s;
    final w = words.trim().isEmpty ? s.words : words.trim();
    if (isFinal) return _end(w, s.lastError);
    return VoiceSearchState(VoicePhase.listening, words: w);
  }

  /// The recogniser stopped by itself: silence, the time limit, or an error
  /// that did not call back.
  static VoiceSearchState ended(VoiceSearchState s) =>
      s.isActive ? _end(s.words, s.lastError) : s;

  /// The microphone never opened within the start deadline.
  static VoiceSearchState startTimedOut(VoiceSearchState s) =>
      s.phase == VoicePhase.starting
      ? const VoiceSearchState(VoicePhase.recognizer)
      : s;

  static VoiceSearchState error(
    VoiceSearchState s,
    String code, {
    required bool permanent,
  }) {
    if (!s.isActive) return s;
    if (!permanent) {
      return VoiceSearchState(s.phase, words: s.words, lastError: code);
    }
    return _end(s.words, code);
  }

  static VoiceSearchState _end(String words, String? error) {
    if (words.isNotEmpty) {
      return VoiceSearchState(VoicePhase.done, words: words);
    }
    return VoiceSearchState(
      error == null ? VoicePhase.noSpeech : phaseForError(error),
    );
  }

  static VoicePhase phaseForError(String code) {
    switch (code) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return VoicePhase.noSpeech;
      case 'error_permission':
      case 'error_insufficient_permissions':
        return VoicePhase.permissionDenied;
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_server_disconnected':
      case 'error_too_many_requests':
        return VoicePhase.network;
      case 'error_speech_recognizer_disabled':
        return VoicePhase.unavailable;
      default:
        return VoicePhase.recognizer;
    }
  }

  static bool isLanguageError(String code) =>
      code == 'error_language_not_supported' ||
      code == 'error_language_unavailable';
}

/// Picks the recogniser locale closest to the app's language, or null to let
/// the recogniser use the system locale.
///
/// [available] are recogniser ids as the plugin reports them (`en_US` on
/// Android, `en-US` on iOS). The system locale wins among same-language
/// candidates, since it carries the user's own region.
String? matchSpeechLocale(
  Locale app,
  Iterable<String> available, {
  String? systemLocaleId,
}) {
  final candidates = available.toList();
  if (candidates.isEmpty) return null;
  final langs = _languageAliases[app.languageCode.toLowerCase()] ??
      {app.languageCode.toLowerCase()};

  bool sameLanguage(String id) {
    final parts = _split(id);
    if (langs.contains(parts.$1)) return true;
    // Cantonese is often listed as Chinese for Hong Kong or Macau.
    return app.languageCode == 'yue' &&
        parts.$1 == 'zh' &&
        (parts.$2 == 'hk' || parts.$2 == 'mo');
  }

  final matches = candidates.where(sameLanguage).toList();
  if (matches.isEmpty) return null;

  final country = app.countryCode?.toLowerCase();
  if (country != null && country.isNotEmpty) {
    for (final id in matches) {
      if (_split(id).$2 == country) return id;
    }
  }
  if (systemLocaleId != null) {
    final system = _normalise(systemLocaleId);
    for (final id in matches) {
      if (_normalise(id) == system) return id;
    }
  }
  final preferred = _preferredRegion[app.languageCode.toLowerCase()];
  if (preferred != null) {
    for (final id in matches) {
      if (_split(id).$2 == preferred) return id;
    }
  }
  return matches.first;
}

/// Older Android and some recognisers use legacy or alternate codes.
const Map<String, Set<String>> _languageAliases = {
  'id': {'id', 'in'},
  'yue': {'yue'},
  'ckb': {'ckb'},
  'ku': {'ku', 'kmr'},
};

/// The region the app's copy is written for, when the language has several.
const Map<String, String> _preferredRegion = {
  'en': 'us',
  'pt': 'br',
  'es': 'es',
  'fr': 'fr',
  'de': 'de',
  'nl': 'nl',
  'ar': 'sa',
  'ru': 'ru',
  'uz': 'uz',
  'tr': 'tr',
  'hi': 'in',
  'id': 'id',
  'vi': 'vn',
  'yue': 'hk',
};

String _normalise(String id) => id.replaceAll('_', '-').toLowerCase();

/// Language and region of an id like `en_US`, `en-US` or `yue-Hant-HK`.
(String, String?) _split(String id) {
  final parts = _normalise(id).split('-');
  String? region;
  for (final p in parts.skip(1)) {
    if (p.length == 2 || (p.length == 3 && int.tryParse(p) != null)) {
      region = p;
      break;
    }
  }
  return (parts.first, region);
}
