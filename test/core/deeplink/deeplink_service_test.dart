import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/deeplink/deeplink_service.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

class _FakeNavigator extends ChangeNotifier implements DeeplinkNavigator {
  _FakeNavigator(this._location);

  String _location;
  final opened = <(String, Object?)>[];

  @override
  String get location => _location;

  void go(String location) {
    _location = location;
    notifyListeners();
  }

  @override
  Future<void> openOverHome(String location, Object? extra) async {
    opened.add((location, extra));
    _location = location.split('?').first;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<(DeeplinkService, _FakeNavigator)> _start(String at) async {
  final nav = _FakeNavigator(at);
  final service = DeeplinkService(
    navigator: () => nav,
    initialLink: () async => null,
    linkStream: const Stream<Uri>.empty(),
  );
  await service.start();
  return (service, nav);
}

void main() {
  test('a link during splash is held, then opened once Home shows', () async {
    final (service, nav) = await _start('/splash');

    await service.handle(
      Uri.parse('https://sozo.azamov.me/play?url=u&provider=hd&ep=3&t=90'),
    );
    await _settle();
    expect(nav.opened, isEmpty);
    expect(service.held, isNotNull);

    nav.go('/main');
    await _settle();

    expect(service.held, isNull);
    expect(nav.opened, hasLength(1));
    final (location, extra) = nav.opened.single;
    expect(location, '/detail');
    final args = extra! as DetailArgs;
    expect(args.contentUrl, 'u');
    expect(args.provider, 'hd');
    expect(args.autoPlay, isTrue);
    expect(args.startEpisode, 3);
    expect(args.startPositionMs, 90000);
    await service.stop();
  });

  test('held through onboarding and the profile picker', () async {
    final (service, nav) = await _start('/splash');
    await service.handle(Uri.parse('sozo://detail?url=u'));

    for (final gated in [
      '/onboarding',
      '/onboarding/genres',
      '/profiles',
      '/pin-verify',
    ]) {
      nav.go(gated);
      await _settle();
      expect(nav.opened, isEmpty, reason: gated);
      expect(service.held, isNotNull, reason: gated);
    }

    nav.go('/main');
    await _settle();
    expect(nav.opened.single.$1, '/detail');
    expect((nav.opened.single.$2! as DetailArgs).autoPlay, isFalse);

    // Spent: later navigation opens nothing more.
    nav.go('/settings');
    await _settle();
    expect(nav.opened, hasLength(1));
    await service.stop();
  });

  test('a warm link opens at once with typed args', () async {
    final (service, nav) = await _start('/settings');

    await service.handle(Uri.parse('sozo://party/ROOM42'));
    await service.handle(Uri.parse('https://sozo.azamov.me/link/TV9'));

    expect(nav.opened.map((o) => o.$1), ['/watch-party', '/link-tv?code=TV9']);
    expect((nav.opened.first.$2! as WatchPartyArgs).code, 'ROOM42');
    await service.stop();
  });

  test('unknown links change nothing', () async {
    final (service, nav) = await _start('/main');

    await service.handle(Uri.parse('https://example.test/detail?url=u'));
    await service.handle(Uri.parse('sozo://nowhere'));
    await service.handle(Uri.parse('sozo://detail'));

    expect(nav.opened, isEmpty);
    expect(service.held, isNull);
    await service.stop();
  });

  test('the initial link is handled like any other', () async {
    final nav = _FakeNavigator('/splash');
    final service = DeeplinkService(
      navigator: () => nav,
      initialLink: () async => Uri.parse('sozo://detail?url=cold'),
      linkStream: const Stream<Uri>.empty(),
    );
    await service.start();
    expect(service.held, isNotNull);
    nav.go('/main');
    await _settle();
    expect((nav.opened.single.$2! as DetailArgs).contentUrl, 'cold');
    await service.stop();
  });
}
