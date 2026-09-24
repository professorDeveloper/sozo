import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/system/app_dates.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/social/domain/social_models.dart';

String socialErrorText(Object? error) {
  final kind = error is SocialException ? error.kind : SocialError.unknown;
  return switch (kind) {
    SocialError.network => 'social.error_network'.tr(),
    SocialError.unauthorized => 'social.error_signin'.tr(),
    SocialError.notFound => 'social.error_not_found'.tr(),
    SocialError.requestsClosed => 'social.error_requests_closed'.tr(),
    SocialError.alreadyFriends => 'social.error_already_friends'.tr(),
    SocialError.friendLimit => 'social.error_friend_limit'.tr(),
    SocialError.tooManyPending => 'social.error_too_many_pending'.tr(),
    SocialError.activityHidden => 'social.activity_hidden_title'.tr(),
    SocialError.rateLimited => 'social.error_rate_limited'.tr(),
    SocialError.invalid || SocialError.unknown => 'social.error_generic'.tr(),
  };
}

void showSocialSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// "3 h ago" for the last week, a date after that.
String socialTimeLabel(BuildContext context, DateTime? at) {
  if (at == null) return '';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'time.now'.tr();
  if (diff.inHours < 1) return 'time.minutes'.tr(args: ['${diff.inMinutes}']);
  if (diff.inDays < 1) return 'time.hours'.tr(args: ['${diff.inHours}']);
  if (diff.inDays < 7) return 'time.days'.tr(args: ['${diff.inDays}']);
  return AppDates.short(context, at);
}

Future<bool> confirmSocial(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirm,
              style: TextStyle(
                color: destructive ? AppColors.errorLight : AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ) ??
    false;

class SocialAvatar extends StatelessWidget {
  const SocialAvatar({super.key, required this.user, this.size = 44});

  final SocialUser user;
  final double size;

  String get _initials {
    final source = user.name.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = user.photoURL;
    final placeholder = Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

/// A person in a list: avatar, name, @username, and whatever actions fit.
class SocialUserTile extends StatelessWidget {
  const SocialUserTile({
    super.key,
    required this.user,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final SocialUser user;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = subtitle ?? '@${user.username}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SocialAvatar(user: user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// A compact pill button for list rows.
class SocialPillButton extends StatelessWidget {
  const SocialPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onPrimary : AppColors.textPrimary;
    final enabled = onPressed != null && !busy;
    return Material(
      color: filled
          ? AppColors.primary.withValues(alpha: enabled ? 1 : 0.5)
          : Colors.white.withValues(alpha: 0.08),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: fg),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: enabled ? fg : fg.withValues(alpha: 0.6),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Empty and error states. Scrollable so pull to refresh still works on them.
class SocialStateView extends StatelessWidget {
  const SocialStateView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool scrollable;

  factory SocialStateView.error(Object? error, VoidCallback onRetry) =>
      SocialStateView(
        icon: Icons.cloud_off_rounded,
        title: socialErrorText(error),
        actionLabel: 'general.retry'.tr(),
        onAction: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.015),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.8,
              ),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            SocialPillButton(
              label: actionLabel!,
              onPressed: onAction,
              filled: true,
            ),
          ],
        ],
      ),
    );
    if (!scrollable) return Center(child: content);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// Footer under a paged list: spinner while loading, retry after a failure.
class SocialListFooter extends StatelessWidget {
  const SocialListFooter({
    super.key,
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }
    if (failed) {
      return Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: Icon(Icons.refresh_rounded, color: AppColors.primary, size: 18),
          label: Text(
            'general.retry'.tr(),
            style: TextStyle(color: AppColors.primary),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}
