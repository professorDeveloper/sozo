import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A novel chapter, rendered from the HTML its source returned.
///
/// ## Why not an HTML package
///
/// What arrives is a chapter of prose: paragraphs, the odd emphasis, a heading
/// and a rule. A full HTML engine would bring a dependency and a layout model
/// to render six tags, and would faithfully reproduce whatever inline styling
/// the site used — grey-on-grey text, a hard-coded serif, a background colour —
/// which is exactly what the reader's own settings exist to override.
///
/// So the markup is reduced to blocks and the reader decides how it looks.
///
/// ## What is deliberately dropped
///
/// Scripts, styles and anything that is not text. These come from arbitrary
/// third-party sites; the safe reading of an unknown tag is its text content,
/// and the safe reading of `<script>` is nothing at all.
class NovelText extends StatelessWidget {
  const NovelText({
    super.key,
    required this.html,
    required this.color,
    required this.fontSize,
    this.fontFamily,
    this.lineHeight = 1.62,
    this.justify = true,
    this.paragraphSpacing = 14,
    this.query = '',
    this.activeMatch = -1,
    this.activeKey,
    this.speakingBlock = -1,
    this.speakingStart = 0,
    this.speakingEnd = 0,
    this.speakingKey,
    this.speakingColor = const Color(0x553D8BFF),
    this.marks = const [],
    this.slices,
    this.onHighlight,
    this.onUnhighlight,
    this.revealBlock = -1,
    this.revealKey,
    this.textScaler,
  });

  /// The sentence being read aloud: characters [speakingStart] to
  /// [speakingEnd] of block [speakingBlock], whose widget carries
  /// [speakingKey] so the reader can keep it in view. -1 for none.
  final int speakingBlock;
  final int speakingStart;
  final int speakingEnd;
  final GlobalKey? speakingKey;
  final Color speakingColor;

  /// Text to find in the chapter, highlighted wherever it occurs. Empty for
  /// none.
  final String query;

  /// Which occurrence, counting through the chapter from 0, is the current
  /// one: drawn stronger, and its block carries [activeKey] so the reader can
  /// scroll to it.
  final int activeMatch;
  final GlobalKey? activeKey;

  final String html;
  final Color color;
  final double fontSize;
  final String? fontFamily;

  /// Leading, as a multiple of the font size.
  ///
  /// Tunable rather than fixed because it is the setting that decides whether a
  /// wall of text is readable, and the right value depends on the script: the
  /// 1.62 that suits Latin prose is cramped for Cyrillic and loose for CJK.
  final double lineHeight;

  /// Justified prose, or ragged-right.
  ///
  /// Justification was the only option and it is the wrong default for a narrow
  /// column: Flutter does not hyphenate, so a phone-width paragraph stretches
  /// its spaces to fit and opens rivers of white down the page. Offered rather
  /// than simply changed, because on a tablet it reads well.
  final bool justify;

  /// Gap after each paragraph.
  final double paragraphSpacing;

  /// The reader's highlights.
  final List<NovelMark> marks;

  /// Only these pieces of the chapter, for one page of the book layout. Null
  /// draws all of it.
  final List<NovelSlice>? slices;

  /// Offered on a selection, in the block's own character offsets.
  final void Function(int block, int start, int end)? onHighlight;
  final void Function(int block, int start, int end)? onUnhighlight;

  /// A block to tag with [revealKey], so the reader can scroll to it.
  final int revealBlock;
  final GlobalKey? revealKey;

