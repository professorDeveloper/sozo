import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `_controlsVisible` is not just a flag the overlay animates on. It is also
/// read by the `IgnorePointer` that decides whether anything on the overlay can
/// be touched, and by `TorrentStatsOverlay`'s `visible`. The fade itself is a
/// `FadeTransition`, which rebuilds only itself — so an assignment without
/// `setState` paints the controls in at full opacity and leaves every one of
/// them inert.
///
/// That is what `_onHDragStart` did: a swipe-seek revealed the controls and
/// killed them in the same motion. Worse, `_scheduleHide` only fires while the
/// video is PLAYING, so pausing in that state left the dead overlay up for
/// good and the only way out was to leave the player.
///
/// Measured before the fix: swipe, then tap the play button — `opacity=1.0`
/// with zero taps delivered. This test is what stops it coming back.
void main() {
  const dir = 'lib/features/detail/presentation/pages';

  /// Character ranges covered by a `setState(` call, parentheses balanced.
  List<(int, int)> setStateRanges(String source) {
    final ranges = <(int, int)>[];
    for (final m in RegExp(r'setState\s*\(').allMatches(source)) {
      var depth = 0;
      for (var i = m.end - 1; i < source.length; i++) {
        final ch = source[i];
        if (ch == '(') depth++;
        if (ch == ')') {
          depth--;
          if (depth == 0) {
            ranges.add((m.start, i));
            break;
          }
        }
      }
    }
    return ranges;
  }

  test('every write to _controlsVisible goes through setState', () {
    final offenders = <String>[];

    for (final file in Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      final ranges = setStateRanges(source);

      // The field's own declaration is an initialiser, not a write.
      for (final m in RegExp(r'(?<!bool )_controlsVisible\s*=(?!=)')
          .allMatches(source)) {
        final inside = ranges.any((r) => m.start > r.$1 && m.start < r.$2);
        if (inside) continue;
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        offenders.add('${file.uri.pathSegments.last}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these writes fade the overlay in without rebuilding the '
          'IgnorePointer that gates it, so the controls appear and do nothing',
    );
  });
}
