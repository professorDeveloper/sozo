import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../glass/glass_surface.dart' show PlatformViewMark;

/// What a hosted view says back: the method and its arguments.
typedef NativeHeard = void Function(String method, Object? arguments);

/// The way to one hosted view once it exists. The channel's in the app; a
/// test's fake records what is said and says things back.
abstract interface class NativeLink {
  /// Tells UIKit [method], not waited on. Nothing once [dispose]d.
  void say(String method, [Object? arguments]);

  /// Asks UIKit [method]; anything that goes wrong is null.
  Future<T?> ask<T>(String method, [Object? arguments]);

  void dispose();
}

/// A tap and a finger resting [hold]: a drag that starts on the view stays
/// the page's (swipe-seek), as it does over an `InkWell`.
Set<Factory<OneSequenceGestureRecognizer>> pressGestures({
  Duration hold = const Duration(milliseconds: 120),
}) => {
  Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
  Factory<LongPressGestureRecognizer>(
    () => LongPressGestureRecognizer(duration: hold),
  ),
};

/// Where hosted views come from: `UiKitView`s and their channels in the app
/// ([ChannelNativeHost]), a fake in a test.
abstract interface class NativeHost {
  Widget view({
    required String type,
    required Map<String, Object?> params,
    required Set<Factory<OneSequenceGestureRecognizer>> gestures,
    required void Function(NativeLink) onLink,
    required NativeHeard onHeard,
  });
}

/// Hosted views as the phone makes them: a `UiKitView` of the type and the
/// view's own channel, `<type>/<id>`.
final class ChannelNativeHost implements NativeHost {
  const ChannelNativeHost();

  @override
  Widget view({
    required String type,
    required Map<String, Object?> params,
    required Set<Factory<OneSequenceGestureRecognizer>> gestures,
    required void Function(NativeLink) onLink,
    required NativeHeard onHeard,
  }) => PlatformViewMark(
    child: UiKitView(
      viewType: type,
      creationParams: params,
      creationParamsCodec: const StandardMessageCodec(),
      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      gestureRecognizers: gestures,
      onPlatformViewCreated: (id) =>
          onLink(ChannelNativeLink(MethodChannel('$type/$id'), onHeard)),
    ),
  );
}

final class ChannelNativeLink implements NativeLink {
  ChannelNativeLink(this._channel, NativeHeard onHeard) {
    _channel.setMethodCallHandler((call) async {
      if (!_disposed) onHeard(call.method, call.arguments);
    });
  }

  final MethodChannel _channel;
  bool _disposed = false;

  @override
  void say(String method, [Object? arguments]) {
    if (_disposed) return;
    _channel.invokeMethod<void>(method, arguments).catchError((Object _) {});
  }

  @override
  Future<T?> ask<T>(String method, [Object? arguments]) async {
    if (_disposed) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}

/// Hands the hosted views under it a [NativeHost] in place of the channels:
/// a test's fake.
class NativeHostScope extends InheritedWidget {
  const NativeHostScope({super.key, required this.host, required super.child});

  final NativeHost host;

  static NativeHost of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NativeHostScope>()?.host ??
      const ChannelNativeHost();

  @override
  bool updateShouldNotify(NativeHostScope old) => old.host != host;
}

/// The state of a hosted control: the link to its view and what the view was
/// last told, so it is told only what changed.
///
/// A control writes [sync] — every [tell] of what it shows, run once the view
/// exists and on the frame after each new configuration — and [heard], what
/// UIKit says back. It builds its view with [hosted].
mixin NativeControlState<W extends StatefulWidget> on State<W> {
  NativeLink? _link;
  final Map<String, Object?> _told = {};
  Map<String, Object?> _made = const {};

  @protected
  void sync();

  @protected
  void heard(String method, Object? arguments);

  @protected
  bool get linked => _link != null;

  /// Tells the view [method] with [value] unless that is what [method] last
  /// told it, compared list by list and key by key.
  @protected
  void tell(String method, Object? value) {
    final link = _link;
    if (link == null) return;
    if (_told.containsKey(method) && nativeSame(_told[method], value)) return;
    _told[method] = value;
    link.say(method, value);
  }

  /// What [method] last told the view.
  @protected
  Object? toldOf(String method) => _told[method];

  /// Counts [value] as told by [method], for a control that said it its own
  /// way (a diff of it).
  @protected
  void remember(String method, Object? value) => _told[method] = value;

  /// Says [method] whatever was said before: a move, not a state.
  @protected
  void say(String method, [Object? arguments]) => _link?.say(method, arguments);

  /// The view. [made] is what it is created with, keyed by the method that
  /// tells each part later, and counts as told.
  @protected
  Widget hosted({
    required String type,
    required Map<String, Object?> params,
    required Set<Factory<OneSequenceGestureRecognizer>> gestures,
    Map<String, Object?> made = const {},
  }) {
    for (final MapEntry(:key, :value) in made.entries) {
      _told.putIfAbsent(key, () => value);
    }
    _made = made;
    return NativeHostScope.of(context).view(
      type: type,
      params: params,
      gestures: gestures,
      onLink: _linked,
      onHeard: _heard,
    );
  }

  void _linked(NativeLink link) {
    if (!mounted) {
      link.dispose();
      return;
    }
    final again = _link != null;
    _link?.dispose();
    _link = link;
    // A view made again was made with what the last build handed it.
    if (again) {
      _told
        ..clear()
        ..addAll(_made);
    }
    sync();
  }

  void _heard(String method, Object? arguments) {
    if (mounted) heard(method, arguments);
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && linked) sync();
    });
  }

  @override
  void dispose() {
    _link?.dispose();
    _link = null;
    super.dispose();
  }
}

/// Two things told alike: lists item by item, maps key by key.
bool nativeSame(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!nativeSame(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !nativeSame(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}
