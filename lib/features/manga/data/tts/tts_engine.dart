import 'package:flutter/foundation.dart';

/// A voice as the platform lists it. [raw] is handed back verbatim to select
/// it, because each platform keys voices differently (Android by name and
/// locale, Apple by identifier).
class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    this.raw = const {},
  });

  final String name;
  final String locale;
  final Map<String, String> raw;

  /// Android lists a cloud twin of most voices; it stalls without a network.
  bool get isNetwork => name.toLowerCase().contains('network');

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// The speech engine the reader talks to, kept behind an interface so the
/// controller can be exercised without a platform channel.
abstract class TtsEngine {
  /// Whether there is an engine on this platform at all.
  bool get isSupported;

  /// Speaks [text] and completes when it has been spoken (true), or when it
  /// was stopped or failed (false).
  Future<bool> speak(String text);

  Future<void> stop();

  /// [multiplier] is the reader's own scale, 1.0 being normal speed.
  Future<void> setRate(double multiplier);

  Future<void> setPitch(double pitch);

  /// False when the engine has no voice for [lang].
  Future<bool> setLanguage(String lang);

  /// Null goes back to the engine's default voice for the language.
  Future<bool> setVoice(TtsVoice? voice);

  Future<List<TtsVoice>> voices();
}

/// The reader's speed multiplier in each engine's own units.
///
/// Android's plugin doubles what it is given (so 0.5 is normal), Windows adds
/// 0.5 to it, and AVSpeechSynthesizer's 0.5 is normal on a curve that is far
/// from linear — 0.7 is already roughly double.
double platformSpeechRate(
  double multiplier,
  TargetPlatform platform, {
  bool web = false,
}) {
  final m = multiplier.clamp(0.5, 2.0);
  if (web) return m;
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return m <= 1 ? 0.5 * m : 0.5 + (m - 1) * 0.2;
    case TargetPlatform.windows:
      return m - 0.5;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
      return m / 2;
  }
}
