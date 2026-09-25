import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_link_store.dart';

/// Who is connected.
class TraktViewer {
  const TraktViewer({required this.slug, required this.name, this.avatarUrl});
  final String slug;
  final String name;
  final String? avatarUrl;
}

/// A link in progress: what the viewer types, where, and until when.
class TraktDeviceCode {
  const TraktDeviceCode({
    required this.userCode,
    required this.verificationUrl,
    required this.expiresAt,
    required this.interval,
  });
  final String userCode;
  final String verificationUrl;
  final DateTime expiresAt;
  final Duration interval;
}

/// How one poll of a link in progress came out.
enum TraktPoll { pending, slowDown, linked, expired, denied, failed }

/// The Trakt account link, held on the Sozo account and cached here.
///
/// Linking is the device flow: the server starts it and polls Trakt, the app
/// shows the code and asks the server how it went. The server keeps the
/// secret, the device code and the refresh token; the app keeps the access
/// token and the public client id, and talks to Trakt directly.
class TraktService extends ChangeNotifier {
  TraktService({
    required Dio backendDio,
    required TraktLinkStore links,
    TraktApi? api,
    Box? box,
  }) : _dio = backendDio,
       _links = links,
       _api = api ?? TraktApi(),
       _override = box;

  final Dio _dio;
  final TraktLinkStore _links;
  final TraktApi _api;
  final Box? _override;
  // The auth box, like MAL's token: it holds a credential, and the auth box
  // is the one a backup leaves out.
  Box get _box => _override ?? Hive.box(AppConstants.authBox);

  TraktViewer? _viewer;
  String? _token;
  String? _clientId;

  TraktViewer? get viewer => _viewer;
  String? get token => _token;
  String? get clientId => _clientId;
  bool get isConnected =>
      (_token?.isNotEmpty ?? false) && (_clientId?.isNotEmpty ?? false);
  TraktApi get api => _api;
  TraktLinkStore get links => _links;

  /// From the device cache at once, then from the account.
  Future<void> restore() async {
    final raw = _box.get(AppConstants.traktLinkKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        _apply(jsonDecode(raw) as Map<String, dynamic>, persist: false);
      } catch (_) {}
    }
    await refreshFromAccount();
    await syncLinks();
  }

  /// Re-reads the link from the account, which refreshes the day-long token
  /// when it is near expiry. Offline or signed out: keeps what it had.
  Future<void> refreshFromAccount() async {
    try {
      final r = await _dio.get('/trakt/link');
      final link = (r.data as Map?)?['trakt'];
      if (link is Map) {
        _apply(link.cast<String, dynamic>());
      } else {
        await _clearLocal();
      }
    } catch (_) {}
  }

  /// Starts a link. Null when the server could not (Trakt down, or not set up).
  Future<TraktDeviceCode?> startLink() async {
    try {
      final r = await _dio.post('/trakt/device');
      final d = (r.data as Map).cast<String, dynamic>();
      return TraktDeviceCode(
        userCode: d['userCode'] as String,
        verificationUrl:
            (d['verificationUrl'] as String?) ?? 'https://trakt.tv/activate',
        expiresAt:
            DateTime.tryParse('${d['expiresAt']}') ??
            DateTime.now().add(const Duration(minutes: 10)),
        interval: Duration(
          seconds: (d['intervalSeconds'] as num?)?.toInt() ?? 5,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// One poll of the link in progress.
  Future<TraktPoll> poll() async {
    try {
      final r = await _dio.post('/trakt/device/poll');
      final d = (r.data as Map).cast<String, dynamic>();
      switch (d['status']) {
        case 'linked':
          final link = d['trakt'];
          if (link is Map) _apply(link.cast<String, dynamic>());
          unawaited(syncLinks());
          return TraktPoll.linked;
        case 'pending':
          return TraktPoll.pending;
        case 'slow_down':
          return TraktPoll.slowDown;
        case 'denied':
          return TraktPoll.denied;
        case 'expired':
        case 'used':
        case 'invalid':
          return TraktPoll.expired;
      }
      return TraktPoll.pending;
    } catch (_) {
      return TraktPoll.failed;
    }
  }

  Future<void> disconnect() async {
    try {
      await _dio.delete('/trakt/link');
    } catch (_) {
      // Even if the account call fails, this device stops acting connected.
    }
    await _links.clear();
    await _clearLocal();
  }

  Future<void> forgetLocal() => _clearLocal();

  Future<void> syncLinks() async {
    if (!isConnected) return;
    try {
      final r = await _dio.post(
        '/trakt/links/sync',
        data: {'items': _links.pendingChanges()},
      );
      final items = (r.data as Map?)?['items'];
      if (items is List) await _links.applyRemote(items);
    } catch (_) {}
  }

  void _apply(Map<String, dynamic> link, {bool persist = true}) {
    final token = link['accessToken'] as String?;
    final clientId = link['clientId'] as String?;
    if (token == null || token.isEmpty || clientId == null) {
      unawaited(_clearLocal());
      return;
    }
    _token = token;
    _clientId = clientId;
    _viewer = TraktViewer(
      slug: (link['userId'] ?? '').toString(),
      name: (link['name'] ?? '').toString(),
      avatarUrl: link['avatarUrl'] as String?,
    );
    if (persist) {
      unawaited(_box.put(AppConstants.traktLinkKey, jsonEncode(link)));
    }
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    if (_token == null && _viewer == null) return;
    _token = null;
    _clientId = null;
    _viewer = null;
    await _box.delete(AppConstants.traktLinkKey);
    notifyListeners();
  }
}
