import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_entity.dart';
import 'package:soplay/features/reports/domain/entities/report_payload.dart';
import 'package:soplay/features/reports/presentation/widgets/report_sheet.dart';
import 'comment_avatar.dart';

class CommentCard extends StatelessWidget {
  const CommentCard({
    super.key,
    required this.comment,
    required this.isOwner,
    required this.canInteract,
    required this.onLike,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReplies,
    required this.repliesExpanded,
    this.compact = false,
  });

  final CommentEntity comment;
  final bool isOwner;
  final bool canInteract;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleReplies;
  final bool repliesExpanded;
  final bool compact;

  Future<void> _onReport(BuildContext context) async {
    final ok = await showReportSheet(
      context,
      targetType: ReportTargetType.comment,
      targetId: comment.id,
    );
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('comments.report_submitted'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReplies = comment.replyCount > 0 && comment.isTopLevel;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(compact ? 0 : 16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentAvatar(author: comment.user, size: compact ? 30 : 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.user.nameOrUsername,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                    if (comment.edited) ...[
                      const SizedBox(width: 6),
                      Text(
                        'comments.edited'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const Spacer(),
                    _MoreButton(
                      isOwner: isOwner,
                      canReport: canInteract && !isOwner,
                      onEdit: onEdit,
                      onDelete: onDelete,
                      onReport: () => _onReport(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ActionButton(
                      icon: comment.likedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: comment.likeCount > 0
                          ? comment.likeCount.toString()
                          : 'comments.like'.tr(),
                      active: comment.likedByMe,
                      onTap: canInteract ? onLike : null,
                    ),
                    if (comment.isTopLevel)
                      _ActionButton(
                        icon: Icons.reply_rounded,
                        label: 'comments.reply'.tr(),
                        active: false,
                        onTap: canInteract ? onReply : null,
                      ),
                    if (hasReplies)
                      _ActionButton(
                        icon: repliesExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        label: repliesExpanded
                            ? 'comments.hide'.tr()
                            : comment.replyCount == 1
                                ? 'comments.replies_one'.tr()
                                : 'comments.replies_other'
                                    .tr(args: ['${comment.replyCount}']),
                        active: repliesExpanded,
                        onTap: onToggleReplies,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.textHint.withValues(alpha: 0.5)
        : active
            ? AppColors.primary
            : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.isOwner,
    required this.canReport,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });
  final bool isOwner;
  final bool canReport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    if (!isOwner && !canReport) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz_rounded,
        color: AppColors.textHint,
        size: 18,
      ),
      color: AppColors.surface,
      padding: EdgeInsets.zero,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          case 'report':
            onReport();
        }
      },
      itemBuilder: (_) => [
        if (isOwner)
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text('general.edit'.tr(),
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        if (isOwner)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_rounded,
                    size: 16, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text('general.delete'.tr(),
                    style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        if (canReport)
          PopupMenuItem(
            value: 'report',
            child: Row(
              children: [
                const Icon(Icons.flag_rounded,
                    size: 16, color: Colors.orangeAccent),
                const SizedBox(width: 8),
                Text('comments.report'.tr(),
                    style: const TextStyle(color: Colors.orangeAccent)),
              ],
            ),
          ),
      ],
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
  return '${diff.inDays ~/ 365}y';
}
