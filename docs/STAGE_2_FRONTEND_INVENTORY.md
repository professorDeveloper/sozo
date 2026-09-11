# KAIZOKU — STAGE 2 FRONTEND INVENTORY & MIGRATION SPECIFICATION

> **Document Status:** CANONICAL STAGE 2 INVENTORY  
> **Preceding Gate:** Stage 1 Conditional Pass (Implementation Complete, Runtime Verification Blocked by Host Toolchain)  
> **Core Objective:** Map 100% of remaining user-facing routes, components, BLoCs, platform hooks, and risks to establish the execution roadmap for Stage 2.

---

## 1. REMAINING ROUTE & SCREEN INVENTORY

| Group | Route Path | Screen Class | Primary Source File | Presentational Complexity | Technical Risk |
|---|---|---|---|:---:|:---:|
| **A. Library** | `/library` | `LibraryPage` | `lib/features/my_list/presentation/pages/library_page.dart` | Medium | Low |
| **A. Library** | `/my-lists` | `UserListsPage` | `lib/features/my_list/presentation/pages/user_lists_page.dart` | Medium | Low |
| **A. Library** | `/history` | `HistoryPage` | `lib/features/history/presentation/pages/history_page.dart` | Medium | Low |
| **A. Library** | `/following` | `FollowingPage` | `lib/features/tracker/presentation/pages/following_page.dart` | Medium | Low |
| **A. Library** | `/private-list` | `PrivateListPage` | `lib/features/private_list/presentation/pages/private_list_page.dart` | High (Vault PIN) | Low |
| **A. Library** | `/activity` | `ActivityPage` | `lib/features/history/presentation/pages/activity_page.dart` | Low | Low |
| **B. Profile** | `/profile` | `ProfilePage` | `lib/features/profile/presentation/pages/profile_page.dart` | High | Low |
| **B. Profile** | `/profile/edit` | `ProfileEditPage` | `lib/features/profile/presentation/pages/profile_edit_page.dart` | Medium | Low |
| **B. Profile** | `/login` | `LoginPage` | `lib/features/auth/presentation/pages/login_page.dart` | Medium | Medium |
| **B. Profile** | `/register` | `RegisterPage` | `lib/features/auth/presentation/pages/register_page.dart` | Medium | Medium |
| **B. Profile** | `/forgot-password` | `ForgotPasswordPage` | `lib/features/auth/presentation/pages/forgot_password_page.dart` | Low | Low |
| **B. Profile** | `/otp` | `OtpVerifyPage` | `lib/features/auth/presentation/pages/otp_verify_page.dart` | Low | Low |
| **B. Profile** | `/connections` | `ConnectionsPage` | `lib/features/profile/presentation/pages/connections_page.dart` | Medium | Low |
| **B. Profile** | `/anilist` | `AnilistLibraryPage` | `lib/features/anilist/presentation/pages/anilist_library_page.dart` | High | Low |
| **B. Profile** | `/anilist/browse` | `AnilistBrowsePage` | `lib/features/anilist/presentation/pages/anilist_browse_page.dart` | High | Low |
| **B. Profile** | `/anilist/calendar`| `AiringCalendarPage` | `lib/features/anilist/presentation/pages/airing_calendar_page.dart` | High | Low |
| **B. Profile** | `/mal` | `MalLibraryPage` | `lib/features/mal/presentation/pages/mal_library_page.dart` | High | Low |
| **B. Profile** | `/discord` | `DiscordSettingsPage`| `lib/features/profile/presentation/pages/discord_settings_page.dart` | Medium | Low |
| **B. Profile** | `/streak` | `StreakPage` | `lib/features/profile/presentation/pages/streak_page.dart` | Medium | Low |
| **C. Playback** | `/player` | `PlayerPage` | `lib/features/detail/presentation/pages/player_page.dart` | **CRITICAL** | **VERY HIGH** |
| **C. Playback** | Overlay Sheets | Quality, Audio, Subs | `lib/features/detail/presentation/widgets/quality_sheet.dart` | High | High |
| **D. Reader** | `/reader` | `ReaderPage` | `lib/features/manga/presentation/pages/reader_page.dart` | High | High |
| **D. Reader** | Novel View | `NovelText` | `lib/features/manga/presentation/pages/novel_text.dart` | Medium | Low |
| **E. Social** | `/watch-party` | `WatchPartyPage` | `lib/features/watch_party/presentation/pages/watch_party_page.dart` | High | Medium |
| **E. Social** | `/link-tv` | `LinkTvPage` | `lib/features/remote/presentation/pages/link_tv_page.dart` | Medium | Low |
| **E. Social** | `/tv-remote` | `TvRemotePage` | `lib/features/remote/presentation/pages/tv_remote_page.dart` | High (10-ft sync) | Medium |
| **E. Social** | `/trivia/*` | Trivia Subsystem | `lib/features/trivia/presentation/pages/` | Medium | Low |
| **F. Downloads**| `/downloads` | `DownloadsPage` | `lib/features/download/presentation/pages/downloads_page.dart` | High | Medium |
| **G. Live TV** | `/live-tv` | `LiveTvPage` | `lib/features/live_tv/presentation/pages/live_tv_page.dart` | High (EPG Grid) | Medium |
| **H. Torrents** | `/torrents` | `TorrentSearchPage`| `lib/features/torrent/presentation/pages/torrent_search_page.dart` | High | High |
| **H. Sources** | `/sources` | `SourcesPage` | `lib/features/sources/presentation/pages/sources_page.dart` | Medium | Low |
| **I. Settings** | `/settings` | `SettingsPage` | `lib/features/profile/presentation/pages/settings_page.dart` | High | Low |
| **I. Settings** | `/appearance` | `AppearancePage` | `lib/features/profile/presentation/pages/appearance_page.dart` | Medium | Low |
| **I. Settings** | `/backup` | `BackupPage` | `lib/features/backup/presentation/pages/backup_page.dart` | Medium | Low |
| **I. Settings** | `/app-lock-settings`| `AppLockSettingsPage`| `lib/features/app_lock/presentation/pages/app_lock_settings_page.dart` | Medium | Low |
| **I. Settings** | `/pin-setup` | `PinSetupPage` | `lib/features/app_lock/presentation/pages/pin_pages.dart` | Medium | Low |
| **I. Settings** | `/about` | `AboutPage` | `lib/features/profile/presentation/pages/about_page.dart` | Low | Low |

