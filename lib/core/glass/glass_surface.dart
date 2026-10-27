import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'app_glass.dart';
import 'route_arrival.dart' show RouteMotion;
import 'glass_hold.dart';
import 'glass_pick.dart';
import 'glass_sense.dart';

export 'glass_hold.dart';
export 'glass_pick.dart';
export 'glass_power.dart';

part 'glass_watch.dart';

/// How the glass under a [GlassGroup] is being drawn right now.
enum GlassMode {
  /// Refraction and a lit rim, on the phone's GPU (Impeller): the real
  /// Liquid Glass.
  liquid,

  /// A blur under a tint and a rim drawn by hand: where the shader cannot
  /// run (Skia, a test), on an Android phone that cannot spend it
  /// ([GlassPower]: an Android Go phone), and for the frames the
  /// glass is put down ([GlassHold]).
  blur,

  /// No glass at all — an opaque fill: the phone asks for less
  /// transparency (Reduce Transparency, [GlassSense]).
  opaque,
}

/// The one way the app draws glass: a group of [GlassShape]s that share one
/// read of the screen under them and one recipe ([GlassRecipe]).
///
/// iOS 26 keeps glass to one floating layer — a bar, its buttons, the
/// player's controls over the video — and never lays glass on glass. So a
/// group is a whole floating thing: two capsules side by side are one group,
/// and melt into each other where they meet ([blend]) the way two drops do;
/// a lone button is a group of its own ([GlassSurface]). A group inside
/// another group is the glass-on-glass the rule forbids, and asserts. A
/// lens held over a bar by a finger is a group beside the bar's, never
/// inside it.
///
/// What is drawn is decided here, once for the whole group ([GlassMode]):
///
/// * the phone asking for less transparency → an opaque fill;
/// * a phone that can run the refraction shader, and can spend it
///   ([GlassPower]) → `liquid_glass_renderer`
///   (pinned 0.2.0-dev.4): the page bends at the glass's rim under a light
///   frost, the tint over it all, and a rim drawn by hand;
/// * otherwise, or while the shell has the glass put down ([GlassHold]) →
///   a blur (the recipe's `blurFrost`) under a thicker tint, sharing the
///   screen layer's [BackdropGroup] read, and the same rim.
///
/// A small shape standing alone ([compact]) — a 44-point bar button —
/// takes the recipe's small-shape glass: a
/// heavier frost and a lighter grey, as the system's are.
///
/// Increase Contrast (`MediaQuery.highContrast`) adds a crisp edge to
/// every shape, whichever way it is drawn.
///
/// Glass in a modal — a sheet's ✕ and ←, anything on an alert or a dialog
/// ([PopupRoute]) — stands on the modal's own opaque material, and reads
/// nothing of the screen ([standsOnModal]): the refraction shader samples
/// round its shape in screen pixels, and on a sheet that moved without a
/// frame after it, or near the sheet's top edge, it sampled the dimmed page
/// *behind* the sheet — a dark band and a white blob in the lower half of
/// the ✕. Over an opaque surface the bent,
/// frosted surface is the surface itself, so the tint laid on it alone is
/// the same glass, pixel for pixel, at rest and through the slide.
/// The menu's glass ([GlassKind.menu]) is the one exception: it is the
/// floating surface itself, over the page.
///
/// The refraction is held — the glass drawn as [GlassHold] draws it, its
/// tint alone, reading nothing of the screen — while the route it stands
/// in moves (coming, going, covered, uncovered, or dragged back by a
/// finger on any navigator above it), and while one of the phone's own
/// views stands under it ([_GlassWatch]): over either the shader drew a
/// hard-edged dark block — and, under a [GlassKeyboardHold], while the
/// keyboard moves. Once they all settle the refraction comes back under the
/// held tint, which fades off it ([release]).
///
/// Only the glass is in here: what stands on it — a glyph, a label — is
/// drawn over it by its owner, and the tree keeps one shape whichever way
/// the glass is drawn, so that switching (a push holding it) never builds
/// the things on it again.
class GlassGroup extends StatefulWidget {
  const GlassGroup({
    super.key,
    this.recipe,
    this.kind = GlassKind.regular,
    this.blend = 0,
    this.visibility = 1,
    this.compact = false,
    this.gathers = false,
    required this.child,
  });

