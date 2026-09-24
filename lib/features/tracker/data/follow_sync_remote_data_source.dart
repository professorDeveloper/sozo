import 'package:dio/dio.dart';

import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

/// `/follows` answered 404 with no code of its own: the route is not on this
/// server yet. The caller carries on with local follows only.
class FollowsNotDeployed implements Exception {
  const FollowsNotDeployed();
}

/// The server refused this one change for good (the follow limit, a malformed
/// item). Retrying it would fail the same way, so it is dropped.
class FollowRejected implements Exception {
  const FollowRejected(this.code);
  final String? code;
}

/// PATCH on a follow the server does not have.
class FollowNotFound implements Exception {
  const FollowNotFound();
}

/// Transport for `/follows`, on the app's authenticated [Dio] — the bearer
/// token and `X-Sozo-Profile` come from its interceptors.
class FollowSyncRemoteDataSource {
  const FollowSyncRemoteDataSource({required this.dio});

  final Dio dio;

  Future<List<FollowedTitle>> list() async {
    final res = await _guard(() => dio.get('/follows'));
    return _items(res.data);
  }

  Future<FollowedTitle?> add(FollowedTitle title) async {
    final res = await _guard(() => dio.post('/follows', data: title.toRemote()));
    return _item(res.data);
  }

  Future<void> remove(String provider, String contentUrl) async {
    await _guard(
      () => dio.delete(
        '/follows',
        data: {'provider': provider, 'contentUrl': contentUrl},
      ),
    );
  }

  Future<FollowedTitle?> patch(
    String provider,
    String contentUrl, {
    bool? notify,
    int? lastEpisodeCount,
  }) async {
    final res = await _guard(
      () => dio.patch(
        '/follows',
        data: {
          'provider': provider,
          'contentUrl': contentUrl,
          'notify': ?notify,
          'lastEpisodeCount': ?lastEpisodeCount,
        },
      ),
    );
    return _item(res.data);
  }

  /// Sends every local follow, and tombstones for the ones removed here, and
  /// returns the account's merged list.
  Future<List<FollowedTitle>> sync({
    required List<FollowedTitle> items,
    required List<({String provider, String contentUrl, int at})> deleted,
  }) async {
    final res = await _guard(
      () => dio.post(
        '/follows/sync',
        data: {
          'items': [
            for (final t in items) t.toRemote(),
            for (final d in deleted)
              {
                'provider': d.provider,
                'contentUrl': d.contentUrl,
                'deleted': true,
                'updatedAt': DateTime.fromMillisecondsSinceEpoch(
                  d.at,
                  isUtc: true,
                ).toIso8601String(),
              },
          ],
        },
      ),
    );
    return _items(res.data);
  }

  Future<Response<dynamic>> _guard(Future<Response<dynamic>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final code = data is Map ? data['code']?.toString() : null;
      if (status == 404) {
        if (code == 'FOLLOW_NOT_FOUND') throw const FollowNotFound();
        if (code == null || code.isEmpty) throw const FollowsNotDeployed();
      }
      if (status == 409 || status == 400 || status == 422) {
        throw FollowRejected(code);
      }
      rethrow;
    }
  }

  static List<FollowedTitle> _items(Object? data) {
    final raw = data is Map ? data['items'] : null;
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) FollowedTitle.fromJson(e.cast<String, dynamic>()),
    ].where((t) => t.contentUrl.isNotEmpty).toList();
  }

  static FollowedTitle? _item(Object? data) {
    final raw = data is Map ? data['item'] : null;
    return raw is Map ? FollowedTitle.fromJson(raw.cast<String, dynamic>()) : null;
  }
}
