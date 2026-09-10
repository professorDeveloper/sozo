import 'package:flutter/cupertino.dart';

import 'package:soplay/features/home/presentation/pages/home_page.dart';
import 'package:soplay/features/search/presentation/pages/search_page.dart';
import 'package:soplay/features/shorts/presentation/pages/shorts_page.dart';
import 'package:soplay/features/my_list/presentation/pages/my_list_page.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';
// Optional feature tabs — already-shipped pages.
import 'package:soplay/features/download/presentation/pages/downloads_page.dart';
import 'package:soplay/features/history/presentation/pages/history_page.dart';
import 'package:soplay/features/tracker/presentation/pages/following_page.dart';
import 'package:soplay/features/trivia/presentation/pages/buff_hub_page.dart';
import 'package:soplay/features/live_tv/presentation/pages/live_tv_page.dart';

/// Stable, persisted key for every navigable tab. Add a value here + one
/// registry entry + a `navigation.<name>` translation to introduce a new tab
/// (Premiere, Buff, ...). `.name` is what gets stored in Hive.
enum TabId { home, search, shorts, myList, profile, downloads, history, following, buff, liveTv }

/// Per-tab runtime state only the shell can supply. Shorts needs to know whether
/// it is the visible tab (autoplay pause) and the refresh tick; every other
/// builder ignores it.
class TabBuildContext {
  const TabBuildContext({required this.isActive, required this.shortsRefreshTick});
  final bool isActive;
  final int shortsRefreshTick;
}

typedef TabPageBuilder = Widget Function(TabBuildContext ctx);

class AppTabDef {
  const AppTabDef({
    required this.id,
    required this.icon,
    required this.activeIcon,
    required this.labelKey,
    required this.builder,
    this.mandatory = false,
  });

  final TabId id;
  final IconData icon;
  final IconData activeIcon;
  final String labelKey; // easy_localization key, e.g. 'navigation.home'
  final TabPageBuilder builder;
  final bool mandatory; // cannot be removed in the customizer
}

// Top-level builders so the registry map can stay `const` (tear-offs are const).
Widget _homeBuilder(TabBuildContext _) => const HomePage();
Widget _searchBuilder(TabBuildContext _) => const SearchPage();
Widget _shortsBuilder(TabBuildContext c) =>
    ShortsPage(active: c.isActive, refreshTick: c.shortsRefreshTick);
Widget _myListBuilder(TabBuildContext _) => const MyListPage();
Widget _profileBuilder(TabBuildContext _) => const ProfilePage();
Widget _downloadsBuilder(TabBuildContext _) => const DownloadsPage(isTab: true);
Widget _historyBuilder(TabBuildContext _) => const HistoryPage();
Widget _followingBuilder(TabBuildContext _) => const FollowingPage();
Widget _buffBuilder(TabBuildContext _) => const BuffHubPage();
Widget _liveTvBuilder(TabBuildContext _) => const LiveTvPage(embedded: true);