  final GlassKind kind;

  /// Whether the [GlassSurface]s under it — and so the [GlassIconButton]s
  /// drawn on one — are shapes of this group rather than groups of their
  /// own: the neighbouring pieces of one floating thing (the player's back
  /// button and the buttons along its top) read the screen once between
  /// them, not once each. Each takes this group's [kind], [compact] and
  /// [visibility] — its own are not read — and they melt only within
  /// [blend]. A hosted UIKit view standing among them holds the whole
  /// group, not one circle:
  /// gather only glass Flutter draws.
  final bool gathers;

  /// A glass of its own for this group, in place of [kind]'s; null, [kind]'s.
  final GlassRecipe? recipe;

  /// How far apart, in points, two shapes of the group start to melt into
  /// one. Zero: they never do.
  final double blend;

  /// How much of the glass is there, 0 to 1: controls fading in and out.
  /// The glass itself thins — on the
  /// shader its bending and frost, on every way of drawing its tint, its
  /// rim and its hair, each by the same amount ([GlassShape]) — rather
  /// than a layer of it being faded: an opacity over a blur reads an
  /// empty layer.
  final double visibility;

  /// A small shape standing alone — a 44-point button: the glass's
  /// small-shape recipe (`GlassRecipe.of`, `compact`).
  final bool compact;

  final Widget child;

  /// Whether glass at [context] can be drawn as [GlassMode.liquid] at all:
  /// the phone's shader, or what a [GlassPickScope] over it picks.
  static bool liquidAt(BuildContext context) =>
      GlassPickScope.liquidAt(context);

  /// Why the glass of the group around [context] is held right now —
  /// empty when it is not ([GlassHoldReasons]); null outside a group.
  static ValueListenable<Set<GlassHoldReason>>? holdOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_GlassScope>()?.reasons;

  /// Whether glass at [context] stands on a modal's own opaque material —
  /// a sheet, an alert, a dialog — rather than on the page: it then reads
  /// nothing of the screen, only lays its tint on what it stands on.
  static bool standsOnModal(BuildContext context) =>
      ModalRoute.of(context) is PopupRoute;

  /// How the glass under [context] would be drawn by a group of [kind].
  static GlassMode modeOf(BuildContext context) {
    if (GlassSense.reduceTransparencyOf(context)) return GlassMode.opaque;
    if (!liquidAt(context) ||
        (!GlassLive.of(context) && GlassHold.downOf(context))) {
      return GlassMode.blur;
    }
    return GlassMode.liquid;
  }

  /// How long the held glass takes to give way to the refraction once
  /// what held it has settled: a cross-fade, so the glass never pops.
  static const Duration release = Duration(milliseconds: 120);

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup>
    with SingleTickerProviderStateMixin {
  /// Every reason the glass is held, in one place: the holds above it,
  /// the route moving, a view of the phone's under it.
  final GlassHoldReasons _reasons = GlassHoldReasons();

  /// The route the group stands in, and every navigator above it: while
  /// any of them moves the glass is held ([GlassHoldReason.route]).
  RouteMotion? _motion;

  /// The held glass's tint laid over the refraction just given back, fading
  /// out ([GlassGroup.release]).
  late final AnimationController _veil;

  bool _held = false;

  /// Whether this group draws the refraction at all: a phone that can, and
  /// glass on the page rather than on a modal's material.
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    _veil = AnimationController(vsync: this, duration: GlassGroup.release);
    _reasons.addListener(_onReasons);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rewatch();
    // Said quietly: the hold above is depended on, and this group is being
    // built again for it anyway.
    _reasons.set(
      GlassHoldReason.above,
      GlassHold.downOf(context),
      quietly: true,
    );
    // The same for the keyboard moving under a [GlassKeyboardHold].
    _reasons.set(
      GlassHoldReason.keyboard,
      GlassKeyboardHold.movingOf(context),
      quietly: true,
    );
  }

