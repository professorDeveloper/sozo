import 'dart:convert';

enum SubtitleEdge { none, shadow, outline }

/// The typeface a caption is drawn in.
///
/// ## Why generic names and not bundled fonts
///
/// A subtitle font that ships with the app is half a megabyte per weight, paid
/// by everyone, for a preference most people never open. These are the family
/// names Flutter hands to the platform's own font manager, which every device
/// already has — so the set costs nothing and cannot fail to load.
///
/// The trade is that the exact face is the platform's choice: `serif` is Noto
/// Serif on Android and Times on iOS. For a caption that is the right trade —
/// the question somebody is answering is "can I read this against a bright
/// scene", and the answer is about weight and shape, not about a specific
/// foundry.
///
/// `condensed` is deliberately included even though it resolves only on
/// Android: a narrower face is the one that genuinely helps, because it fits a
/// long line without shrinking it, and where it does not resolve the platform
/// falls back to its default sans — which is exactly [SubtitleFont.system].
enum SubtitleFont {
  /// Whatever the app itself uses. The default, and the only one that changes
  /// nothing for an install that never opens this.
  system('system', null, 'player.font_system'),

  /// The platform's plain sans, independent of the app's own theme font.
  sans('sans', 'sans-serif', 'player.font_sans'),

  /// A serif face. Some people find it easier over moving footage.
  serif('serif', 'serif', 'player.font_serif'),

  /// Narrower, so a long line fits without dropping the size.
  condensed('condensed', 'sans-serif-condensed', 'player.font_condensed'),

  /// Even letter widths. Useful where captions carry codes or timings.
  mono('mono', 'monospace', 'player.font_mono');

  const SubtitleFont(this.id, this.family, this.labelKey);

  /// Persisted. Never rename one.
  final String id;

  /// What Flutter passes to the platform font manager. Null means "leave it
  /// alone", which inherits the app's font rather than naming one.
  final String? family;

  final String labelKey;

  static SubtitleFont fromId(String? id) {
    for (final f in SubtitleFont.values) {
      if (f.id == id) return f;
    }
    return SubtitleFont.system;
  }
}

enum SubtitlePosition { lower, normal, higher }

class SubtitleStyle {
  const SubtitleStyle({
    required this.fontSize,
    required this.textColor,
    required this.bgOpacity,
    required this.bold,
    required this.edge,
    required this.position,
    this.font = SubtitleFont.system,
  });

  factory SubtitleStyle.defaults() => const SubtitleStyle(
        fontSize: 16,
        textColor: 0xFFFFFFFF,
        bgOpacity: 0.75,
        bold: true,
        edge: SubtitleEdge.shadow,
        position: SubtitlePosition.normal,
      );

  factory SubtitleStyle.fromJsonString(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SubtitleStyle(
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16,
        textColor: (map['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        bgOpacity: (map['bgOpacity'] as num?)?.toDouble() ?? 0.75,
        bold: map['bold'] as bool? ?? true,
        edge: SubtitleEdge.values[(map['edge'] as num?)?.toInt() ?? 1],
        position:
            SubtitlePosition.values[(map['position'] as num?)?.toInt() ?? 1],
        // By id, not by index: an enum written down as a number breaks the
        // moment a value is inserted, and this one has room to grow.
        font: SubtitleFont.fromId(map['font'] as String?),
      );
    } catch (_) {
      return SubtitleStyle.defaults();
    }
  }

  final double fontSize;
  final int textColor;
  final double bgOpacity;
  final bool bold;
  final SubtitleEdge edge;
  final SubtitlePosition position;
  final SubtitleFont font;

  SubtitleStyle copyWith({
    double? fontSize,
    int? textColor,
    double? bgOpacity,
    bool? bold,
    SubtitleEdge? edge,
    SubtitlePosition? position,
    SubtitleFont? font,
  }) {
    return SubtitleStyle(
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      bgOpacity: bgOpacity ?? this.bgOpacity,
      bold: bold ?? this.bold,
      edge: edge ?? this.edge,
      position: position ?? this.position,
      font: font ?? this.font,
    );
  }

  String toJsonString() => jsonEncode({
        'fontSize': fontSize,
        'font': font.id,
        'textColor': textColor,
        'bgOpacity': bgOpacity,
        'bold': bold,
        'edge': edge.index,
        'position': position.index,
      });
}