  /// Pinned by the book layout, which measured its pages with it.
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final blocks = parseNovelBlocks(html);
    final pieces =
        slices ??
        [
          for (var i = 0; i < blocks.length; i++)
            NovelSlice(i, 0, blocks[i].text.length),
        ];
    final before = <int>[];
    if (needle.isNotEmpty) {
      var seen = 0;
      for (final b in blocks) {
        before.add(seen);
        seen += countMatches(b.text.toLowerCase(), needle);
      }
    }
    final children = <Widget>[];
    for (final slice in pieces) {
      final i = slice.block;
      if (i < 0 || i >= blocks.length) continue;
      final block = blocks[i];
      final count = needle.isEmpty
          ? 0
          : countMatches(block.text.toLowerCase(), needle);
      final first = needle.isEmpty ? 0 : before[i];
      final holdsActive = activeMatch >= first && activeMatch < first + count;
      final speaking = i == speakingBlock;
      var w = _block(
        i,
        block,
        slice,
        needle,
        holdsActive ? activeMatch - first : -1,
        speaking ? (speakingStart, speakingEnd) : null,
      );
      if (speaking && speakingKey != null) {
        w = KeyedSubtree(key: speakingKey, child: w);
      }
      if (i == revealBlock && revealKey != null) {
        w = KeyedSubtree(key: revealKey, child: w);
      }
      children.add(
        holdsActive && activeKey != null
            ? KeyedSubtree(key: activeKey, child: w)
            : w,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Non-overlapping occurrences of [needle] in [hay], both lower-cased.
  static int countMatches(String hay, String needle) {
    if (needle.isEmpty) return 0;
    var n = 0;
    for (
      var i = hay.indexOf(needle);
      i >= 0;
      i = hay.indexOf(needle, i + needle.length)
    ) {
      n++;
    }
    return n;
  }

  /// All occurrences in a chapter, the way [build] counts them.
  static int countInChapter(String html, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return 0;
    var n = 0;
    for (final b in parseNovelBlocks(html)) {
      n += countMatches(b.text.toLowerCase(), needle);
    }
    return n;
  }

  /// Where the [index]-th occurrence of [query] starts, as a block and an
  /// offset into it.
  static (int, int)? locateMatch(String html, String query, int index) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty || index < 0) return null;
    var n = 0;
    final blocks = parseNovelBlocks(html);
    for (var b = 0; b < blocks.length; b++) {
      final hay = blocks[b].text.toLowerCase();
      for (
        var i = hay.indexOf(needle);
        i >= 0;
        i = hay.indexOf(needle, i + needle.length)
      ) {
        if (n++ == index) return (b, i);
      }
    }
    return null;
  }

  List<InlineSpan> _decorate(
    int index,
    NovelBlock block,
    List<InlineSpan> spans,
    String needle,
    int active,
    (int, int)? spoken,
  ) {
    var out = spans;
    for (final m in marks) {
      if (m.block != index) continue;
      out = _paint(
        out,
        m.start,
        m.end,
        (s) => s.copyWith(
          backgroundColor: m.color,
          decoration: m.noted ? TextDecoration.underline : null,
          decorationStyle: m.noted ? TextDecorationStyle.dotted : null,
          decorationColor: m.noted ? color.withValues(alpha: 0.7) : null,
        ),
      );
    }
    if (spoken != null) {
      out = _paint(
        out,
        spoken.$1,
        spoken.$2,
        (s) => s.copyWith(backgroundColor: speakingColor),
      );
    }
    if (needle.isNotEmpty) {
      const soft = Color(0x66FFD54F);
      const strong = Color(0xFFFF9800);
      final hay = block.text.toLowerCase();
      var n = 0;
      for (
        var i = hay.indexOf(needle);
        i >= 0;
        i = hay.indexOf(needle, i + needle.length)
      ) {
        final current = n++ == active;
        out = _paint(
          out,
          i,
          i + needle.length,
          (s) => s.copyWith(
            backgroundColor: current ? strong : soft,
            color: current ? Colors.black : null,
          ),
        );
      }
    }
    return out;
  }

