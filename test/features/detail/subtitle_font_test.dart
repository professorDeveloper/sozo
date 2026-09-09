import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_style.dart';

void main() {
  group('SubtitleFont', () {
    test('the default names no family, so it inherits the app font', () {
      // The one option that changes nothing for an install that never opens
      // this. Naming a family here would silently restyle every caption in the
      // app on upgrade.
      expect(SubtitleFont.system.family, isNull);
    });

    test('every other option names a family', () {
      for (final f in SubtitleFont.values.where((f) => f != SubtitleFont.system)) {
        expect(f.family, isNotNull, reason: f.id);
        expect(f.family, isNotEmpty, reason: f.id);
      }
    });

    test('ids are unique and stable-looking', () {
      final ids = SubtitleFont.values.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id), isTrue, reason: id);
      }
    });

    test('an unknown or missing id falls back to the default', () {
      expect(SubtitleFont.fromId(null), SubtitleFont.system);
      expect(SubtitleFont.fromId('comic'), SubtitleFont.system);
    });
  });

  group('persistence', () {
    test('the font survives a round trip', () {
      final style = SubtitleStyle.defaults().copyWith(font: SubtitleFont.serif);
      final back = SubtitleStyle.fromJsonString(style.toJsonString());
      expect(back.font, SubtitleFont.serif);
    });

    test('the font is stored by id, not by position', () {
      // An enum written down as an index breaks the moment a value is inserted
      // — and this one is a list that will grow.
      expect(SubtitleStyle.defaults().copyWith(font: SubtitleFont.mono)
          .toJsonString(), contains('"font":"mono"'));
    });

    test('a style saved before fonts existed reads as the default', () {
      // Every install upgrading into this. Anything but the app's own font
      // would restyle their captions without being asked.
      const legacy =
          '{"fontSize":18,"textColor":4294967295,"bgOpacity":0.5,'
          '"bold":true,"edge":1,"position":1}';
      final style = SubtitleStyle.fromJsonString(legacy);
      expect(style.font, SubtitleFont.system);
      expect(style.fontSize, 18, reason: 'the rest still parses');
    });

    test('a corrupt style falls back whole, fonts included', () {
      final style = SubtitleStyle.fromJsonString('not json');
      expect(style.font, SubtitleFont.system);
      expect(style.fontSize, SubtitleStyle.defaults().fontSize);
    });

    test('copyWith leaves the font alone unless asked', () {
      final style = SubtitleStyle.defaults().copyWith(font: SubtitleFont.condensed);
      expect(style.copyWith(fontSize: 24).font, SubtitleFont.condensed);
    });
  });
}
