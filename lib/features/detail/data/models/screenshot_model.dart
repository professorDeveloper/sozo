import 'package:soplay/features/detail/domain/entities/screenshot_entity.dart';

class ScreenshotModel extends ScreenshotEntity {
  const ScreenshotModel({required super.full, required super.thumb});

  factory ScreenshotModel.fromJson(Map<String, dynamic> json) =>
      ScreenshotModel(
        full: json['full'] as String? ?? '',
        thumb: json['thumb'] as String? ?? '',
      );
}
