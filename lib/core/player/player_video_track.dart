/// One selectable video rendition the ENGINE reports, as opposed to a mirror
/// the provider listed.
///
/// The difference matters and the player used to have no word for it. A
/// provider's "quality" entries are separate URLs on separate hosts; switching
/// between them tears down the stream and starts a new one. An HLS variant is a
/// different rendition inside the SAME stream, and the engine can move between
/// them without a reload — which is what "quality" means in every other player
/// people use.
///
/// mpv reports these on `stream.tracks.video`, which the app subscribed to and
/// then discarded, reading only the audio half. `video_player` cannot report
/// them at all: ExoPlayer selects renditions internally and the plugin exposes
/// no API for it — there, adaptive selection IS the behaviour and there is no
/// list to show.
class PlayerVideoTrack {
  const PlayerVideoTrack({
    required this.id,
    this.width,
    this.height,
    this.bitrate,
    this.codec,
    this.ordinal = 1,
  });

  /// Backend-specific handle, passed straight back to `setVideoTrack`.
  final String id;

  final int? width;
  final int? height;

  /// Bits per second, when the manifest declared one.
  final int? bitrate;

  final String? codec;

  /// 1-based position in the list. Used only to label a track the manifest
  /// described with nothing at all.
  final int ordinal;

  /// Whether this is the engine choosing for itself.
  ///
  /// mpv exposes it as the literal track id `auto`, and it is the one entry
  /// that must survive filtering — it is the default, and the only way back to
  /// adaptive once somebody has pinned a rendition.
  bool get isAuto => id == 'auto';

  /// True when the manifest said something usable about this rendition.
  bool get hasMetadata => (height != null && height! > 0) || bitrate != null;

  /// `1080p`, or null when the height is unknown.
  String? get resolutionLabel {
    final h = height;
    if (h == null || h <= 0) return null;
    return switch (h) {
      >= 2000 => '4K',
      >= 1400 => '1440p',
      >= 1000 => '1080p',
      >= 700 => '720p',
      >= 460 => '480p',
      >= 300 => '360p',
      _ => '${h}p',
    };
  }

  /// `4.2 Mbps`, or null when the manifest declared no bitrate.
  String? get bitrateLabel {
    final b = bitrate;
    if (b == null || b <= 0) return null;
    if (b >= 1000000) return '${(b / 1000000).toStringAsFixed(1)} Mbps';
    return '${(b / 1000).round()} kbps';
  }

  /// What a row in the quality list says.
  ///
  /// Never the bare [id]: a list reading "1" and "2" is indistinguishable from
  /// a bug, which is the same rule [PlayerAudioTrack.label] follows.
  String get label {
    final res = resolutionLabel;
    if (res != null) return res;
    final rate = bitrateLabel;
    if (rate != null) return rate;
    return 'Auto $ordinal';
  }

  /// The second line: what [label] could not fit.
  String? get detail {
    final parts = <String>[];
    if (resolutionLabel != null && width != null && height != null) {
      parts.add('$width×$height');
    }
    final rate = bitrateLabel;
    if (rate != null && resolutionLabel != null) parts.add(rate);
    final c = codec?.trim();
    if (c != null && c.isNotEmpty) parts.add(c);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerVideoTrack &&
      other.id == id &&
      other.width == width &&
      other.height == height &&
      other.bitrate == bitrate &&
      other.codec == codec &&
      other.ordinal == ordinal;

  @override
  int get hashCode => Object.hash(id, width, height, bitrate, codec, ordinal);
}

/// Orders renditions the way a quality list should read.
///
/// Auto first — it is the default and the way back to adaptive — then by
/// height descending, then bitrate descending, so the best is nearest the top
/// and equal heights are broken by the stream that actually carries more data.
List<PlayerVideoTrack> sortVideoTracks(List<PlayerVideoTrack> tracks) {
  final out = [...tracks];
  out.sort((a, b) {
    if (a.isAuto != b.isAuto) return a.isAuto ? -1 : 1;
    final byHeight = (b.height ?? 0).compareTo(a.height ?? 0);
    if (byHeight != 0) return byHeight;
    return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
  });
  return out;
}
