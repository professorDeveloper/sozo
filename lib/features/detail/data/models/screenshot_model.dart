import 'package:soplay/core/js/js_value.dart';
import 'package:soplay/features/detail/domain/entities/screenshot_entity.dart';

class ScreenshotModel extends ScreenshotEntity {
  const ScreenshotModel({required super.full, required super.thumb});

  factory ScreenshotModel.fromJson(Map<String, dynamic> json) {
    final full = jsonText(json['full'] ?? json['url']) ?? '';
    return ScreenshotModel(full: full, thumb: jsonText(json['thumb']) ?? full);
  }

  /// A screenshot as a `{full, thumb}` map or as a bare image url, which is
  /// how Zangetsu sources send them; null for anything else.
  static ScreenshotModel? tryParse(Object? raw) {
    final map = jsonMap(raw);
    if (map != null) return ScreenshotModel.fromJson(map);
    final url = raw is String ? raw.trim() : '';
    return url.isEmpty ? null : ScreenshotModel(full: url, thumb: url);
  }
}
