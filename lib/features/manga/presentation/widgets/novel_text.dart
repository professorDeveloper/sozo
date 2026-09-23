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
  });

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

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    var seen = 0;
    final children = <Widget>[];
    for (final block in parseNovelBlocks(html)) {
      final count = needle.isEmpty
          ? 0
          : countMatches(block.text.toLowerCase(), needle);
      final first = seen;
      seen += count;
      final holdsActive = activeMatch >= first && activeMatch < first + count;
      final w = _block(block, needle, holdsActive ? activeMatch - first : -1);
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

  Widget _block(NovelBlock block, [String needle = '', int active = -1]) {
    switch (block.kind) {
      case NovelBlockKind.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Divider(color: color.withValues(alpha: 0.25), height: 1),
        );
      case NovelBlockKind.heading:
        return Padding(
          padding: EdgeInsets.only(bottom: paragraphSpacing, top: 6),
          child: Text(
            block.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontFamily: fontFamily,
              fontSize: fontSize + 4,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      case NovelBlockKind.paragraph:
        return Padding(
          padding: EdgeInsets.only(bottom: paragraphSpacing),
          // Selectable because somebody reading a translation looks words up.
          child: SelectableText.rich(
            TextSpan(
              children: _highlight(
                block.spans(color, fontFamily, fontSize, lineHeight),
                needle,
                active,
              ),
            ),
            textAlign: justify ? TextAlign.justify : TextAlign.start,
          ),
        );
    }
  }
}

/// [spans] with every occurrence of [needle] painted, the [active]-th (in
/// this block) stronger. Works across the bold and italic runs a paragraph
/// is split into, since a word can straddle them only as a whole run.
List<InlineSpan> _highlight(List<InlineSpan> spans, String needle, int active) {
  if (needle.isEmpty) return spans;
  const soft = Color(0x66FFD54F);
  const strong = Color(0xFFFF9800);
  var index = 0;
  final out = <InlineSpan>[];
  for (final span in spans) {
    if (span is! TextSpan || span.text == null) {
      out.add(span);
      continue;
    }
    final text = span.text!;
    final lower = text.toLowerCase();
    var from = 0;
    for (
      var i = lower.indexOf(needle);
      i >= 0;
      i = lower.indexOf(needle, i + needle.length)
    ) {
      if (i > from) {
        out.add(TextSpan(text: text.substring(from, i), style: span.style));
      }
      out.add(
        TextSpan(
          text: text.substring(i, i + needle.length),
          style: (span.style ?? const TextStyle()).copyWith(
            backgroundColor: index == active ? strong : soft,
            color: index == active ? Colors.black : null,
          ),
        ),
      );
      index++;
      from = i + needle.length;
    }
    if (from < text.length) {
      out.add(TextSpan(text: text.substring(from), style: span.style));
    }
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
  var s = html;

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
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m[1]!)),
    )
    // Ampersand last, or an escaped entity would be decoded twice.
    .replaceAll('&amp;', '&');
