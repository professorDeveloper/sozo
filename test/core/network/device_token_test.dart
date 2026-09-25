import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/network/token_refresher.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/data/datasources/auth_remote_data_source.dart';

String _jwt(Map<String, Object> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.sig';
}

final _tvRefresh = _jwt({'id': 'u1', 'sid': 's1'});
final _phoneRefresh = _jwt({'id': 'u1', 'psid': 'p1'});
final _expired = _jwt({'id': 'u1', 'exp': 1});

/// A paired TV's refresh token is only accepted by the device endpoints.
void main() {
  late Directory dir;
  late HiveService hive;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_device_token_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.authBox, bytes: Uint8List(0));
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
    hive = HiveService();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('the socket refresher', () {
    for (final (who, token, path) in [
      ('a TV', _tvRefresh, '/auth/device/refresh'),
      ('a phone', _phoneRefresh, '/auth/refresh'),
    ]) {
      test('rotates $who token at $path', () async {
        await hive.saveTokens(accessToken: _expired, refreshToken: token);
        final adapter = _Adapter(
          (_) => (200, jsonEncode({'accessToken': 'new', 'refreshToken': 'r'})),
        );
        final refresher = TokenRefresher(hive, dio: _dio(adapter));

        expect(await refresher.ensureFresh(), 'new');
        expect(adapter.requests.single.path, path);
      });
    }
  });

  group('signing out', () {
    test('a TV ends its own device session', () async {
      final adapter = _Adapter((_) => (200, '{}'));
      await AuthRemoteDataSource(
        dio: _dio(adapter),
      ).logout(refreshToken: _tvRefresh);

      final request = adapter.requests.single;
      expect(request.path, '/auth/device/logout');
      expect(request.data, {'refreshToken': _tvRefresh});
    });

    test('a phone ends its session as before', () async {
      final adapter = _Adapter((_) => (200, '{}'));
      await AuthRemoteDataSource(
        dio: _dio(adapter),
      ).logout(refreshToken: _phoneRefresh);

      expect(adapter.requests.single.path, '/auth/logout');
    });
  });
}

Dio _dio(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final (int, String) Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = respond(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
