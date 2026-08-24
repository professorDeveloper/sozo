import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/presentation/widgets/favorite_card.dart';

class PrivateListPage extends StatelessWidget {
  const PrivateListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = getIt<PrivateListService>();
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('app_lock.private_list'.tr()),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: service.revision,
        builder: (context, _, _) {
          final items = service.getAll();
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'app_lock.private_empty'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 142,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.56,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => HoverTap(
                      onLongPress: () => _showActions(context, items[i]),
                      onSecondaryTap: () => _showActions(context, items[i]),
                      child: FavoriteCard(
                        item: items[i],
                        onTap: () => _openDetail(context, items[i]),
                      ),
                    ),
                    childCount: items.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, FavoriteEntity item) {
    context.push(
      '/detail',
      extra: DetailArgs(contentUrl: item.contentUrl, provider: item.provider),
    );
  }

  void _showActions(BuildContext context, FavoriteEntity item) {
    final messenger = ScaffoldMessenger.of(context);
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  'app_lock.move_to_my_list'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await getIt<MyListLocalDataSource>().add(item);
                  await getIt<PrivateListService>().remove(item.contentUrl);
                  messenger.showSnackBar(
                    SnackBar(content: Text('app_lock.move_to_my_list'.tr())),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: Text(
                  'app_lock.removed_from_private'.tr(),
                  style: const TextStyle(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await getIt<PrivateListService>().remove(item.contentUrl);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('app_lock.removed_from_private'.tr()),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