  /// A group handed back with another [GlassGroup.kind] (a menu's glass
  /// becoming a page's, or the other way) may now stand on a modal's
  /// material where it did not before: whether it watches, and the routes
  /// it listens to, are worked out again rather than kept from its first
  /// kind.
  @override
  void didUpdateWidget(covariant GlassGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _rewatch();
  }

  void _rewatch() {
    _watching =
        GlassGroup.liquidAt(context) &&
        !(widget.kind != GlassKind.menu && GlassGroup.standsOnModal(context));
    _listenRoutes();
  }

  /// Listens to the route the glass stands in moving ([RouteMotion]).
  void _listenRoutes() {
    final route = _watching ? ModalRoute.of(context) : null;
    final motion = _motion;
    if (motion != null && _watching && identical(route, motion.route)) return;
    if (motion == null && !_watching) return;
    motion?.cancel();
    _motion = null;
    if (_watching) {
      _motion = RouteMotion(
        route: route,
        context: context,
        onChange: _onRouteMotion,
      );
    }
    _onRouteMotion(quietly: true);
  }

  void _onRouteMotion({bool quietly = false}) {
    if (!mounted) return;
    _reasons.set(
      GlassHoldReason.route,
      _motion?.moving ?? false,
      quietly: quietly,
    );
  }

  bool _queued = false;

  /// A route's word can come while the tree is being built — a page pushed
  /// from a build — and a group cannot be marked for a rebuild then: it
  /// waits for the end of the frame.
  void _onReasons() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_queued) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) setState(() {});
    });
  }

  void _onUnder(bool under) {
    if (!mounted) return;
    _reasons.set(GlassHoldReason.underView, under);
  }

  @override
  void dispose() {
    _motion?.cancel();
    _reasons.dispose();
    _veil.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      context.getInheritedWidgetOfExactType<_GlassScope>() == null,
      'Glass on glass: a GlassGroup inside another. iOS 26 never stacks '
      'glass — put what stands on the glass over '
      'it as a fill or a glyph, not as more glass.',
    );
    // Only a group that draws the refraction is held for its route or a
    // view under it; the holds above put down every glass.
    final held = GlassLive.of(context)
        ? _watching && _reasons.has(GlassHoldReason.underView)
        : _reasons.has(GlassHoldReason.above) ||
              (_watching &&
                  (_reasons.has(GlassHoldReason.route) ||
                      _reasons.has(GlassHoldReason.keyboard) ||
                      _reasons.has(GlassHoldReason.underView)));
    var mode = GlassGroup.modeOf(context);
    if (mode == GlassMode.liquid && held) mode = GlassMode.blur;
    // Held: the held tint is all there is. Given back: the refraction
    // comes back under that tint, which fades off it.
    if (_watching && held != _held) {
      _held = held;
      if (held) {
        _veil.value = 1;
      } else {
        _veil.reverse(from: 1);
      }
    }
    final recipe =
        widget.recipe ?? GlassRecipe.of(widget.kind, compact: widget.compact);
    final shown = widget.visibility.clamp(0.0, 1.0);
    final grounded =
        widget.kind != GlassKind.menu && GlassGroup.standsOnModal(context);
    final scoped = _GlassScope(
      mode: mode,
      recipe: recipe,
      down: held,
      shown: shown,
      grounded: grounded,
      gathers: widget.gathers,
      reasons: _reasons,
      veil: mode == GlassMode.liquid ? _veil : null,
      child: widget.child,
    );
    if (!_watching) return scoped;
    // One shape of tree whichever way the glass is drawn: the layer with no
    // refracting shape in it is a plain pass-through, and the things
    // standing on the glass — a field being typed in — keep their state
    // across a push.
    return _GlassWatch(
      liquid: mode == GlassMode.liquid,
      onUnder: _onUnder,
      child: GlassFoldGuard(child: _liquid(context, recipe, shown, scoped)),
    );
  }

  Widget _liquid(
    BuildContext context,
    GlassRecipe recipe,
    double shown,
    Widget scoped,
  ) {
    return LiquidGlassLayer(
      settings: LiquidGlassSettings(
        visibility: shown,
        // The shader measures its dome in the screen's pixels; the recipe
        // gives it in points, so a 2x and a 3x phone bend alike.
        thickness: recipe.thickness * MediaQuery.devicePixelRatioOf(context),
        blur: recipe.frost,
        // No colour split: its red and blue fringes read as a pink and
        // purple cast at a capsule's ends. The colour at the rim is the
        // page, bent.
        chromaticAberration: recipe.dispersion,
        // No light of the shader's own: it lights the rim from both ends
        // of its light's axis about equally, a bright ring all round. The
        // rim is drawn by hand ([_Rim]) as the system draws it — one fine
        // highlight along the top, fainter along the foot.
        lightIntensity: 0,
        ambientStrength: 0,
        refractiveIndex: recipe.refraction,
        saturation: recipe.saturation,
      ),
      // The frost shares the screen layer's one read of what is under it
      // with every other glass on it (one BackdropGroup per screen layer) —
      // all but the lens: it is held over the bar, its glyphs and its pill,
      // and a shared read is taken before any of them is drawn, so a lens
      // frosting it would lay the page as it was before the bar over the
      // bar. Nor the clear glass over video: it stands over a page pushed
      // over the shell, and a read shared with the shell's bar would be the
      // shell's page, bent.
      useBackdropGroup: widget.kind == GlassKind.regular,
      child: LiquidGlassBlendGroup(blend: widget.blend, child: scoped),
    );
  }
}

