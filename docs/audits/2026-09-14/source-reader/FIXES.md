# Implemented fixes — source selection, reading, and playback

This supersedes the original audit's open-status list. Changes are in the mobile
app and catalog backend working trees; unrelated TV changes were preserved.

## Sources and Profile

Profile now has one Sources entry. Installed sources are grouped by Watch,
Manga, and Novels; tapping selects, while Browse previews without switching.
Tabs update immediately, source languages survive provider mapping, and the
language filter is available beside search. Add source opens a content-filtered
catalog. A successful install refreshes local providers without waiting for the
backend; installed entries offer Use this source. Returning follows the chosen
source's content mode. Repository maintenance remains a secondary menu.

Catalog source results no longer wait for language facets. Failed pagination
stops loading and exposes Retry. Empty/unreachable catalogs offer recommended
repositories directly, including native manga. CloudStream installs only the
chosen plugin, rather than every plugin in the repository. Old catalog entries
resolve known novel/anime sibling indexes correctly; new backend responses carry
exact sourceIndexUrl and externalId. A failed background API request cannot
replace the user's source manager, reader, or player with a global offline page.

## Source engines and reading

- NovelCool phone/emulator difference: phone requested an expired GitHub APK
  release URL; emulator had the same APK cached. Manga/Aniyomi now refresh only
  the owning index and retry a changed APK URL once after HTTP 404/410, with a
  cooldown. Failed reinstallation preserves metadata, new IDs survive restart,
  APK downloads serialize, and failed loader state can be retried.
- Mangayomi source metadata is parsed once per snapshot with an ID map; script
  cache identity includes repository/script origin. Retired sources disappear
  after a valid update; malformed refreshes preserve the last valid snapshot.
- Manga page headers and correctly scoped cookies survive reading and both
  native/Dart downloads. Detail title caches are source-specific.
- Novel form POSTs use form encoding. EPUB2/3 helpers parse real bounded ZIP,
  OPF, NCX/nav and spine data in an isolate, with request deduplication and a
  bounded book cache. No claim that every upstream site's selectors work.
- Reader spread navigation/resume/rotation use consistent page mapping; novel
  scrolling and percent seek work without fake image pages. Chapter transitions
  flush reading progress; offline entry restores it. Download outcomes are
  reported accurately. Novel offline download remains unavailable and is now
  disabled with an explanation instead of appearing to succeed.

## Smoothness and black-screen recovery

- Hidden/background detail trailers cancel delayed startup and release decoder
  resources; stale async completions cannot restart them behind another route.
- Reader image decode size follows the actual column width, reducing allocation
  in two-page mode.
- Preview decoding starts only while scrubbing, with one active request, latest
  queued position, bounded 24-frame/3 MB JPEG cache, no neighbor prefetch, and
  decoder release on scrub end or idle. Late frames from another source or
  header identity are discarded.
- MediaKit duration metadata alone no longer means video readiness. Missing
  dimensions/readiness or surface availability times out and uses a per-stream
  Android native fallback. The plugin signal does not verify rendered pixels. The user's engine preference is preserved. Existing Android
  hardware-decoding defaults remain unchanged.
- Playback generations cover quality switches, episode resolution, retry,
  reconnect and teardown. Old requests cannot restart playback or clear newer
  state after a slow dispose.
- Central transport is Previous episode, seek back, Play/Pause, seek forward,
  Next episode. Positions remain stable at episode boundaries and on narrow
  screens. Legacy bottom-left episode controls migrate to the centre; explicit
  modern customization remains supported.

## Backend

Catalog ingestion now reads actual bounded gzip/protobuf manga indexes (64-bit
IDs preserved as strings), accepts CloudStream direct lists, excludes status=0,
preserves sources on partial/malformed snapshots, and stores sibling provenance.
Read-only live Keiyoushi ingestion returned 2,309 real sources. **Backend changes
have not been deployed and no production DB ingestion was triggered.** Existing
rows gain exact provenance at the next successful ingest after deployment; the
client handles known legacy repository URLs in the meantime.

