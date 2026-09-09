/// A named look, applied through mpv's video equalizer.
///
/// ## Why these exist
///
/// The five properties below are the only picture controls libmpv exposes at
/// runtime, and each is an integer from -100 to 100 where 0 is "do nothing".
/// [natural] is all zeros, which means it is not a filter that happens to look
/// neutral — it is byte-identical to playback with no profile at all. That
/// matters: someone who tries the feature and does not like it must be able to
/// get exactly their old picture back, not a close approximation of it.
///
/// ## Why a short list of names and not five sliders
///
/// Five sliders is a photo editor. Nobody opening an episode wants to dial in a
/// gamma curve, and a picture menu that can be left in a broken state is worse
/// than none — the app then looks broken, and the setting that did it is four
/// taps away and forgotten. Named looks can be wrong for a title but never
/// wrong in a way the viewer cannot undo in one tap.
///
/// ## Where it does not apply
///
/// libmpv only. The platform player has no runtime picture control at all, so
/// the UI hides this rather than offering a menu that silently does nothing —
/// the same rule the audio-track control already follows.
class ColorProfile {
  const ColorProfile(
    this.id,
    this.labelKey, {
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.hue = 0,
  });

  /// Persisted in Hive. Never rename one: a stored id outlives the constant.
  final String id;

  /// Localisation key, so the names translate with everything else.
  final String labelKey;

  final int brightness;
  final int contrast;
  final int saturation;
  final int gamma;
  final int hue;

  /// True when this profile changes nothing, and can therefore be applied by
  /// clearing the equalizer rather than by setting it.
  bool get isNeutral =>
      brightness == 0 && contrast == 0 && saturation == 0 && gamma == 0 && hue == 0;

  /// mpv property names to values, ready to be set one at a time.
  Map<String, int> get properties => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'gamma': gamma,
        'hue': hue,
      };

  static const ColorProfile natural = ColorProfile('natural', 'player.color_natural');

  /// The list, in the order it is offered.
  ///
  /// Kept short on purpose. Every extra entry is another thing to try, fail to
  /// tell apart from its neighbour, and leave switched on by accident.
  static const List<ColorProfile> all = [
    natural,

    // A cinema look: deeper contrast with a small lift so shadow detail does
    // not simply disappear, which is what raising contrast alone does.
    ColorProfile(
      'cinema',
      'player.color_cinema',
      brightness: 2,
      contrast: 12,
      saturation: 8,
      gamma: 5,
    ),

    // For watching in the dark. The brightness cut is the point and the gamma
    // lift is what stops it crushing everything below mid-grey.
    ColorProfile(
      'night',
      'player.color_night',
      brightness: -12,
      contrast: 16,
      saturation: 4,
      gamma: 12,
    ),

    // Animation is drawn in flat, saturated colour and survives — often wants —
    // far more saturation than live action, which is why this is its own entry
    // rather than a stronger "vivid".
    ColorProfile(
      'anime',
      'player.color_anime',
      brightness: 8,
      contrast: 20,
      saturation: 28,
      gamma: -3,
    ),

    // Old or heavily compressed transfers: lift the shadows, hold the colour
    // back so banding and blocking are not amplified along with it.
    ColorProfile(
      'restore',
      'player.color_restore',
      brightness: 10,
      contrast: -4,
      saturation: -6,
      gamma: 14,
    ),
  ];

  static ColorProfile fromId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return natural;
  }
}
