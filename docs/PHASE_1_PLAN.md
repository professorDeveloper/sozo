# KAIZOKU — PHASE 1 IMPLEMENTATION PLAN

> **Execution Mandate:** Scenario A (In-Place Continuation).  
> **Strategic Objective:** Establish the test safety net, construct decoupled presentation architecture primitives, propose design system directions, and begin surgical, incremental implementation while preserving 100% functional parity and technical compatibility.
> 
> *Strict Law: Functional parity has absolute priority. Zero production logic rewrites without test gating.*

---

## 1. ARCHITECTURE CHANGES & PRESENTATION BOUNDARIES

### 1.1 Separation of Concerns
Currently, `lib/features/main/presentation/pages/main_page.dart` (1,701 lines) combines mobile bottom navigation capsule, Android TV focus rail, and desktop layout handling into a single monolithic widget.
* **Target Refactor (Phase 1B):**
  Extract presentation shell rendering into dedicated, single-responsibility adaptive shell widgets:
  1. `lib/core/presentation/shells/mobile_nav_shell.dart`: Pure mobile phone navigation (floating glass capsule, safe areas, haptic micro-interactions).
  2. `lib/core/presentation/shells/desktop_nav_shell.dart`: Desktop widescreen presentation (persistent left rail, hover states, frameless window title bar).
  3. `lib/core/presentation/shells/tv_nav_shell.dart`: Android TV Leanback shell (10-foot D-pad rail, explicit focus scope restoration, auto-centering).
* **Domain & Data Isolation:**
  - `lib/core/` and `lib/features/*/domain/` and `data/` remain strictly decoupled from presentation.
  - Zero modifications to Hive box identifiers, database schemas, or API endpoint formats.

---

## 2. PHASE 1A — TEST SAFETY NET (TDD IMPLEMENTATION)

Before touching presentation widgets or refactoring existing pages, we create isolated unit and widget regression tests for the zero-coverage subsystems identified in Phase 0:

### 2.1 Test Suites to Create
1. `test/features/auth/auth_bloc_test.dart`:
   - Assert `AuthLoginRequested` -> `AuthLoading` -> `AuthAuthenticated(UserEntity)`.
   - Assert `AuthLoginRequested` with invalid credentials -> `AuthError`.
   - Assert `AuthSessionExpired` -> Clears auth box, emits `AuthUnauthenticated`.
2. `test/features/auth/token_refresher_test.dart`:
   - Assert mutex locking prevents multiple concurrent refresh calls on simultaneous 401s.
3. `test/features/app_lock/app_lock_repository_test.dart`:
   - Assert PIN hashing with salt produces consistent hash.
   - Assert `verifyPin` returns true on matching PIN, false on wrong PIN.
   - Assert `isBiometricAvailable` and `setBiometricPreferred`.
4. `test/features/live_tv/live_tv_service_test.dart`:
   - Assert parsing of `/channels/categories` JSON into `LiveFolder`, `LiveCountry`, and `LiveChannel`.
   - Assert `LiveProgramme.progressAt(DateTime)` calculates bar factor clamp between 0.02 and 1.0.
5. `test/features/watch_party/watch_party_service_test.dart`:
   - Assert room code parsing, member list synchronization, and event emissions.
6. `test/features/link_tv/link_tv_bloc_test.dart`:
   - Assert TV pairing code generation, polling status, and failure recovery.
7. `test/features/remote/remote_control_service_test.dart`:
   - Assert D-pad navigation commands (`KEY_UP`, `KEY_DOWN`, `KEY_SELECT`, `KEY_BACK`) format correctly.

---

## 3. PHASE 1B — ARCHITECTURE PRIMITIVES & ADAPTIVE LAYOUT

### 3.1 Responsive Breakpoint System
Create `lib/core/presentation/responsive/kaizoku_breakpoints.dart`:
* **Handheld / Mobile:** `< 600dp` width or `isMobilePlatform`.
* **Tablet / Foldable:** `600dp - 1024dp` width.
* **Desktop / Monitor:** `>= 1024dp` width and `isDesktopPlatform`.
* **Television:** `isTvPlatform` (takes priority over screen dimensions).

### 3.2 TV Interaction Architecture
* Solidify `TvFocusable` and `TvShortcuts` wrappers.
* Enforce explicit `FocusScopeNode` on every content page and navigation rail to guarantee deterministic focus restoration upon D-pad navigation and Back-button presses.

### 3.3 Desktop Interaction Architecture
* Enhance `DesktopWindow` and `WindowTitleBar` integration.
* Register standard keyboard shortcut maps (Space, Arrows, J/K/L, Mute, Fullscreen, Escape).
* Ensure drag-to-scroll is active for mouse/trackpad pointer devices across all carousels.

---

## 4. PHASE 1C — KAIZOKU DESIGN SYSTEM PROPOSALS

In accordance with Phase 0 Gate requirements, the visual design is **not locked**. Below are three candidate visual design directions rooted in the functional UX requirements for user review:

### Direction 1: Cyber-Obsidian & Neon Crimson (Recommended)
* **Canvas:** Deep void black (`#07080B`) with subtle dark blue-grey surface cards (`#12141C`).
* **Accents:** Neon Crimson (`#FF2E55`) for primary actions, Solar Amber (`#FFB703`) for TV focus rings and stars.
* **Atmosphere:** High-contrast, sharp geometric cards (12px radius), frosted glass navigation capsule with backdrop blur. High-tech, cinematic, unapologetically rogue.

### Direction 2: Deep Midnight & Astral Cyan
* **Canvas:** Dark navy obsidian (`#0B0E14`) with elevated slate surfaces (`#161B26`).
* **Accents:** Electric Cyan (`#00E5FF`) for primary buttons and seek sliders, Laser Coral (`#FF5376`) for tags.
* **Atmosphere:** Sleek, modern streaming aesthetic resembling premium sci-fi HUD interfaces.

### Direction 3: Studio Monochrome & Minimalist Gold
* **Canvas:** Neutral matte carbon (`#0E0F12`) with pure black AMOLED cards (`#000000`).
* **Accents:** Warm Imperial Gold (`#E0A96D`) for subtle highlights and primary indicators.
* **Atmosphere:** Understated luxury, gallery-style framing of media posters with minimal chrome.

---

## 5. MIGRATION & INCREMENTAL ORDER

```
Phase 1A: Test Safety Net (Auth, AppLock, LiveTV, WatchParty, Remote)
    │
    ▼
Phase 1B: Architectural Primitives (Shells, Breakpoints, TV/Desktop Primitives)
    │
    ▼
Phase 1C: Design System Foundations (Color tokens, typography, Kaizoku components)
    │
    ▼
Phase 2: Product Identity & Platform Metadata (Kaizoku strings, banners, windows, manifests)
    │
    ▼
Phase 3: Core Discovery & Home Presentation (Hero banner, category rails, view all)
    │
    ▼
Phase 4: Media Playback & Reader (Fullscreen player controls, scrubber, manga/novel)
    │
    ▼
Phase 5: User State & Library (Downloads, history, favorites, private vault)
    │
    ▼
Phase 6: Verification, ECC Multi-Agent Review & Final Gate
```

---

## 6. REGRESSION & ROLLBACK STRATEGY

1. **Git Isolation:** Every phase is developed incrementally on clean, atomic commit boundaries.
2. **Backward Compatible Fallback:** Old routes and schemas remain valid throughout transformation; no destructive deletions of working data sources or providers.
3. **Rollback Safety:** If any architectural primitive introduces build or runtime failure, git revert of that atomic step immediately restores the previous stable working tree.
