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
const MethodChannel _systemControlsChannel = MethodChannel(
  'soplay/system_controls',
);
const double _scrubSecondsPerFullSwipe = 90;

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
  final double span;

  const _ScrubState({
    required this.baseline,
    required this.duration,
    required this.deltaPx,
    required this.span,
  });

  _ScrubState copyWith({double? deltaPx, double? span}) => _ScrubState(
    baseline: baseline,
    duration: duration,
    deltaPx: deltaPx ?? this.deltaPx,
    span: span ?? this.span,
  );

  Duration previewPosition(double secondsPerFullSwipe) {
    if (span <= 0 || duration.inMilliseconds <= 0) return baseline;
    final fraction = (deltaPx / span).clamp(-1.0, 1.0);
    final deltaMs = (fraction * secondsPerFullSwipe * 1000).round();
    final target = baseline.inMilliseconds + deltaMs;
    final clamped = target.clamp(0, duration.inMilliseconds);
    return Duration(milliseconds: clamped);
  }
}

class _VttThumbnail {
  final Duration start;
  final Duration end;
  final String imageUrl;
  final int x;
  final int y;
  final int w;
  final int h;

  const _VttThumbnail({
    required this.start,
    required this.end,
    required this.imageUrl,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
  });

  bool get hasSprite => w > 0 && h > 0;

  bool contains(Duration position) =>
      position >= start && position < end;

  static List<_VttThumbnail> parse(String vttBody, String baseUrl) {
    final lines = vttBody.split('\n').map((l) => l.trim()).toList();
    final results = <_VttThumbnail>[];
    final timePattern = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})',
    );

    for (var i = 0; i < lines.length; i++) {
      final match = timePattern.firstMatch(lines[i]);
      if (match == null) continue;

      final start = Duration(
        hours: int.parse(match.group(1)!),
        minutes: int.parse(match.group(2)!),
        seconds: int.parse(match.group(3)!),
        milliseconds: int.parse(match.group(4)!),
      );
      final end = Duration(
        hours: int.parse(match.group(5)!),
        minutes: int.parse(match.group(6)!),
        seconds: int.parse(match.group(7)!),
        milliseconds: int.parse(match.group(8)!),
      );

      String? imageRef;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].isNotEmpty) {
          imageRef = lines[j];
          break;
        }
      }
      if (imageRef == null) continue;

      var url = imageRef;
      var x = 0, y = 0, w = 0, h = 0;
      final hashIdx = imageRef.indexOf('#xywh=');
      if (hashIdx >= 0) {
        url = imageRef.substring(0, hashIdx);
        final coords = imageRef.substring(hashIdx + 6).split(',');
        if (coords.length == 4) {
          x = int.tryParse(coords[0]) ?? 0;
          y = int.tryParse(coords[1]) ?? 0;
          w = int.tryParse(coords[2]) ?? 0;
          h = int.tryParse(coords[3]) ?? 0;
        }
      }

      if (!url.startsWith('http')) {
        final baseUri = Uri.parse(baseUrl);
        url = baseUri.resolve(url).toString();
      }

      results.add(_VttThumbnail(
        start: start,
        end: end,
        imageUrl: url,
        x: x,
        y: y,
        w: w,
        h: h,
      ));
    }
    return results;
  }
}

class _ProxiedTarget {
  const _ProxiedTarget({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
}
