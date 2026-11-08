import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:soplay/core/native/native_link.dart';

/// One thing said to a fake view.
typedef Said = ({String method, Object? arguments});

class FakeLink implements NativeLink {
  final List<Said> said = [];
  bool disposed = false;

  @override
  void say(String method, [Object? arguments]) {
    if (!disposed) said.add((method: method, arguments: arguments));
  }

  @override
  Future<T?> ask<T>(String method, [Object? arguments]) async {
    say(method, arguments);
    return null;
  }

  @override
  void dispose() => disposed = true;

  Iterable<Said> of(String method) => said.where((s) => s.method == method);
}

class FakeView {
  FakeView(this.type, this.params, this.onHeard);

  final String type;
  final Map<String, Object?> params;
  final NativeHeard onHeard;
  final FakeLink link = FakeLink();

  /// UIKit saying [method].
  void hear(String method, [Object? arguments]) => onHeard(method, arguments);
}

/// Draws a plain box that takes taps, and hands its control a [FakeLink] on
/// the frame after it is built, as a platform view's creation does.
class FakeNativeHost implements NativeHost {
  final List<FakeView> views = [];

  /// Taps that landed on a hosted view rather than falling through.
  int taps = 0;

  @override
  Widget view({
    required String type,
    required Map<String, Object?> params,
    required Set<Factory<OneSequenceGestureRecognizer>> gestures,
    required void Function(NativeLink) onLink,
    required NativeHeard onHeard,
  }) => _FakeBox(
    make: () {
      final v = FakeView(type, params, onHeard);
      views.add(v);
      return v;
    },
    onLink: onLink,
    onTap: () => taps++,
  );
}

class _FakeBox extends StatefulWidget {
  const _FakeBox({
    required this.make,
    required this.onLink,
    required this.onTap,
  });

  final FakeView Function() make;
  final void Function(NativeLink) onLink;
  final VoidCallback onTap;

  @override
  State<_FakeBox> createState() => _FakeBoxState();
}

class _FakeBoxState extends State<_FakeBox> {
  late final FakeView view = widget.make();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLink(view.link);
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    child: const SizedBox.expand(),
  );
}
