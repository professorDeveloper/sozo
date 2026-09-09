import 'package:soplay/core/player/drm_config.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

class VideoSourceModel extends VideoSourceEntity {
  const VideoSourceModel({
    required super.quality,
    required super.videoUrl,
    required super.isDefault,
    required super.accessible,
    super.height,
    super.codec,
    super.hdr,
    super.atmos,
    super.sizeBytes,
    super.mirror,
    super.rawLabel,
    super.warnings,
    super.useLocalProxy,
    super.type,
    super.headers,
    super.localProxy,
    super.requestTransform,
    super.drm,
  });

  factory VideoSourceModel.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type'] as String?;
    return VideoSourceModel(
      quality: json['quality'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      accessible: json['accessible'] as bool? ?? false,
      // All optional and all absent from older providers, so every one falls
      // back to "not stated" rather than to a guess — a source that does not
      // say it is Dolby Vision must not be labelled as anything.
      height: (json['height'] as num?)?.toInt(),
      codec: _nonEmpty(json['codec'] as String?),
      hdr: _nonEmpty(json['hdr'] as String?),
      atmos: json['atmos'] as bool? ?? false,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      mirror: _nonEmpty(json['mirror'] as String?),
      rawLabel: _nonEmpty(json['rawLabel'] as String?),
      warnings: _stringList(json['warnings']),
      useLocalProxy: json['useLocalProxy'] as bool? ?? false,
      type: typeRaw == null || typeRaw.isEmpty ? null : typeRaw.toLowerCase(),
      headers: _parseHeaders(json['headers']),
      localProxy: _parseDynamicMap(json['localProxy']),
      requestTransform: _parseDynamicMap(json['requestTransform']),
      // Null unless the resolve response actually carried usable DRM. A
      // half-filled block — a scheme with no keys and no licence url — is
      // dropped rather than passed on: it would route the stream to the
      // decrypting backend, which then fails, instead of letting the ordinary
      // player have a go at a stream that may not have needed decrypting.
      drm: DrmConfig.fromJson(_parseDynamicMap(json['drm'])),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Null rather than an empty string, so "the source did not say" and "the
  /// source said nothing" are the same thing downstream.
  static String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Map<String, String> _parseHeaders(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v != null) out[k] = v.toString();
    });
    return out;
  }

  static Map<String, dynamic> _parseDynamicMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (k is String) out[k] = _normalizeJsonValue(v);
    });
    return out;
  }

  static dynamic _normalizeJsonValue(dynamic value) {
    if (value is Map) return _parseDynamicMap(value);
    if (value is List) {
      return value.map(_normalizeJsonValue).toList(growable: false);
    }
    return value;
  }
}
