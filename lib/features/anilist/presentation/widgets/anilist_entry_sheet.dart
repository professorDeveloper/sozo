import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';

/// Everything you can do to one library entry, on one sheet.
///
/// A sheet rather than a page because every action here is a single tap that
/// belongs to the card the user just touched — pushing a route would lose the
/// list position they are working down.
class AnilistEntrySheet extends StatefulWidget {
  const AnilistEntrySheet({
    super.key,
    required this.entryId,
    required this.controller,
  });

  final int entryId;
  final AnilistLibraryController controller;

  static Future<void> show(
    BuildContext context, {
    required int entryId,
    required AnilistLibraryController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnilistEntrySheet(entryId: entryId, controller: controller),
    );
  }

  @override
  State<AnilistEntrySheet> createState() => _AnilistEntrySheetState();
}

class _AnilistEntrySheetState extends State<AnilistEntrySheet> {
  AnilistLibraryController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Re-read from the controller on every build rather than holding the entry.
  ///
  /// The sheet stays open across writes, and a captured copy would keep showing
  /// the pre-write progress the user just changed.
  AnilistListEntry? get _entry {
    for (final e in _c.entries) {
      if (e.id == widget.entryId) return e;
    }
    return null;
  }

  Future<void> _run(Future<String?> action) async {
    final error = await action;
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmRemove(AnilistListEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'anilist.remove_entry'.tr(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: Text(
          'anilist.remove_confirm'.tr(args: [entry.media.displayTitle]),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'anilist.remove_entry'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await _c.remove(entry);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('anilist.removed'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) return const SizedBox.shrink();

    final media = entry.media;
    final busy = _c.isBusy(entry.id);
    final total = media.episodes;
    final next = entry.nextEpisode;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        // Scrolls rather than clips: six status pills, a three-line title and a
        // large text scale together outrun the height a sheet is given, and a
        // landscape phone outruns it on its own.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnilistCover(url: media.coverImage, width: 68),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.displayTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            AnilistChip(
                              label: (AnilistStatus.fromValue(entry.status) ??
                                      AnilistStatus.current)
                                  .labelKey
                                  .tr(),
                            ),
                            if (media.format != null)
                              AnilistChip(
                                label: media.format!,
                                color: AppColors.textSecondary,
                              ),
                            if (media.averageScore != null)
                              AnilistChip(
                                label: '${media.averageScore}%',
                                icon: Icons.star_rounded,
                                color: AppColors.rating,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ProgressRow(
                progress: entry.progress,
                total: total,
                busy: busy,
                canDecrement: entry.progress > 0,
                canIncrement: next != null,
                onDecrement: () => _run(_c.setProgress(entry, entry.progress - 1)),
                onIncrement: () => _run(_c.bumpEpisode(entry)),
              ),
              const SizedBox(height: 18),
              Text(
                'anilist.status_label'.tr(),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in AnilistStatus.values)
                    _StatusPill(
                      label: status.labelKey.tr(),
                      selected: entry.status == status.value,
                      onTap: busy || entry.status == status.value
                          ? null
                          : () => _run(_c.setStatus(entry, status)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 8),
              _Action(
                icon: Icons.travel_explore_rounded,
                label: 'anilist.find_in_sources'.tr(),
                subtitle: 'anilist.find_in_sources_hint'.tr(),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/cross-search', extra: media.displayTitle);
                },
              ),
              _Action(
                icon: Icons.open_in_new_rounded,
                label: 'anilist.open_on_anilist'.tr(),
                onTap: media.siteUrl == null
                    ? null
                    : () => launchUrl(
                          Uri.parse(media.siteUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
              ),
              // Behind a confirmation, and last: everything above this line is
              // reversible with one more tap, and this is not — AniList drops
              // the entry and the progress with it.
              _Action(
                icon: Icons.delete_outline_rounded,
                label: 'anilist.remove_entry'.tr(),
                destructive: true,
                onTap: busy ? null : () => _confirmRemove(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.progress,
    required this.total,
    required this.busy,
    required this.canDecrement,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int progress;
  final int? total;
  final bool busy;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
      ),
      child: Row(
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            onTap: busy || !canDecrement ? null : onDecrement,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  total != null ? '$progress / $total' : '$progress',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'anilist.episodes_watched'.tr(),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            primary: true,
            busy: busy,
            onTap: busy || !canIncrement ? null : onIncrement,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: primary && enabled
          ? kAnilistBlue
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 46,
          height: 46,
          child: busy && primary
              ? const Center(
                  child: SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : Icon(
                  icon,
                  size: 21,
                  color: enabled
                      ? (primary ? Colors.white : AppColors.textPrimary)
                      : AppColors.textHint,
                ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kAnilistBlue.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? kAnilistBlue.withValues(alpha: 0.55)
                  : AppColors.border,
              width: selected ? 1 : 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? kAnilistBlue : AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Coloured as a warning and given no chevron: it does not lead anywhere,
  /// it ends something.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        icon,
        color: !enabled
            ? AppColors.textHint
            : destructive
            ? AppColors.error
            : kAnilistBlue,
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: !enabled
              ? AppColors.textHint
              : destructive
              ? AppColors.error
              : AppColors.textPrimary,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
      trailing: destructive
          ? null
          : const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textHint,
              size: 20,
            ),
      onTap: onTap,
    );
  }
}
