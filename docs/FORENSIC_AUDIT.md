# KAIZOKU — FORENSIC AUDIT DOCUMENTATION

> **Project Identity:** Kaizoku (Transforming local reference implementation `Sozo`)  
> **Repository Workspace:** `d:/sandcat2.0/sozo`  
> **Audit Date:** September 2026  
> **Reference Architecture:** Clean Architecture (Domain, Data, Presentation) + BLoC + GetIt + Hive + MethodChannels + Multi-backend Playback

---

## 1. ARCHITECTURAL TOPOLOGY & ENTRY POINTS

### 1.1 Entry Points by Platform
* **Dart / Flutter Framework Entry Point:** `lib/main.dart`
  - Initializes `WidgetsFlutterBinding`.
  - Platform detection: `initTvPlatform()` resolves TV status via `soplay/platform`.
  - Desktop initialization: Initializes `MediaKit` (libmpv) and `windowManager` (frameless title bar, minimum size 800x560).
  - Shader pre-warming: Initializes `LiquidGlassWidgets` if `usesFlutterGlass` is true (mobile non-iOS26).
  - Environment initialization: Loads `.env` via `flutter_dotenv`.
  - Async parallel startup: `EasyLocalization`, `_initHive()` (opens 9 Hive boxes), `initSozoUserAgent()` (aligns WebView User-Agent for Cloudflare challenge passing).
  - Service bootstrap: `WhatsNew.init()`, `_initFirebaseSafely()` (Crashlytics/Analytics on Android), `configureDependencies()` (GetIt DI graph).
  - Background asynchronous tasks (off-critical path):
    - `Analytics.start()`
    - `DownloadRepository.initialize()` & `resumeInterrupted()` (walks downloads folder, verifies integrity)
    - `ProviderRegistry.preload()`
    - `NotificationService.setup()` (FCM & local notifications)
    - `DeeplinkService.start()`
    - `_restoreAnilistAndReminders()` (AniList & MyAnimeList session & schedule sync)
    - `RepoFileImport.start()` (listens for shared `.pb`/`.json` extension bundles)
  - Post-frame callbacks: `JsRuntimeService.ensureReady()`, `warmUpPlayerEngine()`.
* **Android Native Entry Point:** `android/app/src/main/kotlin/com/soplay/sozo/MainActivity.kt`
  - Extends `FlutterFragmentActivity` (required for biometric authentication).
  - Implements PiP controller (`soplay/pip`), system controls (`soplay/system_controls`), download transfer exporter (`soplay/downloads`), platform queries (`soplay/platform`), deep link settings (`soplay/deeplink_settings`).
  - Native runtime hosts:
    - `PluginHost` & `RepoManager` (CloudStream 3 `.cs3` provider plugins via DexClassLoader + `CloudflareKiller`)
    - `AniyomiHost` & `AniyomiRepoManager` (Aniyomi anime source APKs via DexClassLoader + QuickJS bridge)
    - `MangaHost` & `MangaRepoManager` (Mihon/Tachiyomi/Keiyoushi manga source APKs via DexClassLoader)
    - `TorrentServerBridge` (embedded Go `torrentserver` via gomobile, port 8090)
    - `BridgeServer` (NanoHTTPD HTTP server on port 8088 to expose mobile extension hosts to desktop clients)
    - `FramePreview` (FFmpeg-based on-the-fly video frame extraction for player seek scrub previews)
    - `DrmPlayerHost` (Media3 ExoPlayer texture rendering for CENC Widevine/ClearKey DRM streams)
* **Android Background Service:** `android/app/src/main/kotlin/com/soplay/sozo/DownloadForegroundService.kt`
  - Foreground service with notification management, chunked download workers, paused/resumed state handling, wakelock acquisition, and network failover.
* **Windows Native Entry Point:** `windows/runner/main.cpp` & `Runner.rc`
  - Win32 C++ application initializes COM, parses command line, creates `FlutterWindow(L"Sozo", 1280, 720)`.
  - Multi-media libmpv dynamic link libraries (`media_kit_libs_windows_video`).
