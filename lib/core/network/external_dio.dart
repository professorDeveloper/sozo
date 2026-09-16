import 'package:dio/dio.dart';

/// A plain client for third-party hosts — CDNs, playlists, probes.
///
/// The app's main Dio pins the backend's certificate chain, so a request to
/// any host outside it fails the handshake. Traffic that is not Sozo's own API
/// goes through here instead.
class ExternalDio {
  ExternalDio._();

  static final Dio instance = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
}
