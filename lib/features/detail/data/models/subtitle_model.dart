import 'package:soplay/core/subtitles/subtitle_cipher.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';

class SubtitleModel extends SubtitleEntity {
  const SubtitleModel({
    required super.label,
    required super.file,
    required super.isDefault,
    super.headers,
    super.cipher,
  });

  factory SubtitleModel.fromJson(Map<String, dynamic> json) => SubtitleModel(
    label:
        json['label'] as String? ??
        json['lang'] as String? ??
        json['language'] as String? ??
        'Subtitle',
    file:
        json['file'] as String? ??
        json['url'] as String? ??
        json['src'] as String? ??
        '',
    isDefault: json['default'] as bool? ?? json['isDefault'] as bool? ?? false,
    headers: _parseHeaders(json['headers']),
    cipher: SubtitleCipher.fromJson(json['cipher']),
  );

  static Map<String, String> _parseHeaders(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) out[key] = value.toString();
    });
    return out;
  }
}
