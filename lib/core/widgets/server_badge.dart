import 'package:flutter/material.dart';

/// A small coloured mark standing in for a stream server.
///
/// ## Why a monogram and not a logo
///
/// The obvious version of this is each host's real logo, and it is the wrong
/// one. Server names arrive from providers at runtime and there is no list to
/// ship art against: "FSL Server", "10Gbps", "Pixeldrain", "Server 3",
/// "Doodstream", "Vidhide" and whatever appears next month all have to render.
/// Bundling icons covers the handful we know today and leaves a blank square
/// beside everything else — which is worse than no icon, because the servers
/// that look broken are the unfamiliar ones people are least sure about.
///
/// Fetching a favicon by hostname covers everything, and costs a request to a
/// third party carrying the name of the host somebody is about to stream from.
/// That is a real privacy price for decoration.
///
/// So the mark is derived from the name itself. It needs no network, no
/// assets, and no list: every server that can ever appear gets a stable,
/// distinct-looking badge, and it is the same badge every time — which is the
/// property that actually matters. People do not read "Server 2" in a list of
/// six; they remember that the working one was the teal one.
class ServerBadge extends StatelessWidget {
  const ServerBadge({
    super.key,
    required this.name,
    this.size = 34,
    this.selected = false,
  });

  final String name;

  /// Edge length. The monogram and corner radius scale with it, so one widget
  /// serves the 34pt row in the sheet and the 56pt mark in the switch overlay.
  final double size;

  /// Draws a ring, for the row that is currently playing.
  final bool selected;

  /// Colours chosen to stay distinguishable from each other on a black player
  /// background, and to keep white text readable on top.
  static const List<Color> _palette = [
    Color(0xFF3B82F6), // blue
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // red
    Color(0xFF8B5CF6), // violet
    Color(0xFF06B6D4), // cyan
    Color(0xFFEC4899), // pink
    Color(0xFF84CC16), // lime
  ];

  /// FNV-1a over the normalised name.
  ///
  /// `String.hashCode` is not stable across runs in Dart, so using it would
  /// give somebody a different colour every launch — destroying the one
  /// property this badge exists to have.
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Color colorFor(String name) {
    final key = _normalise(name);
    if (key.isEmpty) return _palette.first;
    return _palette[_stableHash(key) % _palette.length];
  }

  /// One or two characters that read as this server at a glance.
  ///
  /// "FSL Server" → `FS`, "10Gbps" → `10`, "Server 3" → `S3`, "Doodstream" →
  /// `DO`. A numbered server keeps its number, because that number is the only
  /// thing distinguishing it from its five siblings.
  static String monogramFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    // A trailing number is the whole identity of "Server 3" / "Sunucu 2".
    final numbered = RegExp(r'^(\D*?)\s*(\d{1,2})\s*$').firstMatch(trimmed);
    if (numbered != null) {
      final word = numbered.group(1)!.trim();
      final digits = numbered.group(2)!;
      if (word.isEmpty) return digits;
      return '${word[0].toUpperCase()}$digits';
    }

    // A leading number is the identity too: "10Gbps", "4K Server".
    final leading = RegExp(r'^(\d{1,3})').firstMatch(trimmed);
    if (leading != null) return leading.group(1)!;

    final words = trimmed
        .split(RegExp(r'[\s_\-.]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    final word = words.first;
    return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(name);
    final text = monogramFor(name);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A flat fill at this size reads as a placeholder; the gradient is
        // what makes it look like a mark somebody chose.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.38)!],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: selected
            ? Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: size * 0.24,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          // Two characters at 40% of the box leaves the badge legible down to
          // about 24pt, which is the smallest it is used at.
          fontSize: size * (text.length > 2 ? 0.32 : 0.40),
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
