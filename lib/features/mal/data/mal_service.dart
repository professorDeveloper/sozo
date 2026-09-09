import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/mal/data/mal_api.dart';
import 'package:soplay/features/mal/data/mal_constants.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';

/// Owns the MyAnimeList link: connecting, disconnecting, and the token
/// everything else needs.
///
/// Shaped like AnilistService on purpose — the backend is the source of truth
/// and Hive is a cache that survives being offline — with one difference that
/// drives the whole class: MAL requires PKCE, and the verifier must be held by
/// whoever performs the exchange. So the app cannot build its own authorize
/// URL; it asks the backend for one. That is also why [beginLink] can fail for
/// a reason AniList's cannot (no account, or MAL not configured server-side).
///
/// A [ChangeNotifier] because "are we connected" is read by several screens at
/// once and must not go stale after connecting on one of them.
class MalService extends ChangeNotifier {
  MalService({
    required Dio backendDio,
    required HiveService hive,
    required MalLinkStore links,
    MalApi? api,
  })  : _dio = backendDio,
        _hive = hive,
        _links = links,
        _api = api ?? MalApi();

  final Dio _dio;
  final HiveService _hive;
  final MalLinkStore _links;
  final MalApi _api;

  MalViewer? _viewer;
  String? _token;
  bool _linking = false;
  String? _lastError;

  MalViewer? get viewer => _viewer;
  bool get isConnected => (_token?.isNotEmpty ?? false);
  MalApi get api => _api;
  MalLinkStore get links => _links;

  /// True while the code handed back by the browser is being exchanged.
  bool get linking => _linking;

  /// The token, or null when not connected.
  String? get token => _token;

  /// Takes the last failure and forgets it, so a screen shows it exactly once
  /// instead of on every rebuild.
  String? consumeError() {
    final e = _lastError;
    _lastError = null;
    return e;
  }

  /// Starts the browser half of the OAuth flow.
  ///
  /// The URL comes from the backend, which mints and keeps the PKCE verifier.
  /// Opened externally rather than in a webview for the same reason as AniList:
  /// an in-app window asking for a MAL password is the shape of a phishing
  /// screen, and password managers refuse to fill it.
  Future<bool> beginLink() async {
    _lastError = null;
    try {
      final response = await _dio.get('/mal/authorize-url');
      final url = (response.data as Map?)?['url'];
      if (url is! String || url.isEmpty) {
        _lastError = 'Could not start the MyAnimeList connection';
        notifyListeners();
        return false;
      }
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on DioException catch (e) {
      _lastError = e.response?.statusCode == 503
          ? 'MyAnimeList is not configured on the server yet'
          : 'Could not start the MyAnimeList connection';
      notifyListeners();
      return false;
    }
  }

  /// Handles the `sozo://mal?code=…` redirect.
  ///
  /// Swallows its exception because nothing is awaiting this call — the browser
  /// is; the error is parked in [consumeError] for whichever screen is open.
  Future<void> handleCallback(Uri uri) async {
    final code = uri.queryParameters['code']?.trim();
    final denied = uri.queryParameters['error']?.trim();

    if (denied != null && denied.isNotEmpty) {
      _lastError = 'MyAnimeList connection was cancelled';
      notifyListeners();
      return;
    }
    if (code == null || code.isEmpty) {
      _lastError = 'MyAnimeList returned no authorization code';
      notifyListeners();
      return;
    }

    _linking = true;
    notifyListeners();
    try {
      await completeLink(code);
    } catch (e) {
      _lastError =
          e is MalException ? e.message : 'Could not connect to MyAnimeList';
    } finally {
      _linking = false;
      notifyListeners();
    }
  }

  /// Restores a previous link from disk, then refreshes from the account.
  Future<void> restore() async {
    _token = _hive.getMalToken();
    final rawViewer = _hive.getMalViewer();
    if (rawViewer is String) {
      try {
        _viewer = MalViewer.fromJson(
          jsonDecode(rawViewer) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (_token != null) notifyListeners();
    await refreshFromAccount();
    await syncLinks();
  }

  /// Exchanges this device's title->anime links with the account.
  ///
  /// Silent on failure: it runs on startup and after a link, neither of which
  /// the user is waiting on.
  Future<void> syncLinks() async {
    if (!isConnected) return;
    try {
      final response = await _dio.post(
        '/mal/links/sync',
        data: {'items': _links.pendingChanges()},
      );
      final items = (response.data as Map?)?['items'];
      if (items is List) await _links.applyRemote(items);
    } catch (_) {
      // Offline, or signed out. The local map and its pending unlinks stay put.
    }
  }

  /// Pulls the link stored on the Sozo account.
  ///
  /// This is also what silently renews an expiring token: the server refreshes
  /// on read, so a device that has been asleep for a month comes back with a
  /// working token instead of a dead one. Failures are swallowed — being
  /// offline must not present as being disconnected.
  Future<void> refreshFromAccount() async {
    try {
      final response = await _dio.get('/mal/link');
      final data = response.data;
      final link = data is Map ? data['mal'] : null;
      if (link is Map) {
        await _store(link.cast<String, dynamic>());
      } else {
        await _clearLocal();
      }
    } catch (_) {
      // Offline, or signed out of Sozo. Keep whatever we already had.
    }
  }

  /// Completes the OAuth handshake with the code the browser handed back.
  ///
  /// Throws on failure so the screen can say what went wrong — this one runs
  /// because the user pressed Connect and is waiting for an answer.
  Future<MalViewer> completeLink(String code) async {
    final response = await _dio.post('/mal/link', data: {'code': code});
    final data = response.data;
    final link = data is Map ? data['mal'] : null;
    if (link is! Map) {
      throw const MalException('Could not connect to MyAnimeList');
    }
    await _store(link.cast<String, dynamic>());
    final v = _viewer;
    if (v == null) {
      throw const MalException('Could not identify the MyAnimeList account');
    }
    unawaited(syncLinks());
    return v;
  }

  /// Drops the link from THIS device without revoking it on the account.
  ///
  /// Distinct from [disconnect]: signing out of Sozo must not silently unlink a
  /// MAL account the user connected deliberately — signing back in restores it
  /// from [refreshFromAccount].
  Future<void> forgetLocal() => _clearLocal();

  Future<void> disconnect() async {
    try {
      await _dio.delete('/mal/link');
    } catch (_) {
      // Even if the account call fails, this device must stop acting connected.
    }
    await _clearLocal();
  }

  Future<void> _store(Map<String, dynamic> link) async {
    final token = link['accessToken'] as String?;
    if (token == null || token.isEmpty) {
      await _clearLocal();
      return;
    }
    _token = token;
    _viewer = MalViewer(
      id: (link['userId'] as num?)?.toInt() ?? 0,
      name: link['name'] as String? ?? '',
      avatarUrl: link['avatarUrl'] as String?,
    );
    await _hive.saveMalToken(token);
    await _hive.saveMalViewer(jsonEncode(_viewer!.toJson()));
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    if (_token == null && _viewer == null) return;
    _token = null;
    _viewer = null;
    await _hive.clearMalToken();
    await _hive.clearMalViewer();
    notifyListeners();
  }
}
