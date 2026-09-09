import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/player_controls_layout.dart';

/// The icon each control wears, on the bar and in this list.
///
/// Here rather than in [PlayerControlCatalogue] because the catalogue is domain
/// code and an `IconData` is Flutter — there is a test that keeps that layer
/// clean. The pairing still has to be exhaustive, which is what [_iconFor]'s
/// fallback makes visible rather than silently blank.
const Map<String, IconData> _kControlIcons = <String, IconData>{
  'previous': Icons.skip_previous_rounded,
  'next': Icons.skip_next_rounded,
  'speed': Icons.speed_rounded,
  'server': Icons.dns_outlined,
  'quality': Icons.high_quality_rounded,
  'episodes': Icons.list_rounded,
  'shader': Icons.auto_awesome_rounded,
  'fit': Icons.aspect_ratio_rounded,
  'sleep': Icons.bedtime_outlined,
  'cast': Icons.cast_rounded,
  'party': Icons.groups_2_outlined,
  'pip': Icons.picture_in_picture_alt_rounded,
  'download': Icons.download_rounded,
  'language': Icons.translate_rounded,
  'subtitles': Icons.subtitles_outlined,
  'orientation': Icons.screen_rotation_rounded,
  'lock': Icons.lock_outline_rounded,
  'settings': Icons.settings_outlined,
  'stats': Icons.info_outline_rounded,
};

IconData iconForControl(String id) =>
    _kControlIcons[id] ?? Icons.radio_button_unchecked_rounded;

/// Lets the viewer arrange the player's bars.
///
/// The bars were a hard-coded widget tree, and every complaint about them was a
/// complaint about that tree: six controls went behind a `⋯` sheet to buy room
/// and had to come back out; quality and episodes shared a slot, so a serial
/// could not reach the quality panel; the bottom row pinned everything to the
/// right edge on a film. Each of those was a real report, and each fix moved one
/// button and risked the next report. Where a control goes is a preference, and
/// preferences belong to the person watching.
///
/// Everything that can be refused is refused by [PlayerControlsLayout], which
/// has the tests. This screen only draws it and says why when it says no.
class PlayerControlsPage extends StatefulWidget {
  const PlayerControlsPage({super.key});

  @override
  State<PlayerControlsPage> createState() => _PlayerControlsPageState();
}

class _PlayerControlsPageState extends State<PlayerControlsPage> {
  final HiveService _hive = getIt<HiveService>();
  late PlayerControlsLayout _layout =
      PlayerControlsLayout.fromStored(_hive.getPlayerControlsLayout());

  /// Saved on every edit, not on leave. There is no Save button and no
  /// confirmation, so a back-swipe must not be able to lose the arrangement.
  void _apply(PlayerControlsLayout next) {
    setState(() => _layout = next);
    _hive.setPlayerControlsLayout(next.toStored());
  }

  void _reset() {
    setState(() => _layout = PlayerControlsLayout.defaults());
    _hive.clearPlayerControlsLayout();
  }

