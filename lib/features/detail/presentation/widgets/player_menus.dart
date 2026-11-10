import 'package:flutter/foundation.dart';
import 'package:soplay/core/native/native_glass_bar.dart';

/// One choice of a player control's native menu: the row the menu draws and
/// what choosing it does.
@immutable
class PlayerMenuOption {
  const PlayerMenuOption({
    required this.key,
    required this.title,
    required this.onPick,
    this.subtitle,
    this.checked,
    this.symbol,
    this.destructive = false,
  });

  /// What the row stands for ([NativeMenuRow.key]).
  final Object key;
  final String title;
  final String? subtitle;
  final bool? checked;
  final String? symbol;
  final bool destructive;
  final VoidCallback onPick;
}

/// A native pull-down menu for a player control (iOS 26 path): runs of
/// options with a separator between runs, each choice's action beside its
/// row so the two never drift apart.
@immutable
class PlayerMenu {
  PlayerMenu(List<List<PlayerMenuOption>> sections)
    : options = [
        for (final run in sections.where((r) => r.isNotEmpty))
          for (final o in run) o,
      ],
      _breaks = _startsOf(sections);

  final List<PlayerMenuOption> options;
  final Set<int> _breaks;

  static Set<int> _startsOf(List<List<PlayerMenuOption>> sections) {
    final starts = <int>{};
    var at = 0;
    for (final run in sections.where((r) => r.isNotEmpty)) {
      if (at > 0) starts.add(at);
      at += run.length;
    }
    return starts;
  }

  List<NativeMenuRow> get rows => [
    for (var i = 0; i < options.length; i++)
      NativeMenuRow(
        title: options[i].title,
        subtitle: options[i].subtitle,
        symbol: options[i].symbol,
        checked: options[i].checked,
        destructive: options[i].destructive,
        breakBefore: _breaks.contains(i),
        key: options[i].key,
      ),
  ];

  /// Runs the choice at [index] of [rows]; an index out of range is a menu
  /// that changed under the finger, and does nothing.
  void pick(int index) {
    if (index < 0 || index >= options.length) return;
    options[index].onPick();
  }
}

/// One value out of [values], the [current] one checked: speed, fit,
/// server, audio language.
PlayerMenu choiceMenu<T extends Object>({
  required List<T> values,
  required bool Function(T value) isCurrent,
  required String Function(T value) label,
  required void Function(T value) onPick,
  String? Function(T value)? subtitle,
  String? Function(T value)? symbol,
}) => PlayerMenu([
  [
    for (final v in values)
      PlayerMenuOption(
        key: v,
        title: label(v),
        subtitle: subtitle?.call(v),
        symbol: symbol?.call(v),
        checked: isCurrent(v),
        onPick: () => onPick(v),
      ),
  ],
]);

/// A subtitle track as the subtitle menu lists it.
@immutable
class SubtitleMenuTrack {
  const SubtitleMenuTrack({
    required this.key,
    required this.label,
    required this.selected,
    required this.onPick,
    this.subtitle,
  });

  final Object key;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPick;
}

/// The subtitle button's menu: Off, the stream's own tracks, the loaded
/// ones, and last the full sheet for everything a menu cannot hold —
/// search, a file, AI translation, style, sync, a second track.
///
/// Null with no track to choose: the button opens the sheet directly, since
/// a menu of Off and "More" is one tap more for nothing.
PlayerMenu? subtitleMenu({
  required String offLabel,
  required bool offSelected,
  required VoidCallback onOff,
  required List<SubtitleMenuTrack> tracks,
  required String moreLabel,
  required VoidCallback onMore,
}) {
  if (tracks.isEmpty) return null;
  return PlayerMenu([
    [
      PlayerMenuOption(
        key: 'off',
        title: offLabel,
        checked: offSelected,
        onPick: onOff,
      ),
      for (final t in tracks)
        PlayerMenuOption(
          key: t.key,
          title: t.label,
          subtitle: t.subtitle,
          checked: t.selected,
          onPick: t.onPick,
        ),
    ],
    [
      PlayerMenuOption(
        key: 'more',
        title: moreLabel,
        symbol: 'ellipsis.circle',
        onPick: onMore,
      ),
    ],
  ]);
}

/// A rendition or a file as the quality menu lists it.
@immutable
class QualityMenuEntry {
  const QualityMenuEntry({
    required this.key,
    required this.label,
    required this.selected,
    required this.onPick,
    this.detail,
    this.blocking = false,
  });

  final Object key;
  final String label;

  /// The line under it: what Auto does, the bitrate, or the worst thing
  /// about the file.
  final String? detail;
  final bool selected;

  /// The file will not play here (Dolby Vision, unreachable): drawn red, as
  /// the sheet draws its warning.
  final bool blocking;
  final VoidCallback onPick;
}

/// The quality button's menu: the stream's renditions, then the server's
/// other files under a separator. Null when there is nothing to choose.
PlayerMenu? qualityMenu({
  required List<QualityMenuEntry> renditions,
  required List<QualityMenuEntry> files,
}) {
  if (renditions.length + files.length < 2) return null;
  PlayerMenuOption option(QualityMenuEntry e) => PlayerMenuOption(
    key: e.key,
    title: e.label,
    subtitle: e.detail,
    checked: e.selected,
    destructive: e.blocking,
    onPick: e.onPick,
  );
  return PlayerMenu([
    [for (final e in renditions) option(e)],
    [for (final e in files) option(e)],
  ]);
}
