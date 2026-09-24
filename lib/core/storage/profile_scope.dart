import 'package:soplay/core/constants/app_constants.dart';

/// Which household profile's local data the app is reading and writing.
///
/// The default profile uses exactly the box names and settings keys every
/// install already has, so the data on the device before profiles existed is
/// the default profile's data with nothing copied or renamed. Only the extra
/// profiles get suffixed boxes (`history_box__p_<id>`) and suffixed settings
/// keys (`incognito_mode@p_<id>`).
///
/// Everything not listed in [profileBoxes] or [profileKeys] is device- or
/// account-level and shared by every profile: tokens and tracker connections
/// (the backend keeps AniList/MAL, streak and notifications per account),
/// downloads, extractors, sources, theme, language, player and reader
/// preferences, app lock, backups.
class ProfileScope {
  ProfileScope._();

  static String? _namespace;
  static String? _remoteId;
  static bool _kids = false;

  /// Null while the default profile is active.
  static String? get namespace => _namespace;

  /// The server id of the active profile, sent as `X-Sozo-Profile`. Null until
  /// the account's profiles have been fetched once, which is also what an app
  /// from before profiles sends: nothing, and the server uses the default.
  static String? get remoteId => _remoteId;

  static bool get isKids => _kids;

  static void set({String? namespace, String? remoteId, bool kids = false}) {
    _namespace = namespace;
    _remoteId = remoteId;
    _kids = kids;
  }

  static void reset() => set();

  static const Set<String> profileBoxes = {
    AppConstants.historyBox,
    AppConstants.favoritesBox,
    AppConstants.privateFavoritesBox,
    AppConstants.userListsBox,
  };

  /// Settings keys that describe one person rather than the device.
  static const Set<String> profileKeys = {
    'history_sync_cursor',
    'history_sync_pushed_at',
    'history_sync_tombstones',
    'history_sync_owner',
    AppConstants.adultContentKey,
    AppConstants.incognitoKey,
    AppConstants.homeRailOrderKey,
    AppConstants.homeRailHiddenKey,
    AppConstants.homeSuggestionsAnsweredKey,
    AppConstants.watchStatsKey,
    AppConstants.titlePrefsKey,
    AppConstants.tasteProfileKey,
    'source_choices',
    'search_recent_queries',
    'followed_titles',
  };

  static String box(String base) => boxFor(base, _namespace);

  static String boxFor(String base, String? namespace) {
    if (namespace == null || !profileBoxes.contains(base)) return base;
    return '${base}__p_$namespace';
  }

  static String key(String base) => keyFor(base, _namespace);

  static String keyFor(String base, String? namespace) {
    if (namespace == null || !profileKeys.contains(base)) return base;
    return '$base@p_$namespace';
  }

  static bool isProfileKey(Object? key) => key is String && key.contains('@p_');
}
