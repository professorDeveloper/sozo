// "Keeps happening? Write to support" under an error opens a request that
// already knows where it came from.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:soplay/features/support/data/support_diagnostics.dart';
import 'package:soplay/features/support/data/support_models.dart';
import 'package:soplay/features/support/presentation/widgets/support_suggestion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('it opens a request on the right category, screen and error', (
    tester,
  ) async {
    SupportRequestArgs? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SupportSuggestion(
              screen: 'home',
              category: SupportCategory.content,
              provider: 'anikai',
              error: 'HTTP 503 from anikai',
            ),
          ),
        ),
        GoRoute(
          path: '/support/new',
          builder: (_, state) {
            opened = state.extra as SupportRequestArgs?;
            return const Scaffold(body: Text('NEW REQUEST'));
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('NEW REQUEST'), findsOneWidget);
    expect(opened?.category, SupportCategory.content);
    expect(opened?.screen, 'home');
    expect(opened?.provider, 'anikai');
    expect(opened?.error, 'HTTP 503 from anikai');
  });

  test('the error reaches the diagnostics, shortened', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Sozo',
      packageName: 'com.soplay.sozo',
      version: '3.2.0',
      buildNumber: '8',
      buildSignature: '',
    );
    final d = await SupportDiagnostics.collect(
      language: 'en',
      includeLog: false,
      args: SupportRequestArgs(screen: 'search', error: 'x' * 500),
    );
    expect(d['screen'], 'search');
    expect(d['error']!.length, 200);
    expect(d['error'], endsWith('…'));
  });
}
