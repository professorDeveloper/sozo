/// Why playback stopped, as a value rather than a sentence.
///
/// The player used to decide what had gone wrong and how to say it in the same
/// breath, and it said it in English: `_humanizeError` returned four hardcoded
/// strings, and three more were written inline at their throw sites. Sozo ships
/// in Uzbek, English, Russian and Arabic, so for three of its four audiences a
/// failed episode ended in a language they had not chosen — in the one place
/// where a user most needs to understand what to do next.
///
/// Splitting the two makes both jobs testable. Classification is a pure
/// function over the engine's raw message, with no `.tr()` in reach; rendering
/// is a lookup in the widget layer, where localisation belongs.
///
/// Deliberately no Flutter import here — a test asserts that.
library;

/// The kinds of failure the player distinguishes.
///
/// Coarse on purpose. These are not error codes; they are the distinct things
/// a viewer can be told, and each one implies different advice. Two raw
/// messages that lead to the same sentence belong to the same kind.
enum PlaybackFaultKind {
  /// The device cannot decode this stream — wrong profile, wrong codec.
  /// Another quality usually plays.
  decoder('player.fault.decoder'),

  /// The container or format is not supported at all. Distinct from [decoder]
  /// because retrying the same file cannot help; the browser might.
  unsupportedFormat('player.fault.unsupported_format'),

  /// The host refused or the file would not open. Often a blocked referer
  /// rather than anything wrong with the device.
  sourceBlocked('player.fault.source_blocked'),

  /// The stream could not be fetched. The connection is the first suspect.
  network('player.fault.network'),

  /// The resolve produced no playable source for this episode.
  noSourceForEpisode('player.fault.no_source'),

  /// A source was chosen but carried no url.
  emptyUrl('player.fault.empty_url'),

  /// The native player never came up. Restarting the app is the only fix, and
  /// saying so is more use than any description of the fault.
  engineUnavailable('player.fault.engine_unavailable'),

  /// Something failed that does not fit above. The raw message is shown, since
  /// an untranslated detail beats a translated non-answer.
  unknown('player.fault.unknown');

  const PlaybackFaultKind(this.messageKey);

  /// The translation key the view renders. Held here rather than in a switch at
  /// the call site so a new kind cannot be added without one.
  final String messageKey;
}

/// A classified failure, with the engine's own words kept alongside.
class PlaybackFault {
  const PlaybackFault(this.kind, {this.raw = ''});

  final PlaybackFaultKind kind;

  /// What the engine said. Never shown as the whole message except for
  /// [PlaybackFaultKind.unknown]; kept regardless so a bug report can quote it.
  final String raw;

  /// What went wrong, from the engine's message.
  ///
  /// The substrings are the ones the player already matched on, unchanged: they
  /// were arrived at from real failures across ExoPlayer, AVFoundation and
  /// libmpv, and rewriting them would be inventing new behaviour under cover of
  /// a refactor.
  static PlaybackFault classify(String raw) {
    if (raw.trim().isEmpty) return const PlaybackFault(PlaybackFaultKind.unknown);
    final lower = raw.toLowerCase();

    // Checked before the generic decoder match: these are AVFoundation's way of
    // saying the format is unsupported outright, and "try another quality" is
    // the wrong advice for them.
    if (lower.contains('cannot decode') ||
        lower.contains('-12906') ||
        lower.contains('-12939') ||
        lower.contains('coremediaerror')) {
      return PlaybackFault(PlaybackFaultKind.unsupportedFormat, raw: raw);
    }
    if (lower.contains('mediacodec') ||
        lower.contains('decoder') ||
        lower.contains('renderer')) {
      return PlaybackFault(PlaybackFaultKind.decoder, raw: raw);
    }
    if (lower.contains('source error') ||
        lower.contains('unrecognizedinputformat') ||
        lower.contains('nodeclaredbrand')) {
      return PlaybackFault(PlaybackFaultKind.sourceBlocked, raw: raw);
    }
    if (lower.contains('http data source')) {
      return PlaybackFault(PlaybackFaultKind.network, raw: raw);
    }
    return PlaybackFault(PlaybackFaultKind.unknown, raw: raw);
  }

  /// Whether the device cannot play this stream as encoded, so the browser is
  /// the honest suggestion rather than another retry.
  bool get isCodecFault =>
      kind == PlaybackFaultKind.decoder ||
      kind == PlaybackFaultKind.unsupportedFormat;

  String get messageKey => kind.messageKey;

  @override
  String toString() => 'PlaybackFault(${kind.name}, raw: $raw)';
}
