import 'package:flutter/material.dart';

/// The detail page's tab contents, switched by [controller].
///
/// A pane is built the first time its tab opens and then kept: switching
/// away puts it offstage instead of disposing it, so Relations and Comments
/// do not refetch, and Similar does not decode thirty posters again, on every
/// swipe. Only this widget rebuilds on a tab change, not the page around it.
class DetailTabPanes extends StatefulWidget {
  const DetailTabPanes({
    super.key,
    required this.controller,
    required this.tabs,
    required this.paneBuilder,
  });

  final TabController controller;
  final List<String> tabs;
  final Widget Function(BuildContext context, String tab) paneBuilder;

  static const Duration fade = Duration(milliseconds: 160);

  @override
  State<DetailTabPanes> createState() => _DetailTabPanesState();
}

class _DetailTabPanesState extends State<DetailTabPanes>
    with SingleTickerProviderStateMixin {
  late int _current = widget.controller.index;
  int? _previous;

  /// Each pane's widget, kept between tab switches so a switch does not
  /// rebuild the panes it does not touch. Dropped when the page rebuilds.
  /// Its keys are the panes built so far, a null value one to build afresh.
  late final Map<int, Widget?> _panes = {_current: null};

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: DetailTabPanes.fade,
    value: 1,
  )..addStatusListener(_onFadeStatus);
  late final Animation<double> _in = _fade.drive(
    CurveTween(curve: Curves.easeOut),
  );
  late final Animation<double> _out = ReverseAnimation(
    _fade,
  ).drive(CurveTween(curve: Curves.easeIn));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTab);
  }

  @override
  void didUpdateWidget(DetailTabPanes old) {
    super.didUpdateWidget(old);
    _panes.updateAll((_, _) => null);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onTab);
      widget.controller.addListener(_onTab);
      _onTab();
    }
  }

  void _onTab() {
    final index = widget.controller.index;
    if (index == _current) return;
    setState(() {
      _previous = _current;
      _current = index;
      _panes.putIfAbsent(index, () => null);
    });
    _fade.forward(from: 0);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _previous != null && mounted) {
      setState(() => _previous = null);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTab);
    _fade.dispose();
    super.dispose();
  }

  Widget _pane(int index) {
    final tab = widget.tabs[index];
    final current = index == _current;
    final live = current || index == _previous;
    return KeyedSubtree(
      key: ValueKey('detail-tab-$tab'),
      child: Offstage(
        offstage: !live,
        child: TickerMode(
          enabled: live,
          child: IgnorePointer(
            ignoring: !current,
            child: FadeTransition(
              opacity: current
                  ? _in
                  : live
                  ? _out
                  : kAlwaysCompleteAnimation,
              child: _panes[index] ??= widget.paneBuilder(context, tab),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Offstage panes report no size, so the stack is as tall as the panes on
    // screen, outgoing below incoming while they cross-fade.
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        for (final i in _panes.keys.toList())
          if (i != _current && i != _previous) _pane(i),
        if (_previous != null) _pane(_previous!),
        _pane(_current),
      ],
    );
  }
}
