import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/network/token_refresher.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/watch_party/data/watch_party_remote_data_source.dart';
import 'package:soplay/features/watch_party/data/watch_party_socket_client.dart';
import 'package:soplay/features/watch_party/domain/entities/party_chat_message.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_member.dart';
import 'package:soplay/features/watch_party/domain/entities/party_playback.dart';
import 'package:soplay/features/watch_party/domain/entities/party_reaction.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';
import 'package:soplay/features/watch_party/domain/entities/party_state.dart';
import 'package:soplay/features/watch_party/domain/party_clock.dart';
import 'package:soplay/features/watch_party/domain/party_wait_policy.dart';

/// Live watch-party session. Registered as an eager get_it singleton and is the
/// single source of truth via [state]. Mirrors `StreakService`'s shape
/// (ValueNotifier + broadcast streams) but drives a socket instead of REST.
class WatchPartyService with WidgetsBindingObserver {
  WatchPartyService({
    required this.remote,
    required this.hive,
    required this.tokenRefresher,
    WatchPartySocketClient? socket,
  }) : _socket = socket ?? WatchPartySocketClient() {
    WidgetsBinding.instance.addObserver(this);
    _wireSocket();
  }

  final WatchPartyRemoteDataSource remote;
  final HiveService hive;
  final TokenRefresher tokenRefresher;
  final WatchPartySocketClient _socket;

  final ValueNotifier<PartyState> state =
      ValueNotifier<PartyState>(PartyState.empty);

  /// The room's chat as shown: history from `party:state`, then live lines.
  final ValueNotifier<List<PartyChatMessage>> chatLog =
      ValueNotifier<List<PartyChatMessage>>(const <PartyChatMessage>[]);
  static const int _chatLogMax = 200;

  final PartyClock clock = PartyClock();
  final PartyWaitPolicy waitPolicy = PartyWaitPolicy();
  static const Duration _pingPeriod = Duration(seconds: 10);
  Timer? _pingTimer;

  // When each member was first seen buffering, on this device's clock.
  final Map<String, DateTime> _bufferingSince = <String, DateTime>{};
  bool? _reportedBuffering;

  final StreamController<PartyChatMessage> _chatCtrl =
      StreamController<PartyChatMessage>.broadcast();
  final StreamController<PartyReaction> _reactionCtrl =
      StreamController<PartyReaction>.broadcast();
  final StreamController<PartyContent> _contentCtrl =
      StreamController<PartyContent>.broadcast();
  final StreamController<PartyPlayback> _syncCtrl =
      StreamController<PartyPlayback>.broadcast();
  final StreamController<String> _errorCtrl =
      StreamController<String>.broadcast();

  Stream<PartyChatMessage> get chat => _chatCtrl.stream;
  Stream<PartyReaction> get reactions => _reactionCtrl.stream;
  Stream<PartyContent> get contentChanges => _contentCtrl.stream;
  Stream<PartyPlayback> get syncs => _syncCtrl.stream;
  Stream<String> get errors => _errorCtrl.stream;

  String? _currentCode;
  bool _handshakeRetried = false;
  bool _disposed = false;

  // Own-echo dedupe: each outgoing chat/reaction carries a per-send client id
  // that the server echoes back. An incoming event is suppressed only when its
  // client id matches a still-pending send from THIS device — never by userId,
  // which is shared with a second device signed into the same account.
  int _clientSeq = 0;
  final Set<String> _pendingChatIds = <String>{};
  final Set<String> _pendingReactionIds = <String>{};

  bool get connected => _socket.connected;

  String? get _myUserId {
    final id = hive.getUser()?.id;
    return (id == null || id.isEmpty) ? null : id;
  }