---

## 2. EXISTING BLOCS, CUBITS & STATE MANAGEMENT

| Domain Feature | BLoC / Cubit / Service | Event / State Architecture | Persistence Dependency |
|---|---|---|---|
| **My List** | `MyListBloc` / `MyListLocalDataSource` | Hive Box `favorites_box` / `my_list_box` | Local Hive Storage |
| **User Lists** | `UserListsRepository` | Watch Later / Watched sets | Hive Key-Value |
| **History** | `HistoryService` | `ChangeNotifier` with revision listenables | Hive Box `history_box` |
| **Tracker** | `FollowService` | Periodic airing status & push alerts | Hive Box `followed_titles` |
| **App Lock** | `AppLockRepository` | Biometric / PIN hash check | Encrypted Secure Storage / Hive |
| **Auth** | `AuthBloc` | `AuthInitial`, `AuthLoading`, `Authenticated`, `Unauthenticated` | JWT Keychain / Hive |
| **AniList** | `AnilistService`, `AnilistBloc` | GraphQL OAuth token, User anime list sync | Secure Storage |
| **MAL** | `MalService`, `MalTracker` | REST OAuth 2.0 PKCE, List tracking | Secure Storage |
| **Discord** | `DiscordIpcClient`, `DiscordGatewayClient` | Desktop IPC pipe / Mobile WebSocket gateway | Ephemeral Gateway Socket |
| **Playback** | `MediaController`, `PlayerEngineSheet` | Native Android ExoPlayer / MediaKit MPV | Stream buffer / Audio track state |
| **Manga** | `MangaPagesUseCase`, `ReaderBloc` | Pre-caching page cache, spread slots | Temp disk cache |
| **Downloads** | `DownloadRepository`, `EnqueueDownloadUseCase` | Android Foreground Service / Desktop worker | Local File Storage |
| **Live TV** | `LiveTvService` | M3U8 Playlist parser, XMLTV EPG parser | Memory Cache |
| **Watch Party**| `WatchPartyService` | Socket.io real-time playback sync | WebRTC / WebSocket |
| **Remote** | `RemoteControlService`, `LinkTvBloc` | LAN HTTP server / Pairing PIN sync | Network broadcast |

---

## 3. EXISTING TEST COVERAGE AUDIT

The repository already contains unit and domain tests for:
- `test/features/home/home_rail_test.dart`
- `test/features/home/home_kaizoku_ui_test.dart` (Created Stage 1)
- `test/features/search/search_kaizoku_ui_test.dart` (Created Stage 1)
- `test/features/detail/detail_kaizoku_ui_test.dart` (Created Stage 1)
- `test/features/detail/episode_window_test.dart`
- `test/features/detail/download_choices_test.dart`
- `test/features/detail/party_rules_test.dart`
- `test/features/detail/playback_readout_test.dart`
- `test/features/detail/player_controls_layout_test.dart`
- `test/features/detail/player_info_fields_test.dart`
- `test/features/auth/auth_bloc_test.dart`
- `test/features/app_lock/app_lock_repository_test.dart`
- `test/features/live_tv/live_tv_service_test.dart`
- `test/features/remote/remote_control_service_test.dart`
- `test/features/watch_party/watch_party_service_test.dart`
- `test/features/manga/` (Manga spread & paging tests)
- `test/features/download/` (Download queue layout tests)