* **Linux Native Entry Point:** `linux/runner/my_application.cc` & `CMakeLists.txt`
  - GTK+ 3.0 desktop application with dark theme preference enforcement, GNOME header bar decoration (`Sozo`), Wayland/X11 compatibility.
* **macOS Native Entry Point:** `macos/Runner/MainFlutterWindow.swift` & `AppInfo.xcconfig`
  - Cocoa application window setup with standard title bar integration and full-size content view.
* **iOS Native Entry Point:** `ios/Runner/AppDelegate.swift` & `Info.plist`
  - FlutterAppDelegate with Google Cast Bonjour service registration (`_googlecast._tcp`), Universal Links, and photo/camera permission descriptions.

---

## 2. STATE MANAGEMENT & DATA FLOW

### 2.1 BLoC Layer (`flutter_bloc: ^9.1.0`)
All complex business logic is encapsulated in unidirectional BLoCs:
1. **AuthBloc:** Session lifecycle, user profile, token expiration, sign-out cache cleanup.
2. **HomeBloc & ViewAllBloc:** Home screen rail generation, catalogue status, pagination, caching.
3. **SearchBloc:** Multi-query search, live autocomplete, genre filtering, source scoping.
4. **DetailBloc, EpisodesBloc, FavoriteBloc:** Title details, episode windowing, bookmarking.
5. **ProviderBloc:** Active provider selection, plugin discovery, probe health status.
6. **BannersBloc:** Dynamic promotional and feature hero banners.
7. **CommentsBloc:** Discussion threads, replies, and reactions.
8. **NotificationsBloc:** System, administrative, and broadcast push notifications.
9. **ShortsBloc:** Vertical video feed, autoplay state, like/view counting.
10. **Trivia Hub, Game, Challenge, Leaderboard, TopFans, Cast Blocs:** Actor trivia and interactive gaming.
11. **LinkTvBloc:** 6-digit pairing code generation and polling for TV-to-mobile sync.

### 2.2 Notifiers & Streams
* **ThemeController (`ChangeNotifier`):** Synchronously installs palette, notifies `MyApp` to mark the element tree dirty for live ~1900 `AppColors` getter updates.
* **NavController (`ChangeNotifier`):** Tab routing and badge indicators.
* **DesktopWindow (`ValueNotifier`):** Custom frameless window controls and immersive full-bleed routes (`/player`, `/reader`).
* **Download Repository Transfers (`Stream<DownloadProgress>`):** Emits byte counts, percentage, download speed, and state transitions.

---

## 3. NETWORKING, SECURITY & API CLIENTS

### 3.1 HTTP Client (`dio: ^5.8.0+1`)
* **Base Client:** `DioClient` with persistent cookie store (`cookie_jar`, `dio_cookie_manager`).
* **Backend Origin:** `https://apisozo.azamov.me/api` (Obfuscated XOR key decode in `AppConstants._decode`).
* **Interceptors:**
  1. `AuthInterceptor`: Attaches `Authorization: Bearer <token>`, intercepts 401s to trigger `TokenRefresher`.
  2. `TokenRefresher`: Mutex-locked refresh token rotation against `/auth/refresh`.
  3. `CfBypassInterceptor`: Detects Cloudflare challenge responses (403/503), invokes `CloudflareSolver` (hidden WebView) to obtain clearance cookies and `cf_clearance`.
  4. `ProviderInterceptor`: Adds active provider header `X-Provider-Id: <id>`.
  5. `LoggingInterceptor`: Pretty-prints requests and responses in debug mode.
  6. `NoInternetInterceptor`: Intercepts socket/DNS failures and redirects to `/no-internet` if critical.

### 3.2 Real-time Sockets
* **Socket.io (`socket_io_client: ^3.1.6`):**
  - Origin: `https://apisozo.azamov.me`
  - Namespace: `/watch` for WatchParty synchronized playback (seek, play, pause, room chat).
* **Discord Gateway Client (`web_socket_channel`):**
  - Direct Discord Gateway connection on mobile for Rich Presence without local IPC sockets.
  - Local Discord IPC Named Pipes on Windows (`\\pipe\\discord-ipc-0`) and Unix sockets on Linux/macOS.

---

## 4. PERSISTENCE & LOCAL STORAGE ARCHITECTURE

