import 'package:flutter/widgets.dart';

import '../glass/native_glass.dart';
import 'native_controls_gate.dart';

/// How the player's controls are drawn on an iPhone, as chosen in
/// Settings → Player.
enum PlayerControlsStyle {
  /// iOS 26's own Liquid Glass buttons, pull-down menus and iOS sheets.
  native,

  /// Flutter's buttons, each on the phone's own clear glass.
  systemGlass,

  /// Flutter's buttons on the Flutter shader glass, with the Flutter sheets.
  classicGlass;

  /// The 3.2.1 look, until the viewer picks another.
  static const PlayerControlsStyle fallback = PlayerControlsStyle.classicGlass;

  /// Stored by name; anything unknown reads as [fallback].
  static PlayerControlsStyle fromName(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => fallback);
}

/// Whether the phone has the clear system glass (iOS 26+) that the system
/// glass style stands on.
bool systemGlassAvailable(NativeGlassCapability cap) =>
    cap.systemGlass && cap.styles.contains(NativeGlassStyle.clear.name);

/// Whether [style] can be drawn on a phone answering [cap].
bool playerControlsStyleAvailable(
  PlayerControlsStyle style,
  NativeGlassCapability cap,
) => switch (style) {
  PlayerControlsStyle.native => systemGlassAvailable(cap) && cap.glassControls,
  PlayerControlsStyle.systemGlass => systemGlassAvailable(cap),
  PlayerControlsStyle.classicGlass => true,
};

/// Whether the player should offer the native controls once: an iPhone or
/// iPad that can draw them, a viewer who never chose a style, and an offer
/// not shown before.
bool shouldOfferNativeControls({
  required bool isIOS,
  required bool isTv,
  required bool isDesktop,
  required NativeGlassCapability cap,
  required bool reduceTransparency,
  required PlayerControlsStyle? stored,
  required bool alreadyOffered,
}) {
  if (!isIOS || isTv || isDesktop || reduceTransparency) return false;
  if (stored != null || alreadyOffered) return false;
  return playerControlsStyleAvailable(PlayerControlsStyle.native, cap);
}

/// What the offer's answer stores: "Try it" is [PlayerControlsStyle.native],
/// and "Not now" or any other dismissal keeps the classic glass for good.
PlayerControlsStyle nativeOfferOutcome(bool? accepted) => accepted == true
    ? PlayerControlsStyle.native
    : PlayerControlsStyle.classicGlass;

/// The style the player actually draws for [chosen]: classic glass off an
/// iPhone, under Reduce Transparency, and below iOS 26. The native choice on
/// a phone with the glass but not the bar factory keeps the system glass
/// under Flutter's buttons, as it always did.
PlayerControlsStyle effectivePlayerControlsStyle({
  required PlayerControlsStyle chosen,
  required bool isIOS,
  required bool isTv,
  required bool isDesktop,
  required NativeGlassCapability cap,
  required bool reduceTransparency,
}) {
  if (!isIOS || isTv || isDesktop || reduceTransparency) {
    return PlayerControlsStyle.classicGlass;
  }
  if (!systemGlassAvailable(cap)) return PlayerControlsStyle.classicGlass;
  if (chosen == PlayerControlsStyle.native) {
    return nativeControlsDraw(
          isIOS: isIOS,
          isTv: isTv,
          isDesktop: isDesktop,
          cap: cap,
          reduceTransparency: reduceTransparency,
        )
        ? PlayerControlsStyle.native
        : PlayerControlsStyle.systemGlass;
  }
  return chosen;
}

/// The chosen style for everything under it; the player's media glass layers
/// read it to keep to the shader on [PlayerControlsStyle.classicGlass].
class PlayerControlsStyleScope extends InheritedWidget {
  const PlayerControlsStyleScope({
    super.key,
    required this.style,
    required super.child,
  });

  final PlayerControlsStyle style;

  static PlayerControlsStyle? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlayerControlsStyleScope>()
      ?.style;

  @override
  bool updateShouldNotify(PlayerControlsStyleScope old) => old.style != style;
}
