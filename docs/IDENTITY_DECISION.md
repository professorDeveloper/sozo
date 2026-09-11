# KAIZOKU — IDENTITY ARCHITECTURE & MIGRATION DECISION

> **Core Strategic Decision:** Should Kaizoku be released as an seamless in-place upgrade/continuation of the existing Sozo application, or as a completely brand-new independent application with new bundle identifiers and database namespaces?

---

## 1. SCENARIO ANALYSIS

### 1.1 Scenario A: Kaizoku is an In-Place Upgrade / Continuation of Sozo

* **Concept:** Kaizoku is published as the direct v4.0 evolution of Sozo.
* **Application ID & Bundle ID:**
  - Android `applicationId`: Preserved as `com.soplay.sozo`.
  - iOS `PRODUCT_BUNDLE_IDENTIFIER`: Preserved as `com.soplay.soplay` (or `com.soplay.sozo`).
  - Dart Package Name: Preserved as `soplay`.
  - User-Facing Display Name: Changed to **Kaizoku**.
* **Upgrade Path & Installed-User Experience:**
  - Users receive Kaizoku as a standard app update (over Telegram APK distribution, GitHub release, or app installer).
  - The OS replaces the APK binary in place.
* **Database & Storage Compatibility:**
  - Zero data loss. All existing Hive boxes (`history_box`, `download_box`, `favorites_box`, `auth_box`) remain in their existing filesystem paths under the app's sandboxed data directory.
  - Downloaded video files, manga chapters, and watch streak records remain instantly accessible without any migration scripts.
* **Firebase Implications:**
  - Existing `google-services.json` remains 100% valid because the package name `com.soplay.sozo` matches.
  - Push notifications, analytics, and Crashlytics continue working without requiring a new Firebase project or regenerated credentials.
* **Deep Links & Intent Filters:**
  - Existing `sozo.azamov.me` App Links continue to resolve and open the app.
  - Existing `sozo://` custom scheme continues to work, while adding `kaizoku://` as a primary scheme.
* **Native Channels & IPC:**
  - Existing `soplay/*` MethodChannels between Dart and Kotlin continue without discrepancy.
* **Risks:** The internal technical identity (`com.soplay.sozo`) retains legacy naming on disk and in OS package lists (`pm list packages`).

---

### 1.2 Scenario B: Kaizoku is a Brand-New Independent Application

* **Concept:** Kaizoku is launched as an entirely clean, standalone product alongside or replacing Sozo.
* **Application ID & Bundle ID:**
  - Android `applicationId`: Changed to `com.kaizoku.app` (or `me.kaizoku.stream`).
  - iOS `PRODUCT_BUNDLE_IDENTIFIER`: Changed to `com.kaizoku.app`.
  - Dart Package Name: Renamed from `soplay` to `kaizoku` across `pubspec.yaml` and 600+ source files.
  - Native MethodChannels: Renamed to `kaizoku/*`.
* **Upgrade Path & Installed-User Experience:**
  - Users cannot update in place. The OS treats Kaizoku as an entirely separate app.
  - Users must download and install Kaizoku separately. Both apps can exist simultaneously on the device.
* **Database & Storage Compatibility:**
  - **Severe Data Isolation:** Android and iOS sandboxing strictly isolates app directories. Kaizoku cannot read Sozo's Hive boxes or downloaded files.
  - Requires writing an explicit inter-app migration routine or external JSON backup export/import (`/backup`) to transfer history, downloads, and settings.
* **Firebase Implications:**
  - The existing `google-services.json` and `GoogleService-Info.plist` will immediately reject the new package name, causing build failures or runtime `FirebaseException`.
  - A new Firebase project must be created, or new Android/iOS client apps registered in Firebase Console to generate new configuration files.
* **Deep Links & Intent Filters:**
  - Digital Asset Links (`assetlinks.json`) and Apple App Site Association (`apple-app-site-association`) on `sozo.azamov.me` will NOT verify `com.kaizoku.app`.
  - A new web domain (e.g. `kaizoku.stream`) must be deployed with SHA-256 fingerprint verification to support App Links.
* **Native Channels & IPC:**
  - Requires synchronized renaming of all 16 MethodChannels across Dart and Kotlin.
* **Risks:** High risk of breaking Firebase authentication, losing user offline libraries, breaking installed user bases, and requiring external infrastructure changes.

---

