import 'package:flutter/material.dart';

/// Which glass a floating thing is made of.
///
/// iOS 26 has two materials, regular and clear, and never mixes them on one
/// thing (WWDC25 219). Sozo has one dark theme, so every recipe here is the
/// after-dark one.
///
/// * [regular] — a bar, a bar button: a grey veil. What passes under it
///   shows through softened and bent at the rim, so a glyph on it always
///   reads.
/// * [lens] — the clear glass a selection becomes under a finger: no frost,
///   no tint, drawn by a bright rim.
/// * [clear] — clear glass over video: the player's controls. No frost, next
///   to no tint, no light inside — the picture shows through, bent at the
///   rim. The dimming that keeps a white glyph legible over a white sky is
///   laid in by whoever stands the glass up, not baked in here.
/// * [panel] — a panel of words over a busy page: the thick glass iOS gives
///   its tips and popovers.
/// * [menu] — a menu's card of choices: the thickest glass, nearly a fill.
enum GlassKind { regular, lens, clear, panel, menu }

/// The blur under each glass, in sigma.
abstract final class GlassBlur {
  /// Under the regular glass's refraction: a veil, so an edge under it stays
  /// an edge.
  static const double liquid = 2.5;

  /// A small shape standing alone: on a 44-point dome a sharper page reads
  /// as streaks, so it is a soft wash of colour instead.
  static const double edge = 8;

  /// A panel or a menu: the page under it a hint, never shapes.
  static const double panel = 24;
}

/// One glass: what it is made of on each of the three ways a phone may draw
/// it (`GlassSurface` picks the way).
///
/// * **Liquid** — the phone runs the refraction shader (Impeller): [tint] is
///   laid over the bent page and its light [frost] alike, and the shader
///   bends what is under it ([thickness], [refraction]). The shader lights
///   no rim of its own: the rim is drawn by hand, as on the other two ways.
/// * **Blur** — no shader (Skia, a test, a weak Android phone, or the glass
///   put down while its page moves): a blur of [blurFrost] under the thicker
///   [blurTint].
/// * **Opaque** — the phone asks for less transparency (Reduce
///   Transparency): [opaque], and nothing of the page through it.
///
/// What the numbers follow, from the system's own dark glass:
///
/// * The glass **lifts** the page, it does not cover it: black under a bar
///   button reads #1F1F1F, a grey laid over at 0.39, not a dark disc.
/// * It **magnifies**: a dome the whole height of the shape, so what is at a
///   capsule's rim folds back on itself in a band along its edge.
/// * The rim is **one fine highlight**, not a ring: brightest along the top,
///   gone at the sides, fainter along the foot. No colour of its own and no
///   shadow.
@immutable
final class GlassRecipe {
  const GlassRecipe({
    required this.tint,
    required this.blurTint,
    required this.opaque,
    required this.rimLit,
    required this.rimShade,
    required this.contrastEdge,
    required this.thickness,
    required this.refraction,
    required this.frost,
    required this.blurFrost,
    required this.saturation,
    this.hairline = Colors.transparent,
    this.sheenTop = Colors.transparent,
    this.sheenFoot = Colors.transparent,
    this.edgeShade = Colors.transparent,
    this.lift = const [],
    this.clear = false,
    this.dispersion = 0,
  });

  /// The glass's own colour, laid over the glass: over the bent page and the
  /// frost alike, so the band the rim draws in from beyond the glass is the
  /// glass's colour too, not a black ring of page.
  final Color tint;

  /// The same where there is only a blur under it: a little thicker, because
  /// a blur alone does not separate the glass from the page the way a
  /// bending rim does.
  final Color blurTint;

  /// The glass with nothing through it, for Reduce Transparency.
  final Color opaque;

  /// The rim's highlight: [rimLit] along the top, nothing at the sides,
  /// [rimShade] along the foot — neutral white, because the light falls on
  /// glass, it is not a colour of it.
  final Color rimLit;
  final Color rimShade;

  /// A hair round the glass. None after dark: the highlight alone draws the
  /// edge against black.
  final Color hairline;

  /// The crisp edge Increase Contrast asks for, on every way of drawing.
  final Color contrastEdge;

  /// How deep the glass is at its rim, in points (the shader is handed it in
  /// the screen's pixels): how far in from the edge the page is bent.
  final double thickness;

  /// The refractive index: how hard the dome bends what is under it. Much
  /// over 1.3 the band at the rim eats the glass.
  final double refraction;

  /// The blur under the liquid glass, in sigma.
  final double frost;

  /// The blur where there is no shader: more than [frost], because without
  /// the bending a sharp page under a thin tint reads as no glass at all.
  final double blurFrost;

  /// How much the glass lifts the colour of what is under it.
  final double saturation;

  /// The light inside the glass, laid over [tint]: brightest just under the
  /// top, nothing through the middle, a little again at the foot — what
  /// makes it read as a drop of glass rather than a flat disc.
  final Color sheenTop;
  final Color sheenFoot;

  /// A shade just inside the rim, fading toward the middle within a few
  /// points: the thickness of a drop seen edge-on.
  final Color edgeShade;

  /// A soft shadow outside the glass, never under it.
  final List<BoxShadow> lift;

  /// Clear glass: no frost on any way of drawing, because a blur would smear
  /// the very picture it is held over to be seen through.
  final bool clear;

  /// How far the shader splits the colours at the rim. None: its red and
  /// blue fringes read as a tinted capsule.
  final double dispersion;

