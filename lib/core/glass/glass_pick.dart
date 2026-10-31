import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'glass_power.dart';

/// Which way the glass under a [GlassPickScope] may be drawn, whatever the
/// phone can do.
enum GlassPick {
  /// As the phone can: the refraction where the shader runs (Impeller) and
  /// the phone can spend it ([GlassPower]: not an Android Go phone), the
  /// blur elsewhere. What the app runs on — there is no scope over it.
  platform,

  /// The blur, never the refraction: a golden of the glass, the token
  /// gallery. The test renderer has no shader anyway; this says so where a
  /// test wants it said.
  blur,

  /// The refraction even where the renderer has no shader (it then draws
  /// its stand-in): tests that check which glass is handed to the shader,
  /// and when it is held. The phone's power still has its say
  /// ([GlassPower]): this stands in for the renderer, not for the phone.
  liquid,
}

/// Picks how the glass under it is drawn ([GlassPick]).
///
/// A scope rather than a static a test sets and resets: one left set by a
/// test that failed half way would go on into every test after it. A scope
/// ends with the tree it was pumped in.
class GlassPickScope extends InheritedWidget {
  const GlassPickScope({super.key, required this.pick, required super.child});

  final GlassPick pick;

  /// The pick over [context]; [GlassPick.platform] with no scope.
  static GlassPick of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassPickScope>()?.pick ??
      GlassPick.platform;

  /// Whether glass at [context] may draw the refraction at all: the
  /// renderer has the shader (or [GlassPick.liquid] says it has), and the
  /// phone can spend it ([GlassPower.affordsAt]).
  static bool liquidAt(BuildContext context) => switch (of(context)) {
    GlassPick.platform =>
      ImageFilter.isShaderFilterSupported && GlassPower.affordsAt(context),
    GlassPick.blur => false,
    GlassPick.liquid => GlassPower.affordsAt(context),
  };

  @override
  bool updateShouldNotify(GlassPickScope old) => old.pick != pick;
}
