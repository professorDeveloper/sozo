import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/trailer/trailer_query.dart';
import 'package:soplay/core/trailer/trailer_service.dart';
import 'package:soplay/features/detail/presentation/widgets/hero_trailer_preview.dart';

class _Settings implements HiveService {
  @override
  bool get heroTrailerAutoplay => true;
  @override
  final heroTrailerAutoplayChanged = ValueNotifier<bool>(true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Trailers implements TrailerService {
  int requests = 0;
  @override
  Future<TrailerResult?> resolveFor(TrailerQuery query) async {
    requests++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _query = TrailerQuery(title: 'Fixture', year: null, isSerial: false);

void main() {
  late _Trailers trailers;
  setUp(() {
    trailers = _Trailers();
    getIt.registerSingleton<HiveService>(_Settings());
    getIt.registerSingleton<TrailerService>(trailers);
  });
  tearDown(() async => getIt.reset());

  testWidgets('covered detail route cannot start a delayed trailer', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(
          body: HeroTrailerPreview(query: _query, active: true),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Reader')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(trailers.requests, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(trailers.requests, 1);
  });

  testWidgets('background cancels delayed start until app resumes', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HeroTrailerPreview(query: _query, active: true)),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(trailers.requests, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(trailers.requests, 1);
  });

  testWidgets('returning to header schedules a canceled preview again', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: active,
            builder: (_, value, _) =>
                HeroTrailerPreview(query: _query, active: value),
          ),
        ),
      ),
    );
    active.value = false;
    await tester.pump();
    active.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(trailers.requests, 1);
    await tester.pumpWidget(const SizedBox());
    active.dispose();
  });
}
