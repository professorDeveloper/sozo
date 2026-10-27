import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether the phone asks for glass that cannot be seen through — iOS's
/// Reduce Transparency — handed to every glass under it.
///
/// Flutter carries Reduce Motion and Increase Contrast to the app
/// (`AccessibilityFeatures`, `MediaQuery.highContrast`) but not this one,
/// so the iPhone is asked itself, over `soplay/glass`
/// (ios/Runner/GlassSense.swift): once when the app starts, again whenever
/// it comes back to the front — the switch lives in Settings, so a change
/// is made with the app behind — and the phone also says it unasked when
/// the switch is thrown from the accessibility shortcut while the app is
/// in front. Anywhere else, and on an Android phone, the answer is no.
///
/// Wrapped round the whole app once; a test puts a [GlassSenseScope] round
/// what it pumps instead.
class GlassSense extends StatefulWidget {
  const GlassSense({super.key, required this.child});

  /// The channel the iPhone answers on.
  static const MethodChannel channel = MethodChannel('soplay/glass');

  final Widget child;

  /// Whether the glass under [context] should be drawn opaque.
  static bool reduceTransparencyOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassSenseScope>()
          ?.reduceTransparency ??
      false;

  @override
  State<GlassSense> createState() => _GlassSenseState();
}

class _GlassSenseState extends State<GlassSense> with WidgetsBindingObserver {
  bool _reduce = false;

  /// Only an iPhone has the switch, and only an iPhone answers: asking
  /// anything else would be an error logged on every launch.
  bool get _asks => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_asks) return;
    WidgetsBinding.instance.addObserver(this);
    GlassSense.channel.setMethodCallHandler(_told);
    unawaited(_ask());
  }

  @override
  void dispose() {
    if (_asks) {
      WidgetsBinding.instance.removeObserver(this);
      GlassSense.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_ask());
  }

  Future<void> _told(MethodCall call) async {
    if (call.method == 'reduceTransparency' && call.arguments is bool) {
      _set(call.arguments as bool);
    }
  }

  Future<void> _ask() async {
    try {
      final reduce = await GlassSense.channel.invokeMethod<bool>(
        'reduceTransparency',
      );
      _set(reduce ?? false);
    } on MissingPluginException {
      // A runner without the bridge — a test, an old build: glass it is.
    } on PlatformException {
      // Nothing to read: glass it is.
    }
  }

  void _set(bool reduce) {
    if (!mounted || reduce == _reduce) return;
    setState(() => _reduce = reduce);
  }

  @override
  Widget build(BuildContext context) =>
      GlassSenseScope(reduceTransparency: _reduce, child: widget.child);
}

/// The answer [GlassSense] reads, for the glass under it.
class GlassSenseScope extends InheritedWidget {
  const GlassSenseScope({
    super.key,
    required this.reduceTransparency,
    required super.child,
  });

  final bool reduceTransparency;

  @override
  bool updateShouldNotify(GlassSenseScope old) =>
      old.reduceTransparency != reduceTransparency;
}
