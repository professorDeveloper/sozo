import 'package:dio/dio.dart';

class ProgressRemoteDataSource {
  const ProgressRemoteDataSource({required this.dio});

  final Dio dio;

  Map<String, dynamic> _body(Response res) {
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : const {};
  }

  Future<Map<String, dynamic>> me() async =>
      _body(await dio.get('/progress/me'));

  /// [seconds] is this device's running total for local [day], not a delta:
  /// the server credits only the rise, so a retry adds nothing.
  Future<Map<String, dynamic>> watchTime({
    required String day,
    required int seconds,
    required String deviceId,
  }) async => _body(
    await dio.post(
      '/progress/watch-time',
      data: {'day': day, 'seconds': seconds, 'deviceId': deviceId},
    ),
  );

  Future<Map<String, dynamic>> equip(Map<String, String?> slots) async =>
      _body(await dio.put('/progress/cosmetics', data: slots));
}
