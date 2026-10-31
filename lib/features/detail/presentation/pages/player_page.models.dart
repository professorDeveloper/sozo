part of 'player_page.dart';

enum _PlayerFit { contain, cover, fill }

/// Resolves the persisted default fill mode. Matches on the enum's *name*, not
/// its index, so the stored value survives reordering; anything unrecognised
/// falls back to [_PlayerFit.contain], which is what the player used before
/// the setting existed.
_PlayerFit _playerFitFromId(String? id) {
  for (final f in _PlayerFit.values) {
    if (f.name == id) return f;
  }
  return _PlayerFit.contain;
}

enum _SidePanel { none, episodes, quality }

enum _LoadingStage { resolving, loading }

/// What the player is switching between, while it is switching.
///
/// The loading overlay used to say "Loading video" whether it was opening an
/// episode for the first time or moving from one mirror to another. Those are
/// different events: the second one follows a deliberate choice somebody just
/// made, and the useful thing to show is that the choice was heard — which
/// server, and that it is on its way — not a generic spinner that looks
/// identical to the failure they were trying to escape.
class ServerSwitch {
  const ServerSwitch({required this.from, required this.to});

  /// Null when nothing was playing yet, so the overlay shows a destination
  /// rather than a journey.
  final String? from;
  final String to;
}

/// `zoom` carries a scale factor (1.0-3.0), not a 0-1 level like the other
/// two, and is drawn as a centre pill rather than an edge bar.
enum _SwipeType { brightness, volume, zoom }

class _SwipeIndicator {
  final _SwipeType type;
  final double value;
  const _SwipeIndicator(this.type, this.value);
}

/// Pinch-zoom bounds. Top level rather than static on the State, because the
/// gesture code lives in an extension and Dart will not let an extension reach
/// a static member of the type it extends unqualified.
///
/// 3x is where a 1080p frame stops being watchable; below 1.0 there is nothing
/// to show but letterbox.
const double _kMinZoom = 1.0;
const double _kMaxZoom = 3.0;

const _kSubLang = 'sub';
const _kDubLang = 'dub';

const List<int> _subtitleColorPresets = <int>[
  0xFFFFFFFF,
  0xFFFFEB3B,
  0xFF00E5FF,
  0xFF76FF03,
  0xFFFF80AB,
  0xFFFF5252,
];

const MethodChannel _pipChannel = MethodChannel('soplay/pip');

/// iOS picture-in-picture, handed to a native player — see NativePip.swift.
const MethodChannel _iosPipChannel = MethodChannel('soplay/ios_pip');
const MethodChannel _systemControlsChannel = MethodChannel(
  'soplay/system_controls',
);

/// Seek-button icons for the step chosen in Settings → Player.
///
/// That screen offers only 5/10/30 precisely because those are the values
/// Material ships numbered icons for, so the button always shows the number it
/// actually jumps. Anything else falls back to the 10s icon rather than
/// silently lying about a number.
IconData _rewindIconFor(int seconds) => switch (seconds) {
  5 => Icons.replay_5_rounded,
  30 => Icons.replay_30_rounded,
  _ => Icons.replay_10_rounded,
};

IconData _forwardIconFor(int seconds) => switch (seconds) {
  5 => Icons.forward_5_rounded,
  30 => Icons.forward_30_rounded,
  _ => Icons.forward_10_rounded,
};

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

class _ScrubState {
  final Duration baseline;
  final Duration duration;
  final double deltaPx;

  /// The screen's long side, what a full swipe is measured against.
  final double widthPx;

  const _ScrubState({
    required this.baseline,
    required this.duration,
    required this.deltaPx,
    required this.widthPx,
  });

  _ScrubState copyWith({double? deltaPx}) => _ScrubState(
    baseline: baseline,
    duration: duration,
    deltaPx: deltaPx ?? this.deltaPx,
    widthPx: widthPx,
  );

  /// Where releasing now would land; see [ScrubCurve].
  Duration previewPosition() => Duration(
    milliseconds: ScrubCurve.targetMs(
      baselineMs: baseline.inMilliseconds,
      durationMs: duration.inMilliseconds,
      deltaPx: deltaPx,
      widthPx: widthPx,
    ),
  );

  /// Back where it started, or closer to it than the two seconds the label
  /// shows: releasing now changes nothing, as the card says.
  bool get cancels =>
      ScrubCurve.cancels(deltaPx) ||
      (previewPosition() - baseline).inSeconds.abs() < 2;
}

class _ProxiedTarget {
  const _ProxiedTarget({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
}
