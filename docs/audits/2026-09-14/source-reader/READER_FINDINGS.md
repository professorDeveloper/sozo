# Reader UX audit — 2026-09-14

Production was read-only. The test harness imports the actual `ReaderPage`; only provider data, settings, download repository, and history service are substituted. Tests ran on the macOS Flutter test host with a 1200×800 surface. No device/network execution is claimed. Six characterization tests passed: five reproduce defects (including progress lost at a chapter transition), one disproves a suspected swipe problem. Passing characterization tests mean the defects were observed, not that functionality is correct.

Command: `flutter test --no-pub docs/audits/2026-09-14/source-reader/repros/reader_audit_test.dart --reporter expanded`

## Confirmed by actual widget tests

### R1 — P1: Spread reader commands the wrong controller and ignores resume

- Trigger: horizontal mode, spread enabled, landscape; open 9-page chapter with `resumePage: 5`, then press ArrowRight (same `_goToPage` path as tap zones and slider).
- Actual: attached spread controller is at slot 0 (cover), while counter says `6/9`. ArrowRight throws `PageController is not attached to a PageView`.
- Impact: spread cannot resume accurately; tap/keyboard/slider navigation fails. No assumption about a fatal process crash in release is made.
- Cause: `lib/features/manga/presentation/pages/reader_page.dart:66` creates spread controller without initial position; loading initializes only `_pageController` at 218–221; `_goToPage` at 322–327 always commands `_pageController`, but spread view at 668 mounts `_spreadController`. There is no page-to-slot routing or resume synchronization.

### R2 — P1: Novel PageDown/Space/arrows skip whole unread chapters

- Trigger: open long novel chapter at its beginning, even in vertical mode; press PageDown.
- Actual: provider calls change from `one` to `two`; prose is not scrolled. Desktop ArrowDown/Space use same path. With horizontal preference selected, left/right text-area tap zones also use the chapter-jump path.
- Impact: ordinary reading navigation unexpectedly leaves unread text and can skip several chapters on key repeat.
- Cause: `reader_page.dart:334` compares current image-page index against zero image pages and invokes `_nextChapter`; `reader_page.dart:430` sends PageDown/Space/ArrowDown there. Novel is always a scroll view at 544, but shared input handling does not branch on `_html`.

### R3 — P2: Novel progress UI reports `1/0` and cannot seek

- Trigger: any successfully loaded HTML novel chapter.
- Actual: bottom counter is `1/0`; Slider.onChanged is null. Novel progress is internally tracked in `_novelPermille` but never represented by the bottom bar.
- Impact: reader sees invalid progress and cannot seek through prose using the offered control.
- Cause: `reader_page.dart:1278` derives slider range only from `_pageCount`; at 1327–1329 it disables slider on <=1 images; at 1340 it displays image counts. Prose has zero images by design.

### R4 — P2: Novel download button is enabled but does nothing

- Trigger: load HTML novel; tap visible enabled download icon.
- Actual: enqueue call count remains zero and no feedback is produced.
- Impact: promised download affordance is a silent dead end; novels cannot be kept offline through this path.
- Cause: `reader_page.dart:894` enables button but `reader_page.dart:901` immediately returns for empty images. Existing chapter transfer path also rejects empty image URLs (`lib/features/download/data/datasources/download_transfer_data_source.dart:386`); it does not persist HTML.

### R5 — P2: Download rejected for no space is announced as started

- Trigger: manga chapter download; repository returns `EnqueueOutcome.noSpace`.
- Actual: UI shows `manga.download_started` success message (localization key in fixture); enqueue was rejected.
- Impact: user expects an offline chapter which was never queued, and receives no actionable reason.
- Cause: `reader_page.dart:907` discards enqueue result; at 922 always emits started. Same control flow for refused/notDownloadable/alreadyPresent.

## Additional progress findings

### R6 — P2: Reopening offline chapters discards saved reading position — source-backed, not runtime reproduced

- Trigger: read partway through a downloaded chapter, leave, reopen through Downloads or Home Downloads.
- Actual flow: both navigation sites create `ReaderArgs` without `resumePage`; its default is 0. Reader starts solely from `args.resumePage` and does not retrieve history itself.
- Impact: existing offline progress is lost from the user's reading session and overwritten by initial-page save.
- Evidence: `lib/features/download/presentation/pages/downloads_page.dart:305`, `lib/features/home/presentation/widgets/home_downloads_section.dart:138`; `lib/features/manga/domain/entities/reader_args.dart:21`; `reader_page.dart:138,205,295`.

### R7 — P2: Chapter changes do not flush current progress before clearing it — widget reproduced

- Trigger: change page/scroll, then choose next/previous/another chapter within 800 ms, or select a new chapter whose load fails.
- Actual flow: `_loadChapter` clears current pages/HTML and resets page before persisting prior chapter. Next successful load restarts the save debounce; a failed load leaves `_saveProgress` with no content and returns.
- Impact: final reading position in the old chapter can be lost; chapter navigation is not a save boundary.
- Widget evidence: first save records chapter 1/page index 0; ArrowRight visibly changes the counter to `2/9`; switching to chapter 2 within 250 ms and waiting 900 ms saves chapter 2 while the last chapter-1 record is still page index 0.
- Source: `reader_page.dart:170–180,290–300,340–351,949–952`. Current load-token protection correctly drops stale network responses, but does not solve this persistence ordering issue.

## Positive controls / exclusions

- Actual horizontal swipe reaches PageView despite the full-screen translucent tap detector; a suspected gesture interception bug was disproved and is not a finding.
- Stale chapter responses are guarded by `_loadToken` after local and remote awaits; no stale-result claim is made.
- Novel HTML rendering and permille history support exist; the findings concern controls, offline persistence and transition behavior, not a claim that all novels fail to display.
- Network image cookie loss during download remains a reachability question because native image proxy URLs may already encapsulate cookies; do not count it as a confirmed download failure without resolving that route.

## Widget screenshots

- `screenshots/spread-resume-counter.png`: actual reader counter claims `6/9`. The image did not decode in the capture harness, so this screenshot alone does not prove the displayed page; the attached controller slot 0 is asserted by the widget test.
- `screenshots/novel-zero-pages.png`: actual HTML prose with `1/0` at bottom.

These are Flutter widget-harness captures, not device screenshots. Fixtures are explicitly labeled; system font is loaded for readable text and MaterialIcons for controls.
