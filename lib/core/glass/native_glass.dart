import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_sense.dart';

/// The phone's own glass, hosted in the tree as a UIKit view
/// (ios/Runner/NativeGlass.swift).
///
/// Everywhere else the app draws Liquid Glass itself — a refraction shader
/// over the page it reads, a rim lit by hand (`GlassGroup` in
/// glass_surface.dart) — because that is the only kind of glass a Flutter
/// layer can be. From iOS 26 the platform draws the material itself
/// (`UIGlassEffect`), and that material is the thing our shader is an
/// approximation *of*: its specular rim, the way its tint answers whatever
/// moves beneath it, and its behaviour under Reduce Transparency and
/// Increase Contrast are all maintained by Apple rather than by us, and
/// they change with the OS rather than with our next release. Where a
/// surface can afford to be a hosted view, the system's material is the
/// better glass.
///
/// ## When to use this, and when not to
///
/// A hosted view is not a Flutter layer, and the difference is not a
/// detail — it decides which surfaces this is right for.
///
/// * **It composites outside Flutter's picture.** The engine cuts the
///   Flutter picture where the view is and puts what Flutter draws after it
///   into a layer above. That is the same seam `_GlassWatch` in
///   glass_watch.dart already has to work around for the native tab bar and
///   the AirPlay button: the refraction shader over a hosted view reads a
///   backdrop with nothing of the page in it and writes an opaque block. So
///   a [NativeGlass] standing inside a `GlassGroup` that draws the
///   refraction will ruin that group's glass, not join it — it belongs
///   *instead of* the group, never inside one.
/// * **It cannot be freely transformed.** Flutter applies a transform to a
///   hosted view by handing UIKit a frame and, where it can, a mask; a
///   rotation, a non-rectangular clip, a shader mask or an arbitrary
///   `Transform` either does not reach it or forces the engine onto a much
///   more expensive path. The shader glass survives all of those because it
///   is paint. So: the still surfaces — a bar that sits where it sits, a
///   panel, a sheet's own material — can be native; the moving pieces — the
///   tab bar's travelling lens, a glass that melts into its neighbour
///   (`GlassGroup.blend`), anything mid-route-transition — should stay on
///   the shader.
/// * **It is invisible to goldens.** A `UiKitView` renders nothing in the
///   test renderer and nothing in a golden file, so a surface drawn this way
///   silently stops being covered by the golden that used to guard it. The
///   decision below ([nativeGlassDraw]) and the fallback are unit-testable;
///   the pixels are only ever testable on a device.
/// * **Its hit-testing is its own.** Flutter wraps a hosted view in a
///   touch-intercepting view and offers it each touch first. This glass
///   declines them all (`isUserInteractionEnabled = false` on the Swift
///   side) so that the Flutter button drawn over it still gets the tap —
///   which is where every tap on glass in this app belongs. The cost is
///   that the system's *interactive* glass, which reacts to a finger
///   landing on the material, cannot light up on its own: pass
///   [interactive] only for a surface that really is the touch target and
///   has no Flutter gesture over it.
///
/// ## What it is told, and by whom
///
/// Nothing here guesses from a version string. The Swift side answers
/// `glassCapability` on the `soplay/glass` channel [GlassSense] already
/// owns, saying what *this* phone has — whether `UIGlassEffect` exists on
/// it, which glass styles, which blur materials, and whether Reduce
/// Transparency is on — and [nativeGlassDraw] decides from that. The app's
/// floor is iOS 15 and it is built against the iOS 27 SDK, so the answer
/// genuinely differs across the phones it ships to, and a wrong guess is a
/// blank rectangle on somebody's screen rather than a slightly wrong grey.
///
/// A phone without the glass effect gets the system blur material, which is
/// a real material and not an imitation of one; a phone that is not an
/// iPhone, or one asking for Reduce Transparency, gets nothing hosted at
/// all and the caller's [fallback] instead.
class NativeGlass extends StatefulWidget {
  const NativeGlass({
    super.key,
    this.style = NativeGlassStyle.regular,
    this.material = NativeGlassMaterial.thin,
    this.borderRadius = BorderRadius.zero,
    this.tint,
    this.interactive = false,
    this.onDraw,
    required this.fallback,
  });