/// Keeps the refraction shader off a glass the screen has folded to a line.
///
/// The renderer draws its glass's shape into an image the size of the shape
/// *on the screen* — through every transform above it — rounded to whole
/// pixels. A page turning edge-on, or a scale coming up from nothing,
/// starts at zero: the glass on it is less than a pixel wide, the image is
/// 0 pixels, and the engine throws "Invalid image dimensions" from inside
/// paint.
///
/// So while the group's own box, carried to the screen, is squeezed to under
/// [least] of itself along either axis — or is not a number at all — the
/// glass and what stands on it are not painted: a sliver that thin shows
/// nothing anyway. The smallest glass the app draws is a 28-point circle;
/// at a 20th, on a 2x phone, that is still near 3 pixels, so no shape of a
/// group that passes rounds to nothing. Nothing is built again: the check
/// is made each paint, and the glass is back the frame the page opens out.
class GlassFoldGuard extends SingleChildRenderObjectWidget {
  const GlassFoldGuard({super.key, super.child});

  /// The least share of its own width and height a glass may keep on the
  /// screen and still be drawn.
  static const double least = 1 / 20;

  /// Whether a box of [size] carried to the screen by [toScreen] is folded
  /// too thin to draw glass in.
  static bool folded(Matrix4 toScreen, Size size) {
    if (size.isEmpty) return true;
    final shown = MatrixUtils.transformRect(toScreen, Offset.zero & size);
    if (!shown.isFinite) return true;
    return shown.width < size.width * least ||
        shown.height < size.height * least;
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassFoldGuard();
}

class _RenderGlassFoldGuard extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (GlassFoldGuard.folded(getTransformTo(null), size)) return;
    super.paint(context, offset);
  }
}

/// One piece of glass in a [GlassGroup]: a rounded superellipse of
/// [radius], or a capsule when [radius] is null — the shape iOS 26 gives
/// every floating control. It takes the size it is laid out at.
///
/// No shadow by default: the system's glass casts none — white right up to
/// its half-point rim over a white page, measured on the simulator — and
/// the lit rim and the bending are what lift it off the page. [shadow]
/// lays the app's one float ([AppSurface.float]) outside the glass only,
/// where something must stand off a busy page: under see-through glass a
/// shadow would show through as a stain.
class GlassShape extends StatelessWidget {
  const GlassShape({super.key, this.radius, this.shadow = false});

