# Manga and novel runtime audit — 2026-09-14

Production files were read only. No AGENTS.md or CONTEXT.md found under the workspace (including hidden files). Reproduction file: `repros/mangayomi_audit_test.dart`.

Run from `sozo`:

```sh
flutter test --no-pub docs/audits/2026-09-14/source-reader/repros/mangayomi_audit_test.dart --reporter expanded
```

Final outcome: **5 tests passed**. Four probes assert the current incorrect behavior; one is a positive control. Repo probes use the actual MangayomiRepoStore, temporary Hive, and local HTTP fixture server. Bridge probes use the actual MangayomiBridge, actual store, and an overridden runtime supplying deterministic extension results. They do not prove remote site availability or exercise an Android APK/WebView renderer.

## Confirmed by actual-path fixture replay

### P2 — Source code remains from old repository after metadata switches

- Location: `lib/features/extensions/data/mangayomi_repo_store.dart:190-195`; matching loaded-instance cache in `mangayomi_runtime.dart:141-158`.
- Trigger: repository A supplies ID `shared`, version `1.0.0`, code A; code is cached; repository B supplies the same ID/version with sourceCodeUrl B.
- Actual: metadata now points to B, while `code(newSource)` returns A without fetching B. Probe prints `metadata B + executable code A at equal ID/version`.
- Impact: switching to a fork/mirror intended to repair a source can continue executing the previous implementation despite changed endpoint metadata. Cache identity must account for code origin as well as ID/version, and runtime identity needs the same treatment.

### P2 — Successful refresh cannot remove retired or migrated sources

- Location: `lib/features/extensions/data/mangayomi_repo_store.dart:119-138`.
- Trigger: first index contains two JavaScript sources; next successful index omits one and marks the other Dart-only.
- Actual: refresh starts from all existing sources; omitted IDs are never removed; skipped Dart entries preserve the previous JS record. Both remain installed with old URLs; `checkUpdates` reports no version change.
- Impact: removed sources and no-longer-supported implementations remain selectable; removing/readding the repository is needed to reconcile the installed catalogue.

### P2 — Image request metadata is flattened and extension getHeaders is skipped

- Location: `lib/features/extensions/data/mangayomi_bridge.dart:449-474`.
- Trigger: getPageList emits two page objects with distinct request headers, or a string list whose provider implements getHeaders.
- Actual: the two header maps become one shared map containing only the last page's headers; neither page retains its own map. The runtime call log contains only getPageList and never getHeaders. Probe verifies page one's PAGE_1 authorization is replaced by PAGE_2.
- Impact: sources with page-specific request credentials lose correct request semantics; custom source image UA/header policy is ignored. No live CDN 403 was claimed.
- Real source-contract examples: [MangaDex getHeaders](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/manga/src/all/mangadex.js) returns the user's custom user-agent; [Comick](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/manga/src/all/comick.js) returns a custom UA and trailing-slash Referer; [ManhwaZ](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/manga/src/en/manhwaz.js) supplies its own UA. These are linked by the default kodjodevf index inspected on the audit date. Source presence does not prove current site operation.

### P2 — Relative-link title cache leaks titles across providers

- Location: `lib/features/extensions/data/mangayomi_bridge.dart:33-43`, fallback at load detail.
- Trigger: source one and source two return different titles under the same relative link `/series/1`; second search runs before first source's title-less detail response.
- Actual: returned detail is provider `my:one`, title `Novel Two`.
- Impact: ordinary cross-source search can attach another provider's title to detail/history. Key title cache by source ID plus link.

### Positive control — novel content routing works

`itemType=2` is parsed as novel and pageList calls getHtmlContent, joining returned HTML string arrays. The fixture receives `<p>First</p><p>Second</p>` with zero getPageList calls. Therefore do not report “all novels call the image API” against this checkout.

## Additional deterministic code-path findings, not executed on Android

### P2 — Retrying an existing native manga repo while offline erases persisted metadata

`android/app/src/main/kotlin/com/soplay/sozo/manga/MangaRepoManager.kt:138-144` catches index-fetch failure and passes an empty array into install; line 202 unconditionally saves the empty array over this repo's metadata. Existing sources remain in the current MangaHost map, masking the loss until restart. ensureLoaded then sees zero saved entries. The add/re-add path must preserve prior state when retrieval fails. The separate checkUpdates path already skips fetch failures.

### P2 — Newly introduced native source IDs are not persisted by updates

`MangaRepoManager.kt:292-296` registers each new source in memory but only replaces entries whose IDs already exist in the old persisted array. A package update adding an ID makes that source usable in the current process and absent after restart. Conversely removed IDs remain in persisted entries. This is a source-list reconciliation issue, not a version comparator issue.

