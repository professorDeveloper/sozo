import 'package:dio/dio.dart';

import 'package:soplay/features/social/domain/social_models.dart';

/// `/api/social`. Every call throws [SocialException] on failure.
class SocialRemoteDataSource {
  const SocialRemoteDataSource({required this.dio});

  final Dio dio;

  static const _base = '/social';

  Future<List<UserSearchResult>> search(String query, {int limit = 20}) =>
      _call(() async {
        final res = await dio.get(
          '$_base/users/search',
          queryParameters: {'q': query, 'limit': limit},
        );
        final items = _body(res)['items'];
        return items is List
            ? items
                  .whereType<Map>()
                  .map((m) => UserSearchResult.fromJson(m.cast()))
                  .toList()
            : const <UserSearchResult>[];
      });

  Future<SocialProfile> profile(String username) => _call(() async {
    final res = await dio.get('$_base/users/${Uri.encodeComponent(username)}');
    return SocialProfile.fromJson(_body(res));
  });

  Future<CursorPage<ActivityItem>> userActivity(
    String username, {
    String? cursor,
    int? limit,
  }) => _page(
    '$_base/users/${Uri.encodeComponent(username)}/activity',
    ActivityItem.fromJson,
    cursor: cursor,
    limit: limit,
  );

  Future<SocialOverview> overview() => _call(() async {
    final res = await dio.get('$_base/overview');
    return SocialOverview.fromJson(_body(res));
  });

  Future<CursorPage<FriendEntry>> friends({String? cursor, int? limit}) =>
      _page(
        '$_base/friends',
        FriendEntry.fromJson,
        cursor: cursor,
        limit: limit,
      );

  Future<void> removeFriend(String userId) =>
      _call(() => dio.delete('$_base/friends/$userId'));

  Future<List<FriendRequest>> requests({required bool incoming}) =>
      _call(() async {
        final res = await dio.get(
          '$_base/requests',
          queryParameters: {'dir': incoming ? 'in' : 'out'},
        );
        final items = _body(res)['items'];
        return items is List
            ? items
                  .whereType<Map>()
                  .map((m) => FriendRequest.fromJson(m.cast()))
                  .toList()
            : const <FriendRequest>[];
      });

  Future<RequestOutcome> sendRequest({String? userId, String? username}) =>
      _call(() async {
        final res = await dio.post(
          '$_base/requests',
          data: {
            'userId': ?userId,
            if (userId == null && username != null) 'username': username,
          },
        );
        return RequestOutcome.fromJson(_body(res));
      });

  Future<RequestOutcome> acceptRequest(String requestId) => _call(() async {
    final res = await dio.post('$_base/requests/$requestId/accept');
    return RequestOutcome.fromJson(_body(res));
  });

  /// Declines an incoming request or cancels an outgoing one.
  Future<void> deleteRequest(String requestId) =>
      _call(() => dio.delete('$_base/requests/$requestId'));

  Future<List<FriendEntry>> blocks() => _call(() async {
    final res = await dio.get('$_base/blocks');
    final items = _body(res)['items'];
    return items is List
        ? items
              .whereType<Map>()
              .map((m) => FriendEntry.fromJson(m.cast()))
              .toList()
        : const <FriendEntry>[];
  });

  Future<void> block(String userId) =>
      _call(() => dio.post('$_base/blocks/$userId'));

  Future<void> unblock(String userId) =>
      _call(() => dio.delete('$_base/blocks/$userId'));

  Future<SocialSettings> settings() => _call(() async {
    final res = await dio.get('$_base/settings');
    return SocialSettings.fromJson(_body(res));
  });

  Future<SocialSettings> updateSettings({
    ProfileVisibility? visibility,
    bool? shareActivity,
    RequestPolicy? allowRequests,
  }) => _call(() async {
    final res = await dio.put(
      '$_base/settings',
      data: {
        if (visibility != null) 'visibility': visibility.name,
        'shareActivity': ?shareActivity,
        if (allowRequests != null) 'allowRequests': allowRequests.name,
      },
    );
    return SocialSettings.fromJson(_body(res));
  });

  Future<CursorPage<ActivityItem>> feed({String? cursor, int? limit}) =>
      _page('$_base/feed', ActivityItem.fromJson, cursor: cursor, limit: limit);

  Future<CursorPage<ActivityItem>> myActivity({String? cursor, int? limit}) =>
      _page(
        '$_base/activity/me',
        ActivityItem.fromJson,
        cursor: cursor,
        limit: limit,
      );

  Future<void> deleteActivity(String id) =>
      _call(() => dio.delete('$_base/activity/$id'));

  Future<CursorPage<T>> _page<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    String? cursor,
    int? limit,
  }) => _call(() async {
    final res = await dio.get(
      path,
      // This app draws badge cards; the server leaves them out for apps
      // that do not say so.
      queryParameters: {'cursor': ?cursor, 'limit': ?limit, 'achievements': 1},
    );
    return CursorPage.fromJson(_body(res), parse);
  });

  static Map<String, dynamic> _body(Response res) {
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : const {};
  }

  static Future<T> _call<T>(Future<T> Function() task) async {
    try {
      return await task();
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  static SocialException mapError(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    final message = data is Map ? data['message']?.toString() : null;
    final kind = switch ((status, code)) {
      (_, 'REQUESTS_CLOSED') => SocialError.requestsClosed,
      (_, 'ALREADY_FRIENDS') => SocialError.alreadyFriends,
      (_, 'FRIEND_LIMIT') => SocialError.friendLimit,
      (_, 'TOO_MANY_PENDING') => SocialError.tooManyPending,
      (_, 'ACTIVITY_HIDDEN') => SocialError.activityHidden,
      (null, _) => SocialError.network,
      (401, _) => SocialError.unauthorized,
      (404, _) => SocialError.notFound,
      (429, _) => SocialError.rateLimited,
      (400, _) => SocialError.invalid,
      _ => SocialError.unknown,
    };
    return SocialException(kind, message: message);
  }
}
