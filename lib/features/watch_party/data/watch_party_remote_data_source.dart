import 'package:dio/dio.dart';

import 'package:soplay/features/watch_party/domain/entities/party_content.dart';

/// `429` from the invite endpoint: this friend was invited moments ago.
class PartyInviteCooldown implements Exception {
  const PartyInviteCooldown(this.retryAfterSec);
  final int retryAfterSec;
}

/// Thin REST layer for watch party rooms. Mirrors `StreakRemoteDataSource`:
/// a single injected [Dio] whose baseUrl already ends with `/api`.
class WatchPartyRemoteDataSource {
  final Dio dio;
  const WatchPartyRemoteDataSource({required this.dio});

  /// `POST /watch-party` → `{ code, party }`.
  Future<Map<String, dynamic>> createParty({
    PartyContent? content,
    int? maxMembers,
    bool? onlyHostControls,
    bool? waitForAll,
  }) async {
    final res = await dio.post(
      '/watch-party',
      data: <String, dynamic>{
        if (content != null) 'content': content.toJson(),
        'maxMembers': ?maxMembers,
        if (onlyHostControls != null || waitForAll != null)
          'settings': <String, dynamic>{
            'onlyHostControls': ?onlyHostControls,
            'waitForAll': ?waitForAll,
          },
      },
    );
    return _asMap(res.data);
  }

  /// `GET /watch-party/:code` — flat room preview for the join screen.
  Future<Map<String, dynamic>> preview(String code) async {
    final res = await dio.get('/watch-party/$code');
    return _asMap(res.data);
  }

  /// `POST /watch-party/:code/invite` `{ userId }` (host only). Returns the
  /// cooldown the server started, in seconds.
  Future<int> invite(String code, String userId) async {
    try {
      final res = await dio.post(
        '/watch-party/$code/invite',
        data: <String, dynamic>{'userId': userId},
      );
      return (_asMap(res.data)['retryAfterSec'] as num?)?.ceil() ?? 0;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final left = _asMap(e.response?.data)['retryAfterSec'] as num?;
        throw PartyInviteCooldown(left?.ceil() ?? 600);
      }
      rethrow;
    }
  }

  /// `GET /watch-party/:code/invites` → `items: [{userId, retryAfterSec}]`.
  Future<List<dynamic>> inviteStatus(String code) async {
    final res = await dio.get('/watch-party/$code/invites');
    final items = _asMap(res.data)['items'];
    return items is List ? items : const <dynamic>[];
  }

  /// `DELETE /watch-party/:code` (host only).
  Future<void> close(String code) async {
    await dio.delete('/watch-party/$code');
  }

  static Map<String, dynamic> _asMap(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}
