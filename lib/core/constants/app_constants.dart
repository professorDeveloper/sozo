import 'dart:convert';

class AppConstants {
  AppConstants._();

  static String? _baseUrl;
  static String get baseUrl => _baseUrl ??= _decode(_obf);

  static const String _obf = 'G0QuQCxKHkE+G1oKMEMJHAAlF1wcRnRdOl9QHjY=';

  static String _decode(String payload) {
    final key = utf8.encode(
      String.fromCharCodes('1v_a2f9_y3k_n1p_0Z0s'.codeUnits.reversed),
    );
    final bytes = base64.decode(payload);
    return utf8.decode(
      List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]),
    );
  }

  /// Origin (scheme + host + port) for the socket.io connection. [baseUrl] ends
  /// with `/api`, but the `/watch` namespace lives at the host root — strip the
  /// path so socket handshakes resolve against the origin.
  static String get socketOrigin => Uri.parse(baseUrl).origin;

  static const String authBox = 'auth_box';
  static const String settingsBox = 'settings_box';
  static const String historyBox = 'history_box';
  static const String downloadBox = 'download_box';
  static const String productsBox = 'products_box';
  static const String cartBox = 'cart_box';
  static const String extractorsBox = 'extractors_box';
  static const String favoritesBox = 'favorites_box';
  static const String privateFavoritesBox = 'private_favorites_box';

  /// Offline cache for the user-curated lists (`Watch Later` / `Watched`).
  /// One box, keyed by list slug — the lists share a shape, so they share a box.
  static const String userListsBox = 'user_lists_box';

  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user';
  static const String themeModeKey = 'theme_mode';
  static const String languageKey = 'language';
  static const String currentProviderKey = 'current_provider';
  static const String liveTvFavouritesKey = 'live_tv_favourites';
  static const String liveTvRecentKey = 'live_tv_recent';
  static const String liveTvCardsKey = 'live_tv_cards';
  static const String airingRemindersKey = 'anilist_airing_reminders';
  static const String airingReminderCountKey = 'anilist_airing_reminder_count';

  /// Provider used until the real list arrives and ProviderBloc persists a
  /// choice. Without it a fresh install races: HomeBloc reads the current
  /// provider before the list has loaded, sends an empty id, and every content
  /// request comes back 400 `Unknown provider ""` — so a brand-new user sees a
  /// broken home screen. Must stay a valid server provider id.
  static const String defaultProviderId = 'vidapi';
  static const String preOutageProviderKey = 'pre_outage_provider';
  static const String cachedProvidersKey = 'cached_providers';
  static const String cachedProvidersAtKey = 'cached_providers_at';
  static const String shortsRefreshShowcaseSeenKey =
      'shorts_refresh_showcase_seen';
  static const String aniListTokenKey = 'anilist_token';
  static const String aniListViewerKey = 'anilist_viewer';

  /// Local title -> AniList media id map. Lives in the SETTINGS box, not the
  /// auth box: it survives a token refresh and is cleared explicitly on
  /// sign-out rather than incidentally.
  static const String aniListLinksKey = 'anilist_links';

  /// Unlinks not yet accepted by the account. Kept separate so clearing the
  /// map never silently drops a pending removal.
  static const String aniListLinkTombstonesKey = 'anilist_link_tombstones';
  static const String malTokenKey = 'mal_token';
  static const String malViewerKey = 'mal_viewer';

  /// Local title -> MAL anime id map. Lives in the SETTINGS box for the same
  /// reason [aniListLinksKey] does: it survives a token refresh and is cleared
  /// explicitly on sign-out rather than incidentally.
  ///
  /// Kept SEPARATE from the AniList map even though most rows are created from
  /// the same match. Each tracker's links die with that tracker's connection,
  /// and one shared map would take the other's associations down with it.
  static const String malLinksKey = 'mal_links';
  static const String malLinkTombstonesKey = 'mal_link_tombstones';
  static const String preferredMediaLangKey = 'preferred_media_lang';
  static const String defaultMediaLang = 'sub';

  /// Playback engine the user picked in Settings → Player. Absent ⇒
  /// [defaultPlayerEngine], i.e. exactly the engine the app has always used, so
  /// an existing install that never opens the setting is bit-for-bit unchanged.
  /// Read through `resolvePlayerEngine()` — never trust this raw value, it only
  /// applies on Android (desktop is always media_kit, iOS always video_player).
  static const String playerEngineKey = 'player_engine';
  static const String defaultPlayerEngine = 'default';
  static const String telegramPromoSeenKey = 'telegram_promo_seen';
  /// Appearance → "Pure black". Absent ⇒ off, i.e. the greys the app has
  /// always shipped.
  static const String amoledModeKey = 'amoled_mode';

  /// Appearance → accent colour. Holds an [AppAccent] preset id, or
  /// `AppAccent.customId` when the user picked their own colour — in which case
  /// the colour itself lives under [customAccentKey]. Absent ⇒ the default red.
  static const String accentIdKey = 'accent_id';

  /// The user's own accent, stored as a 32-bit ARGB int. Only consulted when
  /// [accentIdKey] is `AppAccent.customId`.
  static const String customAccentKey = 'custom_accent';

  /// Appearance → "Colour the tab bar". Absent ⇒ **on**: the accent is a
  /// setting people choose in order to see it, and the tab bar is the one piece
  /// of chrome that is on screen the whole time. Turning it off puts the
  /// original white pill back.
  static const String tintNavKey = 'tint_nav';
  static const String onboardingSeenKey = 'onboarding_seen';
  static const String deeplinkPromptSeenKey = 'deeplink_prompt_seen';
  static const String deeplinkOptInKey = 'deeplink_opt_in';
  static const String openSubtitlesKeyKey = 'opensubtitles_api_key';

  /// Opt-in for adult manga sources. Absent ⇒ off, so a fresh install never
  /// surfaces an 18+ source until the user asks for it.
  static const String showNsfwMangaSourcesKey = 'show_nsfw_manga_sources';

  static const String appLockEnabledKey = 'app_lock_enabled';
  static const String appLockPinLengthKey = 'app_lock_pin_length';
  static const String appLockBiometricKey = 'app_lock_biometric';

  static const String appLockPinHashSecureKey = 'app_lock_pin_hash';
  static const String appLockPinSaltSecureKey = 'app_lock_pin_salt';

  static const String subtitleStyleKey = 'subtitle_style';
  static const String subtitleAutoTranslateKey = 'subtitle_auto_translate';
  static const String subtitleTranslateLangKey = 'subtitle_translate_lang';

  /// Ask which engine to use every time playback starts, instead of silently
  /// using [playerEngineKey]. Absent ⇒ off, so an existing install keeps the
  /// zero-prompt behaviour it already had; the picker is opt-in from
  /// Settings → Player, or from the "don't ask again" checkbox in the sheet
  /// itself (which writes `false` back here).
  static const String askEngineOnPlayKey = 'ask_engine_on_play';

  /// Playback defaults applied at player start. Each one mirrors a control that
  /// already existed inside the fullscreen player and was previously reset on
  /// every open; the stored value only seeds the initial state, so changing it
  /// mid-playback still works exactly as before.
  static const String defaultPlaybackSpeedKey = 'default_playback_speed';
  static const String defaultPlayerFitKey = 'default_player_fit';
  static const String autoPlayNextEpisodeKey = 'auto_play_next_episode';
  static const String doubleTapSeekSecondsKey = 'double_tap_seek_seconds';
  static const String longPressBoostKey = 'long_press_boost';
  static const String brightnessGestureKey = 'brightness_gesture';
  static const String volumeGestureKey = 'volume_gesture';
  static const String keepScreenOnKey = 'keep_screen_on';

  static const String streakBox = 'streak_box';
  static const String streakStateKey = 'streak_state';
}
