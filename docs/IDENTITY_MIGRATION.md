# KAIZOKU — CONTROLLED IDENTITY MIGRATION AUDIT & SPECIFICATION

> **Target Identity:** KAIZOKU  
> **Original Identity:** SOZO  
> **Migration Rule:** Full product identity transformation. Controlled audit classifying every reference into **MIGRATED**, **ADAPTED**, or **INTENTIONALLY RETAINED**.
> 
> *Blind global search-and-replace is strictly prohibited to prevent breaking external API communication, database deserialization, or native IPC channels.*

---

## 1. REPOSITORY IDENTIFIER SCAN SUMMARY

* Total files containing `sozo` / `Sozo`: 178 files across root, `lib/`, `android/`, `ios/`, `windows/`, `linux/`, `macos/`, `assets/`, `docs/`.
* Total matching lines: 983 lines.

---

## 2. CATEGORY 1: USER-FACING PRODUCT IDENTITY (MIGRATED TO KAIZOKU)

These represent the visible brand identity that users, operating systems, and external observers see. All are migrated to **Kaizoku**:

| Surface / Identifier | Original Value | Kaizoku Target Value | File / Path |
|---|---|---|---|
| **App Title (Localization)** | `"app_name": "Sozo"` | `"app_name": "Kaizoku"` | `assets/translations/*.json` (all 11 locales) |
| **MaterialApp Title** | `'app_name'.tr()` (displays "Sozo") | Displays "Kaizoku" | `lib/app.dart` |
| **Android App Label** | `android:label="Sozo"` | `android:label="Kaizoku"` | `android/app/src/main/AndroidManifest.xml` |
| **Android TV Launcher Banner** | `@drawable/tv_banner` (Sozo banner) | Kaizoku TV Banner (320x180) | `android/app/src/main/res/drawable/tv_banner.png` |
| **iOS Display Name** | `<string>Sozo</string>` | `<string>Kaizoku</string>` | `ios/Runner/Info.plist` (`CFBundleDisplayName`) |
| **iOS Bundle Name** | `<string>Sozo</string>` | `<string>Kaizoku</string>` | `ios/Runner/Info.plist` (`CFBundleName`) |
| **iOS Permission Prompts** | `"Sozo looks for Chromecast..."` | `"Kaizoku looks for Chromecast..."` | `ios/Runner/Info.plist` (`NSLocalNetworkUsageDescription`) |
| **Windows Executable Description**| `VALUE "FileDescription", "Sozo"` | `VALUE "FileDescription", "Kaizoku"` | `windows/runner/Runner.rc` |
| **Windows Product Name** | `VALUE "ProductName", "Sozo"` | `VALUE "ProductName", "Kaizoku"` | `windows/runner/Runner.rc` |
| **Windows Window Title** | `window.Create(L"Sozo", ...)` | `window.Create(L"Kaizoku", ...)` | `windows/runner/main.cpp` |
| **Linux GTK Header Title** | `gtk_header_bar_set_title(..., "Sozo")` | `gtk_header_bar_set_title(..., "Kaizoku")` | `linux/runner/my_application.cc` |
| **macOS Product Name** | `PRODUCT_NAME = Sozo` | `PRODUCT_NAME = Kaizoku` | `macos/Runner/Configs/AppInfo.xcconfig` |
| **Brand Vector Mark** | `SozoMark` / `sozo_mark.svg` | `KaizokuMark` / `kaizoku_mark.svg` | `lib/core/widgets/kaizoku_mark.dart` & `assets/brand/` |
| **About Page Metadata** | "Sozo", version, repository link | "Kaizoku", version, repository link | `lib/features/profile/presentation/pages/about_page.dart` |
| **Discord Rich Presence Activity**| `"Watching Sozo"` / Application Name | `"Watching Kaizoku"` | `lib/core/discord/discord_activity.dart` |
| **Splash Screen Presentation** | Sozo SVG splash sequence | Kaizoku cinematic crimson/gold reveal | `lib/features/splash/presentation/pages/splash_page.dart` |

---

## 3. CATEGORY 2: PLATFORM CONFIGURATION & METADATA (MIGRATED WHERE SAFE)