  String get _origin => Uri.parse(AppConstants.baseUrl).origin;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// REST create → connect → join (join emitted on the `connect` event).
  Future<PartyRoom> createParty({
    PartyContent? content,
    int? maxMembers,
    bool? onlyHostControls,
    bool? waitForAll,
  }) async {
    // New session gets a fresh one-shot handshake recovery.
    _handshakeRetried = false;
    final body = await remote.createParty(
      content: content,
      maxMembers: maxMembers,
      onlyHostControls: onlyHostControls,
      waitForAll: waitForAll,
    );
    final rawParty = body['party'];
    final partyJson =
        rawParty is Map ? Map<String, dynamic>.from(rawParty) : body;
    final room = PartyRoom.fromRest(partyJson);
    _currentCode = room.code;
    _resetSession();
    state.value = state.value.copyWith(
      room: room,
      phase: PartyPhase.joining,
      myUserId: _myUserId,
      clearError: true,
      clearClosedReason: true,
    );
    await _openSocket();
    return room;
  }

  /// REST-only room preview for a join screen.
  Future<PartyRoom> preview(String code) async {
    final body = await remote.preview(code);
    return PartyRoom.fromRest(body);
  }

  /// Connect → emit `party:join`.
  Future<void> joinParty(String code) async {
    // New session gets a fresh one-shot handshake recovery.
    _handshakeRetried = false;
    if (_currentCode != code) _resetSession();
    _currentCode = code;
    state.value = state.value.copyWith(
      phase: PartyPhase.joining,
      myUserId: _myUserId,
      clearError: true,
      clearClosedReason: true,
    );
    await _openSocket();
  }

  /// Manual retry from the lobby when the connection failed or stalled on the
  /// join handshake. Forces a fresh token and re-opens the socket for the
  /// current room. No-op if we are not attached to a room.
  Future<void> retryConnection() async {
    if (_currentCode == null) return;
    _handshakeRetried = false;
    state.value = state.value.copyWith(clearError: true);
    await _openSocket(force: true);
  }

  /// Emit `party:leave` → disconnect → reset to empty.
  Future<void> leaveParty() async {
    final code = _currentCode;
    if (code != null) {
      _socket.emit('party:leave', <String, dynamic>{'code': code});
    }
    _currentCode = null;
    _stopPing();
    _socket.disconnect();
    _resetSession();
    state.value = PartyState.empty;
  }

  /// Host-only: REST DELETE. The server broadcasts `party:closed`.
  Future<void> closeParty() async {
    final code = _currentCode ?? state.value.code;
    if (code == null) return;
    try {
      await remote.close(code);
    } catch (_) {
      // The party:closed broadcast (if the room really went away) still cleans
      // up; a failed delete simply leaves the caller's UI as-is.
      rethrow;
    } finally {
      _currentCode = null;
      _stopPing();
      _socket.disconnect();
      _resetSession();
      state.value = PartyState.empty;
    }
  }

  /// Host-only push invite. Returns the seconds until [userId] can be invited
  /// again; throws [PartyInviteCooldown] when they still are cooling down.
  Future<int> invite(String userId) async {
    final code = _currentCode ?? state.value.code;
    if (code == null) return 0;
    return remote.invite(code, userId);
  }

  /// The caller's invite cooldowns as `[{userId, retryAfterSec}]`.
  Future<List<dynamic>> inviteCooldowns() async {
    final code = _currentCode ?? state.value.code;
    if (code == null) return const <dynamic>[];
    return remote.inviteStatus(code);
  }

  /// Host-only. Only the fields given change; the server clamps [maxMembers].
  void updateSettings({
    int? maxMembers,
    bool? onlyHostControls,
    bool? locked,
    bool? waitForAll,
  }) {
    if (!_canEmit) return;
    _socket.emit('party:settings', <String, dynamic>{
      'code': _currentCode,
      'maxMembers': ?maxMembers,
      'onlyHostControls': ?onlyHostControls,
      'locked': ?locked,
      'waitForAll': ?waitForAll,
    });
  }

  /// Host-only: removes [userId] and keeps them out of this room.
  void kick(String userId) {
    if (!_canEmit) return;
    _socket.emit('party:kick', <String, dynamic>{
      'code': _currentCode,
      'userId': userId,
    });
  }

