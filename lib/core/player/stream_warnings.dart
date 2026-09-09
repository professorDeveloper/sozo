import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

/// How risky a stream is, and why, in words somebody can act on.
///
/// ## Why this exists
///
/// A source page routinely offers the same film as a 17 GB 2160p Dolby Vision
/// remux with an Atmos track and as a 3 GB 1080p H.264 copy. The first is the
/// better file and the worse choice on a phone: DV profile 5 renders green on
/// a display that cannot read it, ExoPlayer has no decoder for E-AC3 JOC so
/// the sound is silent, and 17 GB over progressive HTTP never fills its
/// buffer on mobile data.
///
/// All three fail in ways that look like the APP being broken. Somebody who
/// picks the top entry and gets a green screen does not conclude "wrong file
/// for this device" — they conclude Sozo cannot play video, and they are not
/// wrong to, because nothing on screen said otherwise.
///
/// The backend already works this out and ships a `warnings` list per source.
/// This turns it into a line and a colour.
enum StreamRisk {
  /// Will probably not play correctly here.
  blocking,

  /// Will play, but something about it is worth knowing first.
  caution,
}

@immutable
class StreamWarning {
  const StreamWarning({
    required this.code,
    required this.risk,
    required this.icon,
  });

  final String code;
  final StreamRisk risk;
  final IconData icon;

  String get message => 'stream_warning.$code'.tr();

  /// Everything worth saying about a source, worst first.
  ///
  /// Unknown codes are dropped rather than shown raw: the backend may add one
  /// before the app knows the string for it, and an untranslated
  /// `unreachable-503` on screen is worse than one fewer line.
  static List<StreamWarning> forSource(VideoSourceEntity source) {
    final out = <StreamWarning>[];
    for (final code in source.warnings) {
      final known = _known[code];
      if (known != null) {
        out.add(known);
        continue;
      }
      // The unreachable codes carry an HTTP status, so they are a family
      // rather than a fixed string.
      if (code.startsWith('unreachable')) out.add(_unreachable);
    }
    out.sort((a, b) => a.risk.index.compareTo(b.risk.index));
    return out;
  }

  /// The single worst thing about a source, for a one-line summary.
  static StreamWarning? worst(VideoSourceEntity source) {
    final all = forSource(source);
    return all.isEmpty ? null : all.first;
  }

  static const _unreachable = StreamWarning(
    code: 'unreachable',
    risk: StreamRisk.blocking,
    icon: Icons.link_off_rounded,
  );

  static const Map<String, StreamWarning> _known = {
    'dolby-vision': StreamWarning(
      code: 'dolby_vision',
      risk: StreamRisk.blocking,
      icon: Icons.hdr_on_rounded,
    ),
    'atmos-audio': StreamWarning(
      code: 'atmos',
      risk: StreamRisk.blocking,
      icon: Icons.volume_off_rounded,
    ),
    'indirect-host': StreamWarning(
      code: 'indirect_host',
      risk: StreamRisk.blocking,
      icon: Icons.open_in_new_rounded,
    ),
    '4k': StreamWarning(
      code: 'uhd',
      risk: StreamRisk.caution,
      icon: Icons.four_k_rounded,
    ),
    'large-file': StreamWarning(
      code: 'large_file',
      risk: StreamRisk.caution,
      icon: Icons.sd_storage_rounded,
    ),
  };
}

/// A human size, or null when the source did not state one.
String? formatStreamSize(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  const gb = 1000000000;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / 1000000).round()} MB';
}
