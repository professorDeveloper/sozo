// What a support ticket may carry about the device, and what it keeps out.
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:soplay/core/diagnostics/player_log.dart';
import 'package:soplay/features/support/data/support_diagnostics.dart';
import 'package:soplay/features/support/data/support_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('diagnostics', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Sozo',
        packageName: 'com.soplay.sozo',
        version: '3.2.0',
        buildNumber: '8',
        buildSignature: '',
      );
      PlayerLog.instance.clear();
    });

    test('named fields only, and the log already redacted', () async {
      PlayerLog.instance.add('Cookie: cf_clearance=SECRET');
      PlayerLog.instance.add('GET https://cdn/x.m3u8?token=T0K&expires=9');
      final d = await SupportDiagnostics.collect(
        language: 'uz',
        args: const SupportRequestArgs(
          provider: 'anikai',
          content: 'Frieren · 5',
          screen: 'player',
        ),
      );
      expect(d['app'], '3.2.0');
      expect(d['build'], '8');
      expect(d['language'], 'uz');
      expect(d['provider'], 'anikai');
      expect(d['screen'], 'player');
      expect(d['timezone'], startsWith('UTC'));
      expect(
        d.keys.toSet().difference({
          'app',
          'build',
          'platform',
          'os',
          'locale',
          'language',
          'timezone',
          'engine',
          'network',
          'provider',
          'content',
          'screen',
          'log',
        }),
        isEmpty,
      );
      expect(d['log'], isNot(contains('SECRET')));
      expect(d['log'], isNot(contains('T0K')));
      expect(d['log'], contains('expires=9'));
    });

    test('the viewer can leave the log out', () async {
      PlayerLog.instance.add('something happened');
      final d = await SupportDiagnostics.collect(
        language: 'en',
        includeLog: false,
      );
      expect(d.containsKey('log'), isFalse);
    });

    test('a long log keeps its newest lines', () {
      for (var i = 0; i < 700; i++) {
        PlayerLog.instance.add('line $i');
      }
      final text = PlayerLog.instance.formatForSupport(maxLines: 400);
      expect(text, contains('(400 of 700)'));
      expect(text, contains('line 699'));
      expect(text, isNot(contains('line 299\n')));
    });
  });
}
