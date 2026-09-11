import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/link_tv/domain/entities/linked_device.dart';
import 'package:soplay/features/link_tv/domain/link_tv_failure.dart';
import 'package:soplay/features/link_tv/domain/repositories/link_tv_repository.dart';
import 'package:soplay/features/link_tv/presentation/bloc/link_tv_bloc.dart';
import 'package:soplay/features/remote/data/remote_control_service.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  Map<String, dynamic> Function(RequestOptions options)? handler;
  int statusCode = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (statusCode == 409) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'device offline'}),
        409,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (handler != null) {
      final res = handler!(options);
      return ResponseBody.fromString(
        jsonEncode(res),
        statusCode,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString('{}', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeLinkTvRepository implements LinkTvRepository {
  Result<String?> approveResult = const Success('Living Room Kaizoku TV');
  Result<List<LinkedDevice>> listResult = const Success([]);
  Result<void> unlinkResult = const Success(null);

  String? lastApprovedCode;
  String? lastUnlinkedId;

  @override
  Future<Result<String?>> approve(String userCode) async {
    lastApprovedCode = userCode;
    return approveResult;
  }

  @override
  Future<Result<List<LinkedDevice>>> listDevices() async => listResult;

  @override
  Future<Result<void>> unlinkDevice(String id) async {
    lastUnlinkedId = id;
    return unlinkResult;
  }
}

void main() {
  group('RemoteControlService', () {
    late Dio dio;
    late _FakeDioAdapter adapter;
    late RemoteControlService service;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://test.api'));
      adapter = _FakeDioAdapter();
      dio.httpClientAdapter = adapter;
      service = RemoteControlService(dio: dio);
    });

    test('devices() lists remote devices with parsed fields', () async {
      adapter.handler = (options) {
        expect(options.path, '/remote/devices');
        return {
          'items': [
            {
              'id': 'tv-101',
              'name': 'Living Room Sony',
              'online': true,
              'lastSeenAt': '2026-09-10T12:00:00Z',
            },
            {
              'id': 'tv-102',
              'name': '',
              'online': false,
            },
          ]
        };
      };

      final devices = await service.devices();
      expect(devices.length, 2);
      expect(devices[0].id, 'tv-101');
      expect(devices[0].name, 'Living Room Sony');
      expect(devices[0].online, isTrue);
      expect(devices[1].id, 'tv-102');
      expect(devices[1].name, 'TV'); // default fallback
      expect(devices[1].online, isFalse);
    });

    test('state() fetches online status and playback state', () async {
      adapter.handler = (options) {
        expect(options.path, '/remote/state');
        expect(options.queryParameters['deviceId'], 'tv-101');
        return {
          'online': true,
          'state': {
            'screen': 'player',
            'title': 'One Piece',
            'episode': '1115',
            'playing': true,
            'positionMs': 120000,
            'durationMs': 1440000,
          }
        };
      };

      final result = await service.state('tv-101');
      expect(result.online, isTrue);
      expect(result.state, isNotNull);
      expect(result.state?.screen, 'player');
      expect(result.state?.title, 'One Piece');
      expect(result.state?.episode, '1115');
      expect(result.state?.playing, isTrue);
      expect(result.state?.hasPlayback, isTrue);
      expect(result.state?.positionMs, 120000);
      expect(result.state?.durationMs, 1440000);
    });

    test('send() passes command payload to server', () async {
      RequestOptions? sentOptions;
      adapter.handler = (options) {
        sentOptions = options;
        return {'success': true};
      };

      await service.dpad('tv-101', 'up');
      expect(sentOptions?.path, '/remote/command');
      final data = sentOptions?.data as Map;
      expect(data['deviceId'], 'tv-101');
      expect(data['type'], 'dpad');
      expect(data['direction'], 'up');
    });

    test('seekTo and seekBy send correct parameters', () async {
      RequestOptions? sentOptions;
      adapter.handler = (options) {
        sentOptions = options;
        return {'success': true};
      };

      await service.seekTo('tv-101', 45000);
      expect((sentOptions?.data as Map)['positionMs'], 45000);

      await service.seekBy('tv-101', -10000);
      expect((sentOptions?.data as Map)['deltaMs'], -10000);
    });

    test('openOnTv sends title, contentUrl, and provider', () async {
      RequestOptions? sentOptions;
      adapter.handler = (options) {
        sentOptions = options;
        return {'success': true};
      };

      await service.openOnTv(
        'tv-101',
        title: 'Attack on Titan',
        contentUrl: 'https://kaizoku.tv/watch/aot',
        provider: 'kaizoku-ext',
      );

      final data = sentOptions?.data as Map;
      expect(data['type'], 'open');
      expect(data['title'], 'Attack on Titan');
      expect(data['contentUrl'], 'https://kaizoku.tv/watch/aot');
      expect(data['provider'], 'kaizoku-ext');
    });

    test('send() throws RemoteOfflineException on 409 conflict', () async {
      adapter.statusCode = 409;
      expect(
        () => service.play('tv-101'),
        throwsA(isA<RemoteOfflineException>()),
      );
    });
  });

  group('LinkTvBloc', () {
    late _FakeLinkTvRepository repository;
    late LinkTvBloc bloc;

    setUp(() {
      repository = _FakeLinkTvRepository();
      bloc = LinkTvBloc(repository: repository);
    });

    tearDown(() {
      bloc.close();
    });

    test('normalizeCode cleans spaces, converts to uppercase, and strips URLs', () {
      expect(LinkTvBloc.normalizeCode('abcd-1234'), 'ABCD1234');
      expect(
        LinkTvBloc.normalizeCode('https://sozo.azamov.me/link/KAIZ1234'),
        'KAIZ1234',
      );
      expect(
        LinkTvBloc.normalizeCode('https://kaizoku.azamov.me/link/WXYZ-5678'),
        'WXYZ5678',
      );
      expect(LinkTvBloc.normalizeCode(' ab 12 - cd 34 '), 'AB12CD34');
    });

    test('LinkTvCodeChanged updates state code and clears errors', () {
      bloc.add(const LinkTvCodeChanged('ab-cd-12-34'));
      expect(
        bloc.stream,
        emits(predicate<LinkTvState>((s) => s.code == 'ABCD1234' && s.errorKey == null)),
      );
    });

    test('LinkTvApprove rejects codes with length != 8', () async {
      bloc.add(const LinkTvApprove('SHORT'));

      await expectLater(
        bloc.stream,
        emits(predicate<LinkTvState>((s) =>
            s.code == 'SHORT' && s.errorKey == 'link_tv.error_bad_code')),
      );
      expect(repository.lastApprovedCode, isNull);
    });

    test('LinkTvApprove successfully approves 8-character code and requests devices', () async {
      final t1 = DateTime(2026, 9, 10);
      repository.listResult = Success([
        LinkedDevice(id: 'dev-1', deviceName: 'Living Room TV', linkedAt: t1),
      ]);

      bloc.add(const LinkTvApprove('ABCD1234'));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          // 1: submitting
          predicate<LinkTvState>((s) => s.code == 'ABCD1234' && s.submitting == true),
          // 2: approved
          predicate<LinkTvState>((s) =>
              s.submitting == false &&
              s.approved == true &&
              s.approvedDeviceName == 'Living Room Kaizoku TV'),
          // 3: loading devices
          predicate<LinkTvState>((s) => s.loadingDevices == true),
          // 4: devices loaded
          predicate<LinkTvState>((s) =>
              s.loadingDevices == false &&
              s.devices.length == 1 &&
              s.devices.first.deviceName == 'Living Room TV'),
        ]),
      );
      expect(repository.lastApprovedCode, 'ABCD1234');
    });

    test('LinkTvUnlinkRequested removes device from list on success', () async {
      final dev1 = LinkedDevice(id: 'dev-1', deviceName: 'TV 1');
      final dev2 = LinkedDevice(id: 'dev-2', deviceName: 'TV 2');

      // Seed bloc with initial devices
      repository.listResult = Success([dev1, dev2]);
      bloc.add(const LinkTvDevicesRequested());
      await bloc.stream.firstWhere((s) => s.devices.length == 2);

      // Request unlink for dev-1
      bloc.add(const LinkTvUnlinkRequested('dev-1'));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<LinkTvState>((s) => s.unlinkingId == 'dev-1'),
          predicate<LinkTvState>((s) =>
              s.unlinkingId == null &&
              s.devices.length == 1 &&
              s.devices.first.id == 'dev-2'),
        ]),
      );
      expect(repository.lastUnlinkedId, 'dev-1');
    });
  });
}
