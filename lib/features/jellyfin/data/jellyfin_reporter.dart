import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_api.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_urls.dart';

/// Tells the server what is playing, so its resume points, "next up" and
/// watched marks stay right for every other client the user has.
///
/// Fire-and-forget throughout: playback never waits on it and a server that
/// is down is not the viewer's problem. A stop that is lost (the app killed
/// mid-episode) is accepted; Jellyfin times idle sessions out on its own.
class JellyfinReporter {
  JellyfinReporter({
    required this.bridge,
    required this.api,
    required this.store,
    bool Function()? suppressed,
    DateTime Function()? clock,
  }) : _suppressed = suppressed ?? (() => false),
       _clock = clock ?? DateTime.now;

  final JellyfinBridge bridge;
  final JellyfinApi api;
  final JellyfinServerStore store;
  final bool Function() _suppressed;
  final DateTime Function() _clock;

  static const Duration progressEvery = Duration(seconds: 10);

  /// Play sessions already announced, with when progress was last sent.
  final Map<String, ({DateTime lastSent, bool paused})> _live = {};

  JellyfinPlaySession? sessionFor(String url) => bridge.sessionFor(url);

  /// Where the server says the viewer left off, for a stream it handed out.
  Duration resumeFor(String url) =>
      bridge.sessionFor(url)?.resumeAt ?? Duration.zero;

  Map<String, dynamic> _body(
    JellyfinPlaySession s,
    String url,
    Duration position, {
    bool paused = false,
  }) => {
    'ItemId': s.itemId,
    'MediaSourceId': s.mediaSourceId,
    'PlaySessionId': s.playSessionId,
    'PositionTicks': JellyfinUrls.msToTicks(position),
    'IsPaused': paused,
    'CanSeek': true,
    'PlayMethod': JellyfinPlaySession.playMethodFor(url),
  };

  /// Called on the player's tick and on pause. The first call for a session
  /// starts it; later ones send progress at most every [progressEvery], except
  /// a change between playing and paused, which goes at once.
  void progress({
    required String url,
    required Duration position,
    bool paused = false,
  }) {
    if (_suppressed()) return;
    final session = bridge.sessionFor(url);
    if (session == null) return;
    final server = store.byId(session.serverId);
    if (server == null) return;
    final now = _clock();
    final live = _live[session.playSessionId];
    if (live == null) {
      _live[session.playSessionId] = (lastSent: now, paused: paused);
      _send(
        server,
        '/Sessions/Playing',
        _body(session, url, position, paused: paused),
      );
      return;
    }
    final pauseChanged = live.paused != paused;
    if (!pauseChanged && now.difference(live.lastSent) < progressEvery) return;
    _live[session.playSessionId] = (lastSent: now, paused: paused);
    _send(server, '/Sessions/Playing/Progress', {
      ..._body(session, url, position, paused: paused),
      'EventName': pauseChanged ? (paused ? 'Pause' : 'Unpause') : 'TimeUpdate',
    });
  }

  /// Ends the session. [failed] keeps the server from counting a stream that
  /// broke as watched.
  void stop({
    required String url,
    required Duration position,
    bool failed = false,
  }) {
    final session = bridge.sessionFor(url);
    if (session == null) return;
    if (_live.remove(session.playSessionId) == null) return;
    if (_suppressed()) return;
    final server = store.byId(session.serverId);
    if (server == null) return;
    _send(server, '/Sessions/Playing/Stopped', {
      'ItemId': session.itemId,
      'MediaSourceId': session.mediaSourceId,
      'PlaySessionId': session.playSessionId,
      'PositionTicks': JellyfinUrls.msToTicks(position),
      'Failed': failed,
    });
  }

  void _send(JellyfinServer server, String path, Map<String, dynamic> body) {
    unawaited(
      api.report(server, path, body).catchError((Object e) {
        if (kDebugMode) debugPrint('[Jellyfin] $path failed: $e');
      }),
    );
  }

  @visibleForTesting
  bool isLive(String playSessionId) => _live.containsKey(playSessionId);
}
