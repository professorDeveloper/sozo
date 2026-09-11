# KAIZOKU — TARGET ARCHITECTURE SPECIFICATION

> **Architecture Philosophy:** Strict separation of concerns between business capability and presentation.
> 
> ```
> ┌────────────────────────────────────────────────────────┐
> │                   WHAT KAIZOKU DOES                    │
> │  Domain Entities, Use Cases, Repositories, Services,  │
> │  Network, Persistence, Offline Storage, Multi-Engine   │
> └──────────────────────────┬─────────────────────────────┘
>                            │
>                            ▼
> ┌────────────────────────────────────────────────────────┐
> │                   HOW KAIZOKU LOOKS                    │
> │  Kaizoku Design System, Obsidian Surfaces, Crimson/Gold │
> │  Mobile Fluid Layout, Desktop Multi-Column, TV 10-Foot │
> └────────────────────────────────────────────────────────┘
> ```

---

## 1. LAYERED ARCHITECTURAL BOUNDARIES

### 1.1 Domain Layer (Pure Dart / Zero UI Dependencies)
* **Entities:** Pure immutable data structures representing business concepts: `Movie`, `Episode`, `DownloadItem`, `UserProfile`, `TorrentResult`, `SubtitleTrack`, `TrackLink`.
* **Repository Interfaces:** Abstract contracts declaring data capabilities:
  - `HomeRepository`, `DetailRepository`, `SearchRepository`, `DownloadRepository`, `AuthRepository`, `UserListsRepository`, `TriviaRepository`.
* **Use Cases:** Atomic business workflows:
  - `GetHomeCatalogueUseCase`, `ResolveMediaUseCase`, `EnqueueDownloadUseCase`, `SyncFavoritesUseCase`, `VerifyOtpUseCase`, `SearchCrossProvidersUseCase`.
* **Rule:** The domain layer must NEVER import `flutter/material.dart` or any presentation library.

### 1.2 Data Layer (Implementation & Adapters)
* **Data Sources:**
  - **Remote:** `HomeRemoteDataSource`, `DetailRemoteDataSource`, `SearchRemoteDataSource`, `WatchPartyRemoteDataSource`, `TorrentRemoteDataSource`.
  - **Local:** `DownloadLocalDataSource`, `AppLockLocalDataSource`, `MyListLocalDataSource`, `HiveService`.
  - **Native Adapters:** `DownloadNativeDataSource` (interfacing with Android Foreground Service), `MangaHost`, `PluginHost`, `AniyomiHost`.
* **Repository Implementations:** Coordinate local caching with remote fetching, enforce offline fallbacks, and map raw DTOs to Domain Entities.
* **Network & Deserialization:** Dio interceptor pipeline, JSON serialization with safe type converters.

### 1.3 Application & State Layer (BLoC / Notifiers)
* **Feature BLoCs:** Exclusively handle UI intents (Events) and emit reactive ViewStates:
  - Events: e.g., `HomeLoad`, `DetailFetch`, `SearchQueryChanged`, `DownloadTogglePause`.
  - States: Exhaustive sealed hierarchies e.g., `Initial`, `Loading`, `Success(data)`, `Failure(error, isOffline)`.
* **Global Controllers:**
  - `ThemeController`: Manages Kaizoku dynamic palette and theme mode.
  - `NavController`: Tab switching and badge counts.
  - `DesktopWindow`: Window controls and fullscreen states.

### 1.4 Presentation Layer (Kaizoku Frontend Replacement)
* **Complete Decoupling:** Presentation is organized into device-specific adaptive shells:
  - `presentation/mobile/`: Optimized for single-hand touch, bottom navigation capsule, vertical gesture reels.
  - `presentation/desktop/`: Multi-column side rail, resizable layout, keyboard shortcuts, hover effects, window title bar.
  - `presentation/tv/`: 10-foot UI, D-pad navigation rails, TV focus rings, remote-friendly media controls.
* **Design System Primitives:** All pages must use predefined Kaizoku widgets (`KaizokuCard`, `KaizokuButton`, `KaizokuHeader`, `KaizokuGlassContainer`), never ad-hoc styling.

---

## 2. NAVIGATION & ROUTING ARCHITECTURE

