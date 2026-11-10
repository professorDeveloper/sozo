import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/comments/presentation/widgets/comment_avatar.dart';
import 'package:soplay/features/social/data/social_remote_data_source.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/watch_party/data/watch_party_remote_data_source.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/invite_cooldowns.dart';

/// Host-only: pick friends to send a push invite to the current room.
Future<void> showPartyInviteSheet(BuildContext context) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const PartyInviteSheet(),
  );
}

class PartyInviteSheet extends StatefulWidget {
  const PartyInviteSheet({super.key});

  @override
  State<PartyInviteSheet> createState() => _PartyInviteSheetState();
}

class _PartyInviteSheetState extends State<PartyInviteSheet> {
  final WatchPartyService _service = getIt<WatchPartyService>();
  final InviteCooldowns _cooldowns = InviteCooldowns();
  final Set<String> _sending = <String>{};

  static const int _maxFriends = 200;

  List<SocialUser>? _friends;
  bool _failed = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _friends = null;
    });
    try {
      final social = getIt<SocialRemoteDataSource>();
      final out = <SocialUser>[];
      String? cursor;
      do {
        final page = await social.friends(cursor: cursor, limit: 50);
        out.addAll(page.items.map((f) => f.user));
        cursor = page.nextCursor;
      } while (cursor != null && out.length < _maxFriends);
      try {
        _cooldowns.applyServer(await _service.inviteCooldowns());
      } catch (_) {
        // An older server has no status endpoint; cooldowns then show up as
        // they are hit.
      }
      if (!mounted) return;
      setState(() => _friends = out);
      _syncTicker();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _syncTicker() {
    if (_cooldowns.any) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!_cooldowns.any) {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    }
  }

  Future<void> _invite(SocialUser user) async {
    if (_sending.contains(user.id) || _cooldowns.coolingDown(user.id)) return;
    setState(() => _sending.add(user.id));
    try {
      final left = await _service.invite(user.id);
      _cooldowns.set(user.id, left > 0 ? left : 600);
      _toast('watch_party.invite_sent'.tr());
    } on PartyInviteCooldown catch (e) {
      _cooldowns.set(user.id, e.retryAfterSec);
    } catch (_) {
      _toast('watch_party.invite_failed'.tr());
    } finally {
      if (mounted) {
        setState(() => _sending.remove(user.id));
        _syncTicker();
      }
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceVariant,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friends;
    final Widget body;
    if (_failed) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              'watch_party.error_generic'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              autofocus: true,
              onPressed: _load,
              child: Text('general.try_again'.tr()),
            ),
          ],
        ),
      );
    } else if (friends == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    } else if (friends.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Text(
          'watch_party.invite_no_friends'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: friends.length,
          itemBuilder: (_, i) => _FriendRow(
            user: friends[i],
            autofocus: i == 0,
            sending: _sending.contains(friends[i].id),
            cooldown: _cooldowns.remaining(friends[i].id),
            onInvite: () => _invite(friends[i]),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text(
                'watch_party.invite_friends'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.user,
    required this.autofocus,
    required this.sending,
    required this.cooldown,
    required this.onInvite,
  });

  final SocialUser user;
  final bool autofocus;
  final bool sending;
  final Duration cooldown;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final cooling = cooldown > Duration.zero;
    final Widget trailing;
    if (sending) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (cooling) {
      trailing = Text(
        'watch_party.invite_again_in'.tr(
          args: [InviteCooldowns.format(cooldown)],
        ),
        style: const TextStyle(color: AppColors.textHint, fontSize: 12),
      );
    } else {
      trailing = const Icon(Icons.send_rounded, size: 20);
    }
    return ListTile(
      autofocus: autofocus,
      enabled: !cooling && !sending,
      onTap: onInvite,
      leading: CommentAvatar(
        author: CommentAuthor(
          id: user.id,
          username: user.username,
          photoURL: user.photoURL,
        ),
        size: 38,
      ),
      title: Text(
        user.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),
      subtitle: user.displayName != null
          ? Text(
              '@${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            )
          : null,
      trailing: trailing,
    );
  }
}
