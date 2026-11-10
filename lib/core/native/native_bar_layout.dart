import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// One slot of a native bar, as the layout needs to know it.
class BarSlotSpec {
  const BarSlotSpec({
    this.extent,
    this.label,
    this.fontSize = 12,
    this.glyph = 20,
    this.hasGlyph = true,
    this.group = 0,
  });

  /// A square slot of this size; null is the bar's own slot size.
  final double? extent;

  /// Words beside the glyph, measured; null is a glyph alone.
  final String? label;
  final double fontSize;
  final double glyph;

  /// False for words alone (quality's "1080" on a compact row).
  final bool hasGlyph;

  /// Which capsule the slot stands in.
  final int group;
}

/// How the slots share the room.
enum BarSpread {
  /// Side by side, the bar as wide as they are.
  packed,

  /// Spread evenly over all of it, as `MainAxisAlignment.spaceEvenly`.
  even,
}

class BarLayout {
  const BarLayout({
    required this.size,
    required this.slots,
    required this.capsules,
  });

  final Size size;
  final List<Rect> slots;

  /// One per group, in group order; empty for a bar without capsules.
  final List<Rect> capsules;
}

/// The room either side of a label, and between its glyph and its words, as
/// the Flutter bottom-row button draws them.
const double _labelInset = 8;
const double _labelGap = 4;

/// Where every slot of a bar goes, or null when they do not fit in
/// [maxExtent] even tightened (slots 44→40, no gap between them).
///
/// RTL mirrors a horizontal bar: the first group, and the first slot in it,
/// start at the right. A caller with physical order (transport) passes LTR.
BarLayout? layoutBar({
  required List<BarSlotSpec> slots,
  required TextDirection dir,
  Axis axis = Axis.horizontal,
  required double maxExtent,
  double slot = 44,
  double gap = 4,
  double padding = 6,
  double groupGap = 16,
  bool capsules = true,
  BarSpread spread = BarSpread.packed,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (slots.isEmpty) return null;
  final labels = [
    for (final s in slots)
      s.label == null ? 0.0 : _measure(s.label!, s.fontSize, dir, textScaler),
  ];
  BarLayout? attempt(double slot, double gap) => _place(
    slots: slots,
    labels: labels,
    dir: dir,
    axis: axis,
    maxExtent: maxExtent,
    slot: slot,
    gap: gap,
    padding: capsules ? padding : 0,
    groupGap: groupGap,
    capsules: capsules,
    spread: spread,
  );
  return attempt(slot, gap) ?? attempt(math.min(slot, 40), 0);
}

double _measure(String text, double size, TextDirection dir, TextScaler s) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w600),
    ),
    textDirection: dir,
    textScaler: s,
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

BarLayout? _place({
  required List<BarSlotSpec> slots,
  required List<double> labels,
  required TextDirection dir,
  required Axis axis,
  required double maxExtent,
  required double slot,
  required double gap,
  required double padding,
  required double groupGap,
  required bool capsules,
  required BarSpread spread,
}) {
  final mains = <double>[];
  for (var i = 0; i < slots.length; i++) {
    final s = slots[i];
    if (s.label != null) {
      final words = s.hasGlyph ? labels[i] : math.max(labels[i], 20.0);
      final glyph = s.hasGlyph ? s.glyph + _labelGap : 0.0;
      mains.add(math.max(slot, glyph + words + _labelInset * 2));
    } else {
      mains.add(s.extent ?? slot);
    }
  }
  final cross = [slot, for (final s in slots) ?s.extent].reduce(math.max);

  final rects = <Rect>[];
  final groupRects = <Rect>[];
  double total;

  Rect rectAt(double main, double length, double crossLength) {
    final c = (cross - crossLength) / 2;
    return axis == Axis.horizontal
        ? Rect.fromLTWH(main, c, length, crossLength)
        : Rect.fromLTWH(c, main, crossLength, length);
  }

  if (spread == BarSpread.even) {
    final used = mains.fold<double>(0, (a, b) => a + b);
    if (used > maxExtent) return null;
    final space = (maxExtent - used) / (slots.length + 1);
    var at = space;
    for (var i = 0; i < slots.length; i++) {
      rects.add(rectAt(at, mains[i], slots[i].extent ?? slot));
      at += mains[i] + space;
    }
    total = maxExtent;
  } else {
    var at = 0.0;
    int? group;
    double groupStart = 0;
    for (var i = 0; i < slots.length; i++) {
      final g = slots[i].group;
      if (g != group) {
        if (group != null) {
          at += padding;
          groupRects.add(rectAt(groupStart, at - groupStart, slot));
          at += groupGap;
        }
        group = g;
        groupStart = at;
        at += padding;
      } else {
        at += gap;
      }
      rects.add(rectAt(at, mains[i], slots[i].extent ?? slot));
      at += mains[i];
    }
    at += padding;
    groupRects.add(rectAt(groupStart, at - groupStart, slot));
    total = at;
    if (total > maxExtent) return null;
  }

  final size = axis == Axis.horizontal
      ? Size(total, cross)
      : Size(cross, total);
  if (axis == Axis.horizontal && dir == TextDirection.rtl) {
    Rect mirror(Rect r) =>
        Rect.fromLTWH(total - r.right, r.top, r.width, r.height);
    return BarLayout(
      size: size,
      slots: [for (final r in rects) mirror(r)],
      capsules: capsules ? [for (final r in groupRects) mirror(r)] : const [],
    );
  }
  return BarLayout(
    size: size,
    slots: rects,
    capsules: capsules ? groupRects : const [],
  );
}
