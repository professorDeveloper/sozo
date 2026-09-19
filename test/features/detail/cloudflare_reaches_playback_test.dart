// Solving a Cloudflare challenge has to change what playback sends, and the
// player has to be able to offer the solve in the first place.
//
// Three separate breaks, each of which made the other two pointless:
//
//   * the player's "Solve Cloudflare" button tested `isCloudflareError` against
//     `_errorMessage`, which by then is a translated PlaybackFaultKind sentence
//     or a humanised line — the words the classifier keys on are gone. The one
//     screen where a challenge is visible to the viewer was the one screen that
//     could not offer to clear it;
//   * playback headers never carried the cookie. CfBypassService can earn a
//     clearance and the Dio client and the JS runtime both send it; the player,
//     which fetches a segment every few seconds, sent nothing — so solving a
//     challenge changed nothing about playback;
//   * the WebView sniffer ran under a hard-coded `Chrome/125` Samsung string.
//     Cloudflare binds cf_clearance to the exact agent that earned it, so that
//     both invalidated whatever the jar held and could never clear a challenge
//     of its own — and those headers travel on to the player.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('the player can offer to solve a challenge', () {
    final controls = read(
      'lib/features/detail/presentation/pages/player_page.controls.dart',
    );
    final media = read(
      'lib/features/detail/presentation/pages/player_page.media.dart',
    );

    test('the test is against the raw failure, not the translated one', () {
      expect(
        controls,
        contains('isCloudflareError(_errorRaw'),
        reason:
            'against _errorMessage this never matched, because the message '
            'has been through .tr() or _humanizeError by then',
      );
      expect(
        controls.contains('isCloudflareError(_errorMessage)'),
        isFalse,
        reason: 'the dead form is still there',
      );
    });

    test('and the raw failure is actually recorded', () {
      // A gate on a field nothing ever sets is the same dead code in a new
      // place.
      expect(media, contains('_errorRaw = raw'));
    });

    test('and cleared with the message it belongs to', () {
      // Otherwise the button survives onto the next, unrelated failure.
      final clears = '_errorMessage = null'.allMatches(media).length;
      final rawClears = '_errorRaw = null'.allMatches(media).length;
      expect(
        rawClears,
        greaterThanOrEqualTo(clears),
        reason: 'a cleared message left a stale raw behind',
      );
    });
  });

  group('playback sends what the solve earned', () {
    final media = read(
      'lib/features/detail/presentation/pages/player_page.media.dart',
    );

    test('stream headers carry the clearance jar', () {
      expect(media, contains('readClearance'));
      expect(
        media,
        contains("merged['Cookie']"),
        reason:
            'the whole jar travels — Cloudflare pairs cf_clearance with the '
            '__cf_bm and _cfuvid it was issued alongside',
      );
    });

    test('and the in-app player uses that builder, not the bare one', () {
      // The external-player branch hands off to another app and keeps the
      // plain headers; the branch that actually fetches segments must not.
      expect(media, contains('await _streamHeaders('));
    });

    test('the loopback proxy is still given nothing', () {
      // It is our own server and already carries the upstream headers; a
      // Cookie for 127.0.0.1 would be nonsense.
      expect(media, contains("uri.host == '127.0.0.1'"));
    });
  });

  test('the sniffer uses the agent the clearance was issued to', () {
    final sniffer = read('lib/core/player/webview_stream_extractor.dart');
    expect(sniffer, contains('kSozoUserAgent'));
    // The constant itself, not the string — the comment explaining the fix
    // mentions the old value, and matching prose would fail on its own
    // documentation.
    expect(
      sniffer.contains('_mobileUserAgent'),
      isFalse,
      reason:
          'a hard-coded agent both invalidates a clearance earned under the '
          'real one and can never clear a managed challenge, which compares '
          'what the header claims against what the engine is',
    );
  });

  test('every ecosystem the solver handles can reach it', () {
    // requestCloudflareSolve has a whole branch for `my:` — Mangayomi runs in
    // the app's own JS runtime rather than behind an Android host — and the
    // providers page disabled the action for exactly that prefix, so the
    // branch was unreachable and those sources had no way out of a challenge.
    final solver = read('lib/features/cloudflare/cloudflare_solver.dart');
    final page = read(
      'lib/features/profile/presentation/pages/providers_page.dart',
    );
    final handled = <String>[
      for (final p in ['an:', 'mn:', 'cs:', 'my:'])
        if (solver.contains("'$p'")) p,
    ];
    expect(handled, contains('my:'), reason: 'the solver does handle my:');
    for (final prefix in handled) {
      expect(
        page,
        contains("provider.id.startsWith('$prefix')"),
        reason: '$prefix is solvable but the UI gate refuses it',
      );
    }
  });

  test('one solve at a time', () {
    // Every branch awaits a platform channel before pushing the page, so two
    // taps stacked two solver routes — solving the visible one returned to
    // another copy of itself.
    final solver = read('lib/features/cloudflare/cloudflare_solver.dart');
    expect(solver, contains('_solving'));
  });
}
