import 'package:dio/dio.dart';
import 'package:soplay/features/watch_services/data/models/watch_service_model.dart';

/// The catalogue's watch endpoints.
///
/// `cat:tmdb` is spelled into the path rather than taken as a parameter: TMDB
/// is the only catalogue with a streaming line-up, the backend 404s every other
/// kind, and a parameter would suggest otherwise.
class WatchServicesDataSource {
  const WatchServicesDataSource({required this.dio});

  final Dio dio;

  static const String _base = '/catalogue/tmdb/watch';

  Future<List<WatchServiceModel>> loadServices(String region) async {
    final res = await dio.get<dynamic>(
      '$_base/services',
      queryParameters: {'region': region},
    );
    return [
      for (final e in _items(res.data))
        WatchServiceModel.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  /// The list inside the envelope.
  ///
  /// The payload is `{total, items}` rather than a bare array, and that is
  /// deliberate on the server: an empty list has to be distinguishable from a
  /// failed fetch there, or a blip gets cached as "this country has nothing".
  static Iterable<Map> _items(dynamic body) {
    if (body is! Map) return const [];
    final items = body['items'];
    return items is List ? items.whereType<Map>() : const [];
  }
}