  void _move(String id, PlayerControlSlot to) {
    final refusal = _layout.moveRefusal(id, to);
    if (refusal != null) {
      // Said out loud. A drag that springs back with no explanation is the
      // version of this screen people file a bug about.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(refusal.tr()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }
    _apply(_layout.move(id, to));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        title: Text('player.layout_title'.tr()),
        actions: [
          // Only when it would do something. A Reset that is always there but
          // usually inert is a control people stop reading.
          if (!_layout.isDefault)
            TextButton(
              onPressed: _reset,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryLight,
              ),
              child: Text(
                'general.reset'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        children: [
          _LayoutPreview(layout: _layout),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
            child: Text(
              'player.layout_desc'.tr(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          for (final slot in PlayerControlSlot.values) _section(slot),
        ],
      ),
    );
  }

  Widget _section(PlayerControlSlot slot) {
    final ids = _layout.of(slot);
    final isTop = slot == PlayerControlSlot.topBar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Row(
            children: [
              Text(
                _slotLabel(slot).toUpperCase(),
                style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
              // The capacity is shown where it applies rather than only when it
              // is hit, so a refusal later is never a surprise.
              if (isTop)
                Text(
                  ' · ${ids.length}/${PlayerControlsLayout.topBarCapacity}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        if (slot == PlayerControlSlot.hidden)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'player.layout_hidden_desc'.tr(),
              style: const TextStyle(color: Colors.white38, fontSize: 11.5),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ids.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  child: Text(
                    'player.layout_empty'.tr(),
                    style:
                        const TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  buildDefaultDragHandles: false,
                  itemCount: ids.length,
                  // onReorderItem, not the deprecated onReorder: the old one
                  // reports the target as an index in the list BEFORE the item
                  // is removed, so every downward drag lands one place too far
                  // unless the caller subtracts one. This one has already done
                  // it, which is the whole reason it replaced the other.
                  onReorderItem: (from, to) =>
                      _apply(_layout.reorder(slot, from, to)),
                  itemBuilder: (_, i) => _row(slot, ids[i], i),
                ),
        ),
      ],
    );
  }

  Widget _row(PlayerControlSlot slot, String id, int index) {
    final spec = PlayerControlCatalogue.byId(id);
    final pinned = spec?.pinned ?? false;
    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        children: [
          // A pinned control gets no handle at all rather than a handle that
          // refuses — the affordance and the answer agree.
          if (pinned)
            const SizedBox(width: 40, height: 44)
          else
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 40,
                height: 44,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: Colors.white30,
                  size: 20,
                ),
              ),
            ),
          Icon(iconForControl(id), color: Colors.white70, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              (spec?.labelKey ?? id).tr(),
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
            ),
          ),
          if (pinned)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'player.layout_pinned_badge'.tr(),
                style: const TextStyle(color: Colors.white30, fontSize: 11.5),
              ),
            )
          else
            PopupMenuButton<PlayerControlSlot>(
              color: const Color(0xFF1C1C1C),
              tooltip: 'player.layout_move_to'.tr(),
              onSelected: (to) => _move(id, to),
              itemBuilder: (_) => [
                for (final target in PlayerControlSlot.values)
                  if (target != slot)
                    PopupMenuItem(
                      value: target,
                      // Disabled rather than absent when the target is full:
                      // an option that disappears reads as a missing feature,
                      // one that is dimmed reads as a full bar.
                      enabled: _layout.canMove(id, target),
                      child: Text(
                        _slotLabel(target),
                        style: TextStyle(
                          color: _layout.canMove(id, target)
                              ? Colors.white
                              : Colors.white30,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'player.layout_move_to'.tr(),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                    const Icon(
                      Icons.expand_more_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _slotLabel(PlayerControlSlot slot) => switch (slot) {
        PlayerControlSlot.topBar => 'player.layout_top_bar'.tr(),
        PlayerControlSlot.bottomLeft => 'player.layout_bottom_left'.tr(),
        PlayerControlSlot.bottomRight => 'player.layout_bottom_right'.tr(),
        PlayerControlSlot.hidden => 'player.layout_hidden'.tr(),
      };
}

/// A miniature of the real player, drawn from the same layout the player reads.
///
/// It is the only part of this screen that answers the question people actually
/// have — "where will that end up?" — without making them leave, start an
/// episode and look.
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({required this.layout});

  final PlayerControlsLayout layout;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 8.2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2340), Color(0xFF3A2A3E), Color(0xFF23303F)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Show title · E2',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  for (final id in layout.of(PlayerControlSlot.topBar))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        iconForControl(id),
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.38,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                // The same split the real bar uses: transport on the left,
                // everything else on the right — and `start` when the left
                // group is empty, because `spaceBetween` with nothing on one
                // side is what pinned every control to the right edge on a
                // film.
                mainAxisAlignment:
                    layout.of(PlayerControlSlot.bottomLeft).isEmpty
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.spaceBetween,
                children: [
                  _group(layout.of(PlayerControlSlot.bottomLeft)),
                  _group(layout.of(PlayerControlSlot.bottomRight)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(List<String> ids) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(right: 9),
              child: Icon(iconForControl(id), color: Colors.white, size: 14),
            ),
        ],
      );
}
