import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/native/native_bar_layout.dart';

void main() {
  const icon = BarSlotSpec();

  test('LTR lays slots left to right inside the capsule padding', () {
    final l = layoutBar(
      slots: const [icon, icon, icon],
      dir: TextDirection.ltr,
      maxExtent: 400,
    )!;
    expect(l.slots.map((r) => r.left), [6, 54, 102]);
    expect(l.size, const Size(6 + 44 * 3 + 4 * 2 + 6, 44));
    expect(l.capsules.single, Offset.zero & l.size);
  });

  test('RTL mirrors the order', () {
    final l = layoutBar(
      slots: const [icon, icon, icon],
      dir: TextDirection.rtl,
      maxExtent: 400,
    )!;
    expect(l.slots.first.right, l.size.width - 6);
    expect(l.slots.first.left, greaterThan(l.slots.last.left));
  });

  test('an even cluster spaces its slots as spaceEvenly does', () {
    final l = layoutBar(
      slots: const [
        BarSlotSpec(extent: 52),
        BarSlotSpec(extent: 72),
        BarSlotSpec(extent: 52),
      ],
      dir: TextDirection.ltr,
      maxExtent: 264,
      capsules: false,
      spread: BarSpread.even,
    )!;
    const space = (264 - 176) / 4;
    expect(l.slots[0].left, space);
    expect(l.slots[1].left, space * 2 + 52);
    expect(l.slots[1].center.dy, l.slots[0].center.dy);
    expect(l.size, const Size(264, 72));
    expect(l.capsules, isEmpty);
  });

  test('a label is measured, and grows with the text scale', () {
    double width(double scale) => layoutBar(
      slots: const [BarSlotSpec(label: 'Server 1080p')],
      dir: TextDirection.ltr,
      maxExtent: 999,
      textScaler: TextScaler.linear(scale),
    )!.slots.single.width;
    expect(width(1), greaterThan(44));
    expect(width(1.5), greaterThan(width(1)));
  });

  test('a bar that does not fit tightens first, then gives up', () {
    final slots = List.filled(8, icon);
    final loose = 6 + 44 * 8 + 4 * 7 + 6;
    final tight = 6 + 40 * 8 + 6;
    expect(
      layoutBar(
        slots: slots,
        dir: TextDirection.ltr,
        maxExtent: loose + 0.0,
      )!.slots.first.width,
      44,
    );
    final squeezed = layoutBar(
      slots: slots,
      dir: TextDirection.ltr,
      maxExtent: tight + 0.0,
    )!;
    expect(squeezed.slots.first.width, 40);
    expect(squeezed.size.width, tight);
    expect(
      layoutBar(slots: slots, dir: TextDirection.ltr, maxExtent: tight - 1.0),
      isNull,
    );
  });

  test('a vertical bar stacks its slots', () {
    final l = layoutBar(
      slots: const [icon, icon],
      dir: TextDirection.rtl,
      axis: Axis.vertical,
      maxExtent: 400,
    )!;
    expect(l.slots.map((r) => r.top), [6, 54]);
    expect(l.slots.every((r) => r.left == 0), isTrue);
    expect(l.size, const Size(44, 6 + 44 * 2 + 4 + 6));
  });

  test('two groups are two capsules with the group gap between', () {
    final l = layoutBar(
      slots: const [icon, BarSlotSpec(group: 1), BarSlotSpec(group: 1)],
      dir: TextDirection.ltr,
      maxExtent: 999,
    )!;
    expect(l.capsules, hasLength(2));
    expect(l.capsules[1].left - l.capsules[0].right, 16);
    expect(l.capsules[0].contains(l.slots[0].center), isTrue);
    expect(l.capsules[1].contains(l.slots[2].center), isTrue);

    final rtl = layoutBar(
      slots: const [icon, BarSlotSpec(group: 1)],
      dir: TextDirection.rtl,
      maxExtent: 999,
    )!;
    expect(rtl.capsules[0].left, greaterThan(rtl.capsules[1].left));
  });
}
