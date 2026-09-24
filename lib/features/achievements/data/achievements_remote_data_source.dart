import 'package:dio/dio.dart';

class AchievementsRemoteDataSource {
  const AchievementsRemoteDataSource({required this.dio});

  final Dio dio;

  /// The active profile's achievements, as a raw map so the cache can keep
  /// exactly what the server said.
  Future<Map<String, dynamic>> me() async {
    final res = await dio.get('/achievements/me');
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : const {};
  }

  Future<Map<String, dynamic>> setShowcase(List<String> ids) async {
    final res = await dio.put('/achievements/showcase', data: {'ids': ids});
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : const {};
  }
}
