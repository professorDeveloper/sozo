/// How an encrypted stream is unlocked.
///
/// ## Why this exists at all
///
/// Most of what Sozo plays is unencrypted, and everything below is dead weight
/// for those streams — which is why [DrmConfig] is optional everywhere and a
/// null one changes nothing about how playback works.
///
/// It exists for the streams that are not: DASH channels whose segments are
/// CENC-encrypted. libmpv cannot decrypt those at all, so no amount of work on
/// the media_kit path reaches them; ExoPlayer can, through Android's own
/// MediaDrm. That is the whole reason there is a third playback backend.
///
/// ## Scope
///
/// Android only, and deliberately. iOS encrypts with FairPlay, which needs an
/// application certificate issued to a specific vendor by Apple and a licence
/// server that speaks SPC/CKC — none of which is a code change. Advertising a
/// DRM stream on iOS and failing at the licence request would be worse than
/// not offering it, so [isSupported] is the gate and the UI asks it before it
/// offers anything.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// The content-protection systems this app can actually satisfy.
enum DrmScheme {
  /// The keys travel with the stream description — no licence server, no
  /// device identity, nothing to negotiate. Common for live channels whose
  /// operator wants segments unreadable off a CDN listing rather than genuine
  /// rights management, and the only scheme that works with no infrastructure
  /// on our side at all.
  clearKey('clearkey'),

  /// Google Widevine. Needs a licence server; the device proves itself with
  /// MediaDrm and gets keys back per session.
  widevine('widevine'),

  /// Microsoft PlayReady. Supported by ExoPlayer where the device has the
  /// module, which on most phones sold outside a handful of markets it does
  /// not — so this is offered, not promised.
  playReady('playready');

  const DrmScheme(this.id);

  /// Stable string crossing the platform channel and, eventually, the wire.
  /// Never rename: a stored or served value outlives the enum.
  final String id;

  static DrmScheme? fromId(String? id) {
    if (id == null) return null;
    final needle = id.trim().toLowerCase();
    for (final s in DrmScheme.values) {
      if (s.id == needle) return s;
    }
    // The two spellings the wild uses for the same thing.
    if (needle == 'clear-key' || needle == 'org.w3.clearkey') {
      return DrmScheme.clearKey;
    }
    if (needle == 'com.widevine.alpha') return DrmScheme.widevine;
    if (needle == 'com.microsoft.playready') return DrmScheme.playReady;
    return null;
  }
}

/// Everything the decrypting backend needs, and nothing it does not.
@immutable
class DrmConfig {
  const DrmConfig({
    required this.scheme,
    this.licenseUrl = '',
    this.licenseHeaders = const {},
    this.clearKeys = const {},
    this.multiSession = false,
  });

  final DrmScheme scheme;

  /// Where to ask for keys. Empty for [DrmScheme.clearKey], which carries them.
  final String licenseUrl;

  /// Sent with the licence request. Some operators gate their licence server on
  /// a token or a referer exactly as their CDN gates the segments, and a
  /// licence request without them comes back 403 while the manifest loads fine
  /// — which presents as "the video is black" and nothing else.
  final Map<String, String> licenseHeaders;

  /// ClearKey material as `kid: key`, both **hex**.
  ///
  /// Hex rather than the base64url the EME JSON form uses, because hex is how
  /// these are published, pasted and pasted again. Converting once here beats
  /// having every caller guess which encoding a given channel wrote its key in.
  final Map<String, String> clearKeys;

  /// Whether each period needs its own licence. Off by default: it costs a
  /// round trip per period, and only some live packagers require it.
  final bool multiSession;

  /// Whether this device can play DRM at all.
  ///
  /// Asked before a DRM source is offered rather than after it fails. A
  /// "playback error" on a stream the platform was never going to decrypt is
  /// indistinguishable to the viewer from a dead link, and they will retry it
  /// forever.
  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// True when there is enough here to attempt playback.
  ///
  /// A config that is present but unusable is worse than none: it routes the
  /// stream to the DRM backend, which then fails, instead of letting the normal
  /// player have a go at a stream that may not have needed decrypting.
  bool get isUsable => switch (scheme) {
        DrmScheme.clearKey => clearKeys.isNotEmpty,
        DrmScheme.widevine || DrmScheme.playReady => licenseUrl.isNotEmpty,
      };

  /// Parses the shape the backend serves. Null when there is no DRM on this
  /// stream, or when what is there cannot be used.
  ///
  /// Tolerant on purpose about where the keys live — `clearKeys`, `keys`, and a
  /// bare `kid:key` string all turn up in the channel lists these come from,
  /// and rejecting a stream over punctuation helps nobody.
  static DrmConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final scheme = DrmScheme.fromId(json['scheme'] as String?);
    if (scheme == null) return null;

    final config = DrmConfig(
      scheme: scheme,
      licenseUrl: (json['licenseUrl'] as String? ?? '').trim(),
      licenseHeaders: _stringMap(json['licenseHeaders']),
      clearKeys: _keys(json['clearKeys'] ?? json['keys']),
      multiSession: json['multiSession'] == true,
    );
    return config.isUsable ? config : null;
  }

  Map<String, dynamic> toMap() => {
        'scheme': scheme.id,
        'licenseUrl': licenseUrl,
        'licenseHeaders': licenseHeaders,
        'clearKeys': clearKeys,
        'multiSession': multiSession,
      };

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
  }

  /// `{kid: key}` from a map, or from the `kid:key` pairs people write by hand.
  static Map<String, String> _keys(Object? raw) {
    if (raw is Map) return _stringMap(raw);
    if (raw is String) {
      final out = <String, String>{};
      for (final pair in raw.split(RegExp(r'[,\s]+'))) {
        final parts = pair.split(':');
        if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          out[parts[0].trim()] = parts[1].trim();
        }
      }
      return out;
    }
    if (raw is List) {
      final out = <String, String>{};
      for (final entry in raw) {
        if (entry is Map) {
          final kid = (entry['kid'] ?? entry['keyId'])?.toString();
          final key = (entry['key'] ?? entry['k'])?.toString();
          if (kid != null && key != null) out[kid] = key;
        }
      }
      return out;
    }
    return const {};
  }

  @override
  bool operator ==(Object other) =>
      other is DrmConfig &&
      other.scheme == scheme &&
      other.licenseUrl == licenseUrl &&
      other.multiSession == multiSession &&
      mapEquals(other.licenseHeaders, licenseHeaders) &&
      mapEquals(other.clearKeys, clearKeys);

  @override
  int get hashCode => Object.hash(
        scheme,
        licenseUrl,
        multiSession,
        Object.hashAllUnordered(licenseHeaders.entries.map((e) => e.key)),
        Object.hashAllUnordered(clearKeys.keys),
      );

  /// Deliberately never prints key material — this ends up in the diagnostics
  /// log the player already writes, and a log someone pastes into a bug report
  /// must not be a way to hand out someone's content keys.
  @override
  String toString() => 'DrmConfig(${scheme.id}, '
      'license: ${licenseUrl.isEmpty ? 'none' : 'set'}, '
      'keys: ${clearKeys.length})';
}