### P2 — Native loader failure is sticky for the same APK path

`MangaRuntime.kt:79-84` records apkPath before load success; every following lookup skips loading that path. `evictSources` at lines 49-50 removes only sourceCache entries, not loadedApks. If a same-path source is repaired/reimported or an evicted source points back to an already-attempted path, it cannot load again until restart. Version-filename updates to a genuinely new path avoid this condition.

## Unconfirmed compatibility follow-ups (not findings)

- Native image proxy `MangaImageServer.kt:128` reconstructs every page as `Page(index=0,url="",imageUrl=...)`. It loses original Page subtype/index/page URL; this needs a concrete extension fixture that reads those fields in getImage/imageRequest before claiming a broken provider.
- MangayomiRuntime wraps WebView Future in `.timeout` but does not cancel underlying JS; late JS could observe another source's global preferences after lock release. Needs an actual delayed WebView method test, so excluded from confirmed findings.
- Native page-image proxy does call the extension's getImage and interceptor chain: native Cloudflare cookies/custom image handling are retained. Do not conflate this with the unproxied Mangayomi image path.
- Mangayomi Dart-language entries are intentionally unsupported and skipped, not passed through JavaScript compilation. Documentation's “compiled into Mangayomi itself” explanation was not independently verified here; no bug is claimed from that comment.

## Final bounded check: all five current default novel scripts

Primary index: [kodjodevf novel_index.json](https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/novel_index.json). It currently lists Kolnovel (ملوك الروايات), Annas Archive, Wordrain69, Web Novel Translations, and Novel Updates. All five explicitly declare `itemType: 2` and `sourceCodeLanguage: 1`; no item-type inference mismatch exists for these entries. Their unchanged JavaScript files and audit-date URLs/SHA256 hashes are in `repros/novel_fixtures/`.

Replay command, from `sozo`:

```sh
node docs/audits/2026-09-14/source-reader/repros/default_novels_probe.cjs
```

Result: all five instantiate successfully in the actual `assets/js/mangayomi_bridge.js` shim. Deterministic DOM/HTTP fixtures replace external scraping, and Annas Archive mirror resolution is stubbed successful. This is a host-contract replay, not a live website availability test.

### P2 — Default Annas Archive source requires absent EPUB host functions

- Production boundary: `assets/js/mangayomi_bridge.js:547-568` exports the provided host globals; `lib/features/extensions/data/mangayomi_bridge.dart:409-426` routes novels to getHtmlContent. Neither shim/runtime provides `parseEpub` or `parseEpubChapter`.
- Concrete source: [annasarchive.js](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/novel/src/all/annasarchive.js) line 108 calls parseEpub while constructing chapters; line 160 calls parseEpubChapter for the chapter HTML. Search requests specifically filter `ext=epub`.
- Actual unchanged method replay: getDetail fails with `ReferenceError: parseEpub is not defined`; getHtmlContent fails with `ReferenceError: parseEpubChapter is not defined` after a successful fixture mirror resolution.
- Impact: the default catalogue offers this source as a normal novel reader, but its EPUB flow cannot cross the host boundary even when network/mirror access succeeds. This needs an EPUB host implementation or an explicit unsupported-source state.
- No default PDF-reading contract was found in these five scripts; do not generalize this into a tested PDF failure.

### P2 — Novel Updates chapter POST is encoded as JSON under a form Content-Type

- Location: `assets/js/mangayomi_bridge.js:116-121` serializes every object body with JSON.stringify, even when Content-Type is application/x-www-form-urlencoded. `lib/core/js/dart_fetch.dart:249` forwards that resulting string as req.body without re-encoding.
- Concrete source: [novelupdates.js](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/novel/src/en/novelupdates.js) lines 134-145 supplies the form content type plus object fields action=nd_getchapters, mygrr=0, mypostid=<id> to WordPress admin-ajax.
- Actual unchanged getDetail replay captured the outgoing body as `{"action":"nd_getchapters","mygrr":"0","mypostid":"42"}`; a form decoder sees no action field (`new URLSearchParams(body).get('action') === null`).
- Impact: chapter action and novel ID are missing from the declared form request. Login cookies alone cannot repair this encoding; the host must form-encode objects under the requested media type. No live login or remote server request was performed.

The three direct HTML providers use Client/Document/SharedPreferences helpers provided by the shim. Their getHtmlContent signatures match the host's two-argument call. This verifies interface availability only, not their live selectors/site status. Novel Updates additionally requires login per its upstream index notes; that prerequisite was not tested or bypassed.
