# KAIZOKU — FUNCTIONAL PARITY SPECIFICATION (VALIDATED AUDIT)

> **Validation Gate:** All features audited directly against source code in `lib/`, `android/`, `windows/`, `linux/`, `macos/`, and `ios/`.
> 
> **Classification Tiers:**
> - `VERIFIED FUNCTIONAL`: Complete end-to-end implementation with entity mapping, state management, and active provider/native integration.
> - `PARTIALLY IMPLEMENTED`: Functional on specific platforms or with partial feature subsets.
> - `SCAFFOLD/PLACEHOLDER`: UI or models present without active data source connection.
> - `DEAD/UNUSED`: Obsolete code paths or unused remnants.
> - `UNKNOWN`: Requires live backend response or hardware fixture to verify.

---

## 1. FEATURE CLASSIFICATION & PARITY REGISTRY

| Feature Category | Implementation Files | Status | Platform Scope | Backend Dependent? |
|---|---|---|---|:---:|
| **Video Catalogue** | `home_data_source.dart`, `home_bloc.dart` | `VERIFIED FUNCTIONAL` | All | Yes (for default vidapi) |
| **Series & Episodes** | `detail_data_source.dart`, `episodes_bloc.dart` | `VERIFIED FUNCTIONAL` | All | Yes (or via CS3/Aniyomi) |
| **Anime Stream & Track** | `anilist_service.dart`, `mal_service.dart` | `VERIFIED FUNCTIONAL` | All | Trackers direct; video via provider |
| **Manga / Comic Reader** | `reader_page.dart`, `manga_channel.dart` | `VERIFIED FUNCTIONAL` | All (Native on Android) | No (Direct from Keiyoushi/Mangayomi) |
| **Light Novel Reader** | `novel_text.dart`, `reader_page.dart` | `VERIFIED FUNCTIONAL` | All | No (Direct chapter parsing) |
| **Search (Single Provider)**| `search_data_source.dart`, `search_bloc.dart` | `VERIFIED FUNCTIONAL` | All | Dependent on selected provider |
| **Cross-Search** | `cross_search_engine.dart`, `cross_search_page.dart`| `VERIFIED FUNCTIONAL` | All | Parallel to all active providers |
| **Multi-Engine Playback** | `media_controller.dart` (Native, MediaKit, DRM)| `VERIFIED FUNCTIONAL` | All | Stream host dependent |
| **Subtitles & Translators**| `subtitle_parser.dart`, `online_subtitles.dart`| `VERIFIED FUNCTIONAL` | All | OpenSubtitles / Google Translate |
| **Quality & Source Ladder**| `source_ladder.dart`, `hls_variants.dart` | `VERIFIED FUNCTIONAL` | All | Stream host dependent |
| **Downloads & Offline** | `download_repository_impl.dart`, Foreground Svc| `VERIFIED FUNCTIONAL` | All (Foreground on Android)| 100% Offline once downloaded |
| **BitTorrent Streaming** | `torrent_engine.dart`, `torrentserver` (Go) | `PARTIALLY IMPLEMENTED`| Android (embedded TorrServer); Other via magnet | Trackers direct (Nyaa/TokyoToshokan) |
| **Watch Party** | `watch_party_service.dart` (Socket.io) | `VERIFIED FUNCTIONAL` | All | Yes (`socketOrigin: /watch`) |
| **IPTV / Live TV** | `live_tv_service.dart`, `live_tv_page.dart` | `VERIFIED FUNCTIONAL` | All | Yes (`/channels/categories`) |
| **AniList Synchronization**| `anilist_api.dart`, `airing_reminders.dart` | `VERIFIED FUNCTIONAL` | All | No (Direct `graphql.anilist.co`) |
| **MyAnimeList Sync** | `mal_api.dart`, `mal_service.dart` | `VERIFIED FUNCTIONAL` | All | No (Direct `api.myanimelist.net`) |
| **Discord Rich Presence** | `discord_ipc_client.dart` / Gateway | `VERIFIED FUNCTIONAL` | All (IPC Desktop; WS Mobile)| No (Direct Discord Gateway / Pipe) |
| **Cinema Buff Trivia** | `trivia_remote_data_source.dart`, Hub | `VERIFIED FUNCTIONAL` | All | Yes (`/trivia/...`) |
| **Authentication (JWT)** | `auth_remote_data_source.dart`, `auth_bloc` | `VERIFIED FUNCTIONAL` | All | Yes (`/auth/...`) |
| **App Lock & Biometric** | `app_lock_repository_impl.dart`, `local_auth`| `VERIFIED FUNCTIONAL` | All (Sensor where present)| 100% Device-Local |
| **Private Vault Lists** | `private_list_service.dart` (Hive) | `VERIFIED FUNCTIONAL` | All | 100% Device-Local |
| **Push & Local Reminders** | `notification_service.dart`, `timezone` | `VERIFIED FUNCTIONAL` | Android, iOS | FCM for broadcast; Local for calendar |
| **TV Remote Controller** | `remote_control_service.dart` | `VERIFIED FUNCTIONAL` | All | Yes (`/remote/...`) |
| **Desktop Share Bridge** | `BridgeServer.kt` (NanoHTTPD) | `PARTIALLY IMPLEMENTED`| Android host; Desktop/iOS client| Local Wi-Fi Network |
| **CloudStream Providers** | `PluginHost.kt` (DexClassLoader) | `PARTIALLY IMPLEMENTED`| Android Only | Third-party plugin repos |
| **Aniyomi Extensions** | `AniyomiHost.kt` (DexClassLoader) | `PARTIALLY IMPLEMENTED`| Android Only | Third-party extension APKs |
| **Mihon Manga Extensions** | `MangaHost.kt` (DexClassLoader) | `PARTIALLY IMPLEMENTED`| Android Only | Keiyoushi APK repos |
| **Deep Links** | `DeeplinkService.dart`, App Links, Intent | `VERIFIED FUNCTIONAL` | All | Handles `sozo://`, `https://`, file |

