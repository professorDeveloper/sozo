import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/native/sf_symbols.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';

/// Every SF Symbol the player may send, as the phone's own list names them:
/// checked against CoreGlyphs' name_availability.plist (macOS 27, the
/// iOS 26 symbol set); none is newer than iOS 17. A name missing here is a
/// name to check there before it ships, since UIKit draws nothing for one
/// it does not know.
final Set<String> _knownSymbols = {
  'arrow.counterclockwise', 'arrow.down.circle', 'arrow.down.circle.fill', //
  'arrow.up.left.and.arrow.down.right', 'aspectratio', 'backward.end.fill',
  'bubble.left.and.bubble.right', 'captions.bubble', 'captions.bubble.fill',
  'character.bubble', 'chevron.backward', 'ellipsis.circle', 'face.smiling',
  'forward.end.fill', 'forward.fill', 'gauge.with.dots.needle.67percent',
  'gearshape', 'gobackward', 'goforward', 'info.circle', 'info.circle.fill',
  'lock.fill', 'lock.open.fill', 'moon.zzz', 'moon.zzz.fill', 'pause.fill',
  'person.2', 'person.2.fill', 'pip.enter', 'play.fill',
  'rectangle.arrowtriangle.2.outward', 'rectangle.landscape.rotate',
  'rectangle.portrait.rotate', 'rectangle.stack', 'server.rack',
  'slider.horizontal.3', 'sparkles', 'tv.badge.wifi', 'tv.badge.wifi.fill',
  for (final s in [5, 10, 15, 30, 45, 60, 75, 90]) ...[
    'gobackward.$s',
    'goforward.$s',
  ],
};

void main() {
  test('every symbol the player sends is one the phone has', () {
    final sent = {
      ...playerSymbols.values,
      ...activeSymbols.values,
      orientationSymbol(portrait: true),
      orientationSymbol(portrait: false),
      for (var s = 1; s <= 120; s++) ...[rewindSymbol(s), forwardSymbol(s)],
    };
    expect(sent.difference(_knownSymbols), isEmpty);
  });

  test('the fit menu and button wear known symbols', () {
    final source = File(
      'lib/features/detail/presentation/pages/player_page.controls.dart',
    ).readAsStringSync();
    final body = source.substring(
      source.indexOf('static String _fitSymbol('),
      source.indexOf('String _fitLabel('),
    );
    final names = RegExp(r"=> '([^']+)'").allMatches(body).map((m) => m[1]!);
    expect(names, hasLength(3));
    expect(names.toSet().difference(_knownSymbols), isEmpty);
  });

  test('controls Apple draws a certain way wear Apple\'s symbol', () {
    expect(playerSymbol('play'), 'play.fill');
    expect(playerSymbol('pause'), 'pause.fill');
    expect(playerSymbol('previous'), 'backward.end.fill');
    expect(playerSymbol('next'), 'forward.end.fill');
    expect(playerSymbol('subtitles'), 'captions.bubble');
    expect(playerSymbol('speed'), 'gauge.with.dots.needle.67percent');
    expect(playerSymbol('pip'), 'pip.enter');
    expect(playerSymbol('back'), 'chevron.backward');
    expect(playerSymbol('unlock'), 'lock.open.fill');
    // Watch Party is not SharePlay: its symbol would promise Apple's.
    expect(playerSymbol('party'), 'person.2');
    expect(playerSymbol('party', active: true), 'person.2.fill');
  });

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
