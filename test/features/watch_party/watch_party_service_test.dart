import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/token_refresher.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/watch_party/data/watch_party_remote_data_source.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/data/watch_party_socket_client.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_state.dart';

class _FakeWatchPartyRemoteDataSource implements WatchPartyRemoteDataSource {
  Map<String, dynamic> createPartyResponse = {
    'party': {
      'code': 'PARTY123',
      'hostUserId': 'host-user-id',
      'members': [
        {'userId': 'host-user-id', 'username': 'Captain'}
      ],
      'playback': {'state': 'paused', 'positionSec': 0.0, 'rate': 1.0},
    }
  };

  Map<String, dynamic> previewResponse = {
    'code': 'PARTY123',
    'hostUserId': 'host-user-id',
    'members': [],
  };

  String? closedCode;
  String? invitedCode;
  String? invitedUserId;

  @override
  Future<Map<String, dynamic>> createParty({PartyContent? content}) async =>
      createPartyResponse;

  @override
  Future<Map<String, dynamic>> preview(String code) async => previewResponse;

  @override
  Future<void> close(String code) async {
    closedCode = code;
  }

  @override
  Future<void> invite(String code, String userId) async {
    invitedCode = code;
    invitedUserId = userId;
  }
}

class _FakeTokenRefresher implements TokenRefresher {
  String? token = 'valid-jwt-token';
  bool wasForced = false;

  @override
  Future<String?> ensureFresh({bool force = false}) async {
    wasForced = force;
    return token;
  }
}

class _FakeHiveService implements HiveService {
  UserEntity? currentUser = const UserEntity(
    id: 'my-user-id',
    email: 'pirate@kaizoku.app',
    username: 'KaizokuCaptain',
  );

