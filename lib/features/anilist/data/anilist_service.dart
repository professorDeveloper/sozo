import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_constants.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:url_launcher/url_launcher.dart';

/// Owns the AniList link: connecting, disconnecting, and the token everything
/// else needs.
///
/// The token is minted by our backend, which holds the client secret, and is
/// stored against the Sozo account — so this service treats the backend as the
/// source of truth and Hive as a cache that survives being offline.
///
/// A [ChangeNotifier] because "are we connected" is read by several screens at
/// once and must not go stale after connecting on one of them.
class AnilistService extends ChangeNotifier {
  AnilistService({
    required Dio backendDio,
    required HiveService hive,
    required AnilistLinkStore links,
    AnilistApi? api,
  }) : _dio = backendDio,
       _hive = hive,
       _links = links,
       _api = api ?? AnilistApi();

  final Dio _dio;
  final HiveService _hive;
  final AnilistLinkStore _links;
  final AnilistApi _api;

  AnilistViewer? _viewer;
  String? _token;
  bool _linking = false;
  String? _lastError;

  AnilistViewer? get viewer => _viewer;
  bool get isConnected => (_token?.isNotEmpty ?? false);
  AnilistApi get api => _api;

  /// True while the code handed back by the browser is being exchanged.
  ///
  /// That exchange is started by the deeplink handler, not by the screen the
  /// user is looking at, so the state has to live here for the UI to show a
  /// spinner at all.
  bool get linking => _linking;

  /// The token, or null when not connected. Callers must handle null rather
  /// than assume a connected account.
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
  /// Opened externally on purpose: an in-app webview would ask the user to type
  /// their AniList password into a window this app controls, which is exactly
  /// the shape of a phishing screen and which password managers refuse to fill.
  Future<bool> beginLink() async {
    _lastError = null;
    return launchUrl(
      AnilistConstants.authorizeUrl(),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Handles the `sozo://anilist?code=…` redirect.
  ///
  /// Swallows its exception because nothing is awaiting this call — the browser
  /// is; the error is parked in [consumeError] for whichever screen is open.
  Future<void> handleCallback(Uri uri) async {
    final code = uri.queryParameters['code']?.trim();
    final denied = uri.queryParameters['error']?.trim();

    if (denied != null && denied.isNotEmpty) {
      _lastError = 'AniList connection was cancelled';
      notifyListeners();
      return;
    }
    if (code == null || code.isEmpty) {
      _lastError = 'AniList returned no authorization code';
      notifyListeners();
      return;
    }

    _linking = true;
    notifyListeners();
    try {
      await completeLink(code);
    } catch (e) {
      _lastError = e is AnilistException
          ? e.message
          : 'Could not connect to AniList';
    } finally {
      _linking = false;
      notifyListeners();
    }
  }

  /// Restores a previous link from disk, then refreshes from the account.
  ///
  /// Cache first so the UI is correct instantly and offline; the account call
  /// is what picks up a link made on another device.
  Future<void> restore() async {
    _token = _hive.getAniListToken();
    final rawViewer = _hive.getAniListViewer();
    if (rawViewer is String) {
      try {
        _viewer = AnilistViewer.fromJson(
          jsonDecode(rawViewer) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (_token != null) notifyListeners();
    await refreshFromAccount();
    await syncLinks();
  }

  /// Exchanges this device's title->media links with the account.
  ///
  /// This is what makes tracking work on a TV at all: a d-pad cannot realistically
  /// search AniList, and an Uzbek or transliterated source title will never match
  /// exactly — so the TV depends on the association made here by hand.
  ///
  /// Silent on failure. It runs on startup and after a link, neither of which the
  /// user is waiting on, and a tracker that cannot reach the network is not an
  /// error worth a dialog.
  Future<void> syncLinks() async {
    if (!isConnected) return;
    try {
      final response = await _dio.post(
        '/anilist/links/sync',
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
  /// This is how a phone picks up a connection made elsewhere, and how it
  /// notices one that was revoked. Failures are swallowed: being offline must
  /// not present as being disconnected.
  Future<void> refreshFromAccount() async {
    try {
      final response = await _dio.get('/anilist/link');
      final data = response.data;
      final link = data is Map ? data['anilist'] : null;
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
  Future<AnilistViewer> completeLink(String code) async {
    final response = await _dio.post('/anilist/link', data: {'code': code});
    final data = response.data;
    final link = data is Map ? data['anilist'] : null;
    if (link is! Map) {
      throw const AnilistException('Could not connect to AniList');
    }
    await _store(link.cast<String, dynamic>());
    final v = _viewer;
    if (v == null) {
      throw const AnilistException('Could not identify the AniList account');
    }
    // Pull whatever links the account already holds, so a phone that connects
    // second inherits every association made on the first.
    unawaited(syncLinks());
    return v;
  }

  /// Drops the link from THIS device without revoking it on the account.
  ///
  /// Distinct from [disconnect]: signing out of Sozo must not silently unlink
  /// an AniList account the user connected deliberately — signing back in
  /// restores it from [refreshFromAccount].
  Future<void> forgetLocal() => _clearLocal();

  Future<void> disconnect() async {
    try {
      await _dio.delete('/anilist/link');
    } catch (_) {
      // Even if the account call fails, this device must stop acting connected.
    }
    await _clearLocal();
  }

  /// The viewer's library. Requires a connection.
  Future<List<AnilistListEntry>> library() async {
    final token = _token;
    final v = _viewer;
    if (token == null || v == null) {
      throw const AnilistException('AniList is not connected');
    }
    return _api.mediaList(token: token, userId: v.id);
  }

  /// Reports [episodesWatched] finished episodes for [mediaId].
  ///
  /// Silent by design: this fires from playback, where a failed tracker write
  /// must never interrupt what the viewer is doing. Returns whether it landed,
  /// for callers that want to retry.
  Future<bool> reportProgress({
    required int mediaId,
    required int episodesWatched,
    String? status,
  }) async {
    final token = _token;
    if (token == null || mediaId <= 0 || episodesWatched <= 0) return false;
    try {
      await _api.saveProgress(
        token: token,
        mediaId: mediaId,
        progress: episodesWatched,
        status: status,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _store(Map<String, dynamic> link) async {
    final token = link['accessToken'] as String?;
    if (token == null || token.isEmpty) {
      await _clearLocal();
      return;
    }
    _token = token;
    _viewer = AnilistViewer(
      id: (link['userId'] as num?)?.toInt() ?? 0,
      name: link['name'] as String? ?? '',
      avatarUrl: link['avatarUrl'] as String?,
    );
    await _hive.saveAniListToken(token);
    await _hive.saveAniListViewer(jsonEncode(_viewer!.toJson()));
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    if (_token == null && _viewer == null) return;
    _token = null;
    _viewer = null;
    await _hive.clearAniListToken();
    await _hive.clearAniListViewer();
    notifyListeners();
  }
}