  Widget _block(
    int index,
    NovelBlock block,
    NovelSlice slice, [
    String needle = '',
    int active = -1,
    (int, int)? spoken,
  ]) {
    final whole = slice.start <= 0 && slice.end >= block.text.length;
    final ends = slice.end >= block.text.length;
    switch (block.kind) {
      case NovelBlockKind.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: kNovelRulePadding),
          child: Divider(color: color.withValues(alpha: 0.25), height: 1),
        );
      case NovelBlockKind.heading:
        var spans = _paint(
          [TextSpan(text: block.text)],
          spoken?.$1 ?? 0,
          spoken?.$2 ?? 0,
          (s) => s.copyWith(backgroundColor: speakingColor),
        );
        if (!whole) spans = cutSpans(spans, slice.start, slice.end);
        return Padding(
          padding: EdgeInsets.only(
            bottom: ends ? paragraphSpacing : 0,
            top: slice.start == 0 ? kNovelHeadingTop : 0,
          ),
          child: Text.rich(
            TextSpan(children: spans),
            textAlign: TextAlign.center,
            textScaler: textScaler,
            style: headingStyle(color, fontFamily, fontSize),
          ),
        );
      case NovelBlockKind.paragraph:
        var spans = _decorate(
          index,
          block,
          block.spans(color, fontFamily, fontSize, lineHeight),
          needle,
          active,
          spoken,
        );
        if (!whole) spans = cutSpans(spans, slice.start, slice.end);
        return Padding(
          padding: EdgeInsets.only(bottom: ends ? paragraphSpacing : 0),
          // Selectable because somebody reading a translation looks words up.
          child: SelectableText.rich(
            TextSpan(children: spans),
            textAlign: justify ? TextAlign.justify : TextAlign.start,
            textScaler: textScaler,
            strutStyle: StrutStyle.disabled,
            contextMenuBuilder: onHighlight == null
                ? _defaultMenu
                : (context, state) => _menu(state, index, slice.start),
          ),
        );
    }
  }

  static Widget _defaultMenu(BuildContext context, EditableTextState state) =>
      AdaptiveTextSelectionToolbar.editableText(editableTextState: state);

  Widget _menu(EditableTextState state, int index, int offset) {
    final items = state.contextMenuButtonItems.toList();
    final sel = state.textEditingValue.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final a = offset + sel.start;
      final b = offset + sel.end;
      void collapse() {
        state.hideToolbar();
        state.userUpdateTextEditingValue(
          state.textEditingValue.copyWith(
            selection: TextSelection.collapsed(offset: sel.end),
          ),
          SelectionChangedCause.toolbar,
        );
      }

      items.insert(
        0,
        ContextMenuButtonItem(
          label: 'manga.highlight'.tr(),
          onPressed: () {
            collapse();
            onHighlight!(index, a, b);
          },
        ),
      );
      final marked = marks.any(
        (m) => m.block == index && m.start < b && a < m.end,
      );
      if (marked && onUnhighlight != null) {
        items.insert(
          1,
          ContextMenuButtonItem(
            label: 'manga.remove_highlight'.tr(),
            onPressed: () {
              collapse();
              onUnhighlight!(index, a, b);
            },
          ),
        );
      }
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }
}

/// Gap above a heading, and above and below a rule. Shared with the book
/// layout, which has to measure the page the same way it is drawn.
const double kNovelHeadingTop = 6;
const double kNovelRulePadding = 18;

TextStyle headingStyle(Color color, String? family, double size) => TextStyle(
  color: color,
  fontFamily: family,
  fontSize: size + 4,
  height: 1.35,
  fontWeight: FontWeight.w800,
);

/// A highlight to draw: characters [start] to [end] of block [block].
class NovelMark {
  const NovelMark(
    this.block,
    this.start,
    this.end,
    this.color, {
    this.noted = false,
  });

  final int block;
  final int start;
  final int end;
  final Color color;

  /// Carries a note, which is drawn as a dotted underline.
  final bool noted;
}

/// Characters [start] to [end] of block [block]: the whole block, or the part
/// of it that fits on a page.
@immutable
class NovelSlice {
  const NovelSlice(this.block, this.start, this.end);

  final int block;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is NovelSlice &&
      other.block == block &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(block, start, end);

  @override
  String toString() => 'NovelSlice($block, $start, $end)';
}

/// [spans] with characters [from] to [to] of their joined text restyled,
/// split across the emphasis runs the range crosses.
List<InlineSpan> _paint(
  List<InlineSpan> spans,
  int from,
  int to,
  TextStyle Function(TextStyle) restyle,
) {
  if (to <= from) return spans;
  var offset = 0;
  final out = <InlineSpan>[];
  for (final span in spans) {
    if (span is! TextSpan || span.text == null) {
      out.add(span);
      continue;
    }
    final text = span.text!;
    final start = offset;
    final end = offset + text.length;
    offset = end;
    if (to <= start || from >= end) {
      out.add(span);
      continue;
    }
    final a = (from - start).clamp(0, text.length);
    final b = (to - start).clamp(0, text.length);
    if (a > 0) out.add(TextSpan(text: text.substring(0, a), style: span.style));
    out.add(
      TextSpan(
        text: text.substring(a, b),
        style: restyle(span.style ?? const TextStyle()),
      ),
    );
    if (b < text.length) {
      out.add(TextSpan(text: text.substring(b), style: span.style));
    }
  }
  return out;
}

