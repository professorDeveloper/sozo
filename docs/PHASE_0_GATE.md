# KAIZOKU — PHASE 0 VALIDATION & ARCHITECTURE GATE

> **Gate Decision:** This document serves as the formal architectural checkpoint before any production code modification or Phase 1 implementation begins.

---

## 1. VERIFIED FACTS (Directly Established from Code, Config & Tests)

1. **Repository & Workspace Boundaries:**
   - Application Root: `d:/sandcat2.0/sozo` (Contains complete Flutter app, `.git`, `lib`, `android`, `ios`, `windows`, `linux`, `macos`, `test`).
   - ECC Root: `d:/sandcat2.0/.agents` (Contains authoritative project ECC installation with rules, agents, skills, workflows).
   - Documentation Root: `d:/sandcat2.0/sozo/docs` (Mirrored at `d:/sandcat2.0/docs`).
   - Out-of-bounds directories (`D:\sandcat`, `D:\tools`, `D:\Software`, `D:\Backup`, `D:\ECC`) are strictly excluded.
2. **Backend Server Identity:**
   - Active production server is `https://apisozo.azamov.me/api` (XOR obfuscated in `AppConstants`).
   - WebSocket origin is `https://apisozo.azamov.me` (Socket.io `/watch` namespace).
   - 36 distinct REST endpoints in active use.
3. **Backend Independence:**
   - Manga (Keiyoushi), Aniyomi (APKs), CloudStream (.cs3), Embedded TorrServer, Offline Downloads, AniList, MyAnimeList, OpenSubtitles, and YouTube trailers are **completely decoupled from `apisozo.azamov.me`** and operate independently.
4. **Platform Toolchains on Host:**
   - JDK 17 installed in `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\bin` and `D:\tools\jdk-17`.
   - Android SDK installed in `D:\tools\android-sdk`.
   - Flutter SDK is **not currently present in `$env:PATH`**; CI workflow (`.github/workflows/ci.yml`) automates analysis, test, and debug APK build.
5. **Database & Disk Architecture:**
   - 9 Hive boxes; relative path layout for media storage (`DownloadLayout`); startup integrity sweep (`verifyAll()`).
6. **Existing Test Coverage:**
   - 65 test suites exist. High coverage on player tracks, subtitles, episode windows, and search relevance. Zero coverage on AuthBloc, AppLock, LiveTV, and TV Remote.

---

## 2. INFERRED (Reasonable Conclusions Requiring User Confirmation)

1. **Product Evolution Strategy:**
   - Kaizoku is best deployed under **Scenario A (In-Place Continuation)**, preserving `com.soplay.sozo` and `package:soplay/...` while completely replacing user-facing brand, metadata, and frontend presentation.
2. **Design Language:**
   - The user requires a high-density, media-first streaming interface with full TV remote, desktop mouse/keyboard, and mobile touch ergonomics.
3. **Build & Release Strategy:**
   - Production builds and automated testing will primarily execute in GitHub Actions CI/CD or require configuring local Flutter SDK in PATH.

---

## 3. UNKNOWN (Cannot Be Established from Local Files Alone)

1. **Backend Server Lifecycle & Administrative Ownership:**
   - Whether `apisozo.azamov.me` will remain permanently operational, be migrated to a new domain by the user's infrastructure team, or eventually be replaced with self-hosted instances.
2. **User Identity Preference:**
   - Whether the product owners explicitly demand Scenario B (clean package rename to `com.kaizoku.app`) despite the data isolation and Firebase re-configuration costs.
3. **Aesthetic Style Preferences:**
   - The precise visual theme, color palette, and micro-interaction styling desired by the user for Kaizoku.

---

## 4. HIGH-RISK DECISIONS

1. **Renaming Backend Host String:**
   - High Risk: Changing `apisozo.azamov.me` to `apikaizoku...` without backend DNS readiness will instantly sever catalogue discovery, auth, and playback.
2. **Renaming Android ApplicationId (`com.soplay.sozo`):**
   - High Risk: Breaks existing installed user upgrades, breaks Firebase push notifications, and blocks access to existing local Hive databases.
3. **Renaming Dart Package (`soplay`):**
   - High Risk: Requires modifying import statements in 600+ source files, risking compilation errors and merge conflicts.
4. **Modifying Android R8 Proguard Settings:**
   - High Risk: Enabling `isMinifyEnabled = true` will break reflection for Keiyoushi and CloudStream DexClassLoader extension APKs.

---

## 5. RECOMMENDED ARCHITECTURE & ROADMAP

1. **Identity Migration Strategy (Scenario A):**
   - 100% user-facing rebranding: App title, desktop titles, Linux GTK headers, macOS configs, Android launcher labels, TV banners, translations, brand marks, and about screens become **Kaizoku**.
   - Preserve internal binary identifiers (`com.soplay.sozo`, `package:soplay/...`, `soplay/*` MethodChannels).
2. **Presentation Decoupling:**
   - Completely rewrite the UI layer using discrete platform shells (`MobileNavShell`, `DesktopNavShell`, `TvNavShell`).
   - Replace legacy widgets with a brand-new, modern Kaizoku Design System.
3. **Pre-Implementation TDD:**
   - Author regression test suites for currently untested critical subsystems (`AuthBloc`, `AppLock`, `LiveTvService`) before refactoring presentation.

---

## 6. IMPLEMENTATION READY?

```
NO
```

### Justification for "NO" Gate:
1. **Decision Gate 1 (Identity):** User review and formal sign-off between **Scenario A (Continuation)** vs **Scenario B (Clean Slate)** in [docs/IDENTITY_DECISION.md](file:///d:/sandcat2.0/sozo/docs/IDENTITY_DECISION.md) is required.
2. **Decision Gate 2 (Design):** User review of [docs/UX_REQUIREMENTS.md](file:///d:/sandcat2.0/sozo/docs/UX_REQUIREMENTS.md) and aesthetic direction alignment is required before constructing Phase 1 design system primitives.
3. **Decision Gate 3 (Environment):** Confirmation on whether local Flutter SDK will be installed in PATH or if verification will be performed via headless scripts / CI.

*All application code remains unmodified. Standing by for user decision.*
