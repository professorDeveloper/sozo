import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/notifications/domain/entities/notification_item.dart';
import 'package:soplay/features/notifications/presentation/bloc/notifications_bloc.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<NotificationsBloc>()..add(const NotificationsRefresh()),
      child: const _NotificationsView(),
    );
  }
}

class _NotificationsView extends StatefulWidget {
  const _NotificationsView();

  @override
  State<_NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<_NotificationsView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      context.read<NotificationsBloc>().add(const NotificationsLoadMore());
    }
  }

  /// Held open until the fetch settles: returning straight away snapped the
  /// pull-to-refresh spinner shut while the request was still running.
  Future<void> _refresh() async {
    final bloc = context.read<NotificationsBloc>();
    final done = bloc.stream.firstWhere((s) => !s.loading);
    bloc.add(const NotificationsRefresh());
    await done.timeout(
      const Duration(seconds: 20),
      onTimeout: () => bloc.state,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/main'),
        ),
        title: Text(
          'notifications.title'.tr(),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          DesktopRefreshButton(
            color: AppColors.textPrimary,
            onRefresh: () => context
                .read<NotificationsBloc>()
                .add(const NotificationsRefresh()),
          ),
          BlocBuilder<NotificationsBloc, NotificationsState>(
            buildWhen: (a, b) => a.unread != b.unread,
            builder: (context, state) {
              if (state.unread == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => context
                    .read<NotificationsBloc>()
                    .add(const NotificationsMarkAllRead()),
                child: Text(
                  'notifications.mark_all_read'.tr(),
                  style: TextStyle(color: AppColors.primary),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<NotificationsBloc, NotificationsState>(
        builder: (context, state) {
          if (state.loading && state.items.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          // The empty and error states are scrollable too: off desktop the
          // refresh button is hidden, so a pull is the only way back.
          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: _refresh,
            child: _body(context, state),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, NotificationsState state) {
    if (state.error != null && state.items.isEmpty) {
      return _ScrollableFill(
        child: _ErrorView(message: state.error!, onRetry: _refresh),
      );
    }
    if (state.isEmpty) return const _ScrollableFill(child: _EmptyView());

    return MaxWidthBox(
      maxWidth: 560,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          final item = state.items[index];
          return _NotificationTile(
            item: item,
            onTap: () => context
                .read<NotificationsBloc>()
                .add(NotificationsMarkRead(item.id)),
            onDelete: () => context
                .read<NotificationsBloc>()
                .add(NotificationsDelete(item.id)),
          );
        },
      ),
    );
  }
}

class _ScrollableFill extends StatelessWidget {
  const _ScrollableFill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });
  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: item.read ? AppColors.surface : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: isDesktopPlatform ? null : () => _showActions(context),
        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
            ? _buildImageCard(context)
            : _buildTextRow(context),
      ),
    );

    if (isDesktopPlatform) {
      return Stack(
        children: [
          tile,
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: 'general.delete'.tr(),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: onDelete,
              ),
            ),
          ),
        ],
      );
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'general.delete'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: tile,
    );
  }

  /// The swipe is invisible until it is already under way; long-press exposes
  /// the same delete for anyone who never discovers it.
  Future<void> _showActions(BuildContext context) async {
    final remove = await showModalBottomSheet<bool>(
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
            const SizedBox(height: 8),
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
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: Text(
                'general.delete'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (remove ?? false) onDelete();
  }

  Widget _buildImageCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: item.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(
                  color: AppColors.surfaceVariant,
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: AppColors.surfaceVariant,
                ),
              ),
              if (!item.read)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: item.read ? FontWeight.w600 : FontWeight.w800,
                ),
              ),
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _formatDate(context, item.createdAt),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!item.read)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsetsDirectional.only(top: 6, end: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: item.read ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatDate(context, item.createdAt),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shared wording with the history list, and a locale-aware date past the
  /// relative window — `3.4.2026` reads as two different days depending on
  /// where you live.
  String _formatDate(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'time.now'.tr();
    if (diff.inHours < 1) return 'time.minutes'.tr(args: ['${diff.inMinutes}']);
    if (diff.inDays < 1) return 'time.hours'.tr(args: ['${diff.inHours}']);
    if (diff.inDays < 7) return 'time.days'.tr(args: ['${diff.inDays}']);
    return DateFormat.yMMMd(context.locale.toString()).format(dt);
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(scale: 0.92 + t * 0.08, child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
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
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.textSecondary,
                  size: 46,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'notifications.empty_title'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'notifications.empty_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 56),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'general.retry'.tr(),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
