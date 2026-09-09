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

  /// Which kind of catalogue the app is showing — video, manga or novel.
  /// Absent ⇒ video, which is what every install had before modes existed.
  static const String contentModeKey = 'content_mode';

  /// Which bands the home screen shows, and in what order. See [HomeRail].
  static const String homeRailOrderKey = 'home_rail_order';
  static const String homeRailHiddenKey = 'home_rail_hidden';

  /// Accumulated watch time and completions. See [WatchStatsStore] — it cannot
  /// be derived from history, which is a rolling fifty-item window.
  static const String watchStatsKey = 'watch_stats';

  /// When this device last wrote a backup file. Device-local on purpose — it
  /// answers "have I backed this phone up", so a value carried in from another
  /// phone's backup would be a lie. Excluded from the backup for that reason.
  static const String lastBackupAtKey = 'backup_last_export_at';

  /// Hold downloads until the device is on Wi-Fi. Off by default, because a
  /// download that silently does not start is worse than one that costs data
  /// somebody chose to spend.
  static const String downloadWifiOnlyKey = 'download_wifi_only';

  /// Which volume downloads are kept on.
  ///
  /// Holds the VOLUME's base path, not the downloads folder itself, so the
  /// layout under it stays the app's business. Absent ⇒ the app's own
  /// directory, which is where every install has always kept them.
  ///
  /// Checked rather than trusted on read: an SD card can be removed, and a
  /// stored path that no longer exists must fall back rather than leave the
  /// feature unable to start.
  static const String downloadLocationKey = 'download_location';

  /// Pair pages in landscape. Off by default: a spread is right for comics
  /// drawn as spreads and wrong for a webtoon, and the app cannot tell which
  /// it is holding.
  static const String readerSpreadKey = 'reader_spread';
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
  /// [defaultPlayerEngine].
  ///
  /// Read through `resolvePlayerEngine()` — never trust this raw value, it only
  /// applies on Android (desktop is always media_kit, iOS always video_player).
  /// Whether the user has accepted the BitTorrent privacy warning.
  ///
  /// Persisted, deliberately. CloudStream keeps this per session and its own
  /// error string tells a user who declined once to "restart app and accept the
  /// pop-up" — a dead end reachable by one mis-tap. Storing the answer means
  /// declining is recoverable from Settings and accepting is not re-asked every
  /// launch. Absent ⇒ not accepted, so the warning is always shown at least
  /// once.
  static const String torrentConsentKey = 'torrent_consent';

  /// Tracker ids the torrent search queries, as a comma-separated list.
  /// Absent ⇒ every non-adult tracker.
  static const String torrentIndexersKey = 'torrent_indexers';

  static const String playerEngineKey = 'player_engine';

  /// The picture profile, by [ColorProfile.id]. Absent ⇒ natural, which is the
  /// untouched picture — so an existing install sees no change at all.
  static const String colorProfileKey = 'player_color_profile';

  /// Per-title playback choices — the audio language and server somebody picked
  /// for one show, which must not be overwritten by what they picked for
  /// another. See [TitlePrefsStore].
  static const String titlePrefsKey = 'title_prefs';

  /// Anime4K preset and GPU tier. Absent ⇒ off, so nothing is downloaded and
  /// nothing runs until somebody asks for it.
  static const String shaderPresetKey = 'player_shader_preset';
  static const String shaderTierKey = 'player_shader_tier';

  /// The engine used when the setting has never been touched.
  ///
  /// libmpv, not ExoPlayer. The platform player cannot switch audio tracks at
  /// all — the API does not expose them — and a dual-audio release is the norm
  /// in this catalogue, so the shipped default was the one engine that could
  /// not play half of what the app finds. It also refuses containers and
  /// subtitle formats these sources hand out routinely.
  ///
  /// Only ever reached by an install with no stored value: someone who chose
  /// the system player keeps it, because a stored id wins over this constant.
  static const String defaultPlayerEngine = 'media_kit';
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

  /// Whether the detail header plays a title's trailer by itself.
  ///
  /// A preview is a video that starts without being asked for, on a screen
  /// somebody opened to read about a film — worth having on by default,
  /// worth being able to turn off. It also costs mobile data nobody agreed
  /// to spend.
  static const String heroTrailerAutoplayKey = 'hero_trailer_autoplay';

  /// Whether what somebody is watching is published to their Discord profile.
  ///
  /// Off by default and stays off until switched on: this is the one setting
  /// in the app that makes something private visible to other people.
  static const String discordPresenceKey = 'discord_presence_enabled';
  static const String volumeGestureKey = 'volume_gesture';

  /// Explicit on/off per player-info row, as `{fieldId: bool}`. Explicit rather
  /// than a list of enabled ids so a row added in a later release can be told
  /// apart from one the viewer switched off — see `PlayerInfoFields.fromStored`.
  static const String playerInfoFieldsKey = 'player_info_fields';

  /// The player bar arrangement, as `{slotName: [controlId, ...]}`.
  static const String playerControlsLayoutKey = 'player_controls_layout';
  static const String keepScreenOnKey = 'keep_screen_on';

  /// Incognito: watch without leaving a record of *what* was watched.
  static const String incognitoKey = 'incognito_mode';

  /// Skip anime openings/endings without being asked each time.
  static const String autoSkipIntroKey = 'auto_skip_intro';

  /// Last app version whose features the viewer has been shown. Empty on a
  /// fresh install until [WhatsNew.init] stamps it.
  static const String whatsNewVersionKey = 'whats_new_version';

  /// Feature ids the viewer has already opened.
  static const String whatsNewSeenKey = 'whats_new_seen';

  static const String streakBox = 'streak_box';
  static const String streakStateKey = 'streak_state';
}