### 4.1 Hive Storage (`hive_flutter: ^1.1.0`)
Nine persistent boxes opened on startup:
1. `auth_box`: Access token, refresh token, serialized user profile entity.
2. `settings_box`: App theme, accent color, AMOLED mode, language, nav style, active provider, subtitle preferences, player engine preference, AniList/MAL tokens and mapping links.
3. `history_box`: Rolling window of last 50 watched media items with resume timestamps and total duration.
4. `download_box`: Downloaded items metadata, relative disk paths, media kind, download status, file sizes.
5. `extractors_box`: Cached JavaScript extractors and remote provider bundles.
6. `streak_box`: Watch streak counters, last active date, weekly activity maps.
7. `favorites_box`: Local bookmarked titles, sync timestamp.
8. `user_lists_box`: Curated lists ("Watch Later", "Watched") cached offline.
9. `private_favorites_box`: Secret bookmarks hidden behind App Lock PIN/biometric authentication.

### 4.2 Secure Storage (`flutter_secure_storage: ^9.2.2`)
* `app_lock_pin_hash`: PBKDF2 / SHA-256 hashed PIN.
* `app_lock_pin_salt`: Cryptographic salt for PIN verification.

---

## 5. PLAYBACK ARCHITECTURE

### 5.1 Multi-Engine Abstraction (`PlayerController`)
The app features a unified `PlayerController` abstract interface:
1. **Native Engine (`_NativeController`):**
   - Uses `video_player` (ExoPlayer on Android, AVPlayer on iOS).
   - Handles standard HLS and progressive MP4/MKV.
2. **Desktop / MediaKit Engine (`_MediaKitController`):**
   - Uses `media_kit` (libmpv).
   - Mandatory on Windows, Linux, macOS.
   - User-selectable on Android for multi-audio track switching and complex ASS/SSA subtitles.
3. **DRM Media3 Engine (`DrmController`):**
   - Android-specific native ExoPlayer driving `DrmPlayerHost.kt`.
   - Supports CENC Widevine/ClearKey DASH and HLS streams. Renders directly to Flutter SurfaceTexture.
4. **External Player Handoff (`ExternalPlayer`):**
   - Hands stream URL and headers to VLC, MPV, Nova, or MX Player via Android Intents.

### 5.2 Advanced Playback Subsystems
* **Local HLS Proxy (`LocalHlsProxy`):** Local HTTP server proxying m3u8 playlists to rewrite segment headers, bypass referer/origin checks, and decrypt TS segments.
* **Source Ladder (`SourceLadder`):** Auto-recovers failed streams by stepping down resolution or switching server mirrors.
* **Video Shaders (`ShaderPresets`):** Anime4K GLSL post-processing shader pipelines (High, Medium, Low GPU tiers).
* **Color Profiles (`ColorProfile`):** Natural, AMOLED high-contrast, Vivid, Cinema.
* **Frame Preview (`FramePreviewService`):** Seek scrubbing thumbnail strip generator.
* **Cast Controller (`CastController`):** Google Cast protocol client via `dart_cast` with state synchronization.

---

## 6. DOWNLOADS & OFFLINE ARCHITECTURE

### 6.1 Core Principles
* **Disk-Guaranteed Invariant:** A row marked `completed` in Hive MUST have an intact physical file on disk. On every application boot, `verifyAll()` sweeps the storage folder and demotes missing files to `missing`.
* **Relative Path Storage:** Files are stored relative to application storage containers so Android backups/restores or multi-profile switches do not invalidate file references.
* **Two Transfer Engines:**
  - `DownloadNativeDataSource`: Delegates transfers to Android `DownloadForegroundService` with foreground notification, network pause/resume, and system battery optimizations.
  - `DownloadTransferDataSource`: Uses Dio chunked streaming for desktop and iOS environments.
* **Media Kinds:** Supports Video (MP4/TS/MKV), Manga (zipped chapter CBZ / image sets), and Light Novels (HTML/TXT/ePub).

---

## 7. CONTENT & EXTENSIONS ECOSYSTEM

