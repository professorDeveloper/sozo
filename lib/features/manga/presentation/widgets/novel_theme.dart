import 'package:flutter/material.dart';

/// A paper and ink for prose.
class NovelTheme {
  const NovelTheme(
    this.id,
    this.paper,
    this.ink, {
    this.isLight = false,
    required this.label,
  });

  final String id;
  final Color paper;
  final Color ink;
  final bool isLight;

  /// Translation key.
  final String label;

  Color get muted => ink.withValues(alpha: isLight ? 0.55 : 0.5);

  /// How strongly a highlight colour is laid over this paper.
  double get markAlpha => isLight ? 0.5 : 0.34;

  static const dark = NovelTheme(
    'dark',
    Color(0xFF15161A),
    Color(0xFFE4E1DA),
    label: 'manga.theme_dark',
  );
  static const black = NovelTheme(
    'black',
    Color(0xFF000000),
    Color(0xFFBDBDBD),
    label: 'manga.theme_black',
  );
  static const sepia = NovelTheme(
    'sepia',
    Color(0xFFF4EAD5),
    Color(0xFF4A3A28),
    isLight: true,
    label: 'manga.theme_sepia',
  );
  static const light = NovelTheme(
    'light',
    Color(0xFFFAFAF7),
    Color(0xFF1B1C20),
    isLight: true,
    label: 'manga.theme_light',
  );

  static const all = [dark, black, sepia, light];

  /// [id], or the closest match to the comic reader's background for somebody
  /// who has not picked one yet.
  static NovelTheme of(String id, {String background = 'black'}) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return background == 'white' ? light : dark;
  }
}
