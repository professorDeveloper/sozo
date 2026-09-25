# Reader code patterns for Sozo — 2026-09-23

Read-only primary-source investigation of fresh shallow clones. No mobile device operations, production edits, dependency installation or upstream tests were run. These are **implementation observations**, not live-app reliability results. Commit dates demonstrate recent repository activity, not a maintenance guarantee.

## Repository identity and pinned scope

| Project | Official repository / checked commit | License and device boundary |
|---|---|---|
| Mihon | [mihonapp/mihon](https://github.com/mihonapp/mihon), `f52d890e7f8a3c418ddab41f41d4b577bce0dc06`, commit 2026-09-22 18:10:12 +06:00 | [Apache-2.0](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/LICENSE). Official [README](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/README.md#requirements) states Android 8+. Kotlin/Android, not a portable Flutter reader. |
| LNReader | [lnreader/lnreader](https://github.com/lnreader/lnreader), `920f88aee4460a53ac0a3cf73cdc77ee915eb282`, commit 2026-09-23 12:08:49 +05:30 | [MIT](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/LICENSE). Official [README](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/README.md#download) states Android 7+. React Native plus Android native modules, not an assurance of iOS/desktop support. |

LNReader’s [verified GitHub organization](https://github.com/lnreader) links its official website, which identifies the [official plugin repository](https://www.lnreader.app/plugins). The application and third-party content providers are distinct. Do not infer that app licensing grants rights to provider content or every extension. For reuse, preserve applicable upstream notices and review dependency/file licenses; the architectural recommendations below require no code copying.

Local inspection clones: `/tmp/sozo-reader-mihon-20260923` and `/tmp/sozo-reader-lnreader-20260923`. Every implementation link below is pinned to the inspected SHA, not moving `main`.

## Mihon: three concrete flows

### 1. Backup creation → validation → section-aware restore

`BackupCreator.backup` assembles manga, categories, source identities, app preferences, extension stores and source preferences; serializes protobuf into gzip; then validates the written file. Failure removes the output; automatic backup keeps a bounded rotation. Private preferences are an explicit option, rather than accidentally swept into all settings. [Creator](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/data/backup/create/BackupCreator.kt#L62-L170).

Restore decodes once, builds source-name mappings for readable errors, restores selected sections and coordinates category dependencies. Manga restoration attempts batches inside database transactions, with error handling and a completion/error log; a restored download cache is invalidated. A TODO explicitly leaves an optional online library/tracker refresh unfinished. [Restorer](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/data/backup/restore/BackupRestorer.kt#L69-L190).

**For Sozo:** define an explicit manifest covering each Hive box **and** native SharedPreferences/extension identity store. Validate the file before displaying success; show restored/skipped/unavailable sections. A source identity backup is not a backup of the APK or downloaded pages. Do not label today’s Hive-only Sozo export “complete extension recovery.”

### 2. Source migration preserves selected semantics, not raw URLs

The migration use case fetches destination metadata/chapters before mapping. Recognized equal chapter numbers carry bookmarks/fetch dates; chapters up to the maximum previously read number become read. Categories, tracker associations, custom covers and notes are handled; replace removes the old library favorite while copy can preserve it. Download removal is opt-in via a migration flag. [Migration implementation](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/mihon/domain/migration/usecases/MigrateMangaUseCase.kt#L45-L140).

**Important limit:** marking everything up to the greatest read chapter can fill gaps a reader intentionally skipped. Unrecognized numbers are not reliably matched. The use case catches non-cancellation throwables without rethrowing; do not copy this as a model for transparent failure reporting.

**For Sozo:** use a migration preview containing old/new source IDs and chapter matches, allow copy before replacement, preserve per-title settings/tracker links, and disclose unmatched chapters. A repository URL refresh alone cannot migrate content identities.

### 3. Durable download queue + source-aware library refresh

Downloader restores queued chapters from `DownloadStore`, filters existing downloads/duplicate chapter IDs, and selects one active download per source across a configurable number of sources. Its flow reconciles jobs as the queue changes. [Downloader startup and scheduling](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/data/download/Downloader.kt#L90-L230), [enqueue filtering](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/data/download/Downloader.kt#L268-L300).

Library updates group titles by source under a semaphore of five, enqueue newly eligible downloads without immediately starting them, and start downloads after updates finish; scheduled work uses network constraints. This avoids multiplying simultaneous refresh and chapter-download traffic against the same sites. [Library update processing](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/data/library/LibraryUpdateJob.kt#L248-L336), [constraints](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/data/library/LibraryUpdateJob.kt#L430-L475).

**For Sozo:** extend existing Wi-Fi/cooldown controls with per-source concurrency, durable pending work and opt-in followed-title downloads. Keep discovery/refresh and download traffic within one source budget. Android scheduled work does not imply exact wake-up times on Samsung or other battery-managed devices.

## LNReader: three concrete flows

### 1. Selectable backup sections → archive/file remap → honest recovery report

Backup options are library/settings/plugins/downloaded files; downloaded files depend on including the library. [Options](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/backup/options.ts#L1-L29). Local backup prepares structured data, zips selected file sections, then copies the final archive to the selected URI. Restore reads its manifest, handles legacy and current archive layouts, restores files using novel mappings and finalizes restored plugins before presenting completion text. [Local create/restore](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/backup/local/index.ts#L28-L196).

The result layer distinguishes missing plugins rather than asserting a completely working installation. [Restore result](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/backup/restoreResult.ts#L1-L110). Structured backup data records app version and selected sections. [Data preparation](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/backup/utils.ts#L100-L120).

**For Sozo:** offer metadata-only and optional offline-content exports, report bytes/sections before export, remap imported content identities and file paths, then verify source availability separately. Do not copy old absolute storage paths to the new device. No claim is made here that the complete restore is atomic.

### 2. Novel migration transfers reader state and optionally queues re-downloads

`migrateNovel` obtains/fetches destination chapters, lets migration options choose current versus destination metadata/cover, transfers categories and removes the old novel inside a database write. It copies reader settings keyed by plugin ID + novel path, sorts chapters by parsed number, transfers bookmark/unread/read time/progress for matched numbers, updates last-read identity, and queues formerly downloaded chapters when requested. [Migration](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/migrate/migrateNovel.ts#L62-L241).

**Limits worth retaining in a design review:** unknown/zero chapter numbers are skipped; the old novel is deleted before the subsequent chapter-state writes/settings copies and download enqueue finish. Therefore this implementation is evidence for data that should migrate, **not** proof of an all-or-nothing migration or perfect matching.

**For Sozo:** model source migration as a resumable job with destination verification before destructive replacement. Treat prose progress/bookmarks/last-read chapter and per-title typography as first-class migration data. Re-download is a separate, visible optional operation.

### 3. Chapter downloads checkpoint completed attempts and summarize failures

`downloadChapters` parses a saved checkpoint, resumes at `nextIndex`, catches each chapter failure, and persists the next index plus accumulated failures after each attempt. At the end it raises an aggregate error when some chapters failed. [Download loop](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/download/downloadChapter.ts#L100-L160), [checkpoint parser](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/download/downloadCheckpoint.ts#L1-L45).

This is **chapter-level resumability**, not HTTP byte-range resume. Failed attempts also advance the checkpoint; do not infer automatic retry of every failed chapter from this loop. Existing targeted tests cover checkpoint parsing and backup result behavior, but were not executed for this audit. [Checkpoint tests](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/download/__tests__/downloadCheckpoint.test.ts), [restore result tests](https://github.com/lnreader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/backup/__tests__/restoreResult.test.ts).

**For Sozo:** preserve per-chapter success/failure identities, expose partial completion and retry-failed-only, and persist progress before the process can be killed. Reuse Sozo’s existing transfer layer instead of replacing it with a second queue.

## Recommended transfer order for Sozo

1. **Backup coverage contract and round-trip proof:** include all native repo/source state, explicit exclusions, validation and an actionable import report. Test an empty target store and a changed source ID, without using a real user’s phone as the fixture.
2. **Source/content continuity:** non-destructive migration preview, chapter mapping, reader/playback preferences, tracker links, unmatched-data report and resumable commit.
3. **Unified durable work:** source-aware refresh/download budgets, checkpoints, failed-only retries and optional follow-new-chapter scheduling. This builds on existing Sozo Wi-Fi/cooldown/offline support.

These priorities are design inferences from the inspected implementations and Sozo’s current inventory, not claims that either upstream project can be embedded unchanged.