### 7.1 Multi-Catalogue Engine
The app supports 3 primary content modes (`ContentMode`):
1. **Video:** Movies, TV series, anime, live streams, torrent streams.
2. **Manga:** Japanese manga, Korean manhwa, Chinese manhua, western comics.
3. **Novel:** Web novels, light novels with customizable typography and reader theme.

### 7.2 Source Provider Ecosystem
* **Built-in / JS Providers:** Driven by `JsRuntimeService` (QuickJS) executing JavaScript scrapers and extractors.
* **CloudStream 3 Providers (.cs3):** Executed via `PluginHost.kt` leveraging Dalvik/ART DexClassLoader.
* **Aniyomi Anime Extensions (.apk):** Executed via `AniyomiHost.kt`.
* **Mihon / Keiyoushi Manga Extensions (.apk):** Executed via `MangaHost.kt`.
* **Desktop Extension Bridge (`BridgeServer`):** Desktop clients on same Wi-Fi can connect to Android phone via HTTP bridge (`soplay/bridge`) to fetch extension streams.
* **Torrent Engine (`TorrentServerBridge`):** Embedded Go TorrServer instance streaming torrents directly to HTTP localhost port `8090` with magnet URL parsing and peer health tracking.

---

## 8. DEEP LINKS & INTEGRATIONS

### 8.1 URL Schemes and Handlers
* Custom Scheme: `sozo://`
  - `sozo://detail?url=<url>&provider=<id>`
  - `sozo://play?url=<url>&title=<title>`
  - `sozo://watch-party?code=<code>`
* Universal Links & App Links: `https://sozo.azamov.me/detail`
* Extension Repo Files: Automatically claims `.pb`, `index.min.json`, `repo.json` when clicked in browsers or chats.

### 8.2 External Trackers
* **AniList:** OAuth login, GraphQL synchronization, airing calendar with local notifications (`AiringReminders`).
* **MyAnimeList:** OAuth PKCE login, REST API synchronization, tracking status updates.
* **Discord RPC:** Presence reporting current title, episode, duration, and poster artwork.
* **OpenSubtitles:** REST API subtitle search and download.
* **YouTubeExplode:** Direct YouTube trailer stream resolution without iframe or webview overhead.

---

## 9. COMPLETE UI & SCREEN INVENTORY

