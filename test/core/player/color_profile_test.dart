import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/color_profile.dart';

void main() {
  test('natural changes nothing at all', () {
    // The promise the whole feature rests on: somebody who tries this and does
    // not like it gets their exact picture back, not a close approximation.
    expect(ColorProfile.natural.isNeutral, isTrue);
    expect(
      ColorProfile.natural.properties.values.every((v) => v == 0),
      isTrue,
    );
  });

  test('every other profile actually does something', () {
    // A profile that is neutral but not named Natural is a menu entry that
    // looks broken: it is selectable, it is selected, and nothing happens.
    for (final p in ColorProfile.all.where((p) => p.id != 'natural')) {
      expect(p.isNeutral, isFalse, reason: '${p.id} changes nothing');
    }
  });

  test('ids are unique and stable-looking', () {
    final ids = ColorProfile.all.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id), isTrue, reason: id);
    }
  });

  test('every value is inside mpv\'s accepted range', () {
    // mpv clamps out-of-range equalizer values silently, so a typo here would
    // ship as a profile that quietly does less than it says.
    for (final p in ColorProfile.all) {
      for (final entry in p.properties.entries) {
        expect(
          entry.value,
          inInclusiveRange(-100, 100),
          reason: '${p.id}.${entry.key} = ${entry.value}',
        );
      }
    }
  });

  test('the property names are the ones mpv knows', () {
    // Set through a string API, so a misspelling fails at runtime and only on
    // a device — there is no compiler between this list and libmpv.
    expect(
      ColorProfile.natural.properties.keys.toSet(),
      {'brightness', 'contrast', 'saturation', 'gamma', 'hue'},
    );
  });

  test('an unknown or missing id falls back to natural', () {
    // What an install upgraded from a build that had a profile this one dropped
    // will hand us — and the safe landing is the untouched picture.
    expect(ColorProfile.fromId(null).id, 'natural');
    expect(ColorProfile.fromId('').id, 'natural');
    expect(ColorProfile.fromId('vivid_max_2019').id, 'natural');
  });

  test('a stored id round-trips', () {
    for (final p in ColorProfile.all) {
      expect(ColorProfile.fromId(p.id).id, p.id);
    }
  });

  test('every profile names a translation key that exists', () {
    for (final p in ColorProfile.all) {
      expect(p.labelKey.startsWith('player.color_'), isTrue, reason: p.id);
    }
  });
}