| Surface | Original Value | Kaizoku Target Value | Safety Rationale |
|---|---|---|---|
| **Pubspec Description** | `"Sozo — kino, serial, anime..."` | `"Kaizoku — kino, serial, anime..."` | Pure metadata. Fully safe to update. |
| **README & Documentation** | References to Sozo app setup | Migrated to Kaizoku architecture & setup | Documentation only. Fully safe. |
| **Deeplink Helper Page** | `detail.html` ("Sozo'da ochish") | "Kaizoku'da ochish" | Web landing page for deep links. Fully safe. |
| **Custom URL Scheme (Additive)**| `sozo://` | `kaizoku://` (with `sozo://` fallback) | Supporting both ensures backward compatibility for old shared links while adopting `kaizoku://` as primary. |

---

## 4. CATEGORY 3: INTENTIONALLY RETAINED IDENTIFIERS (DO NOT RENAME)

The following technical identifiers MUST be preserved. Modifying them would break communication with active production servers, corrupt persistent databases, or disrupt native IPC channels:

### 4.1 Production API Hostname (`apisozo.azamov.me`)
* **Identifier:** `https://apisozo.azamov.me/api` (and Socket.io host `https://apisozo.azamov.me`)
* **Location:** `lib/core/constants/app_constants.dart` (lines 6-19, `_obf` and `_decode`)
* **Technical Justification:** This is the live backend server hosting media indexing, user profiles, comments, and WatchParty sync. The server is administered on `apisozo.azamov.me`. Renaming this string to `apikaizoku...` would result in complete DNS resolution failure (`SocketException: Failed host lookup`), severing all server features.

### 4.2 Dart Package Name (`soplay`)
* **Identifier:** `package:soplay/...` in `pubspec.yaml` (line 6) and 600+ Dart source files.
* **Location:** `pubspec.yaml`, `lib/**/*.dart`, `test/**/*.dart`
* **Technical Justification:** As explicitly documented by the original codebase authors in `pubspec.yaml`:
  > *"The package name stays `soplay` — it is the prefix of every `package:soplay/…` import in 600+ files and of the Android applicationId already installed on users' devices. Renaming it would be a rename of the app on disk, not of the brand. The brand lives in the Android/iOS app label and in `Sozo` [now `Kaizoku`] everywhere a person can see it."*
  Altering the package name risks widespread import broken references and Hive type adapter collision without providing any user-visible benefit.

### 4.3 Android Application ID & Namespace (`com.soplay.sozo`)
* **Identifier:** `com.soplay.sozo` (and Kotlin package `com.soplay.sozo`)
* **Location:** `android/app/build.gradle.kts` (`applicationId`, `namespace`), `android/app/src/main/kotlin/com/soplay/sozo/...`
* **Technical Justification:**
  1. Changing `applicationId` changes the Android OS package identity. Any user upgrading the app would have the app installed as an unrelated new application, losing all local Hive storage, downloads, and login credentials.
  2. Firebase configuration (`google-services.json`) is bound to package name `com.soplay.sozo`. Modifying it causes `FirebaseApp.initializeApp()` to throw initialization exceptions, disabling push notifications and Crashlytics.
  3. Third-party Android extension runtimes (Aniyomi and Mihon shims in `eu/kanade/tachiyomi/AppInfo.kt`) check host package metadata.

### 4.4 IPC MethodChannels Namespace (`soplay/*`)
* **Identifier:** `soplay/platform`, `soplay/pip`, `soplay/downloads`, `soplay/manga`, `soplay/cloudstream`, `soplay/aniyomi`, `soplay/torrent`, `soplay/drm_player`, `soplay/preview`, `soplay/bridge`, `soplay/system_controls`
* **Location:** `lib/core/...`, `android/app/src/main/kotlin/com/soplay/sozo/MainActivity.kt`
* **Technical Justification:** These are purely internal Dart-to-Kotlin binary communication channels that are never exposed to the user. Retaining the established channel names guarantees zero breakage in native communication pipelines.

### 4.5 Production Universal Link Host (`sozo.azamov.me`)
* **Identifier:** `sozo.azamov.me`
* **Location:** `android/app/src/main/AndroidManifest.xml` (`autoVerify="true"` intent filter)
* **Technical Justification:** Android App Links and iOS Universal Links depend on the remote `.well-known/assetlinks.json` and `apple-app-site-association` hosted at `https://sozo.azamov.me`. Retaining the host filter in `AndroidManifest.xml` preserves deep link routing for historical links.

---

## 5. RECONCILIATION SUMMARY

* **User Perception:** 100% Kaizoku. All names, logos, themes, window titles, launchers, about screens, and strings display "Kaizoku".
* **System Stability:** 100% Preserved. Backend networking, native channels, Firebase bindings, and database schemas remain fully functional.
