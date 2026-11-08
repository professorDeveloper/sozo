import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/deeplink/deeplink_service.dart';

void main() {
  testWidgets('opens over Home, so back returns Home', (tester) async {
    final router = GoRouter(
      initialLocation: '/main',
      routes: [
        for (final path in ['/main', '/settings', '/detail'])
          GoRoute(path: path, builder: (_, _) => Text('page $path')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final nav = GoRouterDeeplinkNavigator(router);

    router.go('/settings');
    await tester.pumpAndSettle();
    expect(nav.location, '/settings');

    final opening = nav.openOverHome('/detail', 'args');
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpAndSettle();

    expect(nav.location, '/detail');
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(nav.location, '/main');
    expect(router.canPop(), isFalse);
  });
}
