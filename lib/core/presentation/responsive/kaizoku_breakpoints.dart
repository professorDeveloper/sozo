import 'package:flutter/widgets.dart';
import 'package:soplay/core/system/platform_utils.dart';

/// Supported physical interaction types for Kaizoku.
enum KaizokuDeviceType {
  mobilePhone,
  mobileTablet,
  desktop,
  tv,
}

/// Standardized responsive breakpoints across all target devices.
class KaizokuBreakpoints {
  const KaizokuBreakpoints._();

  /// Below this is considered a phone form factor (portrait).
  static const double compact = 600.0;

  /// Between compact and medium is a tablet, foldable, or narrow desktop window.
  static const double medium = 1024.0;

  /// Large desktop displays, widescreen monitors.
  static const double large = 1440.0;

  /// Ultra-wide displays.
  static const double ultra = 1920.0;

  /// Resolves device type based on platform properties and current constraints.
  static KaizokuDeviceType resolve(BuildContext context) {
    if (isTvPlatform) {
      return KaizokuDeviceType.tv;
    }

    final width = MediaQuery.sizeOf(context).width;

    if (isDesktopPlatform) {
      // Desktop windows can be resized down to phone widths.
      return width < compact
          ? KaizokuDeviceType.mobilePhone
          : KaizokuDeviceType.desktop;
    }

    if (width < compact) {
      return KaizokuDeviceType.mobilePhone;
    } else if (width < medium) {
      return KaizokuDeviceType.mobileTablet;
    } else {
      return KaizokuDeviceType.desktop;
    }
  }

  /// Helper to test if current context is TV mode.
  static bool isTv(BuildContext context) => resolve(context) == KaizokuDeviceType.tv;

  /// Helper to test if current context is desktop mode.
  static bool isDesktop(BuildContext context) => resolve(context) == KaizokuDeviceType.desktop;

  /// Helper to test if current context is tablet mode.
  static bool isTablet(BuildContext context) => resolve(context) == KaizokuDeviceType.mobileTablet;

  /// Helper to test if current context is mobile phone mode.
  static bool isPhone(BuildContext context) => resolve(context) == KaizokuDeviceType.mobilePhone;
}

/// Adaptive layout builder switching dynamically between phone, tablet, desktop, and TV layouts.
class KaizokuResponsiveLayout extends StatelessWidget {
  const KaizokuResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.tv,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;
  final WidgetBuilder? tv;

  @override
  Widget build(BuildContext context) {
    final type = KaizokuBreakpoints.resolve(context);

    switch (type) {
      case KaizokuDeviceType.tv:
        return (tv ?? desktop ?? mobile)(context);
      case KaizokuDeviceType.desktop:
        return (desktop ?? tablet ?? mobile)(context);
      case KaizokuDeviceType.mobileTablet:
        return (tablet ?? desktop ?? mobile)(context);
      case KaizokuDeviceType.mobilePhone:
        return mobile(context);
    }
  }
}

/// Extension on BuildContext for quick access to device type and responsive helpers.
extension KaizokuResponsiveContext on BuildContext {
  KaizokuDeviceType get deviceType => KaizokuBreakpoints.resolve(this);
  bool get isTv => KaizokuBreakpoints.isTv(this);
  bool get isDesktop => KaizokuBreakpoints.isDesktop(this);
  bool get isTablet => KaizokuBreakpoints.isTablet(this);
  bool get isPhone => KaizokuBreakpoints.isPhone(this);
}