/// Single source of truth — replaces the old body list AND the metadata list.
const Map<TabId, AppTabDef> kTabRegistry = {
  TabId.home: AppTabDef(
      id: TabId.home,
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
      labelKey: 'navigation.home',
      mandatory: true,
      builder: _homeBuilder),
  TabId.search: AppTabDef(
      id: TabId.search,
      icon: CupertinoIcons.search,
      activeIcon: CupertinoIcons.search,
      labelKey: 'navigation.search',
      mandatory: true,
      builder: _searchBuilder),
  TabId.shorts: AppTabDef(
      id: TabId.shorts,
      icon: CupertinoIcons.play_rectangle,
      activeIcon: CupertinoIcons.play_rectangle_fill,
      labelKey: 'navigation.shorts',
      builder: _shortsBuilder),
  TabId.myList: AppTabDef(
      id: TabId.myList,
      icon: CupertinoIcons.bookmark,
      activeIcon: CupertinoIcons.bookmark_fill,
      labelKey: 'navigation.my_list',
      builder: _myListBuilder),
  TabId.profile: AppTabDef(
      id: TabId.profile,
      icon: CupertinoIcons.person,
      activeIcon: CupertinoIcons.person_fill,
      labelKey: 'navigation.profile',
      mandatory: true,
      builder: _profileBuilder),
  // ---- optional, opt-in via the customizer ----
  TabId.downloads: AppTabDef(
      id: TabId.downloads,
      icon: CupertinoIcons.cloud_download,
      activeIcon: CupertinoIcons.cloud_download_fill,
      labelKey: 'navigation.downloads',
      builder: _downloadsBuilder),
  TabId.history: AppTabDef(
      id: TabId.history,
      icon: CupertinoIcons.clock,
      activeIcon: CupertinoIcons.clock_fill,
      labelKey: 'navigation.history',
      builder: _historyBuilder),
  TabId.following: AppTabDef(
      id: TabId.following,
      icon: CupertinoIcons.heart,
      activeIcon: CupertinoIcons.heart_fill,
      labelKey: 'navigation.following',
      builder: _followingBuilder),
  TabId.buff: AppTabDef(
      id: TabId.buff,
      icon: CupertinoIcons.film,
      activeIcon: CupertinoIcons.film_fill,
      labelKey: 'navigation.buff',
      builder: _buffBuilder),
  TabId.liveTv: AppTabDef(
      id: TabId.liveTv,
      icon: CupertinoIcons.tv,
      activeIcon: CupertinoIcons.tv_fill,
      labelKey: 'navigation.live_tv',
      builder: _liveTvBuilder),
};

/// Default = the current shipped 5-tab order → this IS the back-compat contract.
const List<TabId> kDefaultTabs = [
  TabId.home,
  TabId.search,
  TabId.shorts,
  TabId.myList,
  TabId.profile,
];

/// Fixed tab set for Android TV. The customizer is drag-reorder driven and has
/// no D-pad equivalent, so TV never reads/writes the persisted Hive order — it
/// mounts THIS list verbatim. Deliberately NOT fed through [sanitizeTabOrder]:
/// that function is mobile's Hive back-compat contract and must keep behaving
/// exactly as it does today.
///
/// Dropped vs [kDefaultTabs]: `shorts` (a swipe-only PageView with no D-pad
/// page-change affordance). Not opted in: `following`, `history`, `buff`,
/// `downloads` (offline caching has weak value on a mains-powered TV).
const List<TabId> kTvTabs = [
  TabId.home,
  TabId.search,
  TabId.myList,
  TabId.profile,
];

const int kMinTabs = 4;
const int kMaxTabs = 6;

/// Persisted keys that no longer match any [TabId.name] because the enum was
/// renamed after shipping. Hive stores `.name`, so without this a user who had
/// the tab on their bar would silently lose it on upgrade (sanitize drops
/// unknown ids and tops up from defaults).
const Map<String, TabId> _kLegacyTabKeys = {
  'kinoBillar': TabId.buff,
};

TabId? tabIdFromKey(String key) {
  for (final id in TabId.values) {
    if (id.name == key) return id;
  }
  return _kLegacyTabKeys[key];
}

Set<TabId> mandatoryTabs() =>
    {for (final e in kTabRegistry.entries) if (e.value.mandatory) e.key};

/// Ported from satashkent's `_sanitize`. Runs on BOTH read and save so a stale
/// or corrupt Hive value can never break the bar:
///  - drops unknown ids (registry shrank between versions) & de-dupes
///  - force-includes any missing mandatory tab (never lose Home/Profile)
///  - tops up to kMinTabs from defaults, clamps down to kMaxTabs
///  - empty → defaults
List<TabId> sanitizeTabOrder(List<String> raw) {
  final out = <TabId>[];
  for (final k in raw) {
    final id = tabIdFromKey(k);
    if (id != null && kTabRegistry.containsKey(id) && !out.contains(id)) {
      out.add(id);
    }
  }
  for (final id in kDefaultTabs) {
    if (mandatoryTabs().contains(id) && !out.contains(id)) out.add(id);
  }
  if (out.length < kMinTabs) {
    for (final id in kDefaultTabs) {
      if (!out.contains(id)) out.add(id);
      if (out.length >= kMinTabs) break;
    }
  }
  if (out.isEmpty) return List.of(kDefaultTabs);
  return out.length > kMaxTabs ? out.take(kMaxTabs).toList() : out;
}

List<String> encodeTabOrder(List<TabId> ids) => [for (final id in ids) id.name];
