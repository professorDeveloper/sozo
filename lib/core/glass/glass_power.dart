import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What an Android phone says it can spend on the glass: whether it calls
/// itself a low-memory phone.
///
/// The refraction reads the screen under every glass on every frame and
/// bends it in a shader. Every phone draws it — a 4 GB one and one on
/// Battery Saver too — but an Android Go phone, whose maker says it
/// is too small for much at all, draws the glass as the blur instead
/// ([affordsRefraction] false): the recipe's frost under its thicker tint,
/// one shared read of the screen per layer ([BackdropGroup]) — the same
/// glass, still, without the bend.
@immutable
final class GlassPowerReading {
  const GlassPowerReading({this.lowRam = false});

  /// What a phone that has not answered — an iPhone, a test, a build
  /// without the bridge — is taken to have: enough.
  static const GlassPowerReading ample = GlassPowerReading();

  /// Read off the channel's map; anything missing or of the wrong kind is
  /// the generous answer, so a half answer never takes the glass away.
  factory GlassPowerReading.fromChannel(Object? answer) {
    if (answer is! Map) return ample;
    return GlassPowerReading(lowRam: answer['lowRam'] == true);
  }

  /// `ActivityManager.isLowRamDevice`: the phone's maker says it is one of
  /// the phones Android Go is for.
  final bool lowRam;

  /// Whether the phone may draw the refraction's shader at all.
  bool get affordsRefraction => !lowRam;

  @override
  bool operator ==(Object other) =>
      other is GlassPowerReading && other.lowRam == lowRam;

  @override
  int get hashCode => lowRam.hashCode;

  @override
  String toString() => 'GlassPowerReading(lowRam: $lowRam)';
}

/// Asks an Android phone what it can spend on the glass
/// ([GlassPowerReading]) and hands the answer to every glass under it, as
/// [GlassSense] hands down the iPhone's Reduce Transparency.
///
/// Asked over `soplay/glass_power`
/// (android/app/src/main/kotlin/com/soplay/sozo/GlassPower.kt) once, when the app
/// starts: what it asks is the phone's make, which does not change while
/// the app runs. An iPhone is not asked: every iPhone's GPU draws it.
///
/// Wrapped round the whole app once; a test puts one round what it pumps,
/// and speaks for the phone on [channel].
class GlassPower extends StatefulWidget {
  const GlassPower({super.key, required this.child});

  /// The channel the Android phone answers on.
  static const MethodChannel channel = MethodChannel('soplay/glass_power');

  final Widget child;

  /// What the phone over [context] said; [GlassPowerReading.ample] with no
  /// [GlassPower] above it, or before the phone has answered. [context]
  /// is told again only when [GlassPowerReading.affordsRefraction] turns.
  static GlassPowerReading readingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassPowerScope>()?.reading ??
      GlassPowerReading.ample;

  /// Whether glass at [context] may draw the refraction, as far as the
  /// phone's power goes (`GlassPickScope.liquidAt` asks the renderer).
  static bool affordsAt(BuildContext context) =>
      readingOf(context).affordsRefraction;

  @override
  State<GlassPower> createState() => _GlassPowerState();
}

class _GlassPowerState extends State<GlassPower> {
  GlassPowerReading _reading = GlassPowerReading.ample;

  @override
  void initState() {
    super.initState();
    // Only an Android phone has the bridge: asking anything else would be
    // an error on every launch.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_ask());
    }
  }

  Future<void> _ask() async {
    try {
      final reading = GlassPowerReading.fromChannel(
        await GlassPower.channel.invokeMethod<Object?>('read'),
      );
      if (mounted && reading != _reading) {
        setState(() => _reading = reading);
      }
    } on MissingPluginException {
      // A runner without the bridge: the glass as the renderer allows.
    } on PlatformException {
      // Nothing to read: as above.
    }
  }

  @override
  Widget build(BuildContext context) =>
      _GlassPowerScope(reading: _reading, child: widget.child);
}

class _GlassPowerScope extends InheritedWidget {
  const _GlassPowerScope({required this.reading, required super.child});

  final GlassPowerReading reading;

  /// Only a change of the answer that matters wakes the glass.
  @override
  bool updateShouldNotify(_GlassPowerScope old) =>
      old.reading.affordsRefraction != reading.affordsRefraction;
}