---

## 2. DETAILED SUBSYSTEM SPECIFICATIONS

### 2.1 Video Streaming, Series & Anime
* **Behavior:** Seamless pagination of content feeds, windowed episode lists (e.g. 1-100, 101-200), source mirror resolution, audio language preference selection (Sub vs Dub).
* **Inputs:** Detail content URL, provider ID, season/episode indicators.
* **Outputs:** Video playback pipeline, subtitle overlay, watch progress updates written to Hive every 5 seconds.
* **Error Mitigation:** If a stream fails mid-playback, `SourceLadder` steps through backup qualities or alternate mirror servers before throwing a visible error.

### 2.2 Manga & Novel Reading
* **Behavior:** Manga viewer supports paged mode (left-to-right or right-to-left), continuous vertical scroll (webtoon), and landscape dual-page spread slots. Novel reader renders clean typography with adjustable font size, line spacing, and amoled/sepia/light backgrounds.
* **Inputs:** Chapter URL, provider ID, reading progress index.
* **Outputs:** High-performance cached image sequence (`cached_network_image`) or sanitized rich text (`novel_text.dart`).

### 2.3 Downloads & Offline Architecture
* **Behavior:** Background transfer with disk-backed persistence.
* **Safety Invariant:** Startup integrity sweep (`verifyAll()`) guarantees that any row marked completed in Hive actually has a valid, non-zero file on disk. If a file was deleted externally, the status is demoted to `missing` to allow re-downloading.

### 2.4 BitTorrent Streaming Engine
* **Behavior:**
  - On **Android**, an embedded Go binary (`torrentserver`, port 8090) streams magnet links as progressive HTTP video chunks directly to the player.
  - On **Desktop/iOS**, torrent search queries RSS and HTML trackers (Nyaa, Tokyo Toshokan) to parse magnet links and file metadata, but playback delegates to an external torrent client or web bridge.

### 2.5 Security, Privacy & App Lock
* **Behavior:** PBKDF2/SHA-256 hashed PIN with cryptographic salt stored in `flutter_secure_storage`. Biometric fallback via `local_auth`. Protects access to app settings and `/private-list`.
