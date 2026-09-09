import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_state.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';

/// One title in the library: a film, or a season that opens.
///
/// A series used to be one row per episode — twenty rows of the same poster
/// and the same name, differing by a number. Collapsing them means the list is
/// a list of things you downloaded rather than a list of files, and it makes
/// "delete the whole season" one action instead of twenty.
class DownloadGroupTile extends StatefulWidget {
  const DownloadGroupTile({
    super.key,
    required this.group,
    required this.thumbnailOf,
    required this.onOpen,
    required this.onPauseResume,
    required this.onRetry,
    required this.onRemove,
    required this.onExport,
  });

  final DownloadGroup group;

  /// The cached poster's path, or null. Resolved by the domain, because the
  /// widget layer has no business turning a stored path into a device one.
  final String? Function(DownloadItem) thumbnailOf;

  final void Function(DownloadItem) onOpen;
  final void Function(DownloadItem) onPauseResume;
  final void Function(DownloadItem) onRetry;
  final void Function(List<String>) onRemove;
  final void Function(DownloadItem) onExport;

  @override
  State<DownloadGroupTile> createState() => _DownloadGroupTileState();
}

class _DownloadGroupTileState extends State<DownloadGroupTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    if (group.isSingle) {
      return _DownloadRow(
        item: group.lead,
        thumbnail: widget.thumbnailOf(group.lead),
        onOpen: () => widget.onOpen(group.lead),
        onPauseResume: () => widget.onPauseResume(group.lead),
        onRetry: () => widget.onRetry(group.lead),
        onRemove: () => widget.onRemove([group.lead.id]),
        onExport: () => widget.onExport(group.lead),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GroupHeader(
          group: group,
          thumbnail: widget.thumbnailOf(group.lead),
          expanded: _open,
          onToggle: () => setState(() => _open = !_open),
          onRemoveAll: () => widget.onRemove(group.ids),
        ),
        if (_open)
          for (final item in group.items)
            Padding(
              // Indented so an expanded season reads as belonging to the row
              // above it rather than as more top-level entries.
              padding: const EdgeInsetsDirectional.only(start: 18),
              child: _DownloadRow(
                item: item,
                thumbnail: null,
                compact: true,
                onOpen: () => widget.onOpen(item),
                onPauseResume: () => widget.onPauseResume(item),
                onRetry: () => widget.onRetry(item),
                onRemove: () => widget.onRemove([item.id]),
                onExport: () => widget.onExport(item),
              ),
            ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.thumbnail,
    required this.expanded,
    required this.onToggle,
    required this.onRemoveAll,
  });

  final DownloadGroup group;
  final String? thumbnail;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRemoveAll;

  @override
  Widget build(BuildContext context) {
    final done = group.countWhere((i) => i.status == DownloadStatus.completed);

    return InkWell(
      onTap: onToggle,
      onLongPress: onRemoveAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Poster(item: group.lead, path: thumbnail),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'downloads.group_summary'.tr(
                      args: ['$done', '${group.items.length}'],
                    ),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (group.sizeBytes > 0)
                        Text(
                          formatBytes(group.sizeBytes),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                      if (group.hasProblem) ...[
                        if (group.sizeBytes > 0)
                          const Text(
                            '  ·  ',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                            ),
                          ),
                        Text(
                          'downloads.group_problems'.tr(),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (group.hasActive)
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// One download.
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    required this.thumbnail,
    required this.onOpen,
    required this.onPauseResume,
    required this.onRetry,
    required this.onRemove,
    required this.onExport,
    this.compact = false,
  });

  final DownloadItem item;
  final String? thumbnail;
  final bool compact;
  final VoidCallback onOpen;
  final VoidCallback onPauseResume;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // `missing` is tappable on purpose: the tap re-downloads. A row that
      // says the file is gone and then does nothing when pressed is the state
      // this whole screen was rebuilt to remove.
      onTap: item.status == DownloadStatus.completed ||
              item.status == DownloadStatus.missing
          ? onOpen
          : null,
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 8 : 10,
        ),
        child: Row(
          children: [
            if (!compact) ...[
              _Poster(item: item, path: thumbnail),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    compact ? _episodeTitle() : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: compact ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (!compact &&
                      item.isSerial &&
                      item.episodeNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _episodeTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _statusLine(),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _trailing(),
          ],
        ),
      ),
    );
  }