### 2.1 Route Management (`GoRouter`)
* Centralized route table in `lib/core/router/app_router.dart`.
* Deep link routing parses incoming URI parameters (`sozo://` and universal links) and routes directly to destination with fallback to `/main`.
* Custom transition page builder:
  - Instant snappy transitions on desktop.
  - Edge-swipe interactive popping on iOS.
  - Hero-preserving subtle fades on Android.
  - Zero-duration instant switches on Android TV to avoid frame drops on low-end chipsets.

### 2.2 Adaptive Shell Hierarchy
```
               MaterialApp.router
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
       Desktop Shell        Mobile/TV Shell
    (Custom Titlebar +     (TvShortcuts wrapper
     Esc Key Binding)       on Android TV)
             │                   │
             └─────────┬─────────┘
                       ▼
                    MainPage
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
  Mobile Bar      Desktop Rail      TV Rail
 (Floating Glass  (Left Navigation (10-Foot D-pad
    Capsule)          Rail)           Rail)
```

---

## 3. PLAYBACK SUBSYSTEM ARCHITECTURE

```
                  PlayerController (Abstract)
                               │
       ┌───────────────────────┼───────────────────────┐
       ▼                       ▼                       ▼
_NativeController      _MediaKitController       DrmController
 (video_player)         (media_kit / libmpv)      (Media3 CENC)
  - Android Phone        - Windows Desktop         - Widevine DRM
  - iOS Phone/Tablet     - Linux Desktop           - ClearKey
  - Basic HLS / MP4      - macOS Desktop           - SurfaceTexture
                         - Android Multi-Audio
```

* **Local HLS Proxy:** Operates as a local loopback server (`127.0.0.1:<port>`) that intercepts HLS playlist and TS chunk requests to inject custom User-Agent, Origin, Referer, and range headers required by protected streaming hosts.
* **Source Ladder:** Monitored playback state engine that catches `VideoPlayerValue.hasError`, attempts retry on mirror endpoints, and fails gracefully to external players.

---

## 4. OFFLINE STORAGE & DOWNLOAD PIPELINE

```
  DownloadRequest
        │
        ▼
 DownloadRepositoryImpl
        │
        ├─ Platform == Android ──► DownloadForegroundService.kt
        │                           (Sticky service, wake_lock, notifications)
        │
        └─ Platform == Desktop/iOS ──► DownloadTransferDataSource
                                      (Dio chunked stream, disk sync)
        │
        ▼
 DownloadStorage (Relative Paths: /downloads/{kind}/{id}/{filename})
        │
        ▼
 Hive `download_box` (State, metadata, progress, size)
```

---

## 5. SUBSYSTEM CLASSIFICATION (KEEP / REFACTOR / REPLACE / REMOVE)

| Subsystem | Classification | Rationale |
|---|---|---|
| **Core Domain Entities & Use Cases** | **KEEP** | Rock solid, test-backed domain logic representing streaming, episodes, manga chapters, and downloads. |
| **Data Repositories & Data Sources** | **KEEP** | Mature implementations supporting multi-format streaming, caching, and token refresh. |
| **Download Foreground Service & Storage** | **KEEP** | Battle-tested Android native foreground service with relative path disk safety. |
| **Multi-Engine Playback Controller** | **KEEP** | Comprehensive abstraction for ExoPlayer, libmpv, and Media3 DRM. |
| **Native Extension Hosts (CS3/Aniyomi/Mihon)** | **KEEP** | High-performance DexClassLoader runtime for third-party extensions. |
| **Hive Local Persistence** | **KEEP** | Reliable, lightweight NoSQL persistence across 9 boxes. |
| **Theme System & Palette (`AppColors`)** | **REFACTOR** | Refactor from Sozo brand tokens to Kaizoku design system while preserving dynamic accent capability. |
| **Navigation Shell (`MainPage`)** | **REFACTOR** | Decouple monolithic 1,700-line file into dedicated clean components: `MobileNavShell`, `DesktopNavShell`, `TvNavShell`. |
| **All Screen Presentation & UI Widgets** | **REPLACE** | Complete visual replacement: Brand new design system, layouts, typography, micro-interactions, responsive grids. |
| **Brand Identity (Titles, Logos, Assets)** | **REPLACE** | Replace Sozo branding with Kaizoku brand identity across all platforms, manifests, metadata, and assets. |
| **Legacy unused styles / dead classes** | **REMOVE** | Clean up deprecated or unused remnants from early builds. |
