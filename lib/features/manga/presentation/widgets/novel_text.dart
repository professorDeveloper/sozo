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
  });

  final String html;
  final Color color;
  final double fontSize;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in parseNovelBlocks(html)) _block(block),
      ],
    );
  }

  Widget _block(NovelBlock block) {
    switch (block.kind) {
      case NovelBlockKind.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Divider(color: color.withValues(alpha: 0.25), height: 1),
        );
      case NovelBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 6),
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
          padding: const EdgeInsets.only(bottom: 14),
          child: SelectableText.rich(
            TextSpan(children: block.spans(color, fontFamily, fontSize)),
            // Justified, which is what a page of prose wants. Selectable
            // because somebody reading a translation looks words up.
            textAlign: TextAlign.justify,
          ),
        );
    }
  }
}

enum NovelBlockKind { paragraph, heading, rule }

/// One block of a chapter: a paragraph, a heading, or a horizontal rule.
class NovelBlock {
  const NovelBlock(this.kind, this.text, [this.runs = const []]);

  final NovelBlockKind kind;

  /// The block's plain text. [runs] describes its emphasis, when it has any.
  final String text;
  final List<NovelRun> runs;

  List<InlineSpan> spans(Color color, String? family, double size) {
    final base = TextStyle(
      color: color,
      fontFamily: family,
      fontSize: size,
      // Generous leading: this is a wall of text on a phone, and the spacing
      // is what makes it readable rather than the size.
      height: 1.62,
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
    RegExp(r'<(script|style|noscript)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
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

  s = s.replaceAll(RegExp(r'</?(b|strong)[^>]*>', caseSensitive: false), _kBold);
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
    out..add(part)..add(_kRule);
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