  final double? radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GlassScope>();
    assert(scope != null, 'A GlassShape stands in a GlassGroup.');
    final mode = scope?.mode ?? GlassMode.blur;
    final recipe = scope?.recipe ?? GlassRecipe.of(GlassKind.regular);
    final contrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final shown = scope?.shown ?? 1.0;
    Color fade(Color c) => shown >= 1 ? c : c.withValues(alpha: c.a * shown);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final r = radius ?? math.min(size.width, size.height) / 2;
        final border = RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(r),
        );
        final grounded = scope?.grounded ?? false;
        final Widget glass = switch (mode) {
          // On a modal's opaque material: its tint over what it stands
          // on, which is all the shader or the blur would show there.
          GlassMode.liquid || GlassMode.blur when grounded => ClipPath(
            clipper: ShapeBorderClipper(shape: border),
            child: _Tint(
              fade(mode == GlassMode.liquid ? recipe.tint : recipe.blurTint),
              recipe,
              shown,
            ),
          ),
          GlassMode.liquid => Stack(
            fit: StackFit.expand,
            children: [
              LiquidGlass.grouped(
                shape: LiquidRoundedSuperellipse(borderRadius: r),
                // The tint is laid over the glass — over the bent page as
                // well as the frost — so the band its rim draws in from
                // beyond its edge is the glass's grey, not a black ring of
                // page; and it is the same alpha-blend whatever is under it
                // (the shader's own tint multiplies a dark glass into black
                // over a black page).
                glassContainsChild: false,
                child: _Tint(fade(recipe.tint), recipe, shown),
              ),
              // The held glass's tint, fading off the refraction just
              // given back: no pop between the two.
              if (scope?.veil case final veil?)
                IgnorePointer(
                  child: FadeTransition(
                    opacity: veil,
                    child: ClipPath(
                      clipper: ShapeBorderClipper(shape: border),
                      child: _Tint(fade(recipe.blurTint), recipe, shown),
                    ),
                  ),
                ),
            ],
          ),
          GlassMode.blur when recipe.clear => ClipPath(
            clipper: ShapeBorderClipper(shape: border),
            child: _Tint(fade(recipe.blurTint), recipe, shown),
          ),
          GlassMode.blur => ClipPath(
            clipper: ShapeBorderClipper(shape: border),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: recipe.blurFrost * shown,
                sigmaY: recipe.blurFrost * shown,
              ),
              // Put down by switching the blur off, not by taking it out:
              // the tree keeps its shape across a push.
              enabled: !scope!.down,
              backdropGroupKey: BackdropGroup.of(context)?.backdropKey,
              child: _Tint(fade(recipe.blurTint), recipe, shown),
            ),
          ),
          GlassMode.opaque => DecoratedBox(
            decoration: ShapeDecoration(
              color: fade(recipe.opaque),
              shape: border,
            ),
          ),
        };
        // The lens's lift ([GlassRecipe.lift]) is the glass's own; [shadow]
        // is the app's float, asked for by whoever stands the glass up.
        final lift = mode == GlassMode.opaque || recipe.lift.isEmpty
            ? null
            : [for (final s in recipe.lift) s.copyWith(color: fade(s.color))];
        return CustomPaint(
          painter: shadow
              ? _OuterShadow(border, GlassRecipe.float)
              : lift != null
              ? _OuterShadow(border, lift)
              : null,
          foregroundPainter: _Rim(
            border,
            recipe,
            // One rim on the shader's glass and the blur's alike; the
            // opaque bar Reduce Transparency asks for is flat, its hair
            // the only edge.
            lit: mode != GlassMode.opaque,
            contrast: contrast,
            shown: shown,
          ),
          child: SizedBox.expand(child: glass),
        );
      },
    );
  }
}

