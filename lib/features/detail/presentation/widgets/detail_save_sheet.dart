import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_more_menu.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';

/// Where a title goes, all in one place.
///
/// These four lived in the overflow menu next to Share, Copy link and Report a
/// problem — eleven rows of which the first four were about keeping the title
/// and the rest about doing something with it. "Am I saving this?" and "how do
/// I send this to someone?" are different questions and were being answered by
/// one list.
///
/// So they moved to the button that already means "keep this": the tick in the
/// app bar. It used to toggle My List on its own, which was one tap for the
/// common case and no way at all to reach the other three without the menu.
/// Now it opens this, where every list the title could be in is visible at
/// once — including which ones it is already in, which nothing showed before.
Future<void> showDetailSaveSheet(
  BuildContext context, {
  required FavoriteEntity entity,
  required bool isInList,
  required bool inPrivate,
  required bool showFollow,
  required bool following,
  required VoidCallback onToggleMyList,
  required VoidCallback onToggleFollow,
  required VoidCallback onMoveToPrivate,
  required VoidCallback onPrivateActions,
}) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SaveSheet(
      entity: entity,
      isInList: isInList,
      inPrivate: inPrivate,
      showFollow: showFollow,
      following: following,
      onToggleMyList: onToggleMyList,
      onToggleFollow: onToggleFollow,
      onMoveToPrivate: onMoveToPrivate,
      onPrivateActions: onPrivateActions,
    ),
  );
}

class _SaveSheet extends StatefulWidget {
  const _SaveSheet({
    required this.entity,
    required this.isInList,
    required this.inPrivate,
    required this.showFollow,
    required this.following,
    required this.onToggleMyList,
    required this.onToggleFollow,
    required this.onMoveToPrivate,
    required this.onPrivateActions,
  });

  final FavoriteEntity entity;
  final bool isInList;
  final bool inPrivate;
  final bool showFollow;
  final bool following;
  final VoidCallback onToggleMyList;
  final VoidCallback onToggleFollow;
  final VoidCallback onMoveToPrivate;
  final VoidCallback onPrivateActions;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  /// Echoed locally so a tap lands now.
  ///
  /// The page's own state arrives a frame or two later through its bloc, and
  /// a checkbox that waits for that reads as a tap that did not register.
  late bool _inList = widget.isInList;
  late bool _following = widget.following;
  final UserListSync _sync = UserListSync();

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: Text(
              widget.entity.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _Check(
            label: 'detail.my_list'.tr(),
            icon: Icons.bookmark_rounded,
            checked: _inList,
            onTap: () {
              setState(() => _inList = !_inList);
              widget.onToggleMyList();
            },
          ),
          UserListToggle(
            kind: UserListKind.watchLater,
            entity: widget.entity,
            sync: _sync,
            builder: (_, active, toggle) => _Check(
              label: 'detail.watch_later'.tr(),
              icon: Icons.watch_later_rounded,
              checked: active,
              onTap: toggle,
            ),
          ),
          UserListToggle(
            kind: UserListKind.watched,
            entity: widget.entity,
            sync: _sync,
            builder: (_, active, toggle) => _Check(
              label: 'detail.watched'.tr(),
              icon: Icons.visibility_rounded,
              checked: active,
              onTap: toggle,
            ),
          ),
          if (widget.showFollow)
            _Check(
              label: 'detail.follow_series'.tr(),
              icon: Icons.notifications_active_rounded,
              checked: _following,
              onTap: () {
                setState(() => _following = !_following);
                widget.onToggleFollow();
              },
            ),
          const Divider(height: 17, indent: 20, endIndent: 20),
          // Not a checkbox: moving a title to the private list is a move, and
          // it opens its own flow. A box that ticks and then asks something
          // else would be lying about what the tap does.
          ListTile(
            leading: Icon(
              widget.inPrivate
                  ? Icons.lock_rounded
                  : Icons.lock_outline_rounded,
              color: widget.inPrivate ? AppColors.rating : null,
            ),
            title: Text(
              widget.inPrivate
                  ? 'app_lock.private_list'.tr()
                  : 'app_lock.move_to_private'.tr(),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).pop();
              if (widget.inPrivate) {
                widget.onPrivateActions();
              } else {
                widget.onMoveToPrivate();
              }
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.icon,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: checked ? AppColors.primary : null),
      title: Text(label),
      trailing: Icon(
        checked ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: checked ? AppColors.primary : AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}