| Screen / Component | Route / Path | Implementation File | Key Features |
|---|---|---|---|
| **Splash Screen** | `/splash` | `features/splash/presentation/pages/splash_page.dart` | Animated brand mark, auth token validation, startup gate |
| **Onboarding** | `/onboarding` | `features/onboarding/presentation/pages/onboarding_page.dart` | Welcome carousel, source opt-in, feature overview |
| **Main Shell** | `/main` | `features/main/presentation/pages/main_page.dart` | Adaptive bottom bar / desktop rail / TV 10-foot rail |
| **Home Page** | Tab: `home` | `features/home/presentation/pages/home_page.dart` | Hero carousel, continue watching, dynamic genre rails |
| **Home View All** | `/view-all` | `features/home/presentation/pages/home_view_all_page.dart` | Paginated grid view for a specific category/genre |
| **Search Page** | Tab: `search` | `features/search/presentation/pages/search_page.dart` | Live query suggestions, genre chips, source switcher |
| **Cross Search** | `/cross-search` | `features/search/presentation/pages/cross_search_page.dart` | Multi-provider parallel search with health indicators |
| **Torrent Search** | `/torrents` | `features/torrent/presentation/pages/torrent_search_page.dart` | Nyaa/TokyoToshokan RSS + HTML torrent scraper |
| **Shorts Feed** | Tab: `shorts` | `features/shorts/presentation/pages/shorts_page.dart` | TikTok/Reels style vertical video feed with like/share |
| **My List** | Tab: `myList` | `features/my_list/presentation/pages/my_list_page.dart` | Favorites tab, Continue Watching, Watch Later |
| **User Curated Lists** | `/my-lists` | `features/user_lists/presentation/pages/user_lists_page.dart` | Watch Later, Watched history collections |
| **Private List** | `/private-list` | `features/private_list/presentation/pages/private_list_page.dart` | PIN/Biometric guarded private bookmark storage |
| **History Page** | `/history` | `features/history/presentation/pages/history_page.dart` | Full chronological watch history with progress bar |
| **Downloads Page** | `/downloads` | `features/download/presentation/pages/downloads_page.dart` | Offline storage manager, progress indicators, storage stats |
| **Detail Page** | `/detail` | `features/detail/presentation/pages/detail_page.dart` | Hero poster, overview, cast, episodes, comments, trailer |
| **Episodes Page** | `/episodes` | `features/detail/presentation/pages/episodes_page.dart` | Grid/list episode picker with windowing & provider selection |
| **Actor Details** | `/actor` | `features/detail/presentation/pages/actor_page.dart` | Actor biography, filmography, trivia links |
| **Player Page** | `/player` | `features/detail/presentation/pages/player_page.dart` | Fullscreen video player, seek scrub, audio/subs, Anime4K |
| **Manga Reader** | `/reader` | `features/manga/presentation/pages/reader_page.dart` | Continuous vertical scroll / webtoon mode / spread slots |
| **Live TV** | `/live-tv` | `features/live_tv/presentation/pages/live_tv_page.dart` | IPTV channels with EPG program schedule, DRM playback |
| **TV Remote** | `/tv-remote` | `features/remote/presentation/pages/tv_remote_page.dart` | Virtual D-pad controller to control paired TV instances |
| **Watch Party** | `/watch-party` | `features/watch_party/presentation/pages/watch_party_page.dart` | Room code join, host session, synced playback, live chat |
| **Link TV** | `/link-tv` | `features/link_tv/presentation/pages/link_tv_page.dart` | QR code scanner / 6-digit PIN TV authorization |
| **Desktop Share** | `/desktop-share` | `features/desktop_share/presentation/pages/desktop_share_page.dart` | Wi-Fi bridge activation instructions & server status |
| **Following** | `/following` | `features/tracker/presentation/pages/following_page.dart` | Followed anime/manga releases with status indicators |
| **AniList Library** | `/anilist` | `features/anilist/presentation/pages/anilist_library_page.dart` | Current watching, planning, completed anime synced |
| **AniList Browse** | `/anilist/browse` | `features/anilist/presentation/pages/anilist_browse_page.dart` | Seasonal charts, trending anime, top rated |
| **Airing Calendar** | `/anilist/calendar` | `features/anilist/presentation/pages/airing_calendar_page.dart` | Episode release countdown calendar & reminders |
| **AniList Links** | `/anilist/links` | `features/anilist/presentation/pages/anilist_links_page.dart` | Manage associations between local titles and AniList IDs |
| **MAL Library** | `/mal` | `features/mal/presentation/pages/mal_library_page.dart` | MyAnimeList user lists and tracking status |
| **MAL Links** | `/mal/links` | `features/mal/presentation/pages/mal_links_page.dart` | Manage associations between local titles and MAL IDs |
| **Connections** | `/connections` | `features/anilist/presentation/pages/connections_page.dart` | AniList / MyAnimeList account connection hub |
| **Trivia Hub** | Tab: `buff` | `features/trivia/presentation/pages/buff_hub_page.dart` | Cinema Buff trivia center, daily challenges, stats |
| **Trivia Game** | `/trivia/game` | `features/trivia/presentation/pages/game_page.dart` | Timed multiple-choice actor/movie quiz round |
| **Trivia Result** | `/trivia/result` | `features/trivia/presentation/pages/result_page.dart` | Score calculation, accuracy, replay, social share card |
| **Trivia Leaderboard** | `/trivia/leaderboard` | `features/trivia/presentation/pages/leaderboard_page.dart` | Global and actor-specific player rankings |
| **Trivia Top Fans** | `/trivia/top-fans` | `features/trivia/presentation/pages/top_fans_page.dart` | Top fan list for specific actors and cinema genres |
| **Profile Page** | Tab: `profile` | `features/profile/presentation/pages/profile_page.dart` | User avatar, streak stats, quick access to settings |
| **Profile Edit** | `/profile/edit` | `features/profile/presentation/pages/profile_edit_page.dart` | Edit username, avatar image upload, email display |
| **Settings Hub** | `/settings` | `features/profile/presentation/pages/settings_page.dart` | Root settings list categorizing all sub-settings |
| **Appearance Settings**| `/appearance` | `features/profile/presentation/pages/appearance_page.dart` | Accent picker (6 presets + custom), AMOLED, Tab tint |
| **Navbar Settings** | `/navbar` | `features/profile/presentation/pages/navbar_page.dart` | Reorder & toggle visible tabs (4 to 6 tabs) |
| **Player Settings** | `/player-settings` | `features/profile/presentation/pages/player_settings_page.dart` | Engine choice, Anime4K shaders, gestures, audio lang |
| **Providers Page** | `/providers` | `features/profile/presentation/pages/providers_page.dart` | Provider list, health probes, response latency |
| **Sources Page** | `/sources` | `features/profile/presentation/pages/sources_page.dart` | Manage CloudStream, Aniyomi, Keiyoushi repos |
| **Backup Page** | `/backup` | `features/profile/presentation/pages/backup_page.dart` | Export / import full Hive database as JSON |
| **Discord Settings** | `/discord` | `features/profile/presentation/pages/discord_settings_page.dart` | Discord RPC toggle, preview card, status configuration |
| **Discord Web Login** | `/discord/login` | `features/profile/presentation/pages/discord_web_login_page.dart` | In-app web login for mobile Discord token retrieval |
| **App Lock Settings** | `/app-lock-settings` | `features/app_lock/presentation/pages/app_lock_settings_page.dart` | Toggle PIN, biometric unlock, change PIN |
| **PIN Setup** | `/pin-setup` | `features/app_lock/presentation/pages/pin_setup_page.dart` | 4 or 6 digit PIN registration keypad |
| **PIN Verify** | `/pin-verify` | `features/app_lock/presentation/pages/pin_verify_page.dart` | Keypad verification challenge guarding protected paths |
| **Notifications** | `/notifications` | `features/notifications/presentation/pages/notifications_page.dart` | Broadcast messages, system alerts, comment replies |
| **Streak Details** | `/streak` | `features/streak/presentation/pages/streak_page.dart` | Daily watch streak calendar, freeze tokens, badges |
| **About Page** | `/about` | `features/profile/presentation/pages/about_page.dart` | Version, changelog, open source licenses, links |
| **Login Page** | `/login` | `features/auth/presentation/pages/login_page.dart` | Email/password sign-in, Google button, guest button |
| **Register Page** | `/register` | `features/auth/presentation/pages/register_page.dart` | Username, email, password creation |
| **OTP Verify** | `/otp` | `features/auth/presentation/pages/otp_verify_page.dart` | 6-digit email confirmation code entry |
| **Forgot Password** | `/forgot-password` | `features/auth/presentation/pages/forgot_password_page.dart` | Password reset email submission |
| **No Internet** | `/no-internet` | `features/network/presentation/pages/no_internet_page.dart` | Offline fallback page with retry button |