/// A [GlassShape] with something standing on it: a bar button, a pill, a
/// circle — one shape, a group of its own; or, under a [GlassGroup] that
/// [GlassGroup.gathers], one shape of that group.
///
/// The glass takes the size of [child]; [child] is drawn over it.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    this.kind = GlassKind.regular,
    this.radius,
    this.shadow = false,
    this.compact = false,
    this.visibility = 1,
    required this.child,
  });

  final GlassKind kind;
  final double? radius;
  final bool shadow;

  /// A small shape — a 44-point bar button: [GlassGroup.compact].
  final bool compact;

  /// How much of the glass is there, 0 to 1 ([GlassGroup.visibility]): a
  /// capsule coming up and going again thins its own bending, frost, tint
  /// and rim, never through an [Opacity] laid over it — an opacity over
  /// the shader or its blur reads an empty layer. Only the glass thins:
  /// [child] — the glyph, the words on it — is faded by its owner, with an
  /// opacity of its own, since nothing in it reads the screen.
  final double visibility;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shaped = Stack(
      children: [
        Positioned.fill(
          child: GlassShape(radius: radius, shadow: shadow),
        ),
        child,
      ],
    );
    // Inside a group that gathers its surfaces, one shape of it.
    final gathered =
        context.getInheritedWidgetOfExactType<_GlassScope>()?.gathers ?? false;
    if (gathered) return shaped;
    return GlassGroup(
      kind: kind,
      compact: compact,
      visibility: visibility,
      child: shaped,
    );
  }
}

/// Glass that stays itself while its page moves, as UIKit's glass never
/// stops being glass mid-push. Every other glass is held to its tint while
/// its route moves ([GlassHold]); under this a group is held only where a
/// view of the phone's stands under it, or the phone asks for less
/// transparency.
class GlassLive extends InheritedWidget {
  const GlassLive({super.key, required super.child});

  /// Whether the glass at [context] stays live through motion.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GlassLive>() != null;

  @override
  bool updateShouldNotify(GlassLive oldWidget) => false;
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({
    required this.mode,
    required this.recipe,
    required this.down,
    required this.shown,
    required this.grounded,
    required this.reasons,
    this.gathers = false,
    this.veil,
    required super.child,
  });

  /// Whether a [GlassSurface] under it is a shape of it
  /// ([GlassGroup.gathers]).
  final bool gathers;

  /// Why the group's glass is held ([GlassGroup.holdOf]).
  final GlassHoldReasons reasons;

  final GlassMode mode;

  /// The held glass's tint fading off the refraction given back
  /// ([GlassGroup.release]); null when the refraction is not drawn.
  final Animation<double>? veil;
  final GlassRecipe recipe;
  final bool down;

  /// [GlassGroup.standsOnModal]: the glass reads nothing of the screen.
  final bool grounded;

  /// [GlassGroup.visibility].
  final double shown;

  @override
  bool updateShouldNotify(_GlassScope old) =>
      old.mode != mode ||
      old.recipe != recipe ||
      old.down != down ||
      old.shown != shown ||
      old.grounded != grounded ||
      old.gathers != gathers ||
      old.veil != veil;
}

/// The glass's own colour, and the light inside it ([GlassRecipe.sheenTop]):
/// a fill where the recipe has no sheen.
class _Tint extends StatelessWidget {
  const _Tint(this.color, this.recipe, this.shown);

  final Color color;
  final GlassRecipe recipe;
  final double shown;

  @override
  Widget build(BuildContext context) {
    if (recipe.sheenTop.a == 0 && recipe.sheenFoot.a == 0) {
      return ColoredBox(color: color);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(_fade(recipe.sheenTop), color),
            color,
            color,
            Color.alphaBlend(_fade(recipe.sheenFoot), color),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ),
      ),
    );
  }

  Color _fade(Color c) => c.withValues(alpha: c.a * shown);
}

/// The float, outside the glass only.
class _OuterShadow extends CustomPainter {
  const _OuterShadow(this.border, this.shadows);

  final OutlinedBorder border;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = border.getOuterPath(rect);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(64))
          ..addPath(shape, Offset.zero),
      );
    for (final shadow in shadows) {
      canvas.drawPath(shape.shift(shadow.offset), shadow.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) =>
      old.border != border || !listEquals(old.shadows, shadows);
}

