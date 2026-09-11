# KAIZOKU — COMPLETE DESIGN SYSTEM SPECIFICATION

> **Identity:** KAIZOKU (海賊 — "The Pirate / The Rogue / The Rebel Streamer")  
> **Aesthetic Philosophy:** Cinematic Obsidian & Crimson Gold. Premium, sharp, futuristic streaming experience. High contrast, ultra-clean glassmorphic layers, responsive typography, and tactile micro-interactions.
> 
> *The Kaizoku UI is NOT a skin or cosmetic tweak of Sozo. It is an entirely redesigned visual and interactive language.*

---

## 1. COLOR TOKENS & SURFACES

### 1.1 Core Palette
```
┌──────────────────┬─────────────────┬──────────────────────────────────────────┐
│ Token Name       │ Hex Value       │ Role / Usage                             │
├──────────────────┼─────────────────┼──────────────────────────────────────────┤
│ bgPrimary        │ #0A0B0E         │ Deep Void Obsidian (Main canvas)        │
│ bgSecondary      │ #12141A         │ Dark Charcoal Surface (Cards, sidebars)  │
│ bgElevated       │ #1A1D26         │ Elevated Surface (Modals, popups, sheets)│
│ bgGlass          │ #141721 (80%)   │ Frosted Glass (Nav capsules, toolbars)   │
│ accentPrimary    │ #FF2E55         │ Kaizoku Neon Crimson (Primary actions)   │
│ accentSecondary  │ #FF9F1C         │ Solar Amber (Highlights, ratings, stars) │
│ accentTertiary   │ #2EC4B6         │ Electric Mint (Completed, downloads)     │
│ textPrimary      │ #F8F9FA         │ High-emphasis text (Headings, titles)    │
│ textSecondary    │ #A0A5B5         │ Medium-emphasis text (Subtitles, meta)   │
│ textMuted        │ #5D6375         │ Low-emphasis text (Placeholders, labels) │
│ borderSubtle     │ #232736         │ Hairline dividers, card outlines         │
│ borderActive     │ #FF2E55         │ Focused / Selected border highlight      │
│ tvFocusRing      │ #FF9F1C         │ High-visibility 10-foot TV remote ring   │
└──────────────────┴─────────────────┴──────────────────────────────────────────┘
```

### 1.2 AMOLED Pure Black Tier
* When AMOLED mode is activated:
  - `bgPrimary`: `#000000` (Pure Black)
  - `bgSecondary`: `#08090C`
  - `bgElevated`: `#101217`
  - Card borders become `#1A1D24` with ultra-crisp edge definition.

---

## 2. TYPOGRAPHY SYSTEM

Kaizoku utilizes a bold, cinematic typographic scale with high legibility across handheld screens, desktop monitors, and 10-foot television displays:

| Style Name | Size (Mobile) | Size (Desktop/TV) | Weight | Line Height | Letter Spacing |
|---|---|---|---|---|---|
| **Display Large** | 32px | 44px | 900 (Black) | 1.15 | -0.5px |
| **Display Medium** | 26px | 34px | 800 (ExtraBold)| 1.2 | -0.3px |
| **Headline Large** | 20px | 26px | 700 (Bold) | 1.25 | -0.2px |
| **Headline Medium**| 17px | 20px | 700 (Bold) | 1.3 | 0.0px |
| **Body Large** | 15px | 16px | 500 (Medium) | 1.4 | +0.1px |
| **Body Medium** | 13px | 14px | 400 (Regular) | 1.45 | +0.15px |
| **Label Small** | 11px | 12px | 600 (SemiBold)| 1.3 | +0.5px |
| **Badge / Overline**| 10px | 11px | 800 (ExtraBold)| 1.2 | +1.0px (All Caps)|

---

## 3. SPACING, GRID & GEOMETRY

### 3.1 Spacing Scale
* `space4`: 4px (tight micro-spacing between chips and icons)
* `space8`: 8px (standard padding between list items and badges)
* `space12`: 12px (card internal padding, metadata gaps)
* `space16`: 16px (page gutter for mobile, grid gutter)
* `space24`: 24px (section margins, header clearance)
* `space32`: 32px (desktop layout gutters, hero offsets)
* `space48`: 48px (major section separators on desktop/TV)

### 3.2 Corner Radii
* `radiusCard`: 14px (media posters, category cards)
* `radiusButton`: 10px (interactive buttons, chips)
* `radiusCapsule`: 999px (nav capsules, search pill, badges)
* `radiusSheet`: 24px top radius for bottom sheets
* `radiusDialog`: 18px for center modals

---

## 4. COMPONENT SPECIFICATIONS