## 2. TECHNICAL RECOMMENDATION

### **Recommendation: Scenario A (Hybrid Continuation)**
* **Why:** In modern mobile and desktop software architecture, **Brand Identity belongs to the presentation and OS display layer**, while **Technical Identifiers belong to binary stability and transport layers**.
* Changing the package name and application ID provides zero visual or functional value to the end user, while introducing severe breaking risks (breaking local databases, breaking Firebase push notifications, breaking Keiyoushi extension DexClassLoaders, and breaking seamless APK updates).
* **Execution Strategy:**
  1. Transform 100% of user-facing identity, UI, typography, window headers, launcher names, and assets to **Kaizoku**.
  2. Add `kaizoku://` deep-link scheme while preserving `sozo://` compatibility.
  3. Keep binary package identifiers (`com.soplay.sozo`, `package:soplay/...`, `soplay/*`) intact under the hood.

---

## 3. CONTROLLED REPOSITORY-WIDE RENAMING MATRIX

| Existing Identifier | Type | User-Facing? | Safe to Rename? | Technical Reason | Recommended Action |
|---|---|:---:|:---:|---|---|
| `"app_name": "Sozo"` | Localization String | **YES** | **YES** | User-facing application title in 11 translation files. | **MIGRATE TO "Kaizoku"** |
| `android:label="Sozo"` | Android Manifest Label| **YES** | **YES** | Text shown beneath app icon on Android launcher. | **MIGRATE TO "Kaizoku"** |
| `@drawable/tv_banner` | Android TV Asset | **YES** | **YES** | Visual tile on Android TV Leanback launcher. | **REPLACE WITH Kaizoku Banner** |
| `CFBundleDisplayName` | iOS Plist Metadata | **YES** | **YES** | Text shown beneath app icon on iOS home screen. | **MIGRATE TO "Kaizoku"** |
| `PRODUCT_NAME = Sozo` | macOS Config | **YES** | **YES** | macOS menu bar and window title. | **MIGRATE TO "Kaizoku"** |
| `window.Create(L"Sozo")` | Windows Win32 Title | **YES** | **YES** | Native title bar text on Windows. | **MIGRATE TO "Kaizoku"** |
| `gtk_header_bar_set_title` | Linux GTK Title | **YES** | **YES** | Native header bar title on Linux. | **MIGRATE TO "Kaizoku"** |
| `SozoMark` / `sozo_mark.svg`| Brand Vector Asset | **YES** | **YES** | Visual brand logo on splash and header. | **REPLACE WITH KaizokuMark** |
| `"Watching Sozo"` | Discord RPC Activity | **YES** | **YES** | Text shown on user's public Discord profile. | **MIGRATE TO "Watching Kaizoku"**|
| `AboutPage` branding | Presentation UI | **YES** | **YES** | About screen text, version info, credits. | **MIGRATE TO "Kaizoku"** |
| `https://apisozo.azamov.me/api`| Backend Server Host | NO | **NO** | Active production API server. Modifying causes DNS failure. | **PRESERVE** |
| `https://apisozo.azamov.me` | Socket.io Host | NO | **NO** | Active WatchParty WebSocket server. | **PRESERVE** |
| `name: soplay` | Dart Package Name | NO | **NO** | Prefix of 600+ imports. Renaming breaks codebase imports. | **PRESERVE** |
| `com.soplay.sozo` | Android ApplicationId | NO | **NO (Scenario A)**| Preserves user data upgrade path and Firebase bindings. | **PRESERVE** |
| `com.soplay.sozo` | Kotlin Package Name | NO | **NO (Scenario A)**| Internal native code namespace. | **PRESERVE** |
| `soplay/*` (16 channels)| MethodChannel Name | NO | **NO** | Binary IPC between Dart and Kotlin. No user visibility. | **PRESERVE** |
| `sozo://` | Custom URL Scheme | NO | **ADAPTIVE** | Add `kaizoku://` while retaining `sozo://` fallback. | **ADD `kaizoku://`** |
| `sozo.azamov.me` | App Link Host Filter | NO | **NO** | Remote host verifying `assetlinks.json`. | **PRESERVE** |
| `auth_box`, `history_box` | Hive Box Keys | NO | **NO** | Local database box names on disk. | **PRESERVE** |
| `settings_box`, `streak_box`| Hive Box Keys | NO | **NO** | Local database box names on disk. | **PRESERVE** |