  /// The view type the Swift factory is registered under.
  static const String viewType = 'soplay/native_glass';

  /// The method [GlassSense.channel] answers with the capability map.
  static const String capabilityMethod = 'glassCapability';

  /// Which of the system's two glasses: the standard material, or the clear
  /// one for glass over video.
  final NativeGlassStyle style;

  /// The blur material to stand in with where the OS has no glass effect.
  final NativeGlassMaterial material;

  /// The corner the view is clipped to. UIKit clips it with its own
  /// continuous curve — the squircle its bars and buttons use — so only the
  /// radius crosses the channel, and a non-uniform [BorderRadius] takes its
  /// largest corner rather than being silently squared off.
  final BorderRadius borderRadius;

  /// A colour laid on the material: the glass effect's own `tintColor`
  /// where the OS has one, a wash inside the effect view's content where it
  /// does not. Null leaves the material untinted.
  final Color? tint;

  /// Whether this surface is itself the touch target, so the system's
  /// interactive glass may react to a finger on it. False for anything with
  /// a Flutter gesture drawn over it, which is nearly everything here.
  final bool interactive;

  /// Told what was drawn, each time the decision changes. Only for tests
  /// and for a caller that wants to log what a device actually gave: the
  /// widget needs nothing back.
  final ValueChanged<NativeGlassDraw>? onDraw;

  /// Drawn in place of the hosted view wherever one cannot be hosted — not
  /// an iPhone, Reduce Transparency, a capability that says no, or the
  /// moment before the first answer arrives. The caller passes its own
  /// glass here, so a surface that goes native loses nothing where native
  /// is unavailable.
  final WidgetBuilder fallback;

  /// Asks the phone what its glass can do, once per process.
  ///
  /// The future is kept rather than the answer: every [NativeGlass] built
  /// before the first reply awaits the same round trip instead of starting
  /// one of its own. The capability is a property of the OS build, so it
  /// cannot change under a running app — Reduce Transparency can, and that
  /// is why it is read from [GlassSense] on every build and not from this.
  static Future<NativeGlassCapability>? _asked;

  static Future<NativeGlassCapability> capability() =>
      _asked ??= _ask().catchError((Object _) {
        // Only an unforeseen throw reaches here: [_ask] answers `absent`
        // itself for the two failures it expects, and both of those are
        // permanent facts about the build (no bridge compiled in, or the
        // channel refusing the call), so remembering them is right. What
        // must not be remembered is a failure nobody predicted, since the
        // reason for it may well have passed — hence the promise is dropped
        // and the next caller asks the phone again.
        _asked = null;
        return NativeGlassCapability.absent;
      });

  static Future<NativeGlassCapability> _ask() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return NativeGlassCapability.absent;
    }
    try {
      final said = await GlassSense.channel.invokeMapMethod<String, Object?>(
        capabilityMethod,
      );
      return NativeGlassCapability.fromChannel(said);
    } on MissingPluginException {
      // A runner without the bridge — a test, a build from before this
      // existed: no hosted glass, and no error worth logging.
      return NativeGlassCapability.absent;
    } on PlatformException {
      return NativeGlassCapability.absent;
    }
  }

  /// Forgets the remembered probe. Only for a test that pumps more than one
  /// capability in the one process.
  @visibleForTesting
  static void resetCapability() => _asked = null;

  @override
  State<NativeGlass> createState() => _NativeGlassState();
}

class _NativeGlassState extends State<NativeGlass> {
  /// Null until the phone has answered, which is why the first frame of a
  /// native surface is the [NativeGlass.fallback]: a hosted view cannot be
  /// mounted speculatively and taken away again without a visible flash.
  NativeGlassCapability? _said;