### 4.1 Media Cards (`KaizokuMediaCard`)
* **Aspect Ratios:**
  - Standard Poster: `2:3` (Movies, Series, Anime, Manga)
  - Landscape Backdrop: `16:9` (Live TV, Episodes, Shorts)
  - Square Avatar: `1:1` (Actors, Profiles)
* **Visual Styling:**
  - Clip-rounded corners (14px).
  - Subtle dark stroke (`borderSubtle`) to separate from dark canvas.
  - Multi-stop bottom scrim gradient (`transparent` to `rgba(10, 11, 14, 0.95)`) for title overlay.
  - Top-left badge: Quality indicator (4K, 1080p, HDR) in frosted capsule.
  - Top-right badge: Provider tag or episode count.
  - Bottom progress bar: 3px neon crimson bar showing watch progress percentage.
* **Interactions:**
  - Mobile: Instant tap response with haptic feedback (`HapticFeedback.lightImpact`).
  - Desktop: Smooth hover zoom (`1.04x` scale, 180ms easeOutCubic) + elevated drop shadow (`rgba(255, 46, 85, 0.2)`).
  - TV: Animated focus scale (`1.08x`), 3.5px amber ring (`tvFocusRing`), smooth auto-scroll to center.

### 4.2 Buttons (`KaizokuButton`)
* **Primary Variant:** Solid neon crimson `#FF2E55` with bold white text. Gradient sheen on hover.
* **Secondary Variant:** Dark obsidian `#1A1D26` surface with subtle border `#232736` and white text.
* **Ghost / Icon Variant:** Translucent circular glass background (`rgba(255, 255, 255, 0.08)`).
* **Press State:** Instant scale down to `0.96x` with haptic feedback.

### 4.3 Navigation Shells
* **Mobile Phone (`KaizokuMobileNav`):**
  - Floating frosted glass capsule positioned 16px above bottom screen edge.
  - Gaussian blur filter (Sigma 20) with subtle dark tint.
  - Icons animate with spring physics on tab switch; active indicator features subtle crimson glow.
* **Desktop (`KaizokuDesktopNav`):**
  - Slim vertical side rail (72px collapsed, 220px expanded on hover).
  - High-contrast icons, tooltips on hover, and active state pill indicator.
* **Android TV (`KaizokuTvNav`):**
  - Left-hand 10-foot rail with large 28px icons and labels.
  - Active focus ring clearly indicates current rail position.
  - Pressing DPAD_RIGHT navigates directly into the active tab content area.

### 4.4 Player Controls (`KaizokuPlayerOverlay`)
* **Header Bar:** Back button, media title, episode number/title, Cast button, external player icon.
* **Scrubber Bar:** High-visibility slider with current position, total duration, and live seek preview thumbnail card.
* **Quick Toggles:**
  - Audio track selector (Sub, Dub, Dual, commentary).
  - Subtitle track selector + Auto-translate quick toggle.
  - Anime4K shader toggle (Off, Low, Medium, High).
  - Playback speed (0.5x, 1.0x, 1.25x, 1.5x, 2.0x).
  - Episode quick-drawer (sliding horizontal carousel).

### 4.5 Modals, Bottom Sheets & Dialogs
* **Bottom Sheet:** Frosted dark backdrop with top drag pill. Smooth spring-loaded entrance.
* **TV Dialog:** Large center card with high contrast D-pad selectable buttons. Default autofocus on primary action.

### 4.6 Empty, Error & Loading Skeletons
* **Skeleton:** Dynamic shimmer effect with angled linear gradient moving across dark charcoal boxes.
* **Empty States:** Custom vector artwork with bold title, descriptive subtitle, and actionable button ("Explore Titles", "Manage Sources").
* **Error States:** Non-intrusive banner or card with exact error explanation and prominent "Retry" button.

---

## 5. ACCESSIBILITY & MOTION GUIDELINES

### 5.1 Contrast & Accessibility
* All text styles satisfy WCAG AA contrast ratio (> 4.5:1 against respective backgrounds).
* Large typography satisfies WCAG AAA (> 7:1).
* Focus indicators maintain at least 3:1 contrast against surrounding dark surfaces.

### 5.2 Motion & Micro-interactions
* **Durations:**
  - Micro-interactions (taps, hovers, focus): 150ms - 200ms.
  - Sheet / Modal transitions: 250ms - 300ms.
  - Page routes: 200ms - 250ms.
* **Curves:**
  - Entrance: `Curves.easeOutCubic` or `Curves.decelerate`.
  - Exit: `Curves.easeInCubic`.
  - Focus scale: `Curves.easeOutBack` for tactile pop.
