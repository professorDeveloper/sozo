import 'package:dio/dio.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';

class ProfilesListing {
  const ProfilesListing({
    required this.profiles,
    required this.activeProfileId,
    required this.max,
  });

  final List<HouseholdProfile> profiles;

  /// Null when the `X-Sozo-Profile` the app sent names a profile that no
  /// longer exists.
  final String? activeProfileId;
  final int max;
}

class ProfilesRemoteDataSource {
  ProfilesRemoteDataSource({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<ProfilesListing> list() => _call(() async {
    final res = await _dio.get('/auth/profiles');
    final data = _map(res.data);
    return ProfilesListing(
      profiles: [
        for (final p in (data['profiles'] as List? ?? const []))
          if (p is Map) HouseholdProfile.fromJson(p.cast<String, dynamic>()),
      ],
      activeProfileId: data['activeProfileId'] as String?,
      max: (data['max'] as num?)?.toInt() ?? 5,
    );
  });

  Future<HouseholdProfile> create({
    required String name,
    String? avatar,
    String? color,
    bool isKids = false,
    String? pin,
  }) => _call(() async {
    final res = await _dio.post(
      '/auth/profiles',
      data: {
        'name': name,
        'avatar': ?avatar,
        'color': ?color,
        'isKids': isKids,
        'pin': ?pin,
      },
    );
    return _profile(res.data);
  });

  /// Only the fields present in [changes] are sent; `'pin': null` removes it.
  Future<HouseholdProfile> update(
    String id,
    Map<String, dynamic> changes, {
    String? currentPin,
  }) => _call(() async {
    final res = await _dio.patch(
      '/auth/profiles/$id',
      data: {...changes, 'currentPin': ?currentPin},
    );
    return _profile(res.data);
  });

  Future<void> delete(String id, {String? currentPin}) => _call(() async {
    await _dio.delete('/auth/profiles/$id', data: {'currentPin': ?currentPin});
  });

  Future<HouseholdProfile> verifyPin(String id, String pin) => _call(() async {
    final res = await _dio.post(
      '/auth/profiles/$id/verify-pin',
      data: {'pin': pin},
    );
    return _profile(res.data);
  });

  static Map<String, dynamic> _map(Object? data) =>
      data is Map ? data.cast<String, dynamic>() : const {};

  static HouseholdProfile _profile(Object? data) {
    final p = _map(data)['profile'];
    if (p is! Map) throw const ProfileException('Bad response', status: 500);
    return HouseholdProfile.fromJson(p.cast<String, dynamic>());
  }

  static Future<T> _call<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final res = e.response;
      if (res == null) throw ProfileException(e.message ?? 'offline');
      final body = _map(res.data);
      throw ProfileException(
        (body['message'] ?? e.message ?? 'Error').toString(),
        code: body['code'] as String?,
        status: res.statusCode,
      );
    }
  }
}
