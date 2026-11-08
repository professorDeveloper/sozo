import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What a widget that failed to build shows in release, instead of a grey box.
class FriendlyErrorWidget extends StatelessWidget {
  const FriendlyErrorWidget({super.key, required this.onGoHome});

  final VoidCallback onGoHome;

  /// Release only: debug and profile keep the framework's red screen.
  static void install({required VoidCallback onGoHome}) {
    if (!kReleaseMode) return;
    ErrorWidget.builder = (_) => FriendlyErrorWidget(onGoHome: onGoHome);
  }

  static String _t(String key, String fallback) {
    try {
      final v = key.tr();
      return v == key ? fallback : v;
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    // May be built above MaterialApp, so it brings its own direction and
    // material instead of assuming them.
    final direction = Directionality.maybeOf(context) ?? ui.TextDirection.ltr;
    return Directionality(
      textDirection: direction,
      child: Material(
        color: const Color(0xFF0E0E0E),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white54,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  _t('general.error', 'Something went wrong'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onGoHome,
                  child: Text(_t('general.go_home', 'Go home')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
