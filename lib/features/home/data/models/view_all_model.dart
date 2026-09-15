import 'package:soplay/features/home/domain/entities/view_all.dart';

class ViewAllModel extends ViewAllEntity {
  ViewAllModel({required super.slug, required super.type});

  factory ViewAllModel.fromJson(Map<String, dynamic> json) {
    return ViewAllModel(
      slug: json['slug'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }
}
