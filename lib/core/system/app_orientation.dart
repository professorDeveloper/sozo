import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher, Size;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:soplay/core/system/platform_utils.dart';

class AppOrientation {
  AppOrientation._();

  static const _channel = MethodChannel('app/orientation');

  static const List<DeviceOrientation> appDefault = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  /// What was last asked for, so a fold or unfold can re-apply it.
  static List<DeviceOrientation>? _requested;
  static _MetricsWatch? _watch;

  /// A tablet or an unfolded foldable: 600dp is where Material stops treating
  /// a window as a phone.
  @visibleForTesting
  static bool isLargeScreen(Size logicalSize) =>
      !logicalSize.isEmpty && logicalSize.shortestSide >= 600;

  /// A portrait-only request is the phone layout's lock; a large screen is
  /// left free to rotate instead. Landscape requests (the player) are kept.
  @visibleForTesting
  static List<DeviceOrientation> resolve(
    List<DeviceOrientation> requested, {
    required bool largeScreen,
  }) {
    final portraitOnly =
        requested.isNotEmpty &&
        requested.every(
          (o) =>
              o == DeviceOrientation.portraitUp ||
              o == DeviceOrientation.portraitDown,
        );
    if (largeScreen && portraitOnly) return DeviceOrientation.values;
    return requested;
  }

  static Size _screenSize() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return Size.zero;
    final view = views.first;
    try {
      final display = view.display;
      if (!display.size.isEmpty) return display.size / display.devicePixelRatio;
    } catch (_) {}
    return view.physicalSize / view.devicePixelRatio;
  }

  static Future<void> set(List<DeviceOrientation> orientations) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // A television is fixed landscape and cannot be rotated. Applying the app's
    // portrait lock there letterboxes the whole UI into a phone-shaped column
    // in the middle of the screen, so TV keeps the system orientation.
    if (isTvPlatform) return;
    _requested = orientations;
    _watch ??= _MetricsWatch()..attach();
    await _apply(
      resolve(orientations, largeScreen: isLargeScreen(_screenSize())),
    );
  }

  static Future<void> _apply(List<DeviceOrientation> orientations) async {
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>('set', {
          'modes': orientations.map(_name).toList(),
        });
      } catch (_) {
        await SystemChrome.setPreferredOrientations(orientations);
      }
      return;
    }
    await SystemChrome.setPreferredOrientations(orientations);
  }

  static String _name(DeviceOrientation o) => switch (o) {
    DeviceOrientation.portraitUp => 'portraitUp',
    DeviceOrientation.portraitDown => 'portraitDown',
    DeviceOrientation.landscapeLeft => 'landscapeLeft',
    DeviceOrientation.landscapeRight => 'landscapeRight',
  };
}

/// Re-applies the last request when a foldable opens or closes.
class _MetricsWatch with WidgetsBindingObserver {
  bool? _large;

  void attach() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeMetrics() {
    final large = AppOrientation.isLargeScreen(AppOrientation._screenSize());
    if (large == _large) return;
    _large = large;
    final requested = AppOrientation._requested;
    if (requested == null) return;
    AppOrientation._apply(
      AppOrientation.resolve(requested, largeScreen: large),
    ).catchError((Object _) {});
  }
}
