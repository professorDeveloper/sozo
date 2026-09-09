import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/shader_presets.dart';

void main() {
  group('presets', () {
    test('off runs nothing and downloads nothing', () {
      expect(ShaderPreset.off.isOff, isTrue);
      expect(ShaderPreset.off.chainFor('mid'), isEmpty);
      expect(ShaderPreset.off.chainFor('high'), isEmpty);
    });

    test('every other preset has a chain at both tiers', () {
      // A tier with no chain would silently fall back to the other one, so the
      // "Maximum" setting would quietly do nothing on that preset.
      for (final p in ShaderPreset.all.where((p) => !p.isOff)) {
        for (final tier in ShaderTier.values) {
          expect(p.chainFor(tier.id), isNotEmpty, reason: '${p.id}/${tier.id}');
        }
      }
    });

    test('the high tier is not the same chain as the balanced one', () {
      // If they matched, the GPU-budget choice would be a control with no
      // observable effect — worse than not offering it.
      for (final p in ShaderPreset.all.where((p) => !p.isOff)) {
        expect(
          p.chainFor('high'),
          isNot(equals(p.chainFor('mid'))),
          reason: p.id,
        );
      }
    });

    test('every chain starts by clamping highlights', () {
      // Anime4K's own guidance: without it the restore networks blow out
      // bright line art, which is visible and looks like a bug.
      for (final p in ShaderPreset.all.where((p) => !p.isOff)) {
        for (final tier in ShaderTier.values) {
          expect(
            p.chainFor(tier.id).first,
            contains('Clamp_Highlights'),
            reason: '${p.id}/${tier.id}',
          );
        }
      }
    });

    test('ids are unique and stable-looking', () {
      final ids = ShaderPreset.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id), isTrue, reason: id);
      }
    });

    test('an unknown or missing id falls back to off', () {
      // What an install upgraded from a build with a preset this one dropped
      // will hand us — and the safe landing is "do nothing", not a chain that
      // downloads on somebody's mobile data unasked.
      expect(ShaderPreset.fromId(null).id, 'off');
      expect(ShaderPreset.fromId('turbo_max').id, 'off');
    });

    test('a stored id round-trips', () {
      for (final p in ShaderPreset.all) {
        expect(ShaderPreset.fromId(p.id).id, p.id);
      }
    });
  });

  group('shader files', () {
    test('every path looks like a real repository path', () {
      // These become URLs against a pinned tag. A typo is a 404, and a 404 is
      // a chain that never applies — silently, because failure is silent by
      // design.
      for (final f in ShaderPreset.allFiles) {
        expect(f.endsWith('.glsl'), isTrue, reason: f);
        expect(f.contains('/'), isTrue, reason: '$f has no folder');
        expect(f.startsWith('/'), isFalse, reason: '$f is absolute');
        expect(f.contains('..'), isFalse, reason: '$f escapes the folder');
      }
    });

    test('flattened filenames stay unique', () {
      // The store writes them into one directory by basename. Two different
      // shaders sharing a basename would overwrite each other and produce a
      // chain that runs the wrong network.
      final names = [
        for (final f in ShaderPreset.allFiles) f.split('/').last,
      ];
      expect(names.toSet().length, names.length);
    });

    test('no filename carries the list separator mpv uses', () {
      // The chain is handed to mpv joined by ':'. A name containing one would
      // split into two bogus paths.
      for (final f in ShaderPreset.allFiles) {
        expect(f.split('/').last.contains(':'), isFalse, reason: f);
      }
    });
  });

  group('tiers', () {
    test('an unknown tier is the safe one', () {
      expect(ShaderTier.fromId(null), ShaderTier.mid);
      expect(ShaderTier.fromId('extreme'), ShaderTier.mid);
      expect(ShaderTier.fromId('high'), ShaderTier.high);
    });
  });
}
