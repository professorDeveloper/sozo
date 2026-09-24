import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/data/models/user_model.dart';

/// A reply: a JSON body, or `(status, body)` for a failure.
typedef SocialRoute = Object? Function(RequestOptions options);

/// Answers `METHOD /path` from [routes]; anything unrouted is a 404.
class FakeSocialAdapter implements HttpClientAdapter {
  FakeSocialAdapter(this.routes);

  final Map<String, SocialRoute> routes;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final route = routes['${options.method} ${options.uri.path}'];
    final reply = route == null ? (404, {'message': 'nope'}) : route(options);
    final (status, body) = reply is (int, Object?) ? reply : (200, reply);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeSocialAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.test/api'))
      ..httpClientAdapter = adapter;

class SignedInHive implements HiveService {
  @override
  bool get isLoggedIn => true;

  @override
  UserModel? getUser() => UserModel(id: 'me', username: 'me', email: 'a@b.c');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> userJson(String id, {String? name}) => {
  'id': id,
  'username': id,
  'displayName': name,
  'photoURL': null,
};

Map<String, dynamic> activityJson(
  String id, {
  String type = 'watched',
  String mediaType = 'video',
  int? from,
  int? to,
  bool finished = false,
  Map<String, dynamic>? actor,
  String title = 'Frieren',
}) => {
  'id': id,
  'type': type,
  'mediaType': mediaType,
  'provider': 'src',
  'contentUrl': 'https://src.test/$id',
  'contentId': null,
  'title': title,
  'thumbnail': null,
  'episodeFrom': from,
  'episodeTo': to,
  'episodeLabel': null,
  'finished': finished,
  'at': DateTime.now().toUtc().toIso8601String(),
  'actor': ?actor,
};