---

## 10. COMPREHENSIVE FEATURE MATRIX

| ID | Feature Category | Current Implementation | Platforms | Criticality | Existing Tests | Parity Status |
|---|---|---|---|---|---|---|
| **F-01** | Content Streaming (HLS/MP4) | `media_controller.dart` (`video_player`) | Android, iOS | Critical | Yes (`playback_fault_test.dart`) | Keep & Preserve |
| **F-02** | Desktop Playback (libmpv) | `media_controller.dart` (`media_kit`) | Win, Linux, Mac, Android | Critical | Yes (`player_video_track_test.dart`) | Keep & Preserve |
| **F-03** | DRM Playback (CENC) | `DrmController.kt` / `DrmPlayerHost.kt` | Android | High | Yes (`drm_config_test.dart`) | Keep & Preserve |
| **F-04** | Local HLS Proxy | `local_hls_proxy.dart` | All | High | Yes (`local_hls_proxy_test.dart`) | Keep & Preserve |
| **F-05** | Offline Video Downloads | `DownloadRepositoryImpl` | All | Critical | Yes (`download_layout_test.dart`) | Keep & Preserve |
| **F-06** | Android Foreground DL Service | `DownloadForegroundService.kt` | Android | High | Yes (`download_item_model_test.dart`) | Keep & Preserve |
| **F-07** | Manga Reading & Spreads | `reader_page.dart` | All | High | Yes (`spread_slots_test.dart`) | Keep & Preserve |
| **F-08** | Light Novel Reading | `novel_text.dart` | All | Medium | Yes (`novel_text_test.dart`) | Keep & Preserve |
| **F-09** | CloudStream 3 Integration | `PluginHost.kt` (DexClassLoader) | Android | High | No (Native Kotlin) | Keep & Preserve |
| **F-10** | Aniyomi APK Extensions | `AniyomiHost.kt` (DexClassLoader) | Android | High | No (Native Kotlin) | Keep & Preserve |
| **F-11** | Tachiyomi/Mihon Manga Ext | `MangaHost.kt` (DexClassLoader) | Android | High | No (Native Kotlin) | Keep & Preserve |
| **F-12** | Embedded Torrent Server | `torrentserver` (Go gomobile) | Android | High | Yes (`torrent_engine_models_test.dart`) | Keep & Preserve |
| **F-13** | Torrent Search Indexers | `torrent_search_repository.dart` | All | Medium | Yes (`release_name_parser_test.dart`) | Keep & Preserve |
| **F-14** | Desktop Extension Bridge | `BridgeServer.kt` (NanoHTTPD) | Android, Desktop | High | No | Keep & Preserve |
| **F-15** | Watch Party Sync | `watch_party_service.dart` (Socket.io) | All | Medium | Yes (`party_rules_test.dart`) | Keep & Preserve |
| **F-16** | Google Cast Integration | `dart_cast` + CastController | Android, iOS | Medium | Yes (`cast_controller_test.dart`) | Keep & Preserve |
| **F-17** | Picture-in-Picture (PiP) | `MainActivity.kt` (`soplay/pip`) | Android | High | No | Keep & Preserve |
| **F-18** | Android TV D-pad Focus | `tv_focusable.dart` + `TvShortcuts` | Android TV | Critical | No | Keep & Preserve |
| **F-19** | TV Pairing & Remote | `link_tv_page.dart` + `tv_remote_page.dart` | All | High | No | Keep & Preserve |
| **F-20** | AniList Sync & Reminders | `anilist_service.dart` + GraphQL | All | High | Yes (`anilist_matching_test.dart`) | Keep & Preserve |
| **F-21** | MyAnimeList Sync | `mal_service.dart` + REST API | All | High | Yes (`mal_tracker_test.dart`) | Keep & Preserve |
| **F-22** | Discord Rich Presence | `discord_ipc` (Desktop) / Gateway (Mobile) | All | Medium | Yes (`discord_activity_test.dart`) | Keep & Preserve |
| **F-23** | Cinema Buff Trivia Game | `trivia_remote_data_source.dart` | All | Medium | No | Keep & Preserve |
| **F-24** | Subtitle Auto-Translate | `subtitle_auto_translate_service.dart` | All | High | Yes (`subtitle_auto_translate_test.dart`) | Keep & Preserve |
| **F-25** | Online Subtitles Download | `online_subtitles_service.dart` | All | High | Yes (`subtitle_parser_test.dart`) | Keep & Preserve |
| **F-26** | App Lock (PIN & Biometric) | `local_auth` + Hive/SecureStorage | Android, iOS | High | No | Keep & Preserve |
| **F-27** | Custom Accent & AMOLED | `ThemeController` + `AppColors` | All | High | Yes (`app_palette_test.dart`) | Refactor for Kaizoku |
| **F-28** | Dynamic Navigation Customizer | `nav_controller.dart` + `NavPrefs` | Mobile | Medium | No | Refactor for Kaizoku |
| **F-29** | Database Backup & Restore | `backup_service.dart` (JSON export/import) | All | High | No | Keep & Preserve |
| **F-30** | Push Notifications (FCM) | `NotificationService` | Android, iOS | High | No | Keep & Preserve |
| **F-31** | User Accounts & Auth | `AuthBloc` + JWT TokenRefresher | All | Critical | Yes (`sign_out_clears_test.dart`) | Keep & Preserve |
| **F-32** | Deep Linking & Extension Links | `DeeplinkService` + App Links | Android, iOS | High | No | Migrate identity |
