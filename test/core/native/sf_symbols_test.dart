import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/native/sf_symbols.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';

void main() {
  test('every control in the catalogue has a symbol', () {
    final missing = [
      for (final spec in PlayerControlCatalogue.all)
        if (!playerSymbols.containsKey(spec.id)) spec.id,
    ];
    expect(missing, isEmpty);
  });

  test('the player pieces outside the catalogue have one too', () {
    for (final id in [
      'back', 'play', 'pause', 'replay', 'rewind', 'forward', 'react', //
      'comments', 'unlock', 'skip',
    ]) {
      expect(playerSymbols[id], isNotNull, reason: id);
    }
  });

  test(
    'a step SF Symbols numbers gets its number, another the plain arrow',
    () {
      expect(rewindSymbol(10), 'gobackward.10');
      expect(rewindSymbol(7), 'gobackward');
      expect(forwardSymbol(30), 'goforward.30');
      expect(forwardSymbol(20), 'goforward');
    },
  );

  test('an active control wears its filled face where it has one', () {
    expect(playerSymbol('stats', active: true), 'info.circle.fill');
    expect(playerSymbol('stats'), 'info.circle');
    expect(playerSymbol('settings', active: true), 'gearshape');
  });
}
