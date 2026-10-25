// PlayerPage needs the service locator, Hive and a video engine, so it is not
// pumped here. These pin the few lines of it that the desktop corner player
// and the always-on-top mini window depend on, in the same source-scan style
// as player_controls_visibility_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const dir = 'lib/features/detail/presentation/pages';
  String read(String name) => File('$dir/$name').readAsStringSync();

  /// The body of the first `case <label>:` up to the next `case` / `}` at
  /// the same indent.
  String caseBody(String source, String label) {
    final start = source.indexOf('case $label:');
    expect(start, isNonNegative, reason: label);
    final rest = source.substring(start + label.length + 6);
    final end = RegExp(r'\n      case |\n    }').firstMatch(rest)?.start;
    return rest.substring(0, end ?? rest.length);
  }

  test('a desktop focus change does not undo the compact player', () {
    // On the desktop `resumed` fires whenever the window gets focus back. It
    // used to clear _isPip unconditionally, which drew the full control bar
    // into the 426-px always-on-top window on the first click.
    final resumed = caseBody(
      read('player_page.dart'),
      'AppLifecycleState.resumed',
    );
    expect(resumed, contains('_isPip = false'));
    expect(resumed, contains('!_compact'));
  });

  test('_compact covers both small forms', () {
    expect(
      read('player_page.dart'),
      contains('bool get _compact => _desktopMini || _docked;'),
    );
  });

  test('the small player draws its own controls in both forms', () {
    final page = read('player_page.dart');
    expect(page, contains('if (_compact) _buildDesktopMiniOverlay()'));
    expect(page, isNot(contains('if (_desktopMini) _buildDesktopMiniOverlay')));
  });

  test('leaving from the corner closes it rather than popping a route', () {
    final controls = read('player_page.controls.dart');
    final exit = controls.substring(controls.indexOf('void _exit() {'));
    final docked = exit.indexOf('if (_docked)');
    final pop = exit.indexOf('context.canPop()');
    expect(docked, isNonNegative);
    expect(pop, isNonNegative);
    expect(docked, lessThan(pop));
  });

  test('the docking pop does not release what the corner still uses', () {
    final page = read('player_page.dart');
    final pop = page.substring(page.indexOf('onPopInvokedWithResult'));
    expect(
      pop.indexOf('if (_docked) return;'),
      lessThan(pop.indexOf('_restoreSystemUi();')),
    );
  });

  test('the PiP button docks, and a long press pops the window out', () {
    final controls = read('player_page.controls.dart');
    final taps = RegExp(
      r'icon: Icons\.picture_in_picture_alt_rounded,\s*'
      r'onTap: _openMiniPlayer,\s*'
      r'onLongPress: _toggleDesktopMini,',
    ).allMatches(controls);
    // The desktop control row and the layout's 'pip' control.
    expect(taps.length, 2);
    expect(controls, isNot(contains('onTap: _toggleDesktopMini')));
  });

  test('/player builds through PlayerRoute, which keys the page', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final route = router.substring(router.indexOf("path: '/player',"));
    final body = route.substring(0, route.indexOf('GoRoute('));
    expect(body, contains('PlayerRoute(args: args)'));
    expect(body, isNot(contains('PlayerPage(')));
  });

  test('a disposed page is forgotten by the dock', () {
    final page = read('player_page.dart');
    final dispose = page.substring(page.indexOf('void dispose() {'));
    expect(dispose, contains('PlayerDock.instance.forget('));
  });
}