  NativeGlassDraw? _told;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final said = await NativeGlass.capability();
    if (!mounted) return;
    setState(() => _said = said);
  }

  /// Reports a changed decision after the frame: [NativeGlass.onDraw] is a
  /// listener, and calling it from `build` would let it set state during a
  /// build.
  void _report(NativeGlassDraw draw) {
    if (draw == _told) return;
    _told = draw;
    final onDraw = widget.onDraw;
    if (onDraw == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onDraw(draw);
    });
  }

  @override
  Widget build(BuildContext context) {
    final said = _said ?? NativeGlassCapability.absent;
    final draw = nativeGlassDraw(
      platform: defaultTargetPlatform,
      capability: NativeGlassScope.of(context) ?? said,
      style: widget.style,
      reduceTransparency: GlassSense.reduceTransparencyOf(context),
    );
    _report(draw);
    if (draw == NativeGlassDraw.none) return widget.fallback(context);

    final corners = widget.borderRadius;
    final radius = [
      corners.topLeft.x,
      corners.topRight.x,
      corners.bottomLeft.x,
      corners.bottomRight.x,
    ].reduce((a, b) => a > b ? a : b);

    return UiKitView(
      viewType: NativeGlass.viewType,
      creationParams: <String, Object?>{
        'style': widget.style.name,
        'material': widget.material.name,
        'cornerRadius': radius,
        'interactive': widget.interactive,
        'tint': widget.tint?.toARGB32(),
      },
      creationParamsCodec: const StandardMessageCodec(),
      // Glass takes no touches of its own: the Flutter button over it does
      // (see the class comment), and `opaque: false` with no gesture
      // recognizers keeps the hosted view out of the gesture arena.
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}

/// Which of the system's two glass materials.
enum NativeGlassStyle {
  /// The standard material: what a bar or a button is made of.
  regular,

  /// The clear material: glass over video, which keeps the frame's colour
  /// rather than frosting it — the native counterpart of
  /// `GlassKind.clear`.
  clear,
}

/// The system blur material to stand in with where the OS has no glass
/// effect. These name UIKit's dark materials, thinnest first; the app's
/// glass is dark everywhere, so the appearance-following variants are not
/// offered — on a light phone over our dark page they turn white.
enum NativeGlassMaterial { ultraThin, thin, regular, thick, chrome }

/// What a [NativeGlass] draws.
enum NativeGlassDraw {
  /// The system's own glass material (`UIGlassEffect`, iOS 26+).
  systemGlass,

  /// The system's blur material, on an iPhone whose OS has no glass effect.
  systemMaterial,

  /// Nothing hosted: the caller's fallback draws instead.
  none,
}

/// What this phone's glass can do, as the Swift side reported it.
///
/// Read once per process ([NativeGlass.capability]) because it is a property
/// of the OS build. Reduce Transparency is in here too — the probe answers
/// it for a caller that wants one round trip — but it is *not* what the
/// widget branches on: that switch can be thrown while the app runs, so the
/// live value comes from [GlassSense] on every build.
@immutable
final class NativeGlassCapability {
  const NativeGlassCapability({
    required this.systemVersion,
    required this.majorVersion,
    required this.systemGlass,
    required this.styles,
    required this.materials,
    required this.reduceTransparency,
  });

  /// No hosted glass of any kind: not an iPhone, or a phone that did not
  /// answer. Chosen over a nullable capability so the decision below never
  /// has two ways to say "nothing".
  static const NativeGlassCapability absent = NativeGlassCapability(
    systemVersion: '',
    majorVersion: 0,
    systemGlass: false,
    styles: <String>{},
    materials: <String>{},
    reduceTransparency: false,
  );

  /// Reads the map `glassCapability` answers with. Every field is defaulted:
  /// an older Swift side that has not learned a key yet should degrade, not
  /// throw, because the Dart and the native halves of this app are not
  /// always the same age on a phone mid-update.
  factory NativeGlassCapability.fromChannel(Map<String, Object?>? said) {
    if (said == null) return absent;
    Set<String> names(Object? raw) => switch (raw) {
      final List<Object?> list => list.whereType<String>().toSet(),
      _ => const <String>{},
    };
    return NativeGlassCapability(
      systemVersion: said['systemVersion'] as String? ?? '',
      majorVersion: (said['majorVersion'] as num?)?.toInt() ?? 0,
      systemGlass: said['systemGlass'] as bool? ?? false,
      styles: names(said['glassStyles']),
      materials: names(said['materials']),
      reduceTransparency: said['reduceTransparency'] as bool? ?? false,
    );
  }

  /// `UIDevice.systemVersion`, for a log line. Nothing branches on it.
  final String systemVersion;

  /// The OS's major version, for a log line and for the one case a
  /// capability cannot express: telling a phone that *should* have the
  /// glass effect but did not report it apart from one that should not.
  final int majorVersion;

  /// Whether `UIGlassEffect` exists on the phone running this — the one
  /// fact Dart cannot work out for itself.
  final bool systemGlass;

  /// The glass styles it offers, as [NativeGlassStyle] names.
  final Set<String> styles;

  /// The blur materials it offers, as [NativeGlassMaterial] names.
  final Set<String> materials;

  /// Whether the phone asked for less transparency when it was probed. Use
  /// [GlassSense] for the live answer, not this.
  final bool reduceTransparency;

  /// Compared by what it says and not by which object said it, because
  /// [NativeGlassScope.updateShouldNotify] asks this question and two
  /// probes of the same phone are the same answer — without this, a scope
  /// rebuilt with an equal capability would rebuild every surface under it.
  @override
  bool operator ==(Object other) =>
      other is NativeGlassCapability &&
      other.systemVersion == systemVersion &&
      other.majorVersion == majorVersion &&
      other.systemGlass == systemGlass &&
      other.reduceTransparency == reduceTransparency &&
      setEquals(other.styles, styles) &&
      setEquals(other.materials, materials);

  @override
  int get hashCode => Object.hash(
    systemVersion,
    majorVersion,
    systemGlass,
    reduceTransparency,
    Object.hashAllUnordered(styles),
    Object.hashAllUnordered(materials),
  );

  @override
  String toString() =>
      'NativeGlassCapability(iOS $systemVersion, glass: $systemGlass, '
      'styles: $styles, materials: $materials)';
}

/// What a [NativeGlass] should draw, given the phone and what it said.
///
/// Pulled out of the widget as a function of its inputs so the decision can
/// be tested without a device — which matters more here than usual, because
/// the thing it decides between renders nothing at all in a test.
///
/// Reduce Transparency hosts nothing: the opaque fill the app uses then
/// (`GlassMode.opaque`) is a plain painted colour, and painting it in
/// Flutter keeps it inside the Flutter picture where it can be clipped and
/// animated with everything else — a hosted view that is merely opaque buys
/// nothing and still costs a composition seam.
NativeGlassDraw nativeGlassDraw({
  required TargetPlatform platform,
  required NativeGlassCapability capability,
  NativeGlassStyle style = NativeGlassStyle.regular,
  bool reduceTransparency = false,
}) {
  if (platform != TargetPlatform.iOS) return NativeGlassDraw.none;
  if (reduceTransparency) return NativeGlassDraw.none;
  if (capability.systemGlass && capability.styles.contains(style.name)) {
    return NativeGlassDraw.systemGlass;
  }
  if (capability.materials.isNotEmpty) return NativeGlassDraw.systemMaterial;
  return NativeGlassDraw.none;
}

/// Hands the glass under it a capability in place of the phone's.
///
/// A scope rather than a static a test sets and resets, for the reason
/// `GlassPickScope` gives: one left set by a test that failed half way
/// would go on into every test after it.
class NativeGlassScope extends InheritedWidget {
  const NativeGlassScope({
    super.key,
    required this.capability,
    required super.child,
  });

  final NativeGlassCapability capability;

  /// The capability over [context]; null with no scope, so the widget falls
  /// back to what it probed.
  static NativeGlassCapability? of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeGlassScope>()
          ?.capability;

  @override
  bool updateShouldNotify(NativeGlassScope old) =>
      old.capability != capability;
}
