# Native source diagnosis and fixes

Read-only device evidence, 2026-09-14 Asia/Tashkent. App package com.soplay.sozo; phone RFCT32BMLHN pid3396. No device data clearing/installing/launching from this investigation.

## Confirmed phone/emulator difference

Phone log:

    03:58:53.919 MangaHost: apk https://github.com/keiyoushi/extensions/releases/download/34e4d51-0/tachiyomi-all.novelcool-v1.4.8.apk -> 404
    03:58:53.921 flutter: [HomeBloc] home: fail: Exception: Manga: source unavailable: mn:7570101320206504111

Emulator files/manga contains eu.kanade.tachiyomi.extension.all.novelcool-tachiyomi-all.novelcool-v1.4.8.apk. Phone has no cached NovelCool APK. Current primary Keiyoushi index.pb points to https://github.com/keiyoushi/extensions/releases/download/6ca40f6-0/tachiyomi-all.novelcool-v1.4.8.apk — same APK filename, different GitHub release. Thus emulator uses cache while phone tries expired installation URL.

Fix: on APK HTTP404/410, refresh only persisted owning repository, re-read same source ID, retry only if index provides a different URL. Cache-first preserves usable installed APKs. Requests serialize across popular/latest to prevent competing .part.apk writes and racing refresh. 60-second per-stale-URL cooldown prevents repeated refresh/download loops. Signature checks retained.

## Heat/performance observation

Phone thermalservice: Thermal Status4; SKIN46.8°C status4; BAT45.3°C; AP53.3°C. Historical CPU sample 03:54:49–03:59:49: media.swcodec38%, surfaceflinger26%, system_server16%, kswapd0 6.7%. App logs skipped158,51,42 frames. This confirms device thermal pressure and UI jank, but does not establish native source loaders as dominant heat cause. No repeated/heavy phone sampling performed after this observation.

## Other native fixes

- Aniyomi/Manga failed or empty repo reinstallation cannot replace persisted source metadata with empty arrays.
- Update saves newly-added source IDs, including new packages, so they survive restart.
- Explicit runtime eviction also clears matching loaded-APK guard and old load error, allowing replacement at same filename.
- Source metadata and Manga page caches now concurrent; repo mutations and source initialization serialized.
- CloudStream DNS: phone logged NoSuchMethodException. javap pinned v4.8.0 classes.jar proves getApp belongs to MainActivityKt, not MainAPIKt. Corrected the reflective owner to MainActivityKt; typed access was not available on the app compile classpath.
- Download start accepts imageHeaders list, carries it through foreground service, merges per-page overrides case-insensitively with shared headers.

## Validation

native_repo_regression.py compiles actual production MangaRepoManager/AniyomiRepoManager with in-memory Context/preferences, HTTP index and host doubles. Both pass failed/empty preservation, new source restart persistence and expired-URL callback refresh. NATIVE_BASELINE=1 runs HEAD production source instead: it compiles then fails the preservation assertion, confirming regression detector is red-capable.

Full app compilation and post-install emulator/phone validation are coordinated by root task, not claimed here.