  /// Host-only: hands the host role to [userId].
  void transferHost(String userId) {
    if (!_canEmit) return;
    _socket.emit('party:transfer', <String, dynamic>{
      'code': _currentCode,
      'userId': userId,
    });
  }

  /// Tells the room whether this device's player is stalled. Sent only on
  /// change.
  void reportBuffering(bool buffering) {
    if (!_canEmit || _reportedBuffering == buffering) return;
    _reportedBuffering = buffering;
    _socket.emit('party:buffering', <String, dynamic>{
      'code': _currentCode,
      'buffering': buffering,
    });
  }

  /// Host side of "wait for everyone", run from the player's tick. Drives the
  /// local player through [pause]/[play] and tells the room. Returns true when
  /// it has just paused.
  bool waitForAllTick({
    required bool localPlaying,
    required double positionSec,
    required void Function() pause,
    required void Function() play,
  }) {
    final s = state.value;
    final action = waitPolicy.tick(
      enabled: s.room?.waitForAll ?? false,
      isHost: s.isHost && s.inParty,
      localPlaying: localPlaying,
      bufferingSince: othersBufferingSince(),
      now: DateTime.now(),
    );
    switch (action) {
      case PartyWaitAction.pause:
        pause();
        sendControl(action: 'pause', positionSec: positionSec);
        return true;
      case PartyWaitAction.resume:
        play();
        sendControl(action: 'play', positionSec: positionSec);
        return false;
      case PartyWaitAction.none:
        return false;
    }
  }

  /// When each OTHER online member started buffering.
  Iterable<DateTime> othersBufferingSince() {
    final me = _myUserId;
    final online = <String>{
      for (final m in state.value.room?.members ?? const <PartyMember>[])
        if (m.online) m.userId,
    };
    return _bufferingSince.entries
        .where((e) => e.key != me && online.contains(e.key))
        .map((e) => e.value);
  }

  void sendControl({required String action, double? positionSec, double? rate}) {
    if (!_canEmit) return;
    _socket.emit('party:control', <String, dynamic>{
      'code': _currentCode,
      'action': action,
      'positionSec': ?positionSec,
      'rate': ?rate,
    });
  }

  void sendContent(PartyContent content) {
    if (!_canEmit) return;
    _socket.emit('party:content', <String, dynamic>{
      'code': _currentCode,
      ...content.toJson(),
    });
  }

  void sendHeartbeat(double positionSec) {
    if (!_canEmit) return;
    _socket.emit('party:heartbeat', <String, dynamic>{
      'code': _currentCode,
      'positionSec': positionSec,
    });
  }