---

## 4. PLATFORM-SPECIFIC BEHAVIOR & HOOKS

1. **Android TV (10-Foot UI):**
   - Must use deterministic D-pad traversal (`KaizokuTvFocusable`, `_TvNavRail`, `_kTvRowFocusFill`).
   - Remote DPAD Center maps to Tap, DPAD Long Press maps to Context Actions.
   - Zero hover dependencies permitted.
2. **Desktop (Windows / macOS / Linux):**
   - Collapsible left navigation rail (`KaizokuDesktopNavShell`).
   - Mouse hover scaling, tooltips on icons, secondary click for context menus.
   - Hardware key shortcuts (`Space` to pause, `F` for fullscreen, `Arrow keys` for scrub).
3. **Mobile (Android / iOS):**
   - Ergonomic bottom navigation shell.
   - Pull-to-refresh gestures, edge-swipe back gestures (especially preserved on iOS).
   - Biometric prompt integration via `local_auth`.

---

## 5. PROTECTED HIGH-RISK SUBSYSTEMS

### A. Playback Engine (`lib/features/detail/presentation/pages/player_page*`)
- **Protected Elements:**
  - `MediaController` bindings (Native Android vs Libmpv desktop).
  - DRM ClearKey / Widevine handlers (`DrmController.kt`).
  - HLS Local Proxy server for Referer headers (`local_hls_proxy.dart`).
  - Source Ladder auto-fallback logic (`source_ladder.dart`).
  - Subtitle auto-translation & parser pipeline.
  - Picture-in-Picture (`soplay/pip` MethodChannel).
- **Rule:** Strictly presentational upgrades only. Player controls, time displays, audio/subtitle selectors must sit above the unchanged playback controller.

### B. BitTorrent Streaming Engine
- **Protected Elements:** `torrent_search_repository.dart`, `TorrentStreamHandle`, local streaming server on `127.0.0.1`.
- **Rule:** Do not alter stream port listening or chunk buffering.

---

## 6. PROPOSED STAGE 2 EXECUTION ORDER & MILESTONES

We partition Stage 2 into five incremental, test-gated milestones ordered from highest value / lowest risk to highest technical complexity:

### Milestone 2.1: Library & Discovery Collections (Highest Value, Low Risk)
- **Scope:** `LibraryPage`, `UserListsPage` (Watch Later/Watched), `HistoryPage`, `FollowingPage`, `PrivateListPage`.
- **UI Focus:** Kaizoku multi-tab filters, 2:3 & 16:9 `KaizokuMediaCard` grids, Neon Crimson batch actions, Biometric vault lock screen styling.
- **Why First:** Pure presentation over robust local Hive storage, immediate high-visibility UX upgrade for daily users.

### Milestone 2.2: Profile, Accounts & Connections (Low Risk)
- **Scope:** `ProfilePage`, `ProfileEditPage`, `ConnectionsPage`, `AnilistLibraryPage`, `MalLibraryPage`, `DiscordSettingsPage`, `StreakPage`, Auth pages (`LoginPage`, `RegisterPage`).
- **UI Focus:** Cyber Obsidian glass cards, Neon Crimson activity charts, status badges, connection toggles.

### Milestone 2.3: Downloads & Offline Management (Medium Risk)
- **Scope:** `DownloadsPage`, `DownloadChoiceSheet`, storage indicators.
- **UI Focus:** Animated circular progress, batch management, storage allocation bar.

### Milestone 2.4: Community, Live TV & Extensions (Medium Risk)
- **Scope:** `LiveTvPage` (EPG grid), `WatchPartyPage`, `TvRemotePage`, `TriviaPage`, `SourcesPage`.
- **UI Focus:** 10-foot EPG navigation, real-time chat bubbles, remote control D-pad visualizer.

### Milestone 2.5: Playback & Manga Reader (High Technical Complexity)
- **Scope:** `PlayerPage` chrome, `PlayerControls`, `QualitySheet`, `SubtitleSheet`, `ReaderPage`, `NovelText`.
- **UI Focus:** Minimalist ambient player HUD, sleek slider bar with Neon Crimson glow, gesture hints.
- **Safeguard:** Full regression pass over video playback engine and DRM pipelines.

---

## 7. NEXT IMMEDIATE ACTION

Proceed to **Milestone 2.1: Library & Discovery Collections** starting with:
1. `lib/features/my_list/presentation/pages/library_page.dart`
2. `lib/features/my_list/presentation/pages/user_lists_page.dart`
3. `lib/features/history/presentation/pages/history_page.dart`
4. `lib/features/tracker/presentation/pages/following_page.dart`
5. `lib/features/private_list/presentation/pages/private_list_page.dart`