/// Characters [from] to [to] of the joined text of [spans], keeping styles.
List<InlineSpan> cutSpans(List<InlineSpan> spans, int from, int to) {
  var offset = 0;
  final out = <InlineSpan>[];
  for (final span in spans) {
    if (span is! TextSpan || span.text == null) continue;
    final text = span.text!;
    final start = offset;
    offset += text.length;
    if (offset <= from || start >= to) continue;
    final a = (from - start).clamp(0, text.length);
    final b = (to - start).clamp(0, text.length);
    out.add(TextSpan(text: text.substring(a, b), style: span.style));
  }
  return out;
}

enum NovelBlockKind { paragraph, heading, rule }

/// One block of a chapter: a paragraph, a heading, or a horizontal rule.
class NovelBlock {
  const NovelBlock(this.kind, this.text, [this.runs = const []]);

  final NovelBlockKind kind;

  /// The block's plain text. [runs] describes its emphasis, when it has any.
  final String text;
  final List<NovelRun> runs;

  List<InlineSpan> spans(
    Color color,
    String? family,
    double size, [
    double height = 1.62,
  ]) {
    final base = TextStyle(
      color: color,
      fontFamily: family,
      fontSize: size,
      // Generous leading: this is a wall of text on a phone, and the spacing
      // is what makes it readable rather than the size.
      height: height,
    );
    if (runs.isEmpty) return [TextSpan(text: text, style: base)];
    return [
      for (final r in runs)
        TextSpan(
          text: r.text,
          style: base.copyWith(
            fontWeight: r.bold ? FontWeight.w700 : null,
            fontStyle: r.italic ? FontStyle.italic : null,
          ),
        ),
    ];
  }
}

