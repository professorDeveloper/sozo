import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';
import '../../features/auth/data/models/user_model.dart';
import '../../features/detail/domain/entities/subtitle_style.dart';

class HiveService {
  final Box _authBox = Hive.box(AppConstants.authBox);
  final Box _settingsBox = Hive.box(AppConstants.settingsBox);

  String? getToken() => _authBox.get(AppConstants.accessTokenKey);
  String? getRefreshToken() => _authBox.get(AppConstants.refreshTokenKey);

  UserModel? getUser() {
    final raw = _authBox.get(AppConstants.userKey);
    if (raw == null) return null;
    return UserModel.fromJson(
      jsonDecode(raw as String) as Map<String, dynamic>,
    );
  }

  Future<void> saveAuth({
    required String accessToken,
    required String refreshToken,
    required UserModel user,
  }) async {
    await saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    await _authBox.put(AppConstants.userKey, jsonEncode(user.toJson()));
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _authBox.put(AppConstants.accessTokenKey, accessToken);
    await _authBox.put(AppConstants.refreshTokenKey, refreshToken);
  }

  Future<void> saveUser(UserModel user) async {
    await _authBox.put(AppConstants.userKey, jsonEncode(user.toJson()));
  }

  Future<void> clearAuth() async {
    await _authBox.delete(AppConstants.accessTokenKey);
    await _authBox.delete(AppConstants.refreshTokenKey);
    await _authBox.delete(AppConstants.userKey);
  }

  bool get isLoggedIn => getToken()?.isNotEmpty == true;

  String getBridgeUrl() =>
      _settingsBox.get('desktop_bridge_url', defaultValue: '') as String;
  Future<void> setBridgeUrl(String url) =>
      _settingsBox.put('desktop_bridge_url', url.trim());

  String? getAniListToken() => _authBox.get(AppConstants.aniListTokenKey);
  bool get isAniListConnected => getAniListToken() != null;

  Future<void> saveAniListToken(String token) async =>
      _authBox.put(AppConstants.aniListTokenKey, token);

  Future<void> clearAniListToken() async =>
      _authBox.delete(AppConstants.aniListTokenKey);

  /// The linked AniList account as JSON. Cached beside the token so a screen
  /// can say "connected as X" while offline, instead of showing a bare
  /// "connected" that tells the user nothing about which account.
  String? getAniListViewer() => _authBox.get(AppConstants.aniListViewerKey);

  Future<void> saveAniListViewer(String json) async =>
      _authBox.put(AppConstants.aniListViewerKey, json);

  Future<void> clearAniListViewer() async =>
      _authBox.delete(AppConstants.aniListViewerKey);

  String? getMalToken() => _authBox.get(AppConstants.malTokenKey);
  bool get isMalConnected => getMalToken() != null;

  Future<void> saveMalToken(String token) async =>
      _authBox.put(AppConstants.malTokenKey, token);

  Future<void> clearMalToken() async =>
      _authBox.delete(AppConstants.malTokenKey);

  /// The linked MyAnimeList account as JSON — the MAL counterpart of
  /// [getAniListViewer], and cached for the same reason.
  String? getMalViewer() => _authBox.get(AppConstants.malViewerKey);

  Future<void> saveMalViewer(String json) async =>
      _authBox.put(AppConstants.malViewerKey, json);

  Future<void> clearMalViewer() async =>
      _authBox.delete(AppConstants.malViewerKey);

  String getCurrentProvider() {
    final saved = _settingsBox.get(
      AppConstants.currentProviderKey,
      defaultValue: '',
    ) as String;

    return saved.isEmpty ? AppConstants.defaultProviderId : saved;
  }

  Future<void> saveCurrentProvider(String providerId) async {
    await _settingsBox.put(AppConstants.currentProviderKey, providerId);
  }

  String getPreOutageProvider() {
    return _settingsBox.get(AppConstants.preOutageProviderKey, defaultValue: '');
  }

  Future<void> savePreOutageProvider(String providerId) async {
    await _settingsBox.put(AppConstants.preOutageProviderKey, providerId);
  }

  Future<void> clearPreOutageProvider() async {
    await _settingsBox.delete(AppConstants.preOutageProviderKey);
  }

