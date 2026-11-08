import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/presentation/widgets/player_menus.dart';

void main() {
  group('a player menu', () {
    PlayerMenuOption option(String key, List<String> picked) =>
        PlayerMenuOption(key: key, title: key, onPick: () => picked.add(key));

    test('puts a separator before every run but the first', () {
      final menu = PlayerMenu([
        [option('a', []), option('b', [])],
        const [],
        [option('c', [])],
      ]);
      expect(menu.rows.map((r) => r.title), ['a', 'b', 'c']);
      expect(menu.rows.map((r) => r.breakBefore), [false, false, true]);
    });

    test('runs the choice at the index, and ignores one out of range', () {
      final picked = <String>[];
      final menu = PlayerMenu([
        [option('a', picked), option('b', picked)],
      ]);
      menu
        ..pick(1)
        ..pick(2)
        ..pick(-1);
      expect(picked, ['b']);
    });
  });

  test('a choice menu checks the current value and keys rows by it', () {
    double? chose;
    final menu = choiceMenu<double>(
      values: const [0.5, 1, 2],
      isCurrent: (s) => s == 1,
      label: (s) => '${s}x',
      onPick: (s) => chose = s,
    );
    expect(menu.rows.map((r) => r.checked), [false, true, false]);
    expect(menu.rows.map((r) => r.key), [0.5, 1, 2]);
    menu.pick(2);
    expect(chose, 2);
  });

  group('the subtitle menu', () {
    PlayerMenu? build({
      List<SubtitleMenuTrack> tracks = const [],
      bool offSelected = false,
      void Function()? onMore,
    }) => subtitleMenu(
      offLabel: 'Off',
      offSelected: offSelected,
      onOff: () {},
      tracks: tracks,
      moreLabel: 'More options',
      onMore: onMore ?? () {},
    );

    SubtitleMenuTrack track(String label, {bool selected = false}) =>
        SubtitleMenuTrack(
          key: label,
          label: label,
          selected: selected,
          subtitle: 'In the video',
          onPick: () {},
        );

    test('is none without a track: the sheet opens straight away', () {
      expect(build(), isNull);
    });

    test('opens on Off, lists the tracks, and ends on the full sheet', () {
      final menu = build(tracks: [track('English', selected: true)])!;
      final rows = menu.rows;
      expect(rows.map((r) => r.title), ['Off', 'English', 'More options']);
      expect(rows.map((r) => r.checked), [false, true, null]);
      expect(rows[1].subtitle, 'In the video');
      expect(rows.last.breakBefore, isTrue);
      expect(rows.last.symbol, 'ellipsis.circle');
    });

    test('checks Off when nothing is shown', () {
      final menu = build(tracks: [track('English')], offSelected: true)!;
      expect(menu.rows.first.checked, isTrue);
    });

    test('its last row opens the sheet', () {
      var opened = false;
      final menu = build(
        tracks: [track('English')],
        onMore: () => opened = true,
      )!;
      menu.pick(menu.rows.length - 1);
      expect(opened, isTrue);
    });
  });

  group('the quality menu', () {
    QualityMenuEntry entry(
      String label, {
      bool selected = false,
      bool blocking = false,
      String? detail,
    }) => QualityMenuEntry(
      key: label,
      label: label,
      selected: selected,
      blocking: blocking,
      detail: detail,
      onPick: () {},
    );

    test('is none with nothing to choose between', () {
      expect(qualityMenu(renditions: [entry('Auto')], files: const []), isNull);
    });

    test('lists the renditions, then the other files apart', () {
      final menu = qualityMenu(
        renditions: [entry('Auto', selected: true), entry('1080p')],
        files: [entry('720p', detail: 'Dolby Vision', blocking: true)],
      )!;
      final rows = menu.rows;
      expect(rows.map((r) => r.title), ['Auto', '1080p', '720p']);
      expect(rows.map((r) => r.checked), [true, false, false]);
      expect(rows.map((r) => r.breakBefore), [false, false, true]);
      // A file that will not play here reads red, as its warning did.
      expect(rows.last.destructive, isTrue);
      expect(rows.last.subtitle, 'Dolby Vision');
    });
  });
}