/// The rim drawn by hand, on every way of drawing the glass: a hair round
/// it where the recipe has one (by day), and the highlight — about a point
/// wide and fading inward, brightest along the top and a touch to the left,
/// nothing at the sides, fainter along the foot, as the simulator draws
/// the system's own. Never an even ring: that reads as a stroked outline
/// round a 44-point button. When the phone asks for more
/// contrast, a crisp edge instead of both.
class _Rim extends CustomPainter {
  const _Rim(
    this.border,
    this.recipe, {
    required this.lit,
    required this.contrast,
    required this.shown,
  });

  final OutlinedBorder border;
  final GlassRecipe recipe;
  final bool lit;
  final bool contrast;

  /// The tallest a shape may be and still be lit as a low capsule: under a
  /// 44-point bar button's height plus a few, so the button and a bar
  /// keep their own rim.
  static const double _lowCapsule = 46;

  /// How much of the glass is there ([GlassGroup.visibility]).
  final double shown;

  Color _fade(Color c) => c.withValues(alpha: c.a * shown);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (shown <= 0) return;
    if (contrast) {
      canvas.drawPath(
        border.getInnerPath(rect.deflate(0.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _fade(recipe.contrastEdge),
      );
      return;
    }
    if (recipe.hairline.a > 0) {
      canvas.drawPath(
        border.getOuterPath(rect.deflate(0.25)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = _fade(recipe.hairline),
      );
    }
    if (!lit) return;
    if (recipe.edgeShade.a > 0) {
      // Inside the rim only: a band a few points deep, darkest at the edge
      // and gone toward the middle — the glass's thickness seen edge-on.
      final shape = border.getOuterPath(rect);
      canvas
        ..save()
        ..clipPath(shape)
        ..drawPath(
          shape,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
            ..color = _fade(recipe.edgeShade),
        )
        ..restore();
    }
    // A low capsule — a filter strip, a segmented track, under the height
    // of a bar button and well wider than it is tall — is lit along its
    // top alone. Its round ends run the whole of its short height, so the
    // lit top and the shaded foot met round them and closed into an even
    // grey ring on black (the home audit's filter capsules); the system's
    // strips there show a highlight on the top arc and nothing below it.
    final low = size.height <= _lowCapsule && size.width >= size.height * 1.6;
    // Down the height, tilted a little so the top left leads: full along
    // the top, gone by a third of the way down, back to [rimShade] at the
    // foot. On a capsule the whole flat top is lit and its round ends are
    // not, which is where the system's highlight is too.
    //
    // A low capsule's run is far wider than tall, so any tilt there leans
    // the light along it — the right of its top unlit, the left end lit
    // down its whole height — and it is lit straight down instead.
    Shader light(double strength) => LinearGradient(
      begin: low ? Alignment.topCenter : const Alignment(-0.3, -1),
      end: low ? Alignment.bottomCenter : const Alignment(0.3, 1),
      colors: [
        recipe.rimLit.withValues(alpha: recipe.rimLit.a * strength * shown),
        recipe.rimLit.withValues(alpha: 0),
        recipe.rimShade.withValues(alpha: 0),
        recipe.rimShade.withValues(
          alpha: low ? 0 : recipe.rimShade.a * strength * shown,
        ),
      ],
      stops: low ? const [0, 0.26, 0.7, 1] : const [0, 0.32, 0.7, 1],
    ).createShader(rect);
    // Two strokes, the outer half point at full strength and a point
    // inside it at 0.4, so the light fades into the glass rather than
    // ending in a line.
    canvas
      ..drawPath(
        border.getOuterPath(rect.deflate(0.25)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..shader = light(1),
      )
      ..drawPath(
        border.getOuterPath(rect.deflate(1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = light(0.4),
      );
  }

  @override
  bool shouldRepaint(_Rim old) =>
      old.border != border ||
      old.recipe != recipe ||
      old.lit != lit ||
      old.contrast != contrast ||
      old.shown != shown;
}