  String _episodeTitle() {
    final number = item.episodeNumber;
    final label = item.episodeLabel;
    if (number == null) return item.title;
    return label == null || label.isEmpty
        ? 'EP $number'
        : 'EP $number · $label';
  }

  Widget _statusLine() {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.pending:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                // Null while the length is unknown, so the bar is
                // indeterminate rather than pretending to sit at zero.
                value: item.progress,
                minHeight: 3,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              downloadProgressLabel(item),
              style: const TextStyle(color: AppColors.textHint, fontSize: 10),
            ),
          ],
        );
      case DownloadStatus.completed:
        return Text(
          downloadSizeLabel(item),
          style: const TextStyle(
            color: AppColors.success,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        );
      case DownloadStatus.missing:
        return Text(
          'downloads.missing'.tr(),
          style: const TextStyle(
            color: AppColors.rating,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        );
      case DownloadStatus.failed:
        return Text(
          downloadStatusLabel(item),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        );
      case DownloadStatus.paused:
        return Text(
          'downloads.paused'.tr(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        );
    }
  }

  Widget _trailing() {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.pending:
        return _CircleAction(
          icon: Icons.pause_rounded,
          onTap: onPauseResume,
          semanticLabel: 'downloads.pause'.tr(),
        );
      case DownloadStatus.paused:
        return _CircleAction(
          icon: Icons.play_arrow_rounded,
          onTap: onPauseResume,
          semanticLabel: 'downloads.resume'.tr(),
        );
      case DownloadStatus.failed:
      case DownloadStatus.missing:
        return _CircleAction(
          icon: Icons.refresh_rounded,
          color: AppColors.error,
          onTap: onRetry,
          semanticLabel: 'general.retry'.tr(),
        );
      case DownloadStatus.completed:
        return const _CircleAction(
          icon: Icons.check_rounded,
          color: AppColors.success,
          onTap: null,
          semanticLabel: '',
        );
    }
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (item.status.canRetry)
              ListTile(
                leading: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textPrimary,
                ),
                title: Text(
                  'downloads.download_again'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('retry'),
              ),
            // Only for a finished single file: a chapter is a folder of pages,
            // and a folder in Downloads is not something any gallery or player
            // knows what to do with.
            if (item.status == DownloadStatus.completed && !item.isManga)
              ListTile(
                leading: const Icon(
                  Icons.save_alt_rounded,
                  color: AppColors.textPrimary,
                ),
                title: Text(
                  'downloads.export'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  'downloads.export_hint'.tr(),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('export'),
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: Text(
                'downloads.remove'.tr(),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.of(sheetCtx).pop('remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    switch (action) {
      case 'retry':
        onRetry();
      case 'export':
        onExport();
      case 'remove':
        onRemove();
    }
  }
}

/// The poster, from disk where it was cached and from the network otherwise.
class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.path});

  final DownloadItem item;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final local = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 54,
        height: 76,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (local != null)
              Image.file(
                File(local),
                fit: BoxFit.cover,
                // The cached copy can vanish under the app; falling back to
                // the remote is better than a broken-image glyph.
                errorBuilder: (_, _, _) => HomeNetworkImage(
                  url: item.thumbnailUrl,
                  borderRadius: BorderRadius.zero,
                  placeholderIcon: item.isManga
                      ? Icons.menu_book_outlined
                      : Icons.movie_outlined,
                ),
              )
            else
              HomeNetworkImage(
                url: item.thumbnailUrl,
                borderRadius: BorderRadius.zero,
                placeholderIcon: item.isManga
                    ? Icons.menu_book_outlined
                    : Icons.movie_outlined,
              ),
            if (item.status == DownloadStatus.completed)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0x44000000),
                  child: Icon(
                    item.isManga
                        ? Icons.menu_book_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
    if (onTap == null) return SizedBox(width: 44, height: 44, child: Center(child: disc));
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 44,
        height: 44,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Center(child: disc),
        ),
      ),
    );
  }
}