  void sendChat(String text) {
    if (_currentCode == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final capped =
        trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
    // Only wire an own-echo dedupe id when we actually put the message on the
    // socket — otherwise the server never echoes it back and the pending id
    // would leak.
    if (_canEmit) {
      final clientId = _nextClientId();
      _rememberPending(_pendingChatIds, clientId);
      _socket.emit('party:chat', <String, dynamic>{
        'code': _currentCode,
        'text': capped,
        'clientId': clientId,
      });
    }
    final me = hive.getUser();
    final local = PartyChatMessage(
      userId: _myUserId ?? '',
      username: me?.username ?? me?.displayName,
      photoURL: me?.photoURL,
      text: capped,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    _appendLog(local);
    // Optimistic local echo: show instantly instead of waiting for the server
    // round-trip (which can be slow on a distant server), and — crucially —
    // render the sender's own message even during a brief reconnect so it never
    // looks like the chat is dead. The server echoes our clientId back; _onChat
    // suppresses only the matching pending entry on THIS device, so a second
    // device on the same account still renders the message.
    if (!_chatCtrl.isClosed) _chatCtrl.add(local);
  }

  void sendReaction(String emoji) {
    if (_currentCode == null) return;
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;
    final capped = trimmed.length > 16 ? trimmed.substring(0, 16) : trimmed;
    if (_canEmit) {
      final clientId = _nextClientId();
      _rememberPending(_pendingReactionIds, clientId);
      _socket.emit('party:reaction', <String, dynamic>{
        'code': _currentCode,
        'emoji': capped,
        'clientId': clientId,
      });
    }
    // Optimistic local echo (see sendChat); own server echo dropped in
    // _onReaction by matching the pending clientId for THIS device only.
    if (!_reactionCtrl.isClosed) {
      _reactionCtrl.add(PartyReaction(
        userId: _myUserId ?? '',
        emoji: capped,
        ts: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  bool get _canEmit => _socket.connected && _currentCode != null;

  Future<bool> _openSocket({bool force = false}) async {
    final token = await tokenRefresher.ensureFresh(force: force);
    if (_disposed) return false;
    if (token == null || token.isEmpty) {
      state.value = state.value.copyWith(
        connection: PartyConnection.error,
        errorCode: 'unauthorized',
      );
      return false;
    }
    state.value = state.value.copyWith(
      connection: PartyConnection.connecting,
      myUserId: _myUserId,
    );
    _socket.connect(
      origin: _origin,
      token: token,
      photoURL: hive.getUser()?.photoURL,
    );
    return true;
  }

  void _wireSocket() {
    _socket.onConnect(_handleConnect);
    _socket.onConnectError(_handleConnectError);
    _socket.onDisconnect(_handleDisconnect);
    _socket.on('party:state', _onState);
    _socket.on('party:sync', _onSync);
    _socket.on('party:content', _onContent);
    _socket.on('party:member', _onMember);
    _socket.on('party:chat', _onChat);
    _socket.on('party:reaction', _onReaction);
    _socket.on('party:closed', _onClosed);
    _socket.on('party:error', _onErrorEvent);
    _socket.on('party:settings', _onSettings);
    _socket.on('party:system', _onSystem);
    _socket.on('party:buffering', _onBuffering);
    _socket.on('party:pong', _onPong);
  }

  void _resetSession() {
    chatLog.value = const <PartyChatMessage>[];
    _bufferingSince.clear();
    _reportedBuffering = null;
    waitPolicy.release();
    clock.reset();
  }

  void _startPing() {
    _pingTimer?.cancel();
    _ping();
    _pingTimer = Timer.periodic(_pingPeriod, (_) => _ping());
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _ping() {
    if (!_socket.connected) return;
    _socket.emit('party:ping', <String, dynamic>{
      't0': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _appendLog(PartyChatMessage msg) {
    final next = <PartyChatMessage>[...chatLog.value, msg];
    chatLog.value = next.length > _chatLogMax
        ? next.sublist(next.length - _chatLogMax)
        : next;
  }

  /// [pb] re-based from "when it arrived" to "when the server meant it".
  PartyPlayback _aligned(PartyPlayback pb, Map<String, dynamic> json) =>
      PartyPlayback(
        positionSec: pb.positionSec,
        isPlaying: pb.isPlaying,
        rate: pb.rate,
        receivedAt: clock.align(
          serverTime: (json['serverTime'] as num?)?.toInt(),
          receivedAt: pb.receivedAt,
        ),
      );

  void _syncBuffering(List<PartyMember> members) {
    final now = DateTime.now();
    final buffering = <String>{
      for (final m in members)
        if (m.online && m.buffering) m.userId,
    };
    _bufferingSince.removeWhere((id, _) => !buffering.contains(id));
    for (final id in buffering) {
      _bufferingSince.putIfAbsent(id, () => now);
    }
  }

  void _handleConnect() {
    _handshakeRetried = false;
    _reportedBuffering = null;
    _startPing();
    state.value = state.value.copyWith(connection: PartyConnection.connected);
    // Room membership is bound to the socket — (re)join after every connect.
    final code = _currentCode;
    if (code != null) {
      _socket.emit('party:join', <String, dynamic>{'code': code});
    }
  }

  Future<void> _handleConnectError(Object error) async {
    final message = error.toString();
    if (message.contains('unauthorized') && !_handshakeRetried) {
      _handshakeRetried = true;
      final ok = await _openSocket(force: true);
      if (!ok && !_disposed) {
        state.value =
            state.value.copyWith(connection: PartyConnection.error);
      }
      return;
    }
    if (!_disposed) {
      state.value = state.value.copyWith(
        connection: PartyConnection.error,
        errorMessage: message,
      );
    }
  }

  void _handleDisconnect() {
    if (_disposed) return;
    _stopPing();
    if (_currentCode != null && state.value.phase != PartyPhase.closed) {
      // socket.io will auto-reconnect; reflect that in the UI.
      state.value =
          state.value.copyWith(connection: PartyConnection.reconnecting);
    }
  }

  // ---------------------------------------------------------------------------
  // Server → client events
  // ---------------------------------------------------------------------------

  void _onState(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    var room = PartyRoom.fromSnapshot(j);
    final pbJson = _asMap(j['playback']);
    if (pbJson != null) {
      room = room.copyWith(playback: _aligned(room.playback, pbJson));
    }
    if (j.containsKey('chat')) {
      final history = PartyChatMessage.listFrom(j['chat']);
      chatLog.value = history.length > _chatLogMax
          ? history.sublist(history.length - _chatLogMax)
          : history;
    }
    _syncBuffering(room.members);
    state.value = state.value.copyWith(
      room: room,
      phase: PartyPhase.inRoom,
      connection: PartyConnection.connected,
      myUserId: _myUserId,
      clearError: true,
    );
  }

  void _onSync(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final pbJson = _asMap(j['playback']);
    if (pbJson == null) return;
    final pb = _aligned(
      PartyPlayback.fromJson(pbJson, receivedAt: DateTime.now()),
      pbJson,
    );
    final room = state.value.room;
    if (room != null) {
      state.value = state.value.copyWith(room: room.copyWith(playback: pb));
    }
    if (!_syncCtrl.isClosed) _syncCtrl.add(pb);
  }

  void _onContent(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final contentJson = _asMap(j['content']);
    final content =
        contentJson != null ? PartyContent.fromJson(contentJson) : null;
    final pbJson = _asMap(j['playback']);
    final pb = pbJson != null
        ? _aligned(
            PartyPlayback.fromJson(pbJson, receivedAt: DateTime.now()),
            pbJson,
          )
        : null;
    final room = state.value.room;
    if (room != null) {
      state.value = state.value
          .copyWith(room: room.copyWith(content: content, playback: pb));
    }
    if (content != null && !_contentCtrl.isClosed) {
      _contentCtrl.add(content);
    }
  }

  void _onMember(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final members = PartyMember.listFrom(j['members']);
    final hostUserId = j['hostUserId'] as String?;
    _syncBuffering(members);
    final room = state.value.room;
    if (room != null) {
      state.value = state.value.copyWith(
        room: room.copyWith(members: members, hostUserId: hostUserId),
      );
    }
  }

  void _onChat(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final msg = PartyChatMessage.fromJson(j);
    // Suppress ONLY this device's own optimistic echo, matched by the clientId
    // we attached on send and the server echoed back. Never dedupe by userId
    // alone: a second device on the same account shares our account id and must
    // still render our messages.
    final clientId = j['clientId'] as String?;
    if (clientId != null) {
      if (_pendingChatIds.remove(clientId)) return;
    } else if (msg.userId.isNotEmpty && msg.userId == _myUserId) {
      // Legacy fallback for a server that doesn't echo the clientId.
      return;
    }
    _appendLog(msg);
    if (!_chatCtrl.isClosed) _chatCtrl.add(msg);
  }

  void _onSystem(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final msg = PartyChatMessage.tryParse(j);
    if (msg == null || !msg.isSystem) return;
    _appendLog(msg);
  }

  void _onSettings(dynamic d) {
    final j = _asMap(d);
    final room = state.value.room;
    if (j == null || room == null) return;
    final settings = _asMap(j['settings']) ?? const <String, dynamic>{};
    state.value = state.value.copyWith(
      room: room.copyWith(
        onlyHostControls: settings['onlyHostControls'] as bool?,
        locked: settings['locked'] as bool?,
        waitForAll: settings['waitForAll'] as bool?,
        maxMembers: (j['maxMembers'] as num?)?.toInt(),
        maxMembersLimit: (j['maxMembersLimit'] as num?)?.toInt(),
      ),
    );
  }

  void _onBuffering(dynamic d) {
    final j = _asMap(d);
    final room = state.value.room;
    final userId = j?['userId'] as String?;
    if (j == null || room == null || userId == null) return;
    final buffering = j['buffering'] == true;
    final members = [
      for (final m in room.members)
        m.userId == userId ? m.copyWith(buffering: buffering) : m,
    ];
    _syncBuffering(members);
    state.value = state.value.copyWith(room: room.copyWith(members: members));
  }

  void _onPong(dynamic d) {
    final j = _asMap(d);
    final t0 = (j?['t0'] as num?)?.toInt();
    final serverTime = (j?['serverTime'] as num?)?.toInt();
    if (t0 == null || serverTime == null) return;
    clock.add(
      sentAt: t0,
      serverTime: serverTime,
      receivedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _onReaction(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final r = PartyReaction.fromJson(j);
    // Own echo matched by pending clientId only (see _onChat) — not by userId.
    final clientId = j['clientId'] as String?;
    if (clientId != null) {
      if (_pendingReactionIds.remove(clientId)) return;
    } else if (r.userId.isNotEmpty && r.userId == _myUserId) {
      return; // legacy fallback: server didn't echo the clientId
    }
    if (!_reactionCtrl.isClosed) _reactionCtrl.add(r);
  }

  void _onClosed(dynamic d) {
    final j = _asMap(d);
    final reason = j?['reason'] as String?;
    state.value = state.value.copyWith(
      phase: PartyPhase.closed,
      closedReason: reason,
    );
    _currentCode = null;
    _stopPing();
    _socket.disconnect();
  }

  void _onErrorEvent(dynamic d) {
    final j = _asMap(d);
    final code = j?['code'] as String?;
    final message = j?['message'] as String?;
    state.value = state.value.copyWith(
      errorCode: code,
      errorMessage: message,
    );
    if (!_errorCtrl.isClosed) {
      _errorCtrl.add(code ?? message ?? 'error_generic');
    }
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NOTE: shadows the `state` ValueNotifier field, which this body never uses.
    if (state == AppLifecycleState.resumed) {
      _ensureConnected();
    }
  }

  void _ensureConnected() {
    final code = _currentCode;
    if (code == null) return;
    if (_socket.connected) {
      // Defensive re-join in case membership lapsed while backgrounded.
      _socket.emit('party:join', <String, dynamic>{'code': code});
      return;
    }
    _openSocket();
  }

  static Map<String, dynamic>? _asMap(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : null;

  /// Per-send id unique to this device, round-tripped through the server so an
  /// own echo can be recognised without deduping by the shared account userId.
  String _nextClientId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_clientSeq++}';

  /// Records a pending own-send id, evicting the oldest (insertion-ordered) when
  /// the set grows — a server that drops a rate-limited message never echoes its
  /// id back, so the entry would otherwise leak.
  static void _rememberPending(Set<String> pending, String id) {
    pending.add(id);
    while (pending.length > 64) {
      pending.remove(pending.first);
    }
  }

  void dispose() {
    _disposed = true;
    _stopPing();
    WidgetsBinding.instance.removeObserver(this);
    _socket.dispose();
    state.dispose();
    chatLog.dispose();
    _chatCtrl.close();
    _reactionCtrl.close();
    _contentCtrl.close();
    _syncCtrl.close();
    _errorCtrl.close();
  }
}