  /// The one shadow a glass asks for when it must stand off a busy page
  /// (`GlassShape.shadow`), laid outside the glass only.
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x47000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// The recipe for [kind]; [compact] — a small shape standing alone, a
  /// 44-point button — takes the regular glass's small-shape variant.
  static GlassRecipe of(GlassKind kind, {bool compact = false}) =>
      switch (kind) {
        GlassKind.regular => compact ? _compact : _regular,
        GlassKind.lens => _lens,
        GlassKind.clear => _clear,
        GlassKind.panel => _panel,
        GlassKind.menu => _menu,
      };

  /// iOS's opaque dark bar, #1C1C1E: what Reduce Transparency puts down.
  static const Color _opaque = Color(0xFF1C1C1E);

  /// The elevated rung, #2C2C2E: an opaque menu.
  static const Color _elevated = Color(0xFF2C2C2E);

  static final GlassRecipe _regular = GlassRecipe(
    tint: const Color(0xFF4F4F4F).withValues(alpha: 0.39),
    blurTint: const Color(0xFF4F4F4F).withValues(alpha: 0.45),
    opaque: _opaque,
    rimLit: Colors.white.withValues(alpha: 0.3),
    rimShade: Colors.white.withValues(alpha: 0.15),
    contrastEdge: Colors.white.withValues(alpha: 0.7),
    thickness: 12,
    refraction: 1.3,
    frost: GlassBlur.liquid,
    blurFrost: 8,
    saturation: 1.3,
    sheenTop: Colors.white.withValues(alpha: 0.05),
    sheenFoot: Colors.white.withValues(alpha: 0.025),
  );

  // A small dome bent as hard as a bar reads as streaks, so it takes a
  // heavier frost and a lighter grey, and lifts no colour: a red poster
  // washed through at full chroma under a tinted glyph is red on red.
  static final GlassRecipe _compact = GlassRecipe(
    tint: const Color(0xFF4F4F4F).withValues(alpha: 0.52),
    blurTint: const Color(0xFF4F4F4F).withValues(alpha: 0.56),
    opaque: _opaque,
    rimLit: _regular.rimLit,
    rimShade: _regular.rimShade,
    contrastEdge: _regular.contrastEdge,
    thickness: _regular.thickness,
    refraction: _regular.refraction,
    frost: GlassBlur.edge,
    blurFrost: GlassBlur.edge,
    saturation: 1,
    sheenTop: _regular.sheenTop,
    sheenFoot: _regular.sheenFoot,
  );

  // No colour of its own: drawn by a bright rim. Without the shader a breath
  // of white keeps it from vanishing.
  static final GlassRecipe _lens = GlassRecipe(
    tint: Colors.transparent,
    blurTint: Colors.white.withValues(alpha: 0.14),
    opaque: const Color(0xFF3A3A3C),
    rimLit: Colors.white.withValues(alpha: 0.85),
    rimShade: Colors.white.withValues(alpha: 0.5),
    contrastEdge: Colors.white.withValues(alpha: 0.7),
    thickness: 8,
    refraction: 1.3,
    frost: 0,
    blurFrost: 0,
    saturation: 1,
    clear: true,
  );

  // Over video: white at 0.04 so the picture keeps its colour, a highlight
  // along the top that is gone by the sides, no hair, no sheen, no lift — the
  // bending at the rim is what says glass. A finer dome than the bar's: a
  // 44-point circle bent 12 deep is all rim.
  static final GlassRecipe _clear = GlassRecipe(
    tint: Colors.white.withValues(alpha: 0.04),
    blurTint: Colors.white.withValues(alpha: 0.04),
    opaque: _opaque,
    rimLit: Colors.white.withValues(alpha: 0.42),
    rimShade: Colors.white.withValues(alpha: 0.14),
    contrastEdge: Colors.white.withValues(alpha: 0.7),
    thickness: 10,
    refraction: 1.3,
    frost: 0,
    blurFrost: 0,
    saturation: 1,
    clear: true,
  );

  // Thick enough that a white frame under it leaves its secondary words
  // over 4.5:1: #2D2D2F over black.
  static final GlassRecipe _panel = GlassRecipe(
    tint: const Color(0xFF2F2F31).withValues(alpha: 0.94),
    blurTint: const Color(0xFF2F2F31).withValues(alpha: 0.94),
    opaque: _opaque,
    rimLit: _regular.rimLit,
    rimShade: _regular.rimShade,
    contrastEdge: _regular.contrastEdge,
    thickness: _regular.thickness,
    refraction: _regular.refraction,
    frost: GlassBlur.panel,
    blurFrost: GlassBlur.panel,
    saturation: 1.1,
    sheenTop: _regular.sheenTop,
    sheenFoot: _regular.sheenFoot,
  );

  // #2C2C2E over black and within a few steps of it over anything, with no
  // lit rim: iOS's dark menus have no bright edge.
  static final GlassRecipe _menu = GlassRecipe(
    tint: const Color(0xFF2E2E30).withValues(alpha: 0.96),
    blurTint: const Color(0xFF2E2E30).withValues(alpha: 0.96),
    opaque: _elevated,
    rimLit: Colors.transparent,
    rimShade: Colors.transparent,
    contrastEdge: _regular.contrastEdge,
    thickness: _regular.thickness,
    refraction: _regular.refraction,
    frost: GlassBlur.panel,
    blurFrost: GlassBlur.panel,
    saturation: 1,
  );
}
