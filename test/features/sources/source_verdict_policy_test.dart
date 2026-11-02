// Which verdict a row is entitled to: a datacenter cannot speak for a source
// that runs on the handset, and the hide-down count is the count of what hiding
// takes away.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
import 'package:soplay/features/sources/domain/source_verdict_policy.dart';

RemoteVerdict dead(String reason) =>
    RemoteVerdict(state: RemoteHealth.dead, reason: reason);

void main() {
  group('who may call a source down', () {
    test('a sweep that could not reach the site says nothing about a '
        'source that runs on the phone', () {
      for (final reason in ['timeout', 'unreachable', 'tls', 'slow_response']) {
        expect(shownVerdict('an:1', dead(reason)), isNull, reason: reason);
        expect(shownVerdict('cs:1', dead(reason)), isNull, reason: reason);
        expect(shownVerdict('my:1', dead(reason)), isNull, reason: reason);
        expect(shownVerdict('mn:1', dead(reason)), isNull, reason: reason);
        expect(shownVerdict('jf:1', dead(reason)), isNull, reason: reason);
      }
    });

    test('the same answer stands for a Sozo source, which only ever reaches '
        'the app through that same backend', () {
      for (final reason in ['timeout', 'unreachable', 'tls']) {
        expect(shownVerdict('kisskh', dead(reason))?.state, RemoteHealth.dead);
      }
    });

    test('a fact about the domain or the site itself stands wherever it was '
        'found', () {
      for (final reason in [
        'dns',
        'parked',
        'maintainer_down',
        'http_503',
        'http_5xx',
      ]) {
        expect(
          shownVerdict('mn:1', dead(reason))?.state,
          RemoteHealth.dead,
          reason: reason,
        );
      }
    });

    test('a bot wall is not a down verdict and is left alone', () {
      final wall = const RemoteVerdict(
        state: RemoteHealth.cloudflare,
        reason: 'blocked',
      );
      expect(shownVerdict('mn:1', wall)?.state, RemoteHealth.cloudflare);
    });

    test('this phone own answer is never second-guessed', () {
      final here = const RemoteVerdict(
        state: RemoteHealth.dead,
        reason: 'timeout',
        onDevice: true,
      );
      expect(shownVerdict('mn:1', here)?.onDevice, isTrue);
    });

    test('nothing known is no badge', () {
      expect(shownVerdict('mn:1', null), isNull);
    });
  });

  group('what counts as a problem', () {
    test('an empty catalogue is not health', () {
      expect(isProblemVerdict(SourceVerdict.empty), isTrue);
      expect(isProblemVerdict(SourceVerdict.failing), isTrue);
      expect(isProblemVerdict(SourceVerdict.dead), isTrue);
      expect(isProblemVerdict(SourceVerdict.blocked), isTrue);
      expect(isProblemVerdict(SourceVerdict.outdated), isTrue);
      expect(isProblemVerdict(SourceVerdict.alive), isFalse);
      expect(isProblemVerdict(SourceVerdict.unknown), isFalse);
    });
  });

  group('the whole way through the store', _endToEnd);

  group('hiding down sources', () {
    final rows = ['a', 'down1', 'b', 'down2', 'current'];
    bool isDown(String id) => id.startsWith('down') || id == 'current';

    test('the count is the number of rows hiding removes', () {
      final hidden = partitionDown(
        rows,
        isDown: isDown,
        keep: (r) => r == 'current',
        hide: true,
      );
      expect(hidden.rows, ['a', 'b', 'current']);
      expect(hidden.hidable, rows.length - hidden.rows.length);
      expect(hidden.hidable, 2);
    });

    test('and is the same before the switch is flipped', () {
      final shown = partitionDown(
        rows,
        isDown: isDown,
        keep: (r) => r == 'current',
      );
      expect(shown.hidable, 2);
      // Sunk, not gone: the down ones are last and the order within each half
      // is the one they arrived in.
      expect(shown.rows, ['a', 'b', 'down1', 'down2', 'current']);
    });

    test('a list with nothing down is handed back untouched', () {
      final untouched = partitionDown(rows, isDown: (_) => false, hide: true);
      expect(identical(untouched.rows, rows), isTrue);
      expect(untouched.hidable, 0);
    });
  });
}

/// The same question asked of the real store rather than of the policy alone:
/// the report the backend actually serves, through `refreshRemote`, out again
/// as the verdict a row is handed. The reason string is the whole hinge of the
/// policy, and it only reaches a badge if the store keeps it — so prove the
/// path end to end rather than the two halves separately.
void _endToEnd() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_verdict_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('the live report, through the store, loses only the verdicts that '
      'were never about this phone', () async {
    // Shaped exactly as `/api/contents/providers/health` answers today: an
    // ISO date, `sources` empty, and each extension carrying `state`, `cf`
    // and the reason the sweep recorded. The four ids below are the four
    // cases the live payload is made of.
    final store = SourceHealthStore(
      remote: () async => {
        'checkedAt': null,
        'sources': const <String, dynamic>{},
        'extCheckedAt': DateTime.now().toUtc().toIso8601String(),
        'extensions': const {
          'my:1': {'state': 'dead', 'cf': false, 'reason': 'timeout'},
          'an:2': {'state': 'dead', 'cf': false, 'reason': 'tls'},
          'mn:3': {'state': 'dead', 'cf': false, 'reason': 'dns'},
          'mn:4': {'state': 'dead', 'cf': false, 'reason': 'http_503'},
          'kisskh': {'state': 'dead', 'cf': false, 'reason': 'unreachable'},
        },
      },
    );
    await store.refreshRemote();

    // What the store found, before the policy has had a look: all five down.
    expect(
      [
        for (final id in ['my:1', 'an:2', 'mn:3', 'mn:4', 'kisskh'])
          store.badgeOf(id)?.state,
      ],
      List.filled(5, RemoteHealth.dead),
    );

    // And what a row is entitled to show. The two the datacenter could not
    // reach run on the handset, so nothing has been established about them;
    // the Sozo source reaches the app through that same backend, so its
    // answer stands.
    expect(shownVerdict('my:1', store.badgeOf('my:1')), isNull);
    expect(shownVerdict('an:2', store.badgeOf('an:2')), isNull);
    expect(shownVerdict('mn:3', store.badgeOf('mn:3'))?.reason, 'dns');
    expect(shownVerdict('mn:4', store.badgeOf('mn:4'))?.reason, 'http_503');
    expect(
      shownVerdict('kisskh', store.badgeOf('kisskh'))?.state,
      RemoteHealth.dead,
    );
  });
}
