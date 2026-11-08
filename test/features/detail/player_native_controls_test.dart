import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/native/native_glass_bar.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';
import 'package:soplay/features/detail/presentation/widgets/player_control_face.dart';

/// The player page cannot be stood up in a test (a resolved stream, getIt, a
/// controller), so its wiring of the native bars is read from the source, as
/// player_controls_visibility_test.dart reads `_controlsVisible`, and the
/// face each control hands a bar is tested on its own.
void main() {
  const dir = 'lib/features/detail/presentation/pages';
  String read(String name) => File('$dir/$name').readAsStringSync();

  group('a control face as a native item', () {
    PlayerControlFace face({
      String id = 'speed',
      String? label,
      String? compactLabel,
      bool compact = false,
      bool pill = false,
      bool active = false,
    }) => PlayerControlFace(
      id: id,
      icon: Icons.speed_rounded,
      semanticLabel: 'Speed',
      label: label,
      compactLabel: compactLabel,
      compact: compact,
      pill: pill,
      active: active,
      onTap: () {},
      menu: const [NativeMenuRow(title: '1x', checked: true)],
      onMenu: (_) {},
    );

    test('keeps its symbol, label, menu and state', () {
      final item = face(label: '1.25x').toNative(group: 1);
      expect(item.symbol, 'gauge.with.dots.needle.67percent');
      expect(item.title, '1.25x');
      expect(item.group, 1);
      expect(item.menu, hasLength(1));
      expect(item.onMenuSelected, isNotNull);
    });

    test('a compact row drops the words, or shows only them', () {
      expect(face(label: '1.25x', compact: true).toNative().title, isNull);
      final quality = face(
        id: 'quality',
        label: 'Auto · 1080p',
        compactLabel: '1080',
        compact: true,
      ).toNative();
      expect(quality.title, '1080');
      expect(quality.hasGlyph, isFalse);
    });

    test('the language pill keeps its code and its smaller type', () {
      final item = face(id: 'language', label: 'UZ', pill: true).toNative();
      expect(item.symbol, 'character.bubble');
      expect(item.title, 'UZ');
      expect(item.fontSize, 11);
    });

    test('an active control wears its filled face', () {
      expect(
        face(id: 'stats', active: true).toNative().symbol,
        'info.circle.fill',
      );
    });
  });

  test('every catalogue control has a face on the top bar', () {
    final source = read('player_page.controls.dart');
    final body = source.substring(
      source.indexOf('PlayerControlFace? _topBarFace('),
      source.indexOf('/// [face] as the Flutter bottom-row button'),
    );
    final missing = [
      for (final spec in PlayerControlCatalogue.all)
        if (!body.contains("case '${spec.id}':")) spec.id,
    ];
    expect(missing, isEmpty);
  });

  test('the native overlay is held at full and only Flutter pieces fade', () {
    final source = read('player_page.controls.dart');
    expect(
      source,
      contains('FadeTransition(opacity: kAlwaysCompleteAnimation'),
    );
    // The glass hold belongs to the shader path only.
    final hold = source.indexOf('GlassHoldWhile(');
    final native = source.indexOf('final overlay = native');
    expect(native, greaterThan(-1));
    expect(hold, greaterThan(native));
    expect(source, contains('_fadeFlutter(const _ControlsScrim())'));
  });

  test('every bar that hides with the controls is told so', () {
    final sources = [
      read('player_page.controls.dart'),
      read('player_page.reactions.dart'),
    ].join('\n');
    final bars = RegExp(r'NativeGlassBar\(').allMatches(sources).length;
    final told = RegExp(
      r'NativeGlassBar\([^;]*?shown: _controlsVisible',
      dotAll: true,
    ).allMatches(sources).length;
    // The unlock pill is the one bar that does not follow the controls.
    expect(bars, 6);
    expect(told, bars - 1);
  });
}
