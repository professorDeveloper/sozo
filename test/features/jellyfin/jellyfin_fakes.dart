import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_api.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';

typedef Route = Object? Function(RequestOptions request);

/// Answers requests by path; an unknown path is a 404, like a server that
/// does not have the route.
class FakeJellyfinAdapter implements HttpClientAdapter {
  FakeJellyfinAdapter(this.routes);

  final Map<String, Route> routes;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final route = routes[options.uri.path];
    if (route == null) return ResponseBody.fromString('', 404);
    final body = route(options);
    if (body is int) return ResponseBody.fromString('', body);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const testServer = JellyfinServer(
  id: 'srv1',
  name: 'Home NAS',
  baseUrl: 'http://nas:8096',
  userId: 'u1',
  userName: 'ali',
  accessToken: 'tok123',
  version: '10.10.3',
);

JellyfinApi fakeApi(FakeJellyfinAdapter adapter) => JellyfinApi(
  dio: Dio()..httpClientAdapter = adapter,
  deviceId: () => 'dev1',
  deviceName: 'Sozo Test',
  clientVersion: '1.2.3',
);

Future<JellyfinServerStore> storeWith(List<JellyfinServer> servers) async {
  final store = JellyfinServerStore(box: () => null);
  for (final s in servers) {
    await store.save(s);
  }
  return store;
}