  @override
  UserEntity? getUser() => currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocketClient extends WatchPartySocketClient {
  bool isSocketConnected = false;
  final Map<String, void Function(dynamic)> listeners = {};
  final List<({String event, Object data})> emittedEvents = [];

  void Function()? onConnectCallback;
  void Function(Object error)? onConnectErrorCallback;
  void Function()? onDisconnectCallback;

  @override
  bool get connected => isSocketConnected;

  @override
  void onConnect(void Function() cb) {
    onConnectCallback = cb;
  }

  @override
  void onConnectError(void Function(Object error) cb) {
    onConnectErrorCallback = cb;
  }

  @override
  void onDisconnect(void Function() cb) {
    onDisconnectCallback = cb;
  }

  @override
  void on(String event, void Function(dynamic data) cb) {
    listeners[event] = cb;
  }

  @override
  void connect({
    required String origin,
    required String token,
    String? photoURL,
  }) {
    isSocketConnected = true;
    onConnectCallback?.call();
  }

  @override
  void emit(String event, Object data) {
    emittedEvents.add((event: event, data: data));
  }

  @override
  void disconnect() {
    isSocketConnected = false;
    onDisconnectCallback?.call();
  }

  void simulateServerEvent(String event, dynamic data) {
    listeners[event]?.call(data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWatchPartyRemoteDataSource fakeRemote;
  late _FakeHiveService fakeHive;
  late _FakeTokenRefresher fakeTokenRefresher;
  late _FakeSocketClient fakeSocket;
  late WatchPartyService service;

  setUp(() {
    fakeRemote = _FakeWatchPartyRemoteDataSource();
    fakeHive = _FakeHiveService();
    fakeTokenRefresher = _FakeTokenRefresher();
    fakeSocket = _FakeSocketClient();

    service = WatchPartyService(
      remote: fakeRemote,
      hive: fakeHive,
      tokenRefresher: fakeTokenRefresher,
      socket: fakeSocket,
    );
  });

  tearDown(() {
    service.leaveParty();
  });

  group('WatchPartyService Room Lifecycle', () {
    test('createParty() calls remote, sets up room, connects socket and joins', () async {
      final room = await service.createParty();

      expect(room.code, 'PARTY123');
      expect(service.state.value.phase, PartyPhase.joining);
      expect(fakeSocket.isSocketConnected, isTrue);

      // On socket connect, it emits 'party:join'
      final joinEmits = fakeSocket.emittedEvents.where((e) => e.event == 'party:join');
      expect(joinEmits, isNotEmpty);
      expect((joinEmits.first.data as Map)['code'], 'PARTY123');
    });

    test('joinParty() connects to socket and emits party:join', () async {
      await service.joinParty('JOINCODE');

      expect(service.state.value.phase, PartyPhase.joining);
      expect(fakeSocket.isSocketConnected, isTrue);

      final joinEmits = fakeSocket.emittedEvents.where((e) => e.event == 'party:join');
      expect(joinEmits, isNotEmpty);
      expect((joinEmits.first.data as Map)['code'], 'JOINCODE');
    });

    test('leaveParty() emits party:leave, disconnects socket, and resets state', () async {
      await service.joinParty('LEAVECODE');
      await service.leaveParty();

      final leaveEmits = fakeSocket.emittedEvents.where((e) => e.event == 'party:leave');
      expect(leaveEmits, isNotEmpty);
      expect((leaveEmits.first.data as Map)['code'], 'LEAVECODE');
      expect(service.state.value, PartyState.empty);
      expect(fakeSocket.isSocketConnected, isFalse);
    });

    test('closeParty() calls remote close and disconnects socket', () async {
      await service.createParty();
      await service.closeParty();

      expect(fakeRemote.closedCode, 'PARTY123');
      expect(service.state.value, PartyState.empty);
    });
  });

  group('WatchPartyService Socket.io Event Handling', () {
    test('handles party:state server snapshot', () async {
      await service.joinParty('SNAPSHOT_CODE');

      fakeSocket.simulateServerEvent('party:state', {
        'room': {
          'code': 'SNAPSHOT_CODE',
          'hostUserId': 'host-1',
          'members': [
            {'userId': 'host-1', 'username': 'Host'},
            {'userId': 'my-user-id', 'username': 'KaizokuCaptain'},
          ],
          'playback': {
            'state': 'playing',
            'positionSec': 42.5,
            'rate': 1.0,
          },
        }
      });

      expect(service.state.value.phase, PartyPhase.inRoom);
      expect(service.state.value.connection, PartyConnection.connected);
      expect(service.state.value.room?.code, 'SNAPSHOT_CODE');
      expect(service.state.value.room?.members.length, 2);
      expect(service.state.value.room?.playback.isPlaying, isTrue);
      expect(service.state.value.room?.playback.positionSec, 42.5);
    });

    test('handles party:sync event and streams playback update', () async {
      await service.joinParty('ROOM');
      fakeSocket.simulateServerEvent('party:state', {
        'room': {'code': 'ROOM', 'hostUserId': 'host'}
      });

      final syncFuture = service.syncs.first;
      fakeSocket.simulateServerEvent('party:sync', {
        'playback': {
          'state': 'paused',
          'positionSec': 120.0,
          'rate': 1.0,
        }
      });

      final sync = await syncFuture;
      expect(sync.positionSec, 120.0);
      expect(sync.isPaused, isTrue);
      expect(service.state.value.room?.playback.positionSec, 120.0);
    });

    test('handles party:content event and updates active content', () async {
      await service.joinParty('ROOM');
      fakeSocket.simulateServerEvent('party:state', {
        'room': {'code': 'ROOM', 'hostUserId': 'host'}
      });

      final contentFuture = service.contentChanges.first;
      fakeSocket.simulateServerEvent('party:content', {
        'content': {
          'type': 'anime',
          'title': 'One Piece',
          'source': 'kaizoku',
          'url': 'https://stream.kaizoku.app/ep1.m3u8',
          'episode': 1,
        },
        'playback': {
          'state': 'playing',
          'positionSec': 0.0,
        }
      });

      final content = await contentFuture;
      expect(content.title, 'One Piece');
      expect(service.state.value.room?.content?.title, 'One Piece');
    });

    test('handles party:closed event and updates phase and reason', () async {
      await service.joinParty('ROOM');
      fakeSocket.simulateServerEvent('party:closed', {
        'reason': 'host_left',
      });

      expect(service.state.value.phase, PartyPhase.closed);
      expect(service.state.value.closedReason, 'host_left');
      expect(fakeSocket.isSocketConnected, isFalse);
    });
  });

  group('WatchPartyService Client Emits', () {
    setUp(() async {
      await service.joinParty('ACTIVE_PARTY');
    });

    test('sendControl() emits party:control payload', () {
      service.sendControl(action: 'seek', positionSec: 250.0, rate: 1.25);

      final ctrl = fakeSocket.emittedEvents.lastWhere((e) => e.event == 'party:control');
      final data = ctrl.data as Map;
      expect(data['code'], 'ACTIVE_PARTY');
      expect(data['action'], 'seek');
      expect(data['positionSec'], 250.0);
      expect(data['rate'], 1.25);
    });

    test('sendChat() emits party:chat and broadcasts optimistic local echo', () async {
      final chatFuture = service.chat.first;
      service.sendChat('Set sail for the Grand Line!');

      final chatEvent = fakeSocket.emittedEvents.lastWhere((e) => e.event == 'party:chat');
      final data = chatEvent.data as Map;
      expect(data['code'], 'ACTIVE_PARTY');
      expect(data['text'], 'Set sail for the Grand Line!');
      expect(data['clientId'], isNotNull);

      // Verify optimistic local echo
      final localMessage = await chatFuture;
      expect(localMessage.text, 'Set sail for the Grand Line!');
      expect(localMessage.username, 'KaizokuCaptain');
    });

    test('sendReaction() emits party:reaction and broadcasts optimistic echo', () async {
      final reactionFuture = service.reactions.first;
      service.sendReaction('🔥');

      final reactionEvent = fakeSocket.emittedEvents.lastWhere((e) => e.event == 'party:reaction');
      final data = reactionEvent.data as Map;
      expect(data['code'], 'ACTIVE_PARTY');
      expect(data['emoji'], '🔥');

      final localReaction = await reactionFuture;
      expect(localReaction.emoji, '🔥');
    });
  });
}
