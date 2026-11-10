import 'package:flutter/material.dart';
import 'package:soplay/core/player/player_dock.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/pages/player_page.dart';

/// Builds the player for a key and its arguments. Injectable so the hand-off
/// between the route and the corner can be tested without a real player.
typedef PlayerPageBuilder = Widget Function(GlobalKey key, PlayerArgs args);

Widget defaultPlayerPageBuilder(GlobalKey key, PlayerArgs args) =>
    PlayerPage(key: key, args: args);

/// What /player builds. It gives the page a [GlobalKey]: that key is how a
/// page can leave this route for the desktop corner player and come back
/// with all of its state, and how a route recognises a page being handed
/// back to it.
class PlayerRoute extends StatefulWidget {
  const PlayerRoute({
    super.key,
    required this.args,
    this.pageBuilder = defaultPlayerPageBuilder,
  });

  final PlayerArgs args;
  final PlayerPageBuilder pageBuilder;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  final PlayerDock _dock = PlayerDock.instance;
  late final GlobalKey _pageKey;
  bool _ready = true;

  /// Set once the page has gone to the corner. A docked page never comes back
  /// to the route it left (restoring pushes a new one), so from then on this
  /// route draws nothing, whatever the dock does during its exit transition:
  /// restored, replaced or closed meanwhile, building the page again here
  /// would put the key in two places or pull the page into a dying route.
  bool _gaveAway = false;

  @override
  void initState() {
    super.initState();
    final handed = _dock.takeHandBack();
    _pageKey = handed ?? GlobalKey(debugLabel: 'player');
    if (handed == null && _dock.isDocked) {
      // Another title is in the corner. It goes first: its dispose saves its
      // history and also clears page-wide singletons (PlayerLog, the frame
      // preview service, Discord, the PiP channel handler). Disposed after
      // this page's initState, it would tear down what this page had just
      // set up.
      _ready = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _dock.close();
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const ColoredBox(color: Colors.black);
    return ListenableBuilder(
      listenable: _dock,
      // While this route animates away after docking it draws nothing: the
      // page is in the corner now, under the same key, and building it here
      // as well would be the same GlobalKey in two places. Empty rather than
      // black, so the page underneath shows through the exit transition while
      // the picture shrinks into its corner.
      builder: (context, _) {
        if (_dock.dockedKey == _pageKey) _gaveAway = true;
        return _gaveAway
            ? const SizedBox.expand()
            : widget.pageBuilder(_pageKey, widget.args);
      },
    );
  }
}
