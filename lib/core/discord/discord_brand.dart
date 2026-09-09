import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Discord's own mark and colours.
///
/// Kept in one place because a brand rendered slightly wrong reads worse than
/// no brand at all — a Discord panel in the wrong blue looks like a phishing
/// screen, which is the last impression this particular feature should give
/// while it is asking somebody to trust it with a credential.
class DiscordBrand {
  const DiscordBrand._();

  /// "Blurple". Discord's primary, and the only colour of theirs used here.
  static const Color blurple = Color(0xFF5865F2);

  /// The green Discord itself uses for an online presence dot.
  static const Color online = Color(0xFF23A55A);

  /// The grey it uses for offline.
  static const Color offline = Color(0xFF80848E);

  /// Discord's card background, so the preview below actually looks like the
  /// thing it is previewing.
  static const Color surface = Color(0xFF2B2D31);
  static const Color surfaceDeep = Color(0xFF1E1F22);

  /// The Clyde mark, as a path rather than an asset.
  ///
  /// Inline so it cannot go missing from a build, and so the colour is a
  /// parameter rather than baked into a file — the mark is drawn white on
  /// blurple in one place and blurple on dark in another.
  static const String _markPath =
      'M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,'
      '72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,'
      '0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,'
      '75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,'
      '105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-'
      '12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,'
      '11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z';

  static String _svg(Color color) {
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 127.14 96.36">'
        '<path fill="#$hex" d="$_markPath"/></svg>';
  }

  /// The mark, in one of Discord's own colours.
  ///
  /// [color] is deliberately narrow. Discord's brand guidance is that the mark
  /// is used in blurple, white or black and not recoloured — a dimmed or
  /// tinted Clyde is the shape of a fake. A muted state is expressed by fading
  /// what is BEHIND the mark instead; see [muted].
  static Widget mark({double size = 22, MarkColor color = MarkColor.white}) =>
      SvgPicture.string(_svg(color.value), width: size, height: size);

  /// The mark at full strength inside a container that is itself faded.
  ///
  /// Used for an "off" state: the chip loses its colour, the mark does not
  /// lose its own.
  static Widget muted({double size = 22, MarkColor color = MarkColor.white}) =>
      Opacity(opacity: 0.55, child: mark(size: size, color: color));

  /// The composed SVG, so a test can parse it without a widget tree.
  @visibleForTesting
  static String svgForTest(Color color) => _svg(color);
}

/// The only colours Discord's mark is used in.
///
/// An enum rather than a Color so a call site cannot quietly invent a fourth
/// one — the guidance exists because a recoloured logo reads as somebody
/// else's imitation of the product.
enum MarkColor {
  white(Color(0xFFFFFFFF)),
  blurple(DiscordBrand.blurple),
  black(Color(0xFF000000));

  const MarkColor(this.value);
  final Color value;
}