/// A stretch of text inside a paragraph, and whether it is emphasised.
class NovelRun {
  const NovelRun(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;
}

/// Markers that survive the tag strip, so structure is not lost with the tags.
///
/// Ordinary text rather than control characters, and improbable enough that a
/// chapter containing one by accident is not a case worth designing for.
const String _kRule = '@@SOZO_RULE@@';
const String _kHead = '@@SOZO_H@@';
const String _kBold = '@@SOZO_B@@';
const String _kItal = '@@SOZO_I@@';
const String _kBreak = '@@SOZO_BR@@';

/// Turns a chapter's HTML into blocks.
///
/// Kept out of the widget so it can be tested against the shapes these sources
/// actually return — which is the only way to know it handles them, since every
/// source writes its own markup.
List<NovelBlock> parseNovelBlocks(String html) {
  // The same chapter is laid out on every rebuild — each tap that shows the
  // reader's controls — and this is fifteen passes over the whole chapter.
  // The last one is kept.
  if (identical(html, _lastHtml) || html == _lastHtml) return _lastBlocks!;
  final blocks = List<NovelBlock>.unmodifiable(_parseNovelBlocks(html));
  _lastHtml = html;
  _lastBlocks = blocks;
  return blocks;
}

String? _lastHtml;
List<NovelBlock>? _lastBlocks;

final RegExp _blockTag = RegExp(
  r'<(p|div|br|li|blockquote|h[1-6])\b',
  caseSensitive: false,
);

List<NovelBlock> _parseNovelBlocks(String html) {
  var s = html;

  // A chapter that arrives as plain text, one paragraph per line, has no
  // tags to split on and rendered as one wall. Its line breaks are its
  // paragraphs.
  if (!_blockTag.hasMatch(s) && s.contains('\n')) {
    s = s.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll('\n', '<br>');
  }

  // Everything that is not prose. Script and style carry text that would
  // otherwise be rendered as if it were the chapter.
  s = s.replaceAll(
    RegExp(
      r'<(script|style|noscript)[^>]*>[\s\S]*?</\1>',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  s = s.replaceAll(RegExp(r'<hr[^>]*/?>', caseSensitive: false), _kRule);
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), _kBreak);

  // Headings keep their text, wrapped so the block type survives.
  s = s.replaceAllMapped(
    RegExp(r'<h[1-6][^>]*>([\s\S]*?)</h[1-6]>', caseSensitive: false),
    (m) => '$_kBreak$_kHead${m[1]}$_kHead$_kBreak',
  );

  // Block boundaries. A chapter that uses one <div> per paragraph — several do
  // — must not collapse into a single wall.
  s = s.replaceAll(
    RegExp(r'</(p|div|li|blockquote)>', caseSensitive: false),
    _kBreak,
  );
  s = s.replaceAll(
    RegExp(r'<(p|div|li|blockquote)[^>]*>', caseSensitive: false),
    _kBreak,
  );

  s = s.replaceAll(
    RegExp(r'</?(b|strong)[^>]*>', caseSensitive: false),
    _kBold,
  );
  s = s.replaceAll(RegExp(r'</?(i|em)[^>]*>', caseSensitive: false), _kItal);

  // Everything else goes; its text content stays.
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = _unescape(s);

  final blocks = <NovelBlock>[];
  for (final raw in s.split(_kBreak)) {
    for (final piece in _splitKeepingRules(raw)) {
      if (piece == _kRule) {
        // A rule only means something between two pieces of text.
        if (blocks.isNotEmpty && blocks.last.kind != NovelBlockKind.rule) {
          blocks.add(const NovelBlock(NovelBlockKind.rule, ''));
        }
        continue;
      }
      final text = piece.trim();
      if (text.isEmpty) continue;

      if (text.contains(_kHead)) {
        final plain = text.replaceAll(_kHead, '').trim();
        if (plain.isNotEmpty) {
          blocks.add(NovelBlock(NovelBlockKind.heading, _strip(plain)));
        }
        continue;
      }
      blocks.add(
        NovelBlock(NovelBlockKind.paragraph, _strip(text), _runs(text)),
      );
    }
  }
  // A trailing rule separates nothing.
  while (blocks.isNotEmpty && blocks.last.kind == NovelBlockKind.rule) {
    blocks.removeLast();
  }
  return blocks;
}

List<String> _splitKeepingRules(String s) {
  if (!s.contains(_kRule)) return [s];
  final out = <String>[];
  for (final part in s.split(_kRule)) {
    out
      ..add(part)
      ..add(_kRule);
  }
  out.removeLast();
  return out;
}

String _strip(String s) =>
    s.replaceAll(_kBold, '').replaceAll(_kItal, '').replaceAll(_kHead, '');

/// Splits a paragraph on its emphasis markers, toggling as it goes.
List<NovelRun> _runs(String s) {
  if (!s.contains(_kBold) && !s.contains(_kItal)) return const [];
  final runs = <NovelRun>[];
  var bold = false;
  var italic = false;
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    runs.add(NovelRun(buffer.toString(), bold: bold, italic: italic));
    buffer.clear();
  }

  var i = 0;
  while (i < s.length) {
    if (s.startsWith(_kBold, i)) {
      flush();
      bold = !bold;
      i += _kBold.length;
    } else if (s.startsWith(_kItal, i)) {
      flush();
      italic = !italic;
      i += _kItal.length;
    } else {
      buffer.write(s[i]);
      i++;
    }
  }
  flush();
  return runs;
}

/// The entities that actually turn up. A full table would be dead weight.
String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&hellip;', '…')
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&lsquo;', '‘')
    .replaceAll('&ldquo;', '“')
    .replaceAll('&rdquo;', '”')
    // Decimal and hex, the whole Unicode range: "&#x2019;" stayed as typed,
    // and a code point the parse could not take threw.
    .replaceAllMapped(RegExp(r'&#([xX][0-9a-fA-F]+|\d+);'), (m) {
      final raw = m[1]!;
      final code = raw[0] == 'x' || raw[0] == 'X'
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      return code != null && code > 0 && code <= 0x10FFFF
          ? String.fromCharCode(code)
          : m[0]!;
    })
    // Ampersand last, or an escaped entity would be decoded twice.
    .replaceAll('&amp;', '&');