## Verification

- Full Flutter suite: 882 passed before the optional physical-device harness.
- Backend catalog: 15 passed; JS bridge: 4 passed.
- Native manager JVM harness exercises production managers and fails against
  the original implementation; generation race harness likewise fails on the
  old retry continuation and passes with one current startup.
- Emulator UI: Profile → Sources, Manga tab, NovelCool popular/latest catalogue,
  novel catalog installation, and immediate Use this source state verified.
- Final `flutter analyze`: no issues. Android arm64 release APK built successfully
  (148,284,499 bytes), certificate matched the original installed APK, and plain
  `adb install --user 0 -r --no-streaming` succeeded. Normal MainActivity launched
  and its process remained running; the phone was locked at the final UI check.
- Physical phone: controlled four-second 3840×2160 HEVC Main10 sample reported
  MediaKit video dimensions and advancing playback at 1.75 seconds. This checks
  decoder metadata/progress, not proof of rendered pixels or sustained playback.
  The complete integration test **failed** after the screenshot step timed out;
  no screenshot was captured and the user's original failing stream was unknown.

## Physical-test incident and recovery

The temporary Flutter integration test was accidentally run without
`--no-uninstall`. Flutter's default teardown removed `com.soplay.sozo` and its
private local data. A temporary Hive directory inside the harness did not protect
the production app from package removal. This was an agent error and was reported
to the user. The unsafe temporary harness has been removed.

The original APK was reinstalled successfully. A targeted Android backup restore
for Sozo returned `restoreFinished: 0`, but the app data directory remained empty;
there is **no verified recovery of the old local settings/history/favorites**.
No exported Sozo JSON backup was found in Download/Documents or retained phone
diagnostics. The retained APK contains code/resources only. The unrelated TV
backup was not used. The user was asked whether they have an exported Sozo backup.

The final production release was subsequently installed successfully as an
in-place update. Future integration-device work must use an isolated QA package
on a disposable test installation; do not run Flutter integration tests against
a user's production installation. Use `--no-uninstall` for any retained test
installation as an additional safeguard.

Earlier phone thermal readings confirmed thermal pressure. Reduced background
work is implemented; a before/after sustained thermal improvement has not been
measured and should not be inferred from desktop timing or emulator results.

## Follow-up: scrolling, filter feedback, and emulator black video

- Sources uses one CustomScrollView with the original compact toolbar and
  pinned tabs. Hint/search scroll away; the category row moves up below the tabs
  and stays pinned, making both filters available while browsing. The earlier
  oversized FlexibleSpaceBar title was removed following user feedback.
  PageStorage preserves offsets by mode/query/filter.
- Catalog language selection updates before asynchronous persistence; requests
  remain generation guarded. All languages is selected for an empty selection.
  Chips use a filled selection and a 120 ms ease-out transition (disabled when
  reduced motion is requested). Re-selecting the same content type skips reload.
- Reproduced black video with advancing subtitles in MediaKit on the API 36
  arm64 emulator. The same title (One Night Only, UHD Movies, actual 1080p H.264
  MKV despite the provider's 2160p label) displayed correctly with System player.
  media_kit_video 1.3.1 Android completes waitUntilFirstFrameRendered immediately
  after SetSurfaceSize, so that signal cannot prove visible video. A related
  upstream report is https://github.com/media-kit/media-kit/issues/1343.
- Android emulator detection at startup now routes playback to the native
  platform engine without changing the saved preference. Physical phones keep
  their selected engine. Player settings also offer System player for a MediaKit
  session, preserving URL, headers and position through the existing generation
  guards. This is a recovery option, not proof of the S22's underlying cause.
- Full Flutter suite after these changes: 882 passed; analyzer: no issues.
- Final arm64 release installed in-place on emulator-5554. Restored the saved
  MediaKit preference before installation; replaying the same title then showed
  video through automatic native routing. No physical phone test in this follow-up.
