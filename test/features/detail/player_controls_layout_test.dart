import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';
import 'package:soplay/features/detail/presentation/pages/player_page.dart';

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
      final l = PlayerControlsLayout.defaults().move(
        'pip',
        PlayerControlSlot.hidden,
      );
      expect(l.of(PlayerControlSlot.hidden), contains('pip'));
      expect(l.isDefault, isFalse);
    });

    test('an index puts it where the drag ended, not at the end', () {
      final l = PlayerControlsLayout.defaults().move(
        'download',
        PlayerControlSlot.bottomLeft,
        index: 0,
      );
      expect(l.of(PlayerControlSlot.bottomLeft).first, 'download');
    });

    test('an out-of-range index is clamped, not thrown', () {
      final l = PlayerControlsLayout.defaults().move(
        'download',
        PlayerControlSlot.bottomLeft,
        index: 99,
      );
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

    test(
      'a move onto a full bar is refused rather than accepted and squashed',
      () {
        // The bar's overflow behaviour is a FittedBox: an extra button does not
        // wrap or scroll, it shrinks every button until none can be hit.
        final l = fillTopBar();
        expect(l.topBarCount, PlayerControlsLayout.topBarCapacity);
        final outside = PlayerControlCatalogue.all.firstWhere(
          (s) => l.slotOf(s.id) != PlayerControlSlot.topBar,
        );
        expect(l.canMove(outside.id, PlayerControlSlot.topBar), isFalse);
        expect(
          l.moveRefusal(outside.id, PlayerControlSlot.topBar),
          'player.layout_top_bar_full',
        );
      },
    );

    test('a refused move leaves the layout untouched', () {
      // move() is reachable without asking canMove first, and a caller that
      // skips the check must still not be able to build an invalid bar.
      final l = fillTopBar();
      final outside = PlayerControlCatalogue.all.firstWhere(
        (s) => l.slotOf(s.id) != PlayerControlSlot.topBar,
      );
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
      expect(
        l.moveRefusal('settings', PlayerControlSlot.hidden),
        'player.layout_pinned',
      );
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
      final pinned = PlayerControlCatalogue.all
          .where((s) => s.pinned)
          .map((s) => s.id);
      expect(pinned, ['settings']);
    });
  });

  group('surviving an upgrade', () {
    test(
      'legacy bottom-left episode controls migrate beside the seek buttons',
      () {
        final layout = PlayerControlsLayout.fromStored({
          'bottomLeft': ['previous', 'next'],
          'hidden': ['stats'],
        });
        expect(layout.slotOf('previous'), PlayerControlSlot.center);
        expect(layout.slotOf('next'), PlayerControlSlot.center);
        expect(
          layout.of(PlayerControlSlot.bottomLeft),
          isNot(contains('previous')),
        );
      },
    );
    test('modern explicit layout and hidden episode controls survive', () {
      final layout = PlayerControlsLayout.fromStored({
        'center': <String>[],
        'bottomLeft': ['previous'],
        'hidden': ['next'],
      });
      expect(layout.slotOf('previous'), PlayerControlSlot.bottomLeft);
      expect(layout.slotOf('next'), PlayerControlSlot.hidden);
    });

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

    test(
      'a control that no longer exists is dropped, not carried as a ghost',
      () {
        final l = PlayerControlsLayout.fromStored({
          'topBar': ['subtitles', 'chromecast_v1_removed'],
        });
        expect(
          l.of(PlayerControlSlot.topBar),
          isNot(contains('chromecast_v1_removed')),
        );
      },
    );

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
          'subtitles',
          'settings',
          'lock',
          'orientation',
          'language',
          'speed',
          'quality',
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
      expect(
        l
            .reorder(PlayerControlSlot.bottomLeft, 0, 1)
            .of(PlayerControlSlot.bottomLeft),
        isEmpty,
      );
    });

    test('a drag that ends off the edge is clamped', () {
      final l = PlayerControlsLayout.defaults();
      expect(
        () => l.reorder(PlayerControlSlot.bottomRight, 99, -4),
        returnsNormally,
      );
    });
  });

  group('the lock follows the orientation, not the saved slot', () {
    // The saved arrangement has no orientation in it, so resolvedLockSlot is
    // where "landscape puts the lock up top" actually lives. The bars
    // themselves cannot be pumped — every widget in player_page.controls.dart
    // is library-private and needs a live _PlayerPageState behind it — so this
    // is the seam that carries the rule.

    test('landscape lifts a bottom-row lock onto the top bar', () {
      final l = PlayerControlsLayout.defaults();
      expect(l.slotOf('lock'), PlayerControlSlot.bottomRight);
      expect(
        resolvedLockSlot(
          stored: l.slotOf('lock'),
          portrait: false,
          topBarCount: l.topBarCount,
        ),
        PlayerControlSlot.topBar,
      );
    });

    test('a lock stored in the left group is lifted too', () {
      // Either bottom group counts. The viewer can drag it to bottomLeft and
      // the complaint — a lock among the seek-bar controls — is the same one.
      final l = PlayerControlsLayout.defaults().move(
        'lock',
        PlayerControlSlot.bottomLeft,
      );
      expect(
        resolvedLockSlot(
          stored: l.slotOf('lock'),
          portrait: false,
          topBarCount: l.topBarCount,
        ),
        PlayerControlSlot.topBar,
      );
    });

    test('portrait draws no lock button at all', () {
      // Unchanged from before the move, and for the unchanged reason: the only
      // way out of the lock overlay is a tap target a D-pad cannot reach.
      expect(
        resolvedLockSlot(
          stored: PlayerControlSlot.bottomRight,
          portrait: true,
          topBarCount: 0,
        ),
        PlayerControlSlot.hidden,
      );
    });

    test('a lock the viewer hid stays hidden', () {
      // Hiding is a decision, not an absence, and the hoist must not undo it.
      expect(
        resolvedLockSlot(
          stored: PlayerControlSlot.hidden,
          portrait: false,
          topBarCount: 0,
        ),
        PlayerControlSlot.hidden,
      );
    });

    test('a lock the viewer already put on the top bar is left alone', () {
      // Nothing to lift. If this said topBar by lifting rather than by leaving
      // it, the bar would draw two of them.
      expect(
        resolvedLockSlot(
          stored: PlayerControlSlot.topBar,
          portrait: false,
          topBarCount: PlayerControlsLayout.topBarCapacity,
        ),
        PlayerControlSlot.topBar,
      );
    });

    test('a full top bar keeps the lock where the viewer put it', () {
      // The ceiling is a FittedBox, so one button past it shrinks them all past
      // the point of being hittable. A lock still reachable at the bottom beats
      // a top bar nobody can aim at.
      //
      // The ceiling here is the LANDSCAPE one. The lock only ever moves in
      // landscape, and six is a portrait number — a phone held sideways has
      // about twice the room beside the title.
      expect(
        resolvedLockSlot(
          stored: PlayerControlSlot.bottomRight,
          portrait: false,
          topBarCount: PlayerControlsLayout.landscapeTopBarCapacity,
        ),
        PlayerControlSlot.bottomRight,
      );
    });

    test('the portrait ceiling does not hold the lock down in landscape', () {
      // The regression this guards: the hoist read `topBarCapacity`, which is
      // derived from the narrowest PORTRAIT phone, so a landscape bar with
      // room for nine refused the lock at six and left it in the crowded row
      // the move exists to thin out.
      expect(
        resolvedLockSlot(
          stored: PlayerControlSlot.bottomRight,
          portrait: false,
          topBarCount: PlayerControlsLayout.topBarCapacity,
        ),
        PlayerControlSlot.topBar,
      );
    });

    test('the saved arrangement is never rewritten by the lift', () {
      // Turning the phone must not cost the viewer their layout. The stored
      // slot is read, resolved, and left alone — so turning back restores it.
      final stored = PlayerControlsLayout.defaults().toStored();
      resolvedLockSlot(
        stored: PlayerControlsLayout.fromStored(stored).slotOf('lock'),
        portrait: false,
        topBarCount: 6,
      );
      expect(
        PlayerControlsLayout.fromStored(stored).slotOf('lock'),
        PlayerControlSlot.bottomRight,
      );
    });
  });

  group('the bottom control row', () {
    Widget box(String key) =>
        SizedBox(key: ValueKey(key), width: 44, height: 44);

    Future<void> pump(
      WidgetTester tester, {
      required List<Widget> leading,
      required List<Widget> trailing,
      double width = 800,
    }) async {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerBottomControlRow(
                leading: leading,
                trailing: trailing,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('both groups sit centred, not at the two edges', (
      tester,
    ) async {
      await pump(
        tester,
        leading: [box('prev'), box('next')],
        trailing: [box('speed'), box('quality'), box('subs')],
      );
      final first = tester.getRect(find.byKey(const ValueKey('prev')));
      final last = tester.getRect(find.byKey(const ValueKey('subs')));
      expect((first.left + last.right) / 2, closeTo(400, 0.5));
      // And they are one block: spaceBetween would have left the whole middle
      // of the bar empty between the two groups.
      expect(last.right - first.left, lessThan(300));
    });

    testWidgets('a film, with no transport group, is centred too', (
      tester,
    ) async {
      // This is the case that used to fall back to MainAxisAlignment.start and
      // pile everything against the left edge.
      await pump(
        tester,
        leading: const [],
        trailing: [box('speed'), box('quality')],
      );
      final first = tester.getRect(find.byKey(const ValueKey('speed')));
      final last = tester.getRect(find.byKey(const ValueKey('quality')));
      expect((first.left + last.right) / 2, closeTo(400, 0.5));
    });

    testWidgets('the two groups stay visibly apart', (tester) async {
      // Centring them together must not read as one undifferentiated row.
      await pump(
        tester,
        leading: [box('prev')],
        trailing: [box('speed')],
      );
      final left = tester.getRect(find.byKey(const ValueKey('prev')));
      final right = tester.getRect(find.byKey(const ValueKey('speed')));
      expect(
        right.left - left.right,
        closeTo(PlayerBottomControlRow.groupGap, 0.5),
      );
    });

    testWidgets('more controls than fit scroll instead of overflowing', (
      tester,
    ) async {
      // A centred row that clips loses controls at BOTH ends. The viewer can
      // put ten things down here from the layout editor.
      await pump(
        tester,
        leading: const [],
        trailing: [for (var i = 0; i < 10; i++) box('c$i')],
        width: 200,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  test('the returned lists cannot be edited behind the layout', () {
    final l = PlayerControlsLayout.defaults();
    expect(
      () => l.of(PlayerControlSlot.topBar).add('x'),
      throwsUnsupportedError,
    );
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/player_controls_layout.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });

  group('the session controls ride up with the lock in landscape', () {
    test('as many as the bar has room for, in order', () {
      // The complaint was that one eleven-wide row carried everything while a
      // landscape top bar sat half empty. These four are what a session is
      // doing rather than what is playing, so they are the ones that move.
      expect(kLandscapeHoistOrder, ['cast', 'pip', 'sleep', 'party']);
      expect(
        landscapeHoists(candidates: kLandscapeHoistOrder, topBarRendered: 5),
        ['cast', 'pip', 'sleep', 'party'],
      );
    });

    test('a nearly full bar takes only what fits', () {
      expect(
        landscapeHoists(
          candidates: kLandscapeHoistOrder,
          topBarRendered: PlayerControlsLayout.landscapeTopBarCapacity - 2,
        ),
        ['cast', 'pip'],
      );
    });

    test('a full bar takes none, and does not go negative', () {
      expect(
        landscapeHoists(
          candidates: kLandscapeHoistOrder,
          topBarRendered: PlayerControlsLayout.landscapeTopBarCapacity,
        ),
        isEmpty,
      );
      expect(
        landscapeHoists(
          candidates: kLandscapeHoistOrder,
          topBarRendered: PlayerControlsLayout.landscapeTopBarCapacity + 3,
        ),
        isEmpty,
      );
    });

    test('nothing to lift is not an error', () {
      expect(landscapeHoists(candidates: const [], topBarRendered: 0), isEmpty);
    });

    test('the landscape ceiling is above the portrait one', () {
      // If these ever met, the hoist would be a no-op on every phone and the
      // bottom row would quietly go back to carrying everything.
      expect(
        PlayerControlsLayout.landscapeTopBarCapacity,
        greaterThan(PlayerControlsLayout.topBarCapacity),
      );
    });
  });

}
