# Backend catalog audit — 2026-09-14 Asia/Tashkent

No backend production files or database were changed. `backend_catalog_audit.cjs` executes the actual catalogIngest production module in a VM with isolated HTTP/database fakes; all six assertions pass. These are module-level reproductions, not device/UI tests. `backend_catalog_live.cjs` makes read-only requests to primary repository indexes; exact observations are in its JSON output.

## Confirmed defects

1. P1: Novel/anime catalog installation points at manga index. catalogIngest.service.js:213-220 reads sibling indexes, but :268 assigns all harvested rows root repo.url. Mobile source_catalog_page.dart:197 installs that URL; mangayomi_repo_store.dart:105-109 reads exactly one index. Repro confirms novel row URL is index.json, not novel_index.json. Live official novel_index.json serves five sources.
2. P1: Manga catalog harvest substitutes index.min.json for index.pb (catalogIngest.service.js:232). Live Keiyoushi index.pb is gzip HTTP200; its JSON sibling contains only Outdated App/Update to Mihon rows. Yuzono JSON has same two stubs; its .pb is HTTP404. Both stub source IDs equal 1, colliding under kind/externalId identity (:262). Thus discovery cannot represent real Keiyoushi protobuf catalog, even though mobile MangaRepoManager.kt:139 invokes native ExtensionIndex.
3. P1: Partial sibling failure marks that format's existing catalog dead. Mangayomi fetch failure swallowed (:221), one successful sibling permits return (:225); ingestAll :284-286 marks all unseen rows of root repo dead. Same issue for CloudStream child plugin list failure (:167). Malformed HTTP200 JSON can also become [] and trigger whole-repo death. Actual-module repro confirms death update despite failed sibling, and for malformed body.
4. P2: CloudStream standalone plugin arrays supported on device are ignored by catalog parser (:160 expects pluginLists only). Repro confirms empty harvest. Backend parser also ignores status=0 (:176-185); repro confirms author-marked-down plugin remains discoverable.
5. P2: Missing Mangayomi sourceCodeLanguage means non-runnable in backend (:108), but JS in mobile mangayomi_source.dart:127. Repro confirms false backend value. This hides/disables legacy JS sources that manual installation accepts; conditional fixture, not observed prevalence.

## Static additional mismatch

Public catalog controller serialize():7-24 emits only verified boolean, omitting probe state/reason and verifiedAt; ingestion preserves human verification across binary versions (service:273-275). User-facing verified badge cannot express when/which version was tested or newer probe failure. Do not equate verified with current playback/reader validation.

## Re-run

From /Users/azamov/Sozo-Full:

    node sozo/docs/audits/2026-09-14/source-reader/repros/backend_catalog_audit.cjs
    node sozo/docs/audits/2026-09-14/source-reader/repros/backend_catalog_live.cjs
