import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_urls.dart';

enum JellyfinErrorKind { unreachable, notJellyfin, unauthorized, server }

class JellyfinException implements Exception {
  const JellyfinException(this.kind, [this.detail = '']);

  final JellyfinErrorKind kind;
  final String detail;

  @override
  String toString() => detail.isEmpty ? 'Jellyfin: ${kind.name}' : detail;
}

typedef JellyfinPublicInfo = ({String id, String name, String version});

typedef JellyfinLogin = ({String userId, String userName, String token});

/// A thin REST client for one Jellyfin server at a time.
///
/// Its own Dio: the app's main client pins Sozo's certificate and adds the
/// provider interceptor, and a LAN server on plain HTTP needs neither.
class JellyfinApi {
  JellyfinApi({
    Dio? dio,
    required String Function() deviceId,
    String? deviceName,
    this.clientVersion = '1.0.0',
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 15),
             ),
           ),
       _deviceId = deviceId,
       deviceName = deviceName ?? _platformName();

  final Dio _dio;
  final String Function() _deviceId;
  final String deviceName;
  String clientVersion;

  String get deviceId => _deviceId();

  static String _platformName() {
    try {
      final os = Platform.operatingSystem;
      return 'Sozo ${os[0].toUpperCase()}${os.substring(1)}';
    } catch (_) {
      return 'Sozo';
    }
  }

  String authHeader([String? token]) => JellyfinUrls.authorization(
    deviceName: deviceName,
    deviceId: deviceId,
    version: clientVersion,
    token: token,
  );

  Options _opts(String? token) => Options(
    headers: {'Authorization': authHeader(token), 'Accept': 'application/json'},
    responseType: ResponseType.json,
  );

  static const String _listFields =
      'PrimaryImageAspectRatio,ProductionYear,Overview,Genres';

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static JellyfinException _map(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return JellyfinException(JellyfinErrorKind.unauthorized, 'HTTP $code');
    }
    if (code != null) {
      return JellyfinException(JellyfinErrorKind.server, 'HTTP $code');
    }
    return JellyfinException(
      JellyfinErrorKind.unreachable,
      e.message ?? e.type.name,
    );
  }

  Future<Map<String, dynamic>> _get(
    JellyfinServer s,
    String path, [
    Map<String, dynamic>? query,
  ]) => _guard(() async {
    final res = await _dio.get<Object?>(
      '${s.baseUrl}$path',
      queryParameters: query,
      options: _opts(s.accessToken),
    );
    return _asMap(res.data);
  });

  /// 10.9 moved the per-user routes to `?userId=` forms and later releases
  /// dropped the old ones; servers from before 10.9 only have the old ones.
  Future<Map<String, dynamic>> _getEither(
    JellyfinServer s,
    String path,
    String legacyPath, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      return await _get(s, path, {...?query, 'userId': s.userId});
    } on JellyfinException catch (e) {
      if (e.kind != JellyfinErrorKind.server || !e.detail.contains('404')) {
        rethrow;
      }
      return _get(s, legacyPath, query);
    }
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List) return {'Items': data};
    return const {};
  }

  static List<Map<String, dynamic>> itemsOf(Map<String, dynamic> body) => [
    for (final e in (body['Items'] as List?) ?? const [])
      if (e is Map) Map<String, dynamic>.from(e),
  ];

  Future<JellyfinPublicInfo> publicInfo(String baseUrl) => _guard(() async {
    final res = await _dio.get<Object?>(
      '$baseUrl/System/Info/Public',
      options: _opts(null),
    );
    final data = res.data;
    final map = data is Map ? data : null;
    final id = map?['Id']?.toString() ?? '';
    if (map == null || id.isEmpty) {
      throw const JellyfinException(JellyfinErrorKind.notJellyfin);
    }
    return (
      id: id,
      name: map['ServerName']?.toString() ?? 'Jellyfin',
      version: map['Version']?.toString() ?? '',
    );
  });

  Future<JellyfinLogin> authenticate(
    String baseUrl,
    String username,
    String password,
  ) => _guard(() async {
    final res = await _dio.post<Object?>(
      '$baseUrl/Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
      options: _opts(null).copyWith(contentType: Headers.jsonContentType),
    );
    final map = _asMap(res.data);
    final token = map['AccessToken']?.toString() ?? '';
    final user = map['User'];
    if (token.isEmpty || user is! Map) {
      throw const JellyfinException(JellyfinErrorKind.unauthorized);
    }
    return (
      userId: user['Id']?.toString() ?? '',
      userName: user['Name']?.toString() ?? username,
      token: token,
    );
  });

  /// The user's top-level libraries.
  Future<List<Map<String, dynamic>>> views(JellyfinServer s) async =>
      itemsOf(await _getEither(s, '/UserViews', '/Users/${s.userId}/Views'));

  Future<List<Map<String, dynamic>>> resume(
    JellyfinServer s, {
    int limit = 16,
  }) async => itemsOf(
    await _getEither(
      s,
      '/UserItems/Resume',
      '/Users/${s.userId}/Items/Resume',
      {
        'Limit': limit,
        'MediaTypes': 'Video',
        'Fields': _listFields,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
      },
    ),
  );

  Future<List<Map<String, dynamic>>> nextUp(
    JellyfinServer s, {
    int limit = 16,
  }) async => itemsOf(
    await _get(s, '/Shows/NextUp', {
      'userId': s.userId,
      'Limit': limit,
      'Fields': _listFields,
    }),
  );

  Future<List<Map<String, dynamic>>> latest(
    JellyfinServer s,
    String parentId, {
    int limit = 20,
  }) async => itemsOf(
    await _getEither(s, '/Items/Latest', '/Users/${s.userId}/Items/Latest', {
      'ParentId': parentId,
      'Limit': limit,
      'Fields': _listFields,
    }),
  );

  Future<({List<Map<String, dynamic>> items, int total})> items(
    JellyfinServer s, {
    String? parentId,
    String? genreId,
    String? searchTerm,
    String includeTypes = 'Movie,Series',
    int start = 0,
    int limit = 40,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  }) async {
    final body = await _get(s, '/Items', {
      'userId': s.userId,
      'Recursive': 'true',
      'IncludeItemTypes': includeTypes,
      'StartIndex': start,
      'Limit': limit,
      'SortBy': sortBy,
      'SortOrder': sortOrder,
      'Fields': _listFields,
      'ParentId': ?parentId,
      'GenreIds': ?genreId,
      if (searchTerm != null && searchTerm.isNotEmpty) 'searchTerm': searchTerm,
    });
    final list = itemsOf(body);
    final total = (body['TotalRecordCount'] as num?)?.toInt() ?? list.length;
    return (items: list, total: total);
  }

  Future<List<Map<String, dynamic>>> genres(
    JellyfinServer s, {
    String? parentId,
  }) async => itemsOf(
    await _get(s, '/Genres', {
      'userId': s.userId,
      'SortBy': 'SortName',
      'IncludeItemTypes': 'Movie,Series',
      'ParentId': ?parentId,
    }),
  );

  Future<Map<String, dynamic>> item(JellyfinServer s, String id) =>
      _getEither(s, '/Items/$id', '/Users/${s.userId}/Items/$id');

  Future<List<Map<String, dynamic>>> similar(
    JellyfinServer s,
    String id, {
    int limit = 12,
  }) async => itemsOf(
    await _get(s, '/Items/$id/Similar', {
      'userId': s.userId,
      'Limit': limit,
      'Fields': _listFields,
    }),
  );

  /// Every episode of every season in one list, with the user's watch state.
  Future<List<Map<String, dynamic>>> episodes(
    JellyfinServer s,
    String seriesId,
  ) async => itemsOf(
    await _get(s, '/Shows/$seriesId/Episodes', {
      'userId': s.userId,
      'Fields': 'Overview,PrimaryImageAspectRatio',
      'EnableUserData': 'true',
    }),
  );

  Future<Map<String, dynamic>> playbackInfo(
    JellyfinServer s,
    String itemId,
    Map<String, dynamic> body,
  ) => _guard(() async {
    final res = await _dio.post<Object?>(
      '${s.baseUrl}/Items/$itemId/PlaybackInfo',
      queryParameters: {'userId': s.userId},
      data: body,
      options: _opts(
        s.accessToken,
      ).copyWith(contentType: Headers.jsonContentType),
    );
    return _asMap(res.data);
  });

  Future<void> report(
    JellyfinServer s,
    String path,
    Map<String, dynamic> body,
  ) => _guard(() async {
    await _dio.post<Object?>(
      '${s.baseUrl}$path',
      data: body,
      options: _opts(
        s.accessToken,
      ).copyWith(contentType: Headers.jsonContentType),
    );
  });

  Future<void> logout(JellyfinServer s) => _guard(() async {
    await _dio.post<Object?>(
      '${s.baseUrl}/Sessions/Logout',
      options: _opts(s.accessToken),
    );
  });
}
