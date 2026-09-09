import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'discord_activity.dart';

/// Sets Discord presence on a phone, where there is no Discord client to talk
/// to.
///
/// ## Read this before changing anything here
///
/// Desktop has a published mechanism: a local socket, no credentials. Mobile
/// has none. Discord has no API that lets a server or a third-party app set a
/// user's presence — presence belongs to whichever gateway connection is
/// signed in as that user. So the only thing that works is for the app to BE
/// such a connection, using the user's own token.
///
/// That is self-botting. It is against Discord's terms of service, it can get
/// the account actioned, and it means Sozo holds a credential with full access
/// to that account.
///
/// This was explained and the feature was still wanted on every platform, so
/// it exists — with the safeguards that make it defensible and no others:
///
///  * off unless the viewer turns it on,
///  * the token only ever in `flutter_secure_storage`,
///  * never logged, never sent anywhere but `gateway.discord.gg`,
///  * one action disconnects and wipes it,
///  * the risk stated in the screen that asks for it, not in a footnote.
///
/// Do not add a second use for the token. Do not send it to the Sozo backend.
/// Do not log it, not even truncated — a prefix is enough to correlate.
class DiscordGatewayClient {
  DiscordGatewayClient({required this.token});

  /// The user's own Discord token. Never leaves this object except to Discord.
  final String token;

  static const String _endpoint =
      'wss://gateway.discord.gg/?v=10&encoding=json';

  static const int _opDispatch = 0;
  static const int _opHeartbeat = 1;
  static const int _opIdentify = 2;
  static const int _opPresence = 3;
  static const int _opReconnect = 7;
  static const int _opInvalidSession = 9;
  static const int _opHello = 10;
  static const int _opHeartbeatAck = 11;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  int? _sequence;
  bool _ready = false;
  bool _awaitingAck = false;
  DiscordActivity? _pending;

  bool get isConnected => _ready;

  Future<bool> connect() async {
    if (_ready) return true;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_endpoint));
      await channel.ready;
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
      return true;
    } catch (e) {
      // The message is safe to log; the token is not in it.
      debugPrint('[discord] gateway connect failed: $e');
      await _closeQuietly();
      return false;
    }
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final op = frame['op'] as int?;
    if (frame['s'] is int) _sequence = frame['s'] as int;

    switch (op) {
      case _opHello:
        final interval =
            ((frame['d'] as Map?)?['heartbeat_interval'] as num?)?.toInt() ??
            41250;
        _startHeartbeat(interval);
        _identify();
      case _opHeartbeatAck:
        _awaitingAck = false;
      case _opDispatch:
        if (frame['t'] == 'READY') {
          _ready = true;
          // Anything set before the session existed was dropped on the floor.
          final queued = _pending;
          _pending = null;
          if (queued != null) unawaited(setActivity(queued));
        }
      case _opReconnect:
        _onClosed();
      case _opInvalidSession:
        // A rejected token is terminal — retrying with the same one just
        // repeats the rejection, and Discord rate limits identifies hard.
        debugPrint('[discord] session invalid; the saved token is not usable');
        _ready = false;
        unawaited(_closeQuietly());
    }
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      // A missed ack means the connection is a zombie: it still looks open and
      // nothing arrives. Discord's own guidance is to tear it down rather than
      // keep beating into it.
      if (_awaitingAck) {
        _onClosed();
        return;
      }
      _awaitingAck = true;
      _send({'op': _opHeartbeat, 'd': _sequence});
    });
  }

  void _identify() {
    _send({
      'op': _opIdentify,
      'd': {
        'token': token,
        // Announced as a mobile client so Discord shows the phone badge, which
        // is what it actually is.
        'properties': {
          'os': Platform.isIOS ? 'ios' : 'android',
          'browser': 'Discord Android',
          'device': 'Discord Android',
        },
        // No guild, message or member events — nothing here reads them, and
        // asking for them would mean receiving a stream of the account's
        // private conversations into this process.
        'intents': 0,
      },
    });
  }

  Future<void> setActivity(DiscordActivity? activity) async {
    if (!_ready) {
      _pending = activity;
      return;
    }
    _send({
      'op': _opPresence,
      'd': {
        'since': null,
        'status': 'online',
        'afk': false,
        'activities': activity == null ? [] : [_encode(activity)],
      },
    });
  }

  Map<String, dynamic> _encode(DiscordActivity a) {
    final assets = <String, dynamic>{};
    if (a.imageUrl != null && a.imageUrl!.isNotEmpty) {
      // The gateway takes an external url, proxied, where the IPC transport
      // takes an uploaded asset key. Same field, different contents — which is
      // why encoding lives in each transport rather than in the activity.
      assets['large_image'] =
          'mp:external/${Uri.encodeComponent(a.imageUrl!)}';
      if (a.imageText != null) assets['large_text'] = a.imageText;
    }
    return {
      'name': 'Sozo',
      'type': 3,
      'details': a.title,
      if (a.subtitle != null && a.subtitle!.isNotEmpty) 'state': a.subtitle,
      if (assets.isNotEmpty) 'assets': assets,
      'timestamps': {
        if (a.startedAt != null) 'start': a.startedAt!.millisecondsSinceEpoch,
        if (a.endsAt != null) 'end': a.endsAt!.millisecondsSinceEpoch,
      },
    };
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {
      _onClosed();
    }
  }

  void _onClosed() {
    _ready = false;
    unawaited(_closeQuietly());
  }

  Future<void> _closeQuietly() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _awaitingAck = false;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> dispose() async {
    if (_ready) {
      try {
        await setActivity(null);
      } catch (_) {}
    }
    _ready = false;
    await _closeQuietly();
  }
}
