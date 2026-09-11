# KAIZOKU — COMPREHENSIVE UX & INTERACTION REQUIREMENTS

> **Design Independence Statement:** Visual styling, color palettes, and typographic styling are deliberately decoupled from functional UX requirements. Visual identity will be finalized in Phase 1 after all functional behaviors are validated.
> 
> *This document establishes the user interaction contract across Handheld, Desktop, and Television form factors.*

---

## 1. INFORMATION HIERARCHY & CONTENT DENSITY

### 1.1 Discovery & Browsing Hierarchy
* **Level 1 (Immediate Focus):** Featured / Spotlight media item displaying high-resolution artwork, title, key metadata (year, rating, genres, content mode tag), and prominent "Play" / "Continue" call-to-action.
* **Level 2 (Active Engagement):** "Continue Watching" row positioned immediately below the hero, rendering episode numbers and a clear visual progress bar indicating watch percentage.
* **Level 3 (Exploration):** Horizontally scrolling categorized rails grouped by genre, trending status, or release cadence.
* **Level 4 (Direct Access):** Quick navigation affordances for search, library, and settings.

### 1.2 Required Content Density by Device
* **Mobile Phones (Compact Viewport, 360-430dp width):**
  - Card Grids: Strictly 2 to 3 columns for poster cards (2:3 aspect ratio).
  - Horizontal Rails: 2.2 to 2.5 visible cards per viewport width to visually afford horizontal scrollability.
  - Episode Lists: Compact list tiles or horizontal pill carousels to avoid infinite vertical scrolling.
* **Tablets & Small Desktops (600-1024dp width):**
  - Card Grids: 4 to 5 columns.
  - Rails: 4 to 5 visible cards.
* **Large Desktop & Televisions (1080p / 4K Displays, 1280dp+ width):**
  - Card Grids: 6 to 8 columns with large artwork and clear title captions.
  - Multi-pane views: Split-screen layouts for episode selection and title details.

---

## 2. NAVIGATION INTERACTION REQUIREMENTS

### 2.1 Mobile Phone Navigation Contract
* Single-hand reachable navigation anchored at the bottom of the screen.
* Safe Area padding strictly enforced above the system home indicator / gesture bar.
* Dynamic Tab Management: Must support customizing visible tabs (minimum 4, maximum 6) while enforcing mandatory retention of Home and Profile.
* Pull-to-refresh affordance on all feed and catalogue screens.

### 2.2 Desktop Navigation Contract
* Left-anchored persistent navigation rail or sidebar, freeing vertical space for widescreen content.
* Hover states with smooth scale/glow transitions and informative tooltips for icon-only representations.
* Custom frameless window controls (Minimize, Maximize/Restore, Close) cleanly integrated into the top bar.
* Pointer & Scroll Affordances: Horizontal lists must support mouse wheel horizontal scrolling, drag-to-scroll, and discrete left/right arrow buttons.

### 2.3 Android TV (10-Foot Leanback) Navigation Contract
* **Touchless Operation:** 100% of interactive surfaces must be operable via standard 5-way directional pad (Up, Down, Left, Right, Select).
* **Focus Traversal & Rings:**
  - Active item must display an unambiguous, high-contrast focus ring with slight scale elevation.
  - Focus must never be lost into an invisible or empty element.
  - Auto-scrolling must ensure the focused element is centered in the viewport before user action.
* **Back-Stack Behavior:**
  - Pressing BACK inside content area moves focus to the left navigation rail.
  - Pressing BACK on the rail switches to the Home tab.
  - Pressing BACK on the Home tab prompts confirmation to exit.

---

## 3. PLAYBACK INTERACTION REQUIREMENTS

### 3.1 Handheld Media Controls
* Touch-driven gesture zones:
  - Left half vertical drag: Brightness adjustment with live onscreen indicator.
  - Right half vertical drag: Volume adjustment with live onscreen indicator.
  - Double-tap left/right: Configurable seek jump (default 10s).
  - Long press anywhere: 2x speed boost while held.
* Auto-hiding control overlays: Controls vanish after 3 seconds of inactivity during playback.
* Picture-in-Picture (PiP): Must trigger automatically when home gesture/button is pressed during active playback.

### 3.2 Television Media Controls
* Remote key mappings:
  - DPAD_CENTER: Instant Play / Pause toggle.
  - DPAD_LEFT / RIGHT: Seek backward / forward 10 seconds.
  - DPAD_DOWN: Reveals bottom scrubber and track selector drawer.
  - DPAD_UP: Reveals top media info and episode switcher.
  - Media Keys (KEY_PLAY, KEY_PAUSE, KEY_FAST_FORWARD, KEY_REWIND): Direct hardware binding.

### 3.3 Desktop Media Controls
* Full keyboard shortcut support:
  - `Space` / `K`: Play/Pause.
  - `Left` / `Right`: Seek 5 seconds.
  - `J` / `L`: Seek 10 seconds.
  - `Up` / `Down`: Volume up/down 5%.
  - `M`: Mute toggle.
  - `F`: Fullscreen toggle.
  - `Escape`: Exit fullscreen / dismiss overlays.

---

## 4. DISCOVERY & SEARCH UX REQUIREMENTS

* Instant live search: Search field submits queries with debounce (300ms) without requiring keyboard submit press.
* Provider source filter: Clear chip selector indicating which provider generated the result.
* Search history: Recent searches displayed as dismissible tags below the search bar.
* Cross-provider parallel search: Results populate incrementally as individual providers return; slow or failing providers must not block display of successful results.

---

## 5. ACCESSIBILITY REQUIREMENTS

* **Contrast Ratios:** Text must satisfy WCAG AA standards (minimum 4.5:1 against background surfaces).
* **Target Sizes:** Touch targets on mobile must be at least 48x48dp. Focus targets on TV must be at least 64x64dp.
* **Screen Reader Semantics:** Media posters must expose `Semantics(label: "<Title>, Rating: <X>")`.
* **RTL Language Support:** Layout must cleanly mirror for Arabic (`ar`) locales without corrupting physical video seek bars or audio volume sliders.