  List<Map<String, dynamic>> getCachedProviders() {
    final raw = _settingsBox.get(AppConstants.cachedProvidersKey);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// When [getCachedProviders] was written, so the UI can say how stale it is.
  DateTime? getCachedProvidersAt() {
    final raw = _settingsBox.get(AppConstants.cachedProvidersAtKey);
    if (raw is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> saveCachedProviders(List<Map<String, dynamic>> providers) async {
    await _settingsBox.put(
      AppConstants.cachedProvidersKey,
      jsonEncode(providers),
    );
    await _settingsBox.put(
      AppConstants.cachedProvidersAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<String> getFavoriteProviders() {
    return (_settingsBox.get('favorite_providers') as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
  }

  bool isFavoriteProvider(String id) => getFavoriteProviders().contains(id);

  Future<void> toggleFavoriteProvider(String id) async {
    final list = getFavoriteProviders();
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    await _settingsBox.put('favorite_providers', list);
  }
  List<String> getCrossSearchProviders() {
    return (_settingsBox.get('cross_search_providers') as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
  }

  Future<void> setCrossSearchProviders(List<String> ids) async {
    await _settingsBox.put('cross_search_providers', ids);
  }

  List<Map<String, dynamic>> getFollowedRaw() {
    final raw = _settingsBox.get('followed_titles');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> setFollowedRaw(List<Map<String, dynamic>> items) async {
    await _settingsBox.put('followed_titles', jsonEncode(items));
  }

  String getOpenSubtitlesKey() {
    return _settingsBox.get(AppConstants.openSubtitlesKeyKey, defaultValue: '');
  }

  Future<void> saveOpenSubtitlesKey(String key) async {
    await _settingsBox.put(AppConstants.openSubtitlesKeyKey, key.trim());
  }

  bool get hasSeenShortsRefreshShowcase {
    return _settingsBox.get(
          AppConstants.shortsRefreshShowcaseSeenKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> markShortsRefreshShowcaseSeen() async {
    await _settingsBox.put(AppConstants.shortsRefreshShowcaseSeenKey, true);
  }

  String getLanguage() {
    return _settingsBox.get(AppConstants.languageKey, defaultValue: 'en');
  }

  Future<void> saveLanguage(String langCode) async {
    await _settingsBox.put(AppConstants.languageKey, langCode);
  }

  String getPreferredMediaLang() {
    return _settingsBox.get(
      AppConstants.preferredMediaLangKey,
      defaultValue: AppConstants.defaultMediaLang,
    );
  }

  Future<void> savePreferredMediaLang(String lang) async {
    await _settingsBox.put(AppConstants.preferredMediaLangKey, lang);
  }

  String getPlayerEngine() {
    return _settingsBox.get(
      AppConstants.playerEngineKey,
      defaultValue: AppConstants.defaultPlayerEngine,
    );
  }

  Future<void> savePlayerEngine(String engineId) async {
    await _settingsBox.put(AppConstants.playerEngineKey, engineId);
  }
  bool get askEngineOnPlay {
    return _settingsBox.get(
          AppConstants.askEngineOnPlayKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setAskEngineOnPlay(bool value) async {
    await _settingsBox.put(AppConstants.askEngineOnPlayKey, value);
  }

  // --- Playback defaults -----------------------------------------------
  //
  // Every default below seeds a control that already existed inside the
  // player. Reads are clamped to the same ranges the in-player controls
  // enforce, so a hand-edited or corrupted box can never push the player into
  // a state its own UI could not produce.

  double getDefaultPlaybackSpeed() {
    final raw = _settingsBox.get(
      AppConstants.defaultPlaybackSpeedKey,
      defaultValue: 1.0,
    );
    final v = raw is num ? raw.toDouble() : 1.0;
    return v.clamp(0.25, 4.0);
  }

  Future<void> saveDefaultPlaybackSpeed(double speed) async {
    await _settingsBox.put(AppConstants.defaultPlaybackSpeedKey, speed);
  }

  /// Stored as the enum's stable name (`contain` / `cover` / `fill`), never its
  /// index — reordering the enum must not silently repoint existing installs.
  String getDefaultPlayerFit() {
    return _settingsBox.get(
      AppConstants.defaultPlayerFitKey,
      defaultValue: 'contain',
    );
  }

  Future<void> saveDefaultPlayerFit(String fit) async {
    await _settingsBox.put(AppConstants.defaultPlayerFitKey, fit);
  }

  /// Defaults to true — auto-advance is what the player has always done, and
  /// this key exists only so it can be turned *off*.
  bool get autoPlayNextEpisode {
    return _settingsBox.get(
          AppConstants.autoPlayNextEpisodeKey,
          defaultValue: true,
        ) ==
        true;
  }

  Future<void> setAutoPlayNextEpisode(bool value) async {
    await _settingsBox.put(AppConstants.autoPlayNextEpisodeKey, value);
  }

  int getDoubleTapSeekSeconds() {
    final raw = _settingsBox.get(
      AppConstants.doubleTapSeekSecondsKey,
      defaultValue: 10,
    );
    final v = raw is num ? raw.toInt() : 10;
    return v.clamp(5, 60);
  }

  Future<void> saveDoubleTapSeekSeconds(int seconds) async {
    await _settingsBox.put(AppConstants.doubleTapSeekSecondsKey, seconds);
  }

  double getLongPressBoost() {
    final raw = _settingsBox.get(
      AppConstants.longPressBoostKey,
      defaultValue: 2.0,
    );
    final v = raw is num ? raw.toDouble() : 2.0;
    return v.clamp(1.25, 4.0);
  }

  Future<void> saveLongPressBoost(double rate) async {
    await _settingsBox.put(AppConstants.longPressBoostKey, rate);
  }

  /// Whether to remind before an episode on the AniList list airs.
  bool get airingRemindersEnabled =>
      _settingsBox.get(AppConstants.airingRemindersKey, defaultValue: false) == true;

  Future<void> setAiringRemindersEnabled(bool value) =>
      _settingsBox.put(AppConstants.airingRemindersKey, value);

  /// How many reminders were scheduled last time, so exactly those can be
  /// cancelled before the next batch.
  int get airingReminderCount {
    final raw = _settingsBox.get(AppConstants.airingReminderCountKey, defaultValue: 0);
    return raw is int && raw >= 0 ? raw : 0;
  }

  Future<void> setAiringReminderCount(int value) =>
      _settingsBox.put(AppConstants.airingReminderCountKey, value < 0 ? 0 : value);

  /// Channels the user pinned to the top of Live TV.
  ///
  /// Ids rather than whole channels: the line-up comes from the server and a
  /// stored copy would go stale the first time a channel is renamed.
  List<String> getLiveTvFavourites() {
    final raw = _settingsBox.get(AppConstants.liveTvFavouritesKey);
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> setLiveTvFavourites(List<String> ids) =>
      _settingsBox.put(AppConstants.liveTvFavouritesKey, ids);

  /// The last channels watched, most recent first.
  ///
  /// Live TV is flipped through rather than browsed — you come back to the same
  /// three or four channels — so where you were last is worth more here than a
  /// catalogue is.
  List<String> getLiveTvRecent() {
    final raw = _settingsBox.get(AppConstants.liveTvRecentKey);
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  /// Bounded: a history of everything ever watched is not a shortcut any more.
  Future<void> pushLiveTvRecent(String id) {
    final ids = [id, ...getLiveTvRecent().where((e) => e != id)].take(12).toList();
    return _settingsBox.put(AppConstants.liveTvRecentKey, ids);
  }

  /// Enough of a channel to draw it without having fetched the page it is on.
  ///
  /// Favourites and recents are ids, and once the line-up is paged there is no
  /// guarantee the page holding a given id was ever loaded — so a pinned
  /// channel would simply vanish from its own shelf. The card is written back
  /// whenever the channel is seen, so it stays close to current, and it is kept
  /// only for the handful of ids that need it.
  Map<String, Map<String, String>> getLiveTvCards() {
    final raw = _settingsBox.get(AppConstants.liveTvCardsKey);
    if (raw is! Map) return {};
    final out = <String, Map<String, String>>{};
    raw.forEach((key, value) {
      if (value is Map) {
        out[key.toString()] = {
          for (final e in value.entries) e.key.toString(): e.value?.toString() ?? '',
        };
      }
    });
    return out;
  }

  Future<void> setLiveTvCards(Map<String, Map<String, String>> cards) =>
      _settingsBox.put(AppConstants.liveTvCardsKey, cards);

  bool get brightnessGestureEnabled {
    return _settingsBox.get(
          AppConstants.brightnessGestureKey,
          defaultValue: true,
        ) ==
        true;
  }

  Future<void> setBrightnessGestureEnabled(bool value) async {
    await _settingsBox.put(AppConstants.brightnessGestureKey, value);
  }

  bool get volumeGestureEnabled {
    return _settingsBox.get(
          AppConstants.volumeGestureKey,
          defaultValue: true,
        ) ==
        true;
  }

  Future<void> setVolumeGestureEnabled(bool value) async {
    await _settingsBox.put(AppConstants.volumeGestureKey, value);
  }

  bool get keepScreenOn {
    return _settingsBox.get(
          AppConstants.keepScreenOnKey,
          defaultValue: true,
        ) ==
        true;
  }

  Future<void> setKeepScreenOn(bool value) async {
    await _settingsBox.put(AppConstants.keepScreenOnKey, value);
  }

  /// In-memory mirror of [AppConstants.telegramPromoSeenKey].
  ///
  /// [setTelegramPromoSeen] is called fire-and-forget from the promo sheet, so
  /// between the call and the Hive flush a second synchronous read would still
  /// see `false` and let another sheet through. Writing the mirror before the
  /// `await` closes that window.
  bool? _telegramPromoSeen;

  bool get hasTelegramPromoSeen {
    return _telegramPromoSeen ??=
        _settingsBox.get(
              AppConstants.telegramPromoSeenKey,
              defaultValue: false,
            ) ==
            true;
  }

  Future<void> setTelegramPromoSeen(bool value) async {
    _telegramPromoSeen = value; // visible to the very next synchronous read
    await _settingsBox.put(AppConstants.telegramPromoSeenKey, value);
  }

  Future<void> markTelegramPromoSeen() => setTelegramPromoSeen(true);

  bool get isAmoledMode {
    return _settingsBox.get(AppConstants.amoledModeKey, defaultValue: false) == true;
  }

  Future<void> setAmoledMode(bool enabled) async {
    await _settingsBox.put(AppConstants.amoledModeKey, enabled);
  }

  /// Accent colour id, or `AppAccent.customId`. Empty ⇒ never chosen, so the
  /// caller falls back to the shipped default rather than to a stored value.
  String get accentId {
    final raw = _settingsBox.get(AppConstants.accentIdKey);
    return raw is String ? raw : '';
  }

  Future<void> setAccentId(String id) async {
    await _settingsBox.put(AppConstants.accentIdKey, id);
  }

  /// The user's own accent as a 32-bit ARGB int, or null if they never picked
  /// one. Anything non-int in the box is treated as absent: a corrupt value
  /// must fall back to a preset, never crash the first paint.
  int? get customAccentArgb {
    final raw = _settingsBox.get(AppConstants.customAccentKey);
    return raw is int ? raw : null;
  }

  Future<void> setCustomAccentArgb(int argb) async {
    await _settingsBox.put(AppConstants.customAccentKey, argb);
  }

  bool get isNavTinted {
    return _settingsBox.get(AppConstants.tintNavKey, defaultValue: true) ==
        true;
  }

  Future<void> setNavTinted(bool enabled) async {
    await _settingsBox.put(AppConstants.tintNavKey, enabled);
  }

  bool get hasOnboardingSeen {
    return _settingsBox.get(AppConstants.onboardingSeenKey, defaultValue: false) == true;
  }

  Future<void> markOnboardingSeen() async {
    await _settingsBox.put(AppConstants.onboardingSeenKey, true);
  }

  bool get hasDeeplinkPromptSeen {
    return _settingsBox.get(
          AppConstants.deeplinkPromptSeenKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> markDeeplinkPromptSeen() async {
    await _settingsBox.put(AppConstants.deeplinkPromptSeenKey, true);
  }

  bool get isDeeplinkOptIn {
    return _settingsBox.get(
          AppConstants.deeplinkOptInKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setDeeplinkOptIn(bool value) async {
    await _settingsBox.put(AppConstants.deeplinkOptInKey, value);
  }

  bool get isAppLockEnabled {
    return _settingsBox.get(
          AppConstants.appLockEnabledKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    await _settingsBox.put(AppConstants.appLockEnabledKey, enabled);
  }

  int get appLockPinLength {
    final v = _settingsBox.get(AppConstants.appLockPinLengthKey, defaultValue: 4);
    return (v is int && (v == 4 || v == 6)) ? v : 4;
  }

  Future<void> setAppLockPinLength(int length) async {
    await _settingsBox.put(AppConstants.appLockPinLengthKey, length);
  }

  bool get isAppLockBiometricEnabled {
    return _settingsBox.get(
          AppConstants.appLockBiometricKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setAppLockBiometricEnabled(bool enabled) async {
    await _settingsBox.put(AppConstants.appLockBiometricKey, enabled);
  }


  bool get useNativeTitleBar =>
      _settingsBox.get('use_native_title_bar', defaultValue: false) == true;

  Future<void> setUseNativeTitleBar(bool value) =>
      _settingsBox.put('use_native_title_bar', value);

  // Mobile bottom-nav style: 'solid' | 'glass' | 'classic' (default 'solid').
  String get navStyle {
    final v = _settingsBox.get('nav_style', defaultValue: 'solid');
    return v is String ? v : 'solid';
  }

  Future<void> setNavStyle(String value) =>
      _settingsBox.put('nav_style', value);

  // Bottom-nav tab set + order (list of TabId.name). Absent ⇒ current shipped
  // 5 tabs ⇒ existing users see an identical bar (back-compat).
  List<String> get tabOrder {
    final v = _settingsBox.get('tab_order');
    if (v is List) return v.map((e) => e.toString()).toList();
    return const ['home', 'search', 'shorts', 'myList', 'profile'];
  }

  Future<void> setTabOrder(List<String> ids) =>
      _settingsBox.put('tab_order', ids);


  bool get hasSeenPrivateShowcase =>
      _settingsBox.get('private_showcase_seen', defaultValue: false) == true;

  Future<void> markPrivateShowcaseSeen() async =>
      _settingsBox.put('private_showcase_seen', true);

  bool get isPrivateAlwaysAsk =>
      _settingsBox.get('private_always_ask', defaultValue: false) == true;

  Future<void> setPrivateAlwaysAsk(bool value) async =>
      _settingsBox.put('private_always_ask', value);

  /// Whether adult manga sources are shown. Off unless the user opts in, and
  /// read by both the manga sources list and [ProviderBloc] — the picker builds
  /// its manga entries from the same plugin list, so a source hidden in one
  /// place has to be hidden in the other or the opt-out means nothing.
  bool get showNsfwMangaSources {
    return _settingsBox.get(
          AppConstants.showNsfwMangaSourcesKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setShowNsfwMangaSources(bool enabled) async {
    await _settingsBox.put(AppConstants.showNsfwMangaSourcesKey, enabled);
  }

  String getReaderMode(String contentUrl) {
    return _settingsBox.get('reader_mode::$contentUrl', defaultValue: 'vertical');
  }

  Future<void> saveReaderMode(String contentUrl, String mode) async {
    await _settingsBox.put('reader_mode::$contentUrl', mode);
  }

  bool getReaderRtl(String contentUrl) {
    return _settingsBox.get('reader_rtl::$contentUrl', defaultValue: false) == true;
  }

  Future<void> saveReaderRtl(String contentUrl, bool rtl) async {
    await _settingsBox.put('reader_rtl::$contentUrl', rtl);
  }

  String getReaderBackground() {
    return _settingsBox.get('reader_bg', defaultValue: 'black');
  }

  Future<void> saveReaderBackground(String bg) async {
    await _settingsBox.put('reader_bg', bg);
  }

  /// Whether to translate a subtitle on play when the source has none in the
  /// chosen language. Off by default — it spends a shared, capped budget.
  bool getSubtitleAutoTranslate() {
    return _settingsBox.get(
          AppConstants.subtitleAutoTranslateKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setSubtitleAutoTranslate(bool value) async {
    await _settingsBox.put(AppConstants.subtitleAutoTranslateKey, value);
  }

  /// Target language for subtitle translation. Falls back to the app language,
  /// which is the one the person already reads the interface in.
  String getSubtitleTranslateLang() {
    final saved = _settingsBox.get(AppConstants.subtitleTranslateLangKey);
    if (saved is String && saved.isNotEmpty) return saved;
    return getLanguage();
  }

  Future<void> setSubtitleTranslateLang(String lang) async {
    await _settingsBox.put(AppConstants.subtitleTranslateLangKey, lang.trim());
  }

  SubtitleStyle getSubtitleStyle() {
    final raw = _settingsBox.get(AppConstants.subtitleStyleKey);
    if (raw is String && raw.isNotEmpty) {
      return SubtitleStyle.fromJsonString(raw);
    }
    return SubtitleStyle.defaults();
  }

  Future<void> saveSubtitleStyle(SubtitleStyle style) async {
    await _settingsBox.put(
      AppConstants.subtitleStyleKey,
      style.toJsonString(),
    );
  }

  /// Subtitle sync is tuned per title+episode: a shift that fixes episode 1 is
  /// usually wrong for episode 2, and it used to live in a bare ValueNotifier
  /// that reset to zero every time the player opened.
  int getSubtitleOffsetMs(String key) {
    final raw = _settingsBox.get('sub_offset::$key');
    return raw is int ? raw : 0;
  }

  Future<void> saveSubtitleOffsetMs(String key, int ms) async {
    if (ms == 0) {
      await _settingsBox.delete('sub_offset::$key');
      return;
    }
    await _settingsBox.put('sub_offset::$key', ms);
  }

  /// Frame-rate conversion factor for the active subtitle (1.0 = off).
  double getSubtitleRate(String key) {
    final raw = _settingsBox.get('sub_rate::$key');
    if (raw is num && raw > 0) return raw.toDouble();
    return 1.0;
  }

  Future<void> saveSubtitleRate(String key, double rate) async {
    if ((rate - 1.0).abs() < 0.00001) {
      await _settingsBox.delete('sub_rate::$key');
      return;
    }
    await _settingsBox.put('sub_rate::$key', rate);
  }
}
