import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/mal/presentation/controllers/mal_library_controller.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';

/// Edit one MyAnimeList entry: status, progress, score, or remove it.
///
/// Reads its row from the controller by id on every build rather than holding a
/// copy. An edit made here changes the list the library is showing underneath,
/// and a captured entry would keep rendering the values from before the write.
class MalEntrySheet extends StatefulWidget {
  const MalEntrySheet({
    super.key,
    required this.animeId,
    required this.controller,
  });

  final int animeId;
  final MalLibraryController controller;

  static Future<void> show(
    BuildContext context, {
    required int animeId,
    required MalLibraryController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MalEntrySheet(animeId: animeId, controller: controller),
    );
  }

  @override
  State<MalEntrySheet> createState() => _MalEntrySheetState();
}

class _MalEntrySheetState extends State<MalEntrySheet> {
  MalLibraryController get _library => widget.controller;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onChange);
  }

  @override
  void dispose() {
    _library.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // The row can vanish underneath this sheet — removing it is one of the
    // things this sheet does. Closing is the only sensible answer; rendering an
    // empty sheet is not.
    if (_library.entryFor(widget.animeId) == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _run(Future<String?> action) async {
    final error = await action;
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmRemove(MalListEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'mal.remove_entry'.tr(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: Text(
          'mal.remove_confirm'.tr(args: [entry.anime.title]),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'mal.remove_entry'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(_library.remove(entry));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('mal.removed'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = _library.entryFor(widget.animeId);
    if (entry == null) return const SizedBox.shrink();

    final busy = _library.isBusy(entry.anime.id);
    final total = entry.anime.episodes;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnilistCover(url: entry.anime.picture, width: 54, radius: 9),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.anime.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const MalLogo(size: 15, radius: 4),
                            const SizedBox(width: 6),
                            Text(
                              total != null
                                  ? 'anilist.n_episodes_short'.tr(args: ['$total'])
                                  : 'MyAnimeList',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kMalBlue,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              _SectionLabel('anilist.status_label'.tr()),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in kMalLibraryStatuses)
                    _StatusPill(
                      label: malStatusLabel(status),
                      selected: entry.status == status,
                      onTap: busy
                          ? null
                          : () => _run(_library.setStatus(entry, status)),
                    ),
                ],
              ),

              // A rewatch is a flag MAL sets, not a status the app can send.
              // Saying so is better than leaving a pill that looks selectable
              // and quietly is not.
              if (entry.isRewatching) ...[
                const SizedBox(height: 10),
                Text(
                  'mal.rewatching_note'.tr(),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel('anilist.episodes_watched'.tr().toUpperCase()),
              const SizedBox(height: 8),
              _ProgressRow(
                progress: entry.progress,
                total: total,
                enabled: !busy,
                onStep: (next) => _run(_library.setProgress(entry, next)),
              ),

              const SizedBox(height: 20),
              _SectionLabel('mal.score_label'.tr()),
              const SizedBox(height: 8),
              _ScoreRow(
                score: entry.score,
                enabled: !busy,
                onPick: (value) => _run(_library.setScore(entry, value)),
              ),

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _confirmRemove(entry),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kButtonRadius),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('mal.remove_entry'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      );
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.progress,
    required this.total,
    required this.enabled,
    required this.onStep,
  });

  final int progress;
  final int? total;
  final bool enabled;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final atEnd = total != null && total! > 0 && progress >= total!;
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          enabled: enabled && progress > 0,
          onTap: () => onStep(progress - 1),
        ),
        Expanded(
          child: Center(
            child: Text(
              total != null ? '$progress / $total' : '$progress',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          enabled: enabled && !atEnd,
          onTap: () => onStep(progress + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 46,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? AppColors.textPrimary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

/// MAL scores are whole numbers from 1 to 10, and 0 means "not scored".
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.score,
    required this.enabled,
    required this.onPick,
  });

  final int score;
  final bool enabled;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // Tapping the current score clears it — otherwise a score set by
        // accident can never be taken back off the entry.
        _ScoreChip(
          label: '—',
          selected: score == 0,
          onTap: enabled && score != 0 ? () => onPick(0) : null,
        ),
        for (var value = 1; value <= 10; value++)
          _ScoreChip(
            label: '$value',
            selected: score == value,
            onTap: enabled ? () => onPick(score == value ? 0 : value) : null,
          ),
      ],
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kMalBlue : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 38,
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kMalBlue : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
