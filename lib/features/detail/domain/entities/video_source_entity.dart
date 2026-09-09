import 'package:soplay/core/player/drm_config.dart';

class VideoSourceEntity {
  final String quality;
  final String videoUrl;
  final bool isDefault;
  final bool accessible;
  final bool useLocalProxy;
  final String? type;
  final Map<String, String> headers;
  final Map<String, dynamic> localProxy;
  final Map<String, dynamic> requestTransform;

  /// Vertical resolution, when the source stated one.
  final int? height;

  /// `h264`, `h265`, `av1`, or null when the label did not say.
  ///
  /// Worth surfacing because it is the commonest reason one stream plays and
  /// another does not on the same phone: H.264 decodes in hardware on every
  /// Android device shipped in the last decade, H.265 usually does, and
  /// "usually" is what produces the reports that a title works for one person
  /// and not the next.
  final String? codec;

  /// `dv`, `hdr10`, or null.
  ///
  /// Dolby Vision is tracked apart from HDR10 because the failure differs in
  /// kind: HDR10 on an SDR screen looks washed out but plays, while DV profile
  /// 5 on a decoder that cannot read it renders green or purple — which people
  /// report as the app being broken.
  final String? hdr;

  /// Whether the audio track is Atmos / E-AC3 JOC.
  ///
  /// ExoPlayer has no software decoder for it, so the picture plays and the
  /// sound is silent.
  final bool atmos;

  /// File size, when the label stated one.
  final int? sizeBytes;

  /// Which mirror serves this — "FSL Server", "10Gbps", "Pixeldrain".
  final String? mirror;

  /// What the source itself called this variant, before it was tidied.
  ///
  /// Kept so a bug report can quote the original rather than the app's
  /// rendering of it.
  final String? rawLabel;

  /// What is risky about this stream: `dolby-vision`, `atmos-audio`, `4k`,
  /// `large-file`, `indirect-host`, `unreachable-<code>`.
  ///
  /// The backend derives these; the app's job is to say them out loud rather
  /// than let somebody pick a 17 GB Dolby Vision remux and conclude the app
  /// cannot play video.
  final List<String> warnings;

  /// How to decrypt this stream, when it is encrypted.
  ///
  /// Null for almost everything, and that is the normal case — a null here
  /// means the stream plays on whichever engine the user chose. A non-null one
  /// overrides that choice, because encryption is not a preference: libmpv
  /// cannot decrypt CENC and `video_player` exposes no way to configure it, so
  /// there is exactly one backend that can play this at all.
  final DrmConfig? drm;

  const VideoSourceEntity({
    required this.quality,
    required this.videoUrl,
    required this.isDefault,
    required this.accessible,
    this.height,
    this.codec,
    this.hdr,
    this.atmos = false,
    this.sizeBytes,
    this.mirror,
    this.rawLabel,
    this.warnings = const [],
    this.useLocalProxy = false,
    this.type,
    this.headers = const {},
    this.localProxy = const {},
    this.requestTransform = const {},
    this.drm,
  });
}
