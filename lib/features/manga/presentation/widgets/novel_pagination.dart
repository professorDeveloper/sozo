import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

/// Everything that decides where a page breaks. Equal metrics give equal
/// pages, which is how the reader knows when to paginate again.
@immutable
class NovelPageMetrics {
  const NovelPageMetrics({
    required this.width,
    required this.height,
    required this.fontSize,
    required this.lineHeight,
    required this.justify,
    required this.paragraphSpacing,
    this.fontFamily,
    this.textScaler = TextScaler.noScaling,
    this.baseStyle = const TextStyle(),
    this.firstPageInset = 0,
    this.textDirection = TextDirection.ltr,
    this.locale,
  });

  final double width;
  final double height;
  final double fontSize;
  final double lineHeight;
  final bool justify;
  final double paragraphSpacing;
  final String? fontFamily;
  final TextScaler textScaler;

  /// The ambient text style the rendered page inherits.
  final TextStyle baseStyle;

  /// Room the first page keeps for the chapter header.
  final double firstPageInset;
  final TextDirection textDirection;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      other is NovelPageMetrics &&
      other.width == width &&
      other.height == height &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.justify == justify &&
      other.paragraphSpacing == paragraphSpacing &&
      other.fontFamily == fontFamily &&
      other.textScaler == textScaler &&
      other.baseStyle == baseStyle &&
      other.firstPageInset == firstPageInset &&
      other.textDirection == textDirection &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    fontSize,
    lineHeight,
    justify,
    paragraphSpacing,
    fontFamily,
    textScaler,
    baseStyle,
    firstPageInset,
    textDirection,
    locale,
  );
}

/// One screenful of a chapter, and where in the chapter it starts.
class NovelPage {
  const NovelPage(this.slices, this.block, this.offset);

  final List<NovelSlice> slices;
  final int block;
  final int offset;
}

/// The selectable text reserves room for its caret: a 1px gap and the 2px
/// cursor.
const double _caretMargin = 3;
const double _slack = 0.5;

/// Cuts [blocks] into pages of [m].
///
/// Measured with the same styles, scaler and widths [NovelText] draws with,
/// so a page holds exactly what fits. A paragraph that does not fit is broken
/// at a line boundary and carries on at the top of the next page.
List<NovelPage> paginateNovel(List<NovelBlock> blocks, NovelPageMetrics m) {
  final pages = <NovelPage>[];
  var slices = <NovelSlice>[];
  var y = m.firstPageInset;
  var startBlock = 0;
  var startOffset = 0;

  void turn(int block, int offset) {
    pages.add(NovelPage(slices, startBlock, startOffset));
    slices = <NovelSlice>[];
    y = 0;
    startBlock = block;
    startOffset = offset;
  }

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (block.kind == NovelBlockKind.rule) {
      const h = kNovelRulePadding * 2 + 1;
      if (slices.isNotEmpty && y + h > m.height) turn(i, 0);
      slices.add(NovelSlice(i, 0, 0));
      y += h;
      continue;
    }
    final length = block.text.length;
    var start = 0;
    while (start < length) {
      final top = block.kind == NovelBlockKind.heading && start == 0
          ? kNovelHeadingTop
          : 0.0;
      final painter = _painter(block, start, m);
      if (y + top + painter.height <= m.height + _slack) {
        slices.add(NovelSlice(i, start, length));
        y += top + painter.height + m.paragraphSpacing;
        painter.dispose();
        break;
      }
      final room = m.height - y - top;
      final lines = painter.computeLineMetrics();
      var used = 0.0;
      var fit = 0;
      for (final line in lines) {
        if (used + line.height > room + _slack) break;
        used += line.height;
        fit++;
      }
      if (fit == 0) {
        if (slices.isNotEmpty || y > 0) {
          painter.dispose();
          turn(i, start);
          continue;
        }
        // A single line taller than the page; it gets a page to itself.
        fit = 1;
        used = lines.first.height;
      }
      if (fit >= lines.length) {
        slices.add(NovelSlice(i, start, length));
        y += top + painter.height + m.paragraphSpacing;
        painter.dispose();
        break;
      }
      final probe = painter.getPositionForOffset(
        Offset(0, used + lines[fit].height / 2),
      );
      var cut = painter.getLineBoundary(probe).start;
      if (cut <= 0 || cut >= length - start) {
        cut = probe.offset.clamp(1, math.max(1, length - start - 1));
      }
      painter.dispose();
      slices.add(NovelSlice(i, start, start + cut));
      turn(i, start + cut);
      start += cut;
    }
  }
  if (slices.isNotEmpty || pages.isEmpty) {
    pages.add(NovelPage(slices, startBlock, startOffset));
  }
  return pages;
}

TextPainter _painter(NovelBlock block, int start, NovelPageMetrics m) {
  const ink = Color(0xFF000000);
  final heading = block.kind == NovelBlockKind.heading;
  final spans = heading
      ? <InlineSpan>[TextSpan(text: block.text)]
      : block.spans(ink, m.fontFamily, m.fontSize, m.lineHeight);
  final style = heading
      ? m.baseStyle.merge(headingStyle(ink, m.fontFamily, m.fontSize))
      : m.baseStyle;
  return TextPainter(
    text: TextSpan(
      style: style,
      children: [
        TextSpan(
          children: start == 0
              ? spans
              : cutSpans(spans, start, block.text.length),
        ),
      ],
    ),
    textAlign: heading
        ? TextAlign.center
        : (m.justify ? TextAlign.justify : TextAlign.start),
    textDirection: m.textDirection,
    textScaler: m.textScaler,
    locale: m.locale,
    strutStyle: heading
        ? null
        : StrutStyle.disabled.inheritFromTextStyle(style),
  )..layout(
    maxWidth: heading ? m.width : math.max(0.0, m.width - _caretMargin),
  );
}

/// The page that shows character [offset] of block [block].
int novelPageOf(List<NovelPage> pages, int block, int offset) {
  for (var p = pages.length - 1; p > 0; p--) {
    final page = pages[p];
    if (page.block < block || (page.block == block && page.offset <= offset)) {
      return p;
    }
  }
  return 0;
}
