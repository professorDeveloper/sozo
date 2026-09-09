import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';

void main() {
  group('defaults', () {
    test('every control in the catalogue has a place', () {
      final l = PlayerControlsLayout.defaults();
      final placed = <String>{
        for (final slot in PlayerControlSlot.values) ...l.of(slot),
      };
      expect(placed.length, PlayerControlCatalogue.all.length);
      for (final spec in PlayerControlCatalogue.all) {
        expect(placed, contains(spec.id), reason: spec.id);
      }
    });

    test('the shipped top bar leaves room for one more', () {
      // Not just "within the ceiling" — ON the ceiling would make the editor
      // refuse the first move anybody tries, which reads as a broken screen
      // rather than a full bar.
      final l = PlayerControlsLayout.defaults();
      expect(l.topBarCount, lessThan(PlayerControlsLayout.topBarCapacity));
    });

    test('defaults report themselves as default', () {
      expect(PlayerControlsLayout.defaults().isDefault, isTrue);
    });

    test('ids are unique — two controls cannot share a stored key', () {
      final ids = PlayerControlCatalogue.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('moving', () {
    test('a control changes slot and leaves the old one', () {
      final l = PlayerControlsLayout.defaults().move(
        'speed',
        PlayerControlSlot.topBar,
      );
      expect(l.slotOf('speed'), PlayerControlSlot.topBar);
      expect(l.of(PlayerControlSlot.bottomRight), isNot(contains('speed')));
    });

    test('hiding is a move like any other', () {
      final l = PlayerControlsLayout.defaults()
          .move('pip', PlayerControlSlot.hidden);
      expect(l.of(PlayerControlSlot.hidden), contains('pip'));
      expect(l.isDefault, isFalse);
    });

    test('an index puts it where the drag ended, not at the end', () {
      final l = PlayerControlsLayout.defaults()
          .move('download', PlayerControlSlot.bottomLeft, index: 0);
      expect(l.of(PlayerControlSlot.bottomLeft).first, 'download');
    });

    test('an out-of-range index is clamped, not thrown', () {
      final l = PlayerControlsLayout.defaults()
          .move('download', PlayerControlSlot.bottomLeft, index: 99);
      expect(l.of(PlayerControlSlot.bottomLeft), contains('download'));
    });
  });

  group('the top bar has a real ceiling', () {
    PlayerControlsLayout fillTopBar() {
      var l = PlayerControlsLayout.defaults();
      final movable = PlayerControlCatalogue.all
          .where((s) => l.slotOf(s.id) != PlayerControlSlot.topBar)
          .map((s) => s.id);
      for (final id in movable) {
        l = l.move(id, PlayerControlSlot.topBar);
      }
      return l;
    }

    test('a move onto a full bar is refused rather than accepted and squashed',
        () {
      // The bar's overflow behaviour is a FittedBox: an extra button does not
      // wrap or scroll, it shrinks every button until none can be hit.
      final l = fillTopBar();
      expect(l.topBarCount, PlayerControlsLayout.topBarCapacity);
      final outside = PlayerControlCatalogue.all
          .firstWhere((s) => l.slotOf(s.id) != PlayerControlSlot.topBar);
      expect(l.canMove(outside.id, PlayerControlSlot.topBar), isFalse);
      expect(l.moveRefusal(outside.id, PlayerControlSlot.topBar),
          'player.layout_top_bar_full');
    });

    test('a refused move leaves the layout untouched', () {
      // move() is reachable without asking canMove first, and a caller that
      // skips the check must still not be able to build an invalid bar.
      final l = fillTopBar();
      final outside = PlayerControlCatalogue.all
          .firstWhere((s) => l.slotOf(s.id) != PlayerControlSlot.topBar);
      final after = l.move(outside.id, PlayerControlSlot.topBar);
      expect(after.topBarCount, PlayerControlsLayout.topBarCapacity);
      expect(after.slotOf(outside.id), l.slotOf(outside.id));
    });

    test('reordering within a full bar is always allowed', () {
      // The ceiling is about how many fit, not about which order they are in.
      final l = fillTopBar();
      final first = l.of(PlayerControlSlot.topBar).first;
      expect(l.canMove(first, PlayerControlSlot.topBar), isTrue);
    });
  });

  group('the pinned control', () {
    test('settings cannot be hidden', () {
      // It is the way back to every panel that is not on a bar, so hiding it
      // hides the screen that would undo the hiding.
      final l = PlayerControlsLayout.defaults();
      expect(l.canMove('settings', PlayerControlSlot.hidden), isFalse);
      expect(l.moveRefusal('settings', PlayerControlSlot.hidden),
          'player.layout_pinned');
      expect(
        l.move('settings', PlayerControlSlot.hidden).slotOf('settings'),
        PlayerControlSlot.topBar,
      );
    });

    test('and storage that hides it anyway is corrected on load', () {
      final l = PlayerControlsLayout.fromStored({
        'topBar': ['subtitles'],
        'hidden': ['settings'],
      });
      expect(l.slotOf('settings'), PlayerControlSlot.topBar);
    });

    test('exactly one thing is pinned', () {
      final pinned =
          PlayerControlCatalogue.all.where((s) => s.pinned).map((s) => s.id);
      expect(pinned, ['settings']);
    });
  });

  group('surviving an upgrade', () {
    test('a control added since the layout was saved appears in its default '
        'slot', () {
      // Absent from storage means NEW — hiding writes the id into the hidden
      // list, so the two are distinguishable. Without this an upgrade leaves
      // the new control invisible forever with nothing on screen to say why.
      final stored = PlayerControlsLayout.defaults().toStored()
        ..forEach((_, v) => v.remove('cast'));
      final l = PlayerControlsLayout.fromStored(stored);
      expect(l.slotOf('cast'), PlayerControlSlot.bottomRight);
    });

    test('a deliberately hidden control stays hidden across a reload', () {
      // The other half of the same rule: hidden must not be mistaken for new.
      final stored = PlayerControlsLayout.defaults()
          .move('pip', PlayerControlSlot.hidden)
          .toStored();
      expect(
        PlayerControlsLayout.fromStored(stored).slotOf('pip'),
        PlayerControlSlot.hidden,
      );
    });

    test('a control that no longer exists is dropped, not carried as a ghost',
        () {
      final l = PlayerControlsLayout.fromStored({
        'topBar': ['subtitles', 'chromecast_v1_removed'],
      });
      expect(l.of(PlayerControlSlot.topBar), isNot(contains('chromecast_v1_removed')));
    });

    test('an id stored twice lands once', () {
      final l = PlayerControlsLayout.fromStored({
        'topBar': ['speed'],
        'bottomRight': ['speed'],
      });
      final count = PlayerControlSlot.values
          .expand((s) => l.of(s))
          .where((id) => id == 'speed')
          .length;
      expect(count, 1);
    });

    test('a stored bar over capacity spills the overflow into hidden', () {
      // An older build with a larger ceiling. Deterministic and in stored
      // order, so the viewer's first choices are the ones kept.
      final l = PlayerControlsLayout.fromStored({
        'topBar': [
          'subtitles', 'settings', 'lock', 'orientation', 'language',
          'speed', 'quality',
        ],
      });
      expect(l.topBarCount, PlayerControlsLayout.topBarCapacity);
      expect(l.of(PlayerControlSlot.hidden), contains('quality'));
      expect(l.of(PlayerControlSlot.topBar), contains('subtitles'));
    });

    test('empty storage is the defaults, not an empty player', () {
      expect(PlayerControlsLayout.fromStored(const {}).isDefault, isTrue);
    });

    test('a round trip through storage changes nothing', () {
      final edited = PlayerControlsLayout.defaults()
          .move('cast', PlayerControlSlot.topBar)
          .move('pip', PlayerControlSlot.hidden)
          .reorder(PlayerControlSlot.bottomRight, 0, 2);
      final back = PlayerControlsLayout.fromStored(edited.toStored());
      for (final slot in PlayerControlSlot.values) {
        expect(back.of(slot), edited.of(slot), reason: slot.name);
      }
    });
  });

  group('reordering', () {
    test('moves one control past another', () {
      final l = PlayerControlsLayout.defaults();
      final before = l.of(PlayerControlSlot.bottomRight);
      final after = l.reorder(PlayerControlSlot.bottomRight, 0, 2);
      expect(after.of(PlayerControlSlot.bottomRight)[2], before[0]);
    });

    test('an empty slot is a no-op, not a crash', () {
      final l = PlayerControlsLayout.defaults()
          .move('previous', PlayerControlSlot.hidden)
          .move('next', PlayerControlSlot.hidden);
      expect(l.of(PlayerControlSlot.bottomLeft), isEmpty);
      expect(l.reorder(PlayerControlSlot.bottomLeft, 0, 1).of(PlayerControlSlot.bottomLeft),
          isEmpty);
    });

    test('a drag that ends off the edge is clamped', () {
      final l = PlayerControlsLayout.defaults();
      expect(
        () => l.reorder(PlayerControlSlot.bottomRight, 99, -4),
        returnsNormally,
      );
    });
  });

  test('the returned lists cannot be edited behind the layout', () {
    final l = PlayerControlsLayout.defaults();
    expect(() => l.of(PlayerControlSlot.topBar).add('x'), throwsUnsupportedError);
  });

  test('the domain layer stays free of Flutter', () {
    final source =
        File('lib/features/detail/domain/player_controls_layout.dart')
            .readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
