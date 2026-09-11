# KAIZOKU — TEST AUDIT & COVERAGE GAP ANALYSIS

> **Verification Standard:** Direct inspection of test suites across `test/core/` and `test/features/`.
> 
> *Phase 1A has eliminated critical zero-coverage risks before presentation refactoring.*

---

## 1. TEST EXECUTION ENVIRONMENT STATUS

* **Local Shell Execution:** Cannot be executed directly in the current local Windows terminal because `flutter` CLI is not in the system `$env:PATH`.
* **CI Execution:** Fully automated in `.github/workflows/ci.yml` via:
  ```bash
  flutter test --reporter expanded
  ```
* **Test Architecture Quality:** Tests are written to high standards using `flutter_test`, fake implementations, and isolated mocks. The suites assert discrete invariants rather than shallow smoke tests.

---

## 2. COVERED DOMAIN SUBSYSTEMS (WELL-TESTED)

| Subsystem | Suite Count | Key Test Files | Verified Invariants |
|---|:---:|---|---|
| **Player Tracks & Options** | 10 | `player_video_track_test.dart`, `source_ladder_test.dart`, `playback_fault_test.dart` | Source ladder retry, video track resolution, HLS proxy, playback faults. |
| **Subtitle System** | 4 | `subtitle_parser_test.dart`, `subtitle_auto_translate_test.dart`, `subtitle_font_test.dart` | SRT/VTT parsing, line breaking, auto-translation error handling, font sizing. |
| **Detail & Episode Windowing**| 12 | `episode_window_test.dart`, `episode_blocks_test.dart`, `watch_progress_test.dart` | 100-episode windowing, watch progress % thresholds, title preferences. |
| **Search & Cross-Search** | 5 | `cross_search_controller_test.dart`, `search_relevance_test.dart`, `source_health_store_test.dart` | Concurrent search dispatch, relevance ranking, provider health scoring. |
| **Manga & Novel Readers** | 2 | `spread_slots_test.dart`, `novel_text_test.dart` | Landscape dual-page spread calculations, novel text HTML stripping/rendering. |
| **Torrent Parsing** | 3 | `release_name_parser_test.dart`, `torrent_engine_models_test.dart`, `torrent_stream_url_test.dart` | Release group/codec regex extraction, stream URL generation, peer models. |
| **Download Data Models** | 2 | `download_item_model_test.dart`, `download_layout_test.dart` | Relative path serialization, download status state machine transitions. |
| **Trackers (AniList & MAL)** | 3 | `anilist_matching_test.dart`, `anilist_relation_test.dart`, `mal_tracker_test.dart` | Fuzzy anime title matching, episode progress tracking at >85%. |
| **Discord RPC** | 3 | `discord_activity_test.dart`, `discord_brand_test.dart`, `discord_throttle_test.dart` | Payload rate-limiting, title formatting, media duration calculations. |

---

## 3. PHASE 1A COMPLETED SAFETY NET SUITES

The critical zero-coverage areas identified during Phase 0 have now been tested:

### 1. User Authentication Flow (`test/features/auth/auth_bloc_test.dart`)
* **Verified Invariants:**
  - Login with valid credentials dispatches profile fetch and favorite sync.
  - Authentication failure emits discrete error messages without swallowing errors.
  - Registration triggers OTP verification requirements.
  - OTP verification establishes tokens and initializes the user session.
  - Session expiration correctly purges tokens and transitions state to unauthenticated.

### 2. App Lock & Security Vault (`test/features/app_lock/app_lock_repository_test.dart`)
* **Verified Invariants:**
  - PIN hashing using PBKDF2/SHA-256 with cryptographically distinct salts per device/user.
  - Correct PIN validates successfully; incorrect PIN rejects.
  - Self-healing state consistency when biometric authentication is toggled or reset.
  - Biometric authentication fallback logic.

### 3. Live TV & EPG Parser (`test/features/live_tv/live_tv_service_test.dart`)
* **Verified Invariants:**
  - `LiveProgramme` JSON parsing with ISO-8601 strings and Unix epoch timestamps (seconds & millis).
  - Window validation (`hasWindow`), timeline progress bar calculation clamped to `[0.0, 1.0]`.
  - Remaining time calculation avoiding negative durations.
  - `isBarWorthy` thresholds (rejecting slots < 5 min or > 360 min).
  - Channel schedule sorting by start time with untimed programs at the end.
  - Category, country, and search query parameters in `browse()`.

### 4. Real-time WatchParty (`test/features/watch_party/watch_party_service_test.dart`)
* **Verified Invariants:**
  - Room creation and joining emits `party:join` over Socket.io.
  - Room state snapshots update local room and membership.
  - Playback sync events (`party:sync`) update playback state and stream updates.
  - Content switches (`party:content`) update active media metadata.
  - Optimistic local chat and reaction broadcasts with client-side deduplication.
  - Graceful disconnect and room closure handling (`party:closed`).

### 5. TV Pairing & Remote Service (`test/features/remote/remote_control_service_test.dart`)
* **Verified Invariants:**
  - Remote device listing and state query parsing.
  - D-pad, playback, seek (`seekTo`, `seekBy`), and text typing command dispatches.
  - HTTP 409 conflict correctly maps to `RemoteOfflineException`.
  - `LinkTvBloc.normalizeCode()` strips spaces/separators, converts to uppercase, and normalizes URLs.
  - QR/PIN approval flow enforces 8-character code validation.
  - Device unlinking removes unlinked device from active state list.

---

## 4. REMAINING ARCHITECTURAL TEST ROADMAP

As Phase 1B (Architecture Primitives) and Phase 1C (Design System) proceed:
1. `test/core/presentation/responsive/kaizoku_breakpoints_test.dart`
2. `test/core/presentation/navigation/navigation_shell_test.dart`
3. `test/core/presentation/tv/tv_focus_scope_test.dart`
