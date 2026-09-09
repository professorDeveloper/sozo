import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/presentation/pages/my_list_page.dart';
import 'package:soplay/features/private_list/presentation/private_unlock.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';

/// The four lists a viewer keeps by hand.
///
/// History, downloads and stats are deliberately *not* here: those are records
/// the app writes on its own, and mixing them in made one screen of eight rows
/// where the reader had to work out which half they were looking at. They live
/// in Activity instead.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final MyListLocalDataSource _favorites = getIt<MyListLocalDataSource>();
  final PrivateListService _private = getIt<PrivateListService>();

  @override
  void initState() {
    super.initState();
    _favorites.revision.addListener(_onChange);
    _private.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    _favorites.revision.removeListener(_onChange);
    _private.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// My List is normally a tab, so the natural way to reach it is to switch
  /// there and leave this page. When the user has removed that tab, push the
  /// page instead.
  void _openFavorites() {
    if (getIt<NavController>().goToId(TabId.myList)) {
      context.pop();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyListPage()));
  }

  Future<void> _openPrivate() async {
    final unlocked = await requestPrivateUnlock(context);
    if (unlocked && mounted) context.push('/private-list');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = getIt<HiveService>().isLoggedIn;
    return SettingsPageScaffold(
      title: 'profile.library'.tr(),
      children: [
        SettingsLabel('profile.section_lists'.tr()),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.favorite_rounded,
              title: 'profile.favorites'.tr(),
              value: countLabel(_favorites.getAll().length),
              onTap: _openFavorites,
            ),
            // The two server lists bind to a Sozo account.
            if (signedIn) ...[
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.watch_later_outlined,
                title: 'profile.watch_later'.tr(),
                onTap: () =>
                    context.push('/my-lists', extra: UserListKind.watchLater),
              ),
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.task_alt_rounded,
                title: 'profile.watched'.tr(),
                onTap: () =>
                    context.push('/my-lists', extra: UserListKind.watched),
              ),
            ],
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.lock_outline_rounded,
              title: 'app_lock.private_list'.tr(),
              // Only while unlocked: the count is itself information about
              // what is in there.
              value: _private.isUnlockedForSession
                  ? countLabel(_private.getAll().length)
                  : null,
              onTap: _openPrivate,
            ),
          ],
        ),
      ],
    );
  }
}
