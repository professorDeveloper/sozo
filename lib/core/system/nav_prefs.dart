import 'package:flutter/foundation.dart';

/// User preference for the MOBILE bottom navigation style:
///   'solid'   — floating solid dark capsule (default; shader-free, always smooth)
///   'glass'   — iOS-26 floating liquid-glass capsule
///   'classic' — the original full-width frosted bottom bar
///
/// Persisted via HiveService (`nav_style`). This notifier lets the nav rebuild
/// INSTANTLY when the style is changed from Profile → Appearance — Profile is a
/// tab hosted inside the same shell (`main_page`) as the nav, so a plain rebuild
/// wouldn't reach the sibling nav; the shared notifier does.
class NavPrefs {
  NavPrefs._();

  static const String glass = 'glass';
  static const String solid = 'solid';
  static const String classic = 'classic';

  static final ValueNotifier<bool> compactOnScroll = ValueNotifier<bool>(true);

  static final ValueNotifier<String> navStyle = ValueNotifier<String>(solid);

  /// Persisted bottom-nav tab set/order (list of TabId.name). Instant-rebuild
  /// for the same reason as [navStyle]: the customizer lives in the Profile tab,
  /// a sibling of the nav inside the same shell. Default = current shipped tabs.
  static final ValueNotifier<List<String>> tabOrder =
      ValueNotifier<List<String>>(const [
        'home',
        'search',
        'shorts',
        'myList',
        'profile',
      ]);
}
