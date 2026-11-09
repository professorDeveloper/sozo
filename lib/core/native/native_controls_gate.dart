import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../glass/glass_sense.dart';
import '../glass/native_glass.dart';
import '../system/platform_utils.dart';
import 'player_controls_style.dart';

/// Whether the player's controls are the phone's own glass buttons
/// (ios/Runner/NativePlayerBar.swift) rather than Flutter's.
///
/// In the order [nativeGlassDraw] asks: an iPhone, no Reduce Transparency,
/// the clear system glass, and then the bar factory itself. TV and desktop
/// never host, whatever they report.
bool nativeControlsDraw({
  required bool isIOS,
  required bool isTv,
  required bool isDesktop,
  required NativeGlassCapability cap,
  required bool reduceTransparency,
}) {
  if (!isIOS || isTv || isDesktop) return false;
  if (reduceTransparency) return false;
  if (!cap.systemGlass || !cap.styles.contains(NativeGlassStyle.clear.name)) {
    return false;
  }
  return cap.glassControls;
}

/// Overrides [isDesktopPlatform] for the gate: `flutter test` runs on a
/// desktop host, so without this no test could reach the native path.
@visibleForTesting
bool? debugNativeControlsDesktopOverride;

abstract final class NativeControls {
  static NativeGlassCapability? _known;

  /// Asks the phone once, before the first frame, so the player can decide
  /// on its first build instead of swapping Flutter for UIKit under the
  /// viewer. A phone slower than [timeout] keeps Flutter until it answers.
  static Future<void> warm({
    Duration timeout = const Duration(milliseconds: 300),
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final asked = NativeGlass.capability().then((c) => _known = c);
    try {
      await asked.timeout(timeout);
    } on TimeoutException {
      // Answered later; [_known] is set then.
    }
  }

  @visibleForTesting
  static void debugReset() => _known = null;

  /// The live decision for [context]: a [NativeControlsScope] above wins,
  /// so the player can latch one answer for the whole page.
  static bool of(BuildContext context) {
    final latched = NativeControlsScope.maybeOf(context);
    if (latched != null) return latched;
    return decide(context);
  }

  /// The decision from the capability and the switches, ignoring any scope;
  /// only the native [chosen] style draws the native bars.
  static bool decide(
    BuildContext context, {
    PlayerControlsStyle chosen = PlayerControlsStyle.native,
  }) =>
      effectivePlayerControlsStyle(
        chosen: chosen,
        isIOS: defaultTargetPlatform == TargetPlatform.iOS,
        isTv: isTvPlatform,
        isDesktop: debugNativeControlsDesktopOverride ?? isDesktopPlatform,
        cap: capabilityOf(context),
        reduceTransparency: GlassSense.reduceTransparencyOf(context),
      ) ==
      PlayerControlsStyle.native;

  /// Whether to offer the native controls once, on the same switches as
  /// [decide].
  static bool shouldOffer(
    BuildContext context, {
    required PlayerControlsStyle? stored,
    required bool alreadyOffered,
  }) => shouldOfferNativeControls(
    isIOS: defaultTargetPlatform == TargetPlatform.iOS,
    isTv: isTvPlatform,
    isDesktop: debugNativeControlsDesktopOverride ?? isDesktopPlatform,
    cap: capabilityOf(context),
    reduceTransparency: GlassSense.reduceTransparencyOf(context),
    stored: stored,
    alreadyOffered: alreadyOffered,
  );

  /// What the phone said, or [NativeGlassCapability.absent] before it has.
  static NativeGlassCapability capabilityOf(BuildContext context) =>
      NativeGlassScope.of(context) ?? _known ?? NativeGlassCapability.absent;
}

/// One decision for everything under it.
class NativeControlsScope extends InheritedWidget {
  const NativeControlsScope({
    super.key,
    required this.native,
    required super.child,
  });

  final bool native;

  static bool? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NativeControlsScope>()?.native;

  @override
  bool updateShouldNotify(NativeControlsScope old) => old.native != native;
}
