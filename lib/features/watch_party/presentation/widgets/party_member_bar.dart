import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/comments/presentation/widgets/comment_avatar.dart';
import 'package:soplay/features/watch_party/domain/entities/party_member.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';

/// What the host picked from a member's menu.
enum PartyMemberAction { makeHost, remove }

/// Horizontal strip of party members: avatar (with host crown, online dot and
/// a buffering badge), name, and an `online/max` counter chip.
///
/// For the host, every other member is a button (tap, long-press, or D-pad
/// select on TV) that opens [onAction]'s menu.
class PartyMemberBar extends StatelessWidget {
  const PartyMemberBar({
    super.key,
    required this.room,
    this.myUserId,
    this.isHost = false,
    this.onAction,
  });

  final PartyRoom room;
  final String? myUserId;
  final bool isHost;
  final void Function(PartyMember member, PartyMemberAction action)? onAction;

  Future<void> _openMenu(BuildContext context, PartyMember member) async {
    final onAction = this.onAction;
    if (onAction == null) return;
    final name = (member.username ?? '').trim().isNotEmpty
        ? member.username!.trim()
        : '—';
    final picked = await showAdaptiveModal<PartyMemberAction>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (member.online)
              ListTile(
                autofocus: true,
                leading: const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.rating,
                ),
                title: Text('watch_party.make_host'.tr()),
                onTap: () =>
                    Navigator.of(ctx).pop(PartyMemberAction.makeHost),
              ),
            ListTile(
              autofocus: !member.online,
              leading: const Icon(
                Icons.person_remove_rounded,
                color: AppColors.error,
              ),
              title: Text(
                'watch_party.remove_member'.tr(),
                style: const TextStyle(color: AppColors.error),
              ),
              onTap: () => Navigator.of(ctx).pop(PartyMemberAction.remove),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) onAction(member, picked);
  }

  @override
  Widget build(BuildContext context) {
    final members = room.members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'watch_party.members'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${room.onlineCount}/${room.maxMembers}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final m = members[i];
              final isMe = myUserId != null && m.userId == myUserId;
              final actionable =
                  isHost && onAction != null && !isMe && !m.isHost;
              final tile = _MemberTile(member: m, isMe: isMe);
              if (!actionable) return tile;
              return HoverTap(
                borderRadius: 12,
                onTap: () => _openMenu(context, m),
                onLongPress: () => _openMenu(context, m),
                child: tile,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.isMe});

  final PartyMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final author = CommentAuthor(
      id: member.userId,
      username: member.username ?? '',
      photoURL: member.photoURL,
    );
    final label = isMe
        ? 'watch_party.you'.tr()
        : (member.username ?? '').trim().isNotEmpty
            ? member.username!.trim()
            : '—';

    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: member.online ? 1 : 0.45,
                child: CommentAvatar(author: author, size: 44),
              ),
              if (member.isHost)
                Positioned(
                  top: -4,
                  left: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.rating,
                      size: 15,
                    ),
                  ),
                ),
              if (member.buffering)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Tooltip(
                    message: 'watch_party.buffering'.tr(),
                    child: Container(
                      width: 18,
                      height: 18,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: const CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: AppColors.rating,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: member.online ? AppColors.success : AppColors.textHint,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isMe ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 10.5,
              fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
