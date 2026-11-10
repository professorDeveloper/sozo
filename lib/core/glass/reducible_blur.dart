import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'glass_power.dart';

/// A backdrop blur that drops to a plain translucent fill on phones where
/// [GlassPowerReading.reducesEffects] holds. The caller still clips it.
class ReducibleBlur extends StatelessWidget {
  const ReducibleBlur({
    super.key,
    required this.sigma,
    required this.child,
    this.reducedFill,
  });

  final double sigma;
  final Widget child;

  /// Painted under [child] instead of the blur, to keep the surface legible.
  final Color? reducedFill;

  @override
  Widget build(BuildContext context) {
    if (GlassPower.reducesEffectsAt(context)) {
      final fill = reducedFill;
      return fill == null ? child : ColoredBox(color: fill, child: child);
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
