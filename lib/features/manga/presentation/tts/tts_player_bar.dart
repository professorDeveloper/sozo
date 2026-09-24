import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/extensions/source_language.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/manga/presentation/tts/novel_tts_controller.dart';

/// `1×`, `1.25×` — trailing zeros dropped.
String formatTtsSpeed(double v) {
  final s = v.toStringAsFixed(2);
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return '$trimmed×';
}

/// The floating read-aloud controls over a novel chapter.
class TtsPlayerBar extends StatefulWidget {
  const TtsPlayerBar({
    super.key,
    required this.controller,
    required this.accent,
  });

  final NovelTtsController controller;
  final Color accent;

  @override
  State<TtsPlayerBar> createState() => _TtsPlayerBarState();
}

class _TtsPlayerBarState extends State<TtsPlayerBar> {
  /// Keeps the sleep countdown moving between sentences.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && widget.controller.sleepEndsAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    final c = widget.controller;
    final loading = c.status == TtsStatus.loading;
    return Material(
      color: const Color(0xF2181A1F),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 2,
            child: loading
                ? LinearProgressIndicator(
                    color: widget.accent,
                    backgroundColor: Colors.white10,
                  )
                : LinearProgressIndicator(
                    value: c.spokenPermille / 1000,
                    color: widget.accent,
                    backgroundColor: Colors.white10,
                  ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'manga.tts_loading_next'.tr(),
                style: const TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
            child: Row(
              children: [
                _icon(
                  icon: Icons.close_rounded,
                  tooltip: 'manga.tts_stop'.tr(),
                  color: Colors.white54,
                  onPressed: c.stop,
                ),
                const Spacer(),
                _icon(
                  icon: Icons.fast_rewind_rounded,
                  tooltip: 'manga.tts_prev_sentence'.tr(),
                  onPressed: loading ? null : c.previous,
                ),
                const SizedBox(width: 4),
                _playButton(c, loading),
                const SizedBox(width: 4),
                _icon(
                  icon: Icons.fast_forward_rounded,
                  tooltip: 'manga.tts_next_sentence'.tr(),
                  onPressed: loading ? null : c.next,
                ),
                const Spacer(),
                _speedChip(c),
                _icon(
                  icon: Icons.record_voice_over_rounded,
                  tooltip: 'manga.tts_voice'.tr(),
                  onPressed: () => showTtsVoicePicker(
                    context,
                    controller: c,
                    accent: widget.accent,
                  ),
                ),
                _sleepButton(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _icon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color color = Colors.white,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: 22,
        color: onPressed == null ? Colors.white24 : color,
      ),
      onPressed: onPressed,
    );
  }

  Widget _playButton(NovelTtsController c, bool loading) {
    final playing = c.status == TtsStatus.playing;
    return Tooltip(
      message: playing ? 'manga.tts_pause'.tr() : 'manga.tts_play'.tr(),
      child: Material(
        color: widget.accent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : c.toggle,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _speedChip(NovelTtsController c) {
    return PopupMenuButton<double>(
      tooltip: 'manga.tts_speed'.tr(),
      color: const Color(0xFF1E2026),
      initialValue: c.rate,
      onSelected: c.setRate,
      position: PopupMenuPosition.over,
      itemBuilder: (_) => [
        for (final s in NovelTtsController.speeds)
          PopupMenuItem<double>(
            value: s,
            height: 40,
            child: Text(
              formatTtsSpeed(s),
              style: TextStyle(
                color: (s - c.rate).abs() < 0.01 ? widget.accent : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          formatTtsSpeed(c.rate),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _sleepButton(NovelTtsController c) {
    final on = c.sleepMinutes != 0;
    Widget? badge;
    final ends = c.sleepEndsAt;
    if (c.sleepMinutes == NovelTtsController.sleepEndOfChapter) {
      badge = const Icon(Icons.flag_rounded, size: 9, color: Colors.white);
    } else if (ends != null) {
      final left = ends.difference(DateTime.now()).inMinutes + 1;
      badge = Text(
        '${left.clamp(1, 999)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return PopupMenuButton<int>(
      tooltip: 'manga.tts_sleep_timer'.tr(),
      color: const Color(0xFF1E2026),
      position: PopupMenuPosition.over,
      onSelected: c.setSleep,
      itemBuilder: (_) => [
        _sleepItem(0, 'manga.tts_sleep_off'.tr(), c.sleepMinutes == 0),
        for (final m in NovelTtsController.sleepChoices)
          _sleepItem(
            m,
            'manga.tts_sleep_minutes'.tr(args: ['$m']),
            c.sleepMinutes == m,
          ),
        _sleepItem(
          NovelTtsController.sleepEndOfChapter,
          'manga.tts_sleep_end_of_chapter'.tr(),
          c.sleepMinutes == NovelTtsController.sleepEndOfChapter,
        ),
      ],
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              on ? Icons.bedtime_rounded : Icons.bedtime_outlined,
              size: 21,
              color: on ? widget.accent : Colors.white,
            ),
            if (badge != null)
              Positioned(
                right: 2,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: badge,
                ),
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _sleepItem(int value, String label, bool selected) {
    return PopupMenuItem<int>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? widget.accent : Colors.white,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 18, color: widget.accent),
        ],
      ),
    );
  }
}

/// Read-aloud settings, for the reader's settings sheet.
class TtsSettingsSection extends StatefulWidget {
  const TtsSettingsSection({
    super.key,
    required this.controller,
    required this.accent,
  });

  final NovelTtsController controller;
  final Color accent;

  @override
  State<TtsSettingsSection> createState() => _TtsSettingsSectionState();
}

class _TtsSettingsSectionState extends State<TtsSettingsSection> {
  // Held while a slider is dragged: applying each step would restart the
  // sentence being spoken dozens of times.
  double? _rate;
  double? _pitch;

  static const _label = TextStyle(color: Colors.white70, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final voice = c.voice;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.headphones_rounded, color: widget.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'manga.tts_read_aloud'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('manga.tts_speed'.tr(), style: _label),
            _slider(
              value: _rate ?? c.rate,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: formatTtsSpeed(_rate ?? c.rate),
              onChanged: (v) => setState(() => _rate = v),
              onChangeEnd: (v) {
                setState(() => _rate = null);
                c.setRate(v);
              },
            ),
            Text('manga.tts_pitch'.tr(), style: _label),
            _slider(
              value: _pitch ?? c.pitch,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: (_pitch ?? c.pitch).toStringAsFixed(2),
              onChanged: (v) => setState(() => _pitch = v),
              onChangeEnd: (v) {
                setState(() => _pitch = null);
                c.setPitch(v);
              },
            ),
            const SizedBox(height: 4),
            HoverTap(
              onTap: () => showTtsVoicePicker(
                context,
                controller: c,
                accent: widget.accent,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.record_voice_over_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('manga.tts_voice'.tr(), style: _label),
                          const SizedBox(height: 2),
                          Text(
                            voice?.name ?? 'manga.tts_voice_default'.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.language.isNotEmpty)
                      Text(
                        labelFor(c.language),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11.5,
                        ),
                      ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'manga.tts_auto_next'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'manga.tts_auto_next_desc'.tr(),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: c.autoNext,
                  onChanged: c.setAutoNext,
                  activeThumbColor: Colors.white,
                  activeTrackColor: widget.accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            activeColor: widget.accent,
            inactiveColor: Colors.white24,
            min: min,
            max: max,
            divisions: divisions,
            value: value.clamp(min, max),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// The voices this device has for the chapter's language.
Future<void> showTtsVoicePicker(
  BuildContext context, {
  required NovelTtsController controller,
  required Color accent,
}) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: const Color(0xFF161616),
    showDragHandle: !isDesktopPlatform,
    isScrollControlled: true,
    builder: (ctx) => _VoicePicker(controller: controller, accent: accent),
  );
}

class _VoicePicker extends StatelessWidget {
  const _VoicePicker({required this.controller, required this.accent});

  final NovelTtsController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final voices = controller.voices;
    final selected = controller.voice;
    final lang = controller.language;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'manga.tts_voice'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                labelFor(lang),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                _tile(
                  context,
                  title: 'manga.tts_voice_default'.tr(),
                  subtitle: null,
                  network: false,
                  selected: selected == null,
                  onTap: () => controller.setVoice(null),
                ),
                if (voices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'manga.tts_no_voices'.tr(),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final v in voices)
                  _tile(
                    context,
                    title: v.name,
                    subtitle: v.locale,
                    network: v.isNetwork,
                    selected: selected == v,
                    onTap: () => controller.setVoice(v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required String? subtitle,
    required bool network,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: accent.withValues(alpha: 0.12),
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.graphic_eq_rounded,
        color: selected ? accent : Colors.white38,
        size: 20,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? accent : Colors.white,
          fontSize: 13.5,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11.5),
            ),
      trailing: network
          ? Tooltip(
              message: 'manga.tts_voice_network'.tr(),
              child: const Icon(
                Icons.cloud_outlined,
                color: Colors.white38,
                size: 18,
              ),
            )
          : null,
      onTap: () {
        onTap();
        Navigator.of(context).pop();
      },
    );
  }
}
