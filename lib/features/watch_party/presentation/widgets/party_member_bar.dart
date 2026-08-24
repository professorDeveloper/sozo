import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/comments/presentation/widgets/comment_avatar.dart';
import 'package:soplay/features/watch_party/domain/entities/party_member.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';

/// Horizontal strip of party members: avatar (with host crown + online dot),
/// name, and an `online/max` counter chip.
class PartyMemberBar extends StatelessWidget {
  const PartyMemberBar({super.key, required this.room, this.myUserId});

  final PartyRoom room;
  final String? myUserId;

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
            itemBuilder: (_, i) => _MemberTile(
              member: members[i],
              isMe: myUserId != null && members[i].userId == myUserId,
            ),
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
