package com.soplay.sozo.manga

import android.content.Context
import android.util.Log
import com.soplay.sozo.extensions.ApkSignature
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.SChapterImpl
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SMangaImpl
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.coroutines.Dispatchers
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Bridges Mihon/Tachiyomi manga [CatalogueSource]s to the soplay JSON contracts.
 * Mirror of `AniyomiHost` but: providers are namespaced `mn:` (group "manga"),
 * `load` returns chapters as the `episodes` array (a chapter is structurally an
 * episode), and instead of `loadLinks`→videoSources it exposes `pageList`→pages.
 */
class MangaHost(private val context: Context) {

    companion object {
        private const val TAG = "MangaHost"
        private const val UA =
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
    }

    private data class SourceMeta(
        val id: String,
        val name: String,
        val lang: String,
        val baseUrl: String,
        val pkg: String,
        val className: String,
        val apkUrl: String,
        val iconUrl: String,
        val nsfw: Boolean,
        val repoName: String,
        // The repo's signing-key SHA-256, empty when it declares none.
        val fingerprint: String = "",
    )

    private val sources = LinkedHashMap<String, SourceMeta>()

    // Home pages are expensive (network scrape + HTML parse). Cache the built
    // JSON briefly so navigating away and back is instant instead of re-scraping.
    private data class CacheEntry(val ts: Long, val json: String)
    private val pageCache = HashMap<String, CacheEntry>()
    private val cacheTtlMs = 5 * 60 * 1000L

    fun registerMeta(entry: JSONObject, repoName: String) {
        val id = entry.optString("id")
        if (id.isEmpty()) return
        sources[id] = SourceMeta(
            id = id,
            name = entry.optString("name"),
            lang = entry.optString("lang"),
            baseUrl = entry.optString("baseUrl"),
            pkg = entry.optString("pkg"),
            className = entry.optString("className"),
            apkUrl = entry.optString("apkUrl"),
            iconUrl = entry.optString("iconUrl"),
            nsfw = entry.optBoolean("nsfw", false),
            repoName = repoName,
            fingerprint = entry.optString("fingerprint"),
        )
    }

    fun removeSources(ids: List<String>) {
        ids.forEach { sources.remove(it) }
    }

    /**
     * Invalidates everything cached for the extension published at [apkUrl] so the
     * next use re-downloads it. Called by the updater after an upstream version bump.
     *
     * Deleting the file alone is not enough: [MangaRuntime] caches the constructed
     * `CatalogueSource` by id, so without evicting those the app would keep serving
     * the old code from memory for the rest of the process's life.
     */
    fun dropCachedApk(apkUrl: String) {
        if (apkUrl.isEmpty()) return
        val affected = sources.values.filter { it.apkUrl == apkUrl }
        if (affected.isEmpty()) return
        MangaRuntime.evictSources(affected.map { it.id })
        for (meta in affected) {
            val f = cachedApkFile(meta)
            if (f.exists()) {
                // setWritable first: the runtime marks loaded apks read-only for W^X.
                f.setWritable(true)
                if (!f.delete()) Log.w(TAG, "could not delete stale apk ${f.name}")
            }
        }
    }

    /**
     * Where a source's language sits when several sources share a name.
     *
     * Lower wins. `preferred` is the user's own order, straight from the
     * picker's language row; with it empty this is the constant `en → all →
     * anything else` it replaced, so an install that never touches the filter
     * sees the identical list.
     *
     * That constant was the reason a French user could install a repo carrying
     * fourteen French sources and be shown none of them: for anything that
     * ships one entry per language, the English entry held the name and every
     * other language was dropped with nothing to say it had happened.
     */
    private fun langRank(lang: String, preferred: List<String>): Int {
        val key = lang.trim().lowercase()
        val i = preferred.indexOfFirst { it.trim().lowercase() == key }
        if (i >= 0) return i
        val base = preferred.size
        if (preferred.isEmpty() && key == "en") return base
        if (key == "all") return base + 1
        return base + 2
    }

    fun providersJson(preferred: List<String> = emptyList()): String {
        val picked = LinkedHashMap<String, SourceMeta>()
        for (s in sources.values) {
            val name = s.name.trim().lowercase()
            if (name.isEmpty()) continue
            // A language the user asked for does not compete for a name: it is
            // kept under its own key and the picker labels the variants apart.
            // Only the languages nobody asked for still collapse, which is what
            // stops an aggregator that publishes forty-five languages from
            // filling the list with forty-five identical rows.
            val wanted = preferred.any { it.trim().lowercase() == s.lang.trim().lowercase() }
            val key = if (wanted) "$name|${s.lang.trim().lowercase()}" else name
            val cur = picked[key]
            if (cur == null || langRank(s.lang, preferred) < langRank(cur.lang, preferred)) {
                picked[key] = s
            }
        }
        val arr = JSONArray()
        for (s in picked.values) {
            arr.put(JSONObject().apply {
                put("id", "mn:${s.id}")
                put("name", s.name)
                put("lang", s.lang)
                put("baseUrl", s.baseUrl)
                put("icon", s.iconUrl)
                put("nsfw", s.nsfw)
                put("repo", s.repoName)
                put("mode", "client")
                put("group", "manga")
            })
        }
        return arr.toString()
    }

    // --- runtime: load source + convert to soplay JSON ---

    /**
     * Downloads the extension apk if it isn't cached, and returns it.
     *
     * Two things here are load-bearing:
     *
     * 1. **The cache key includes the apk's filename**, which upstream versions
     *    (`tachiyomi-all.comicklive-v1.4.5.apk`). Keyed on the package alone, a
     *    published extension update could never be picked up — the old file
     *    existed, so it was returned forever.
     *
     * 2. **The download lands on a temp file and is renamed only once complete.**
     *    Writing straight to the final path meant a dropped connection left a
     *    truncated apk that `exists() && length() > 0` happily accepted, and
     *    MangaRuntime then `setReadOnly()`s it — so the source was permanently
     *    broken with no way to recover short of clearing app data.
     */
    /** Where [meta]'s apk is (or would be) cached. Single source of truth for the name. */
    private fun cachedApkFile(meta: SourceMeta): File {
        val dir = File(context.filesDir, "manga").apply { mkdirs() }
        val base = (meta.pkg.ifEmpty { meta.id }).replace('/', '_')
        val remoteName = meta.apkUrl.substringAfterLast('/').substringBefore('?')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .takeIf { it.isNotEmpty() && it != ".apk" }
        return File(dir, if (remoteName != null) "$base-$remoteName" else "$base.apk")
    }

    private fun ensureApk(meta: SourceMeta): File? {
        if (meta.apkUrl.isEmpty()) return null
        val file = cachedApkFile(meta)
        val dir = file.parentFile!!
        if (file.exists() && file.length() > 0) return file

        // `<name>.part.apk`, not `<name>.apk.part`.
        //
        // The signature check runs against this temp file, and
        // getPackageArchiveInfo is documented against apk paths. It does
        // dispatch on content rather than extension in current AOSP, so the old
        // name worked — but if it ever returned null here, `fingerprints` would
        // come back empty and every apk from a repo that declares a fingerprint
        // would be rejected. That failure mode is indistinguishable from
        // "nothing works", and the extension costs nothing.
        val tmp = File(dir, "${file.nameWithoutExtension}.part.apk")
        return try {
            val conn = (URL(meta.apkUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; instanceFollowRedirects = true
                connectTimeout = 20000; readTimeout = 60000
                setRequestProperty("User-Agent", UA)
            }
            if (conn.responseCode !in 200..299) {
                Log.e(TAG, "apk ${meta.apkUrl} -> ${conn.responseCode}"); return null
            }
            val expected = conn.contentLengthLong
            tmp.delete()
            val written = conn.inputStream.use { input ->
                FileOutputStream(tmp).use { input.copyTo(it) }
            }
            // Only trust Content-Length when the server actually sent one; chunked
            // responses report -1 and a short read there is indistinguishable from
            // a complete one.
            if (expected > 0 && written != expected) {
                Log.e(TAG, "apk ${meta.apkUrl} truncated: $written/$expected bytes")
                tmp.delete()
                return null
            }
            if (written <= 0) {
                Log.e(TAG, "apk ${meta.apkUrl} empty"); tmp.delete(); return null
            }
            // An apk the repo's own key did not sign never reaches the class
            // loader — see ApkSignature for why this runs in-process at all.
            if (!ApkSignature.matches(context, tmp.absolutePath, meta.fingerprint)) {
                Log.e(TAG, "apk ${meta.apkUrl} signature does not match its repo")
                tmp.delete()
                return null
            }
            // Clear read-only in case a previous load marked an older file at this
            // path; renameTo onto a read-only target fails silently otherwise.
            if (file.exists()) {
                file.setWritable(true)
                file.delete()
            }
            if (!tmp.renameTo(file)) {
                Log.e(TAG, "apk rename failed for ${file.name}"); tmp.delete(); return null
            }
            Log.i(TAG, "apk downloaded ${file.name} ($written bytes)")
            file
        } catch (t: Throwable) {
            tmp.delete()
            Log.e(TAG, "apk download failed: ${t.javaClass.simpleName}: ${t.message}")
            null
        }
    }

    private fun sourceFor(id: String): CatalogueSource? {
        val meta = sources[id] ?: return null
        val apk = ensureApk(meta) ?: return null
        return MangaRuntime.source(context, apk.absolutePath, meta.pkg, meta.id)
    }

    private fun cardJson(m: SManga, id: String) = JSONObject().apply {
        put("provider", "mn:$id")
        put("externalId", m.url)
        put("title", m.title)
        put("slug", m.url)
        put("contentUrl", m.url)
        put("thumbnail", m.thumbnail_url)
        put("type", "Manga")
    }

    /**
     * A chapter's `mediaRef`: its url, plus the memo when it carries one.
     *
     * extensions-lib 1.6 lets a source stash per-chapter state in [SChapter.memo]
     * and read it back in `getPageList`. We rebuild the chapter from its ref, so
     * a ref that is only a url arrives with an empty memo and those sources find
     * no pages. Plain url when there is no memo, so every ref already stored in
     * history and downloads keeps working.
     */
    private fun chapterRef(c: eu.kanade.tachiyomi.source.model.SChapter): String {
        val memo = try { c.memo } catch (_: Throwable) { null }
        if (memo == null || memo.isEmpty()) return c.url
        return JSONObject().put("u", c.url).put("m", memo.toString()).toString()
    }

    /** The inverse of [chapterRef]. */
    private fun chapterFromRef(ref: String): SChapterImpl {
        val chapter = SChapterImpl().apply { url = ref; name = "" }
        if (!ref.startsWith("{")) return chapter
        return try {
            val obj = JSONObject(ref)
            chapter.url = obj.optString("u", ref)
            val memo = obj.optString("m")
            if (memo.isNotEmpty()) {
                chapter.memo = Json.parseToJsonElement(memo).jsonObject
            }
            chapter
        } catch (_: Throwable) {
            chapter
        }
    }

    private fun newManga(url: String) = SMangaImpl().apply { this.url = url; title = "" }

    fun getMainPageJson(id: String, page: Int): String {
        val cacheKey = "main:$id:$page"
        pageCache[cacheKey]?.let {
            if (System.currentTimeMillis() - it.ts < cacheTtlMs) return it.json
        }

        val src = sourceFor(id)
        val sections = JSONArray()
        val banner = JSONArray()
        var queryError: String? = null
        if (src != null) {
            // Fetch popular + latest CONCURRENTLY (was sequential, which doubled the
            // wall-clock of every home load).
            val popular: Result<eu.kanade.tachiyomi.source.model.MangasPage>
            val latest: Result<eu.kanade.tachiyomi.source.model.MangasPage?>
            runBlocking {
                // runCatching INSIDE each job so one failing call can't cancel
                // the sibling via the shared parent scope.
                val popJob = async(Dispatchers.IO) {
                    runCatching { src.getPopularManga(page) }
                }
                val latJob = async(Dispatchers.IO) {
                    runCatching {
                        if (src.supportsLatest) src.getLatestUpdates(page) else null
                    }
                }
                popular = popJob.await()
                latest = latJob.await()
            }

            popular.getOrNull()?.let { pop ->
                val items = JSONArray()
                for (m in pop.mangas.take(30)) items.put(cardJson(m, id))
                if (items.length() > 0) {
                    var i = 0
                    while (i < items.length() && i < 12) { banner.put(items.get(i)); i++ }
                    sections.put(JSONObject().apply {
                        put("key", "popular"); put("label", "Popular")
                        put("viewAll", JSONObject().apply { put("type", "mn"); put("slug", "popular") })
                        put("items", items)
                    })
                }
            }
            popular.exceptionOrNull()?.let { t ->
                queryError = "getPopular: ${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "getPopular $id", t)
            }

            latest.getOrNull()?.let { lat ->
                val items = JSONArray()
                for (m in lat.mangas.take(30)) items.put(cardJson(m, id))
                if (items.length() > 0) sections.put(JSONObject().apply {
                    put("key", "latest"); put("label", "Latest")
                    put("viewAll", JSONObject().apply { put("type", "mn"); put("slug", "latest") })
                    put("items", items)
                })
            }
            latest.exceptionOrNull()?.let { t ->
                if (queryError == null) queryError = "getLatest: ${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "getLatest $id", t)
            }
        }

        val json = JSONObject().apply {
            put("provider", "mn:$id"); put("banner", banner); put("sections", sections)
            // Surface the real failure (otherwise the home is silently empty).
            if (src == null) {
                put("error", MangaRuntime.lastError ?: "source unavailable: mn:$id")
            } else if (sections.length() == 0 && queryError != null) {
                put("error", queryError)
            }
        }.toString()
        // Cache only successful pages so an error/empty isn't pinned for 5 min.
        if (sections.length() > 0) pageCache[cacheKey] = CacheEntry(System.currentTimeMillis(), json)
        return json
    }

    fun getSectionJson(id: String, data: String, page: Int): String {
        val src = sourceFor(id)
        val items = JSONArray()
        var hasNext = false
        var error: String? =
            if (src == null) (MangaRuntime.lastError ?: "source unavailable: mn:$id") else null
        if (src != null) try {
            val pg = runBlocking {
                if (data == "latest" && src.supportsLatest) src.getLatestUpdates(page)
                else src.getPopularManga(page)
            }
            for (m in pg.mangas) items.put(cardJson(m, id))
            hasNext = pg.hasNextPage
        } catch (t: Throwable) {
            error = "${t.javaClass.simpleName}: ${t.message}"
            Log.e(TAG, "getSection $id", t)
        }
        return JSONObject().apply {
            put("provider", "mn:$id"); put("items", items); put("page", page)
            put("totalPages", if (hasNext) page + 1 else page)
            // Same as searchJson: View all on a broken source showed an empty
            // grid, which reads as "this source has nothing".
            if (error != null && items.length() == 0) put("error", error)
        }.toString()
    }

    fun searchJson(id: String, query: String, page: Int = 1): String {
        val src = sourceFor(id)
        val items = JSONArray()
        var hasNext = false
        var error: String? =
            if (src == null) (MangaRuntime.lastError ?: "source unavailable: mn:$id") else null
        if (src != null) try {
            val pg = runBlocking { src.getSearchManga(page, query, FilterList()) }
            for (m in pg.mangas) items.put(cardJson(m, id))
            hasNext = pg.hasNextPage
        } catch (t: Throwable) {
            error = "${t.javaClass.simpleName}: ${t.message}"
            Log.e(TAG, "search $id", t)
        }
        return JSONObject().apply {
            put("provider", "mn:$id"); put("items", items)
            put("query", query); put("page", page)
            put("totalPages", if (hasNext) page + 1 else page)
            // Lets the caller tell "this source is broken" from "0 matches".
            if (error != null && items.length() == 0) put("error", error)
        }.toString()
    }

    fun getGenresJson(id: String): String = "[]"

    /**
     * Returns `{"baseUrl","userAgent"}` for the interactive Cloudflare solver.
     * The userAgent is the EXACT one the native OkHttp client sends for this
     * source (the source's own header, falling back to [NetworkHelper]'s default)
     * so the harvested `cf_clearance` cookie — which is UA-bound — is accepted.
     * Returns `{}` when the source can't be resolved or has no base url.
     */
    fun cloudflareInfo(id: String): String {
        val meta = sources[id]
        val src = sourceFor(id) as? HttpSource
        val baseUrl = (src?.baseUrl ?: meta?.baseUrl).orEmpty()
        if (baseUrl.isEmpty()) return "{}"
        val ua = src?.headers?.get("User-Agent")
            ?: NetworkHelper.defaultUserAgentProvider()
        return JSONObject().apply {
            put("baseUrl", baseUrl)
            put("userAgent", ua)
        }.toString()
    }

    private fun statusLabel(status: Int): String? = when (status) {
        1 -> "Ongoing"
        2 -> "Completed"
        3 -> "Licensed"
        4 -> "Publishing finished"
        5 -> "Cancelled"
        6 -> "On hiatus"
        else -> null
    }

    fun loadJson(id: String, url: String): String {
        val cacheKey = "load:$id:$url"
        pageCache[cacheKey]?.let {
            if (System.currentTimeMillis() - it.ts < cacheTtlMs) return it.json
        }
        // An empty object told the app nothing, so it said "source unavailable"
        // over whatever really happened — a failed dex load, a missing apk, an
        // extension that threw on construction. getMainPageJson has always
        // reported the reason; this path did not.
        val src = sourceFor(id)
            ?: return JSONObject()
                .put("error", MangaRuntime.lastError ?: "source unavailable: mn:$id")
                .toString()
        val manga = newManga(url)
        var failure: String? = null
        // One call, not two.
        //
        // extensions-lib 1.6 folded details and chapters into getMangaUpdate,
        // and an extension built against it implements ONLY that — asking for
        // the two halves separately ran our own defaults into a
        // `mangaDetailsParse` the extension never declared, so every detail page
        // on a modern source was AbstractMethodError: blank title, no chapters.
        // The Source default still splits the work for older extensions, so both
        // generations answer here.
        val update = runBlocking {
            runCatching {
                withContext(Dispatchers.IO) {
                    src.getMangaUpdate(manga, emptyList(), true, true)
                }
            }
                .onFailure {
                    Log.e(TAG, "update $id", it)
                    failure = it.message ?: it.javaClass.simpleName
                }
                .getOrNull()
        }
        val details = update?.manga ?: manga
        val chaps = update?.chapters ?: emptyList()

        // Reading order = oldest→newest so episodeIndex 0 is chapter 1. Sources usually
        // return newest-first; sort by chapter_number when parsed, else reverse source order.
        val ordered =
            if (chaps.any { it.chapter_number > 0 }) chaps.sortedBy { it.chapter_number }
            else chaps.reversed()
        val episodes = JSONArray()
        ordered.forEachIndexed { i, c ->
            episodes.put(JSONObject().apply {
                put("episode", i + 1)
                put("label", c.name.ifEmpty { "Chapter ${i + 1}" })
                put("mediaRef", chapterRef(c))
            })
        }

        val title = try { details.title } catch (_: Throwable) { "" }
        val author = try { details.author } catch (_: Throwable) { null }
        val status = statusLabel(try { details.status } catch (_: Throwable) { 0 })
        val desc = buildString {
            status?.let { append("• ").append(it) }
            val d = try { details.description } catch (_: Throwable) { null }
            if (!d.isNullOrBlank()) {
                if (isNotEmpty()) append("\n\n")
                append(d)
            }
        }
        // Manga has no "recommendations" API, so derive a "similar" row from a title search.
        val related = JSONArray()
        try {
            val q = title.replace(Regex("\\(.*?\\)"), "").trim()
            if (q.length >= 2) {
                val results = runBlocking { src.getSearchManga(1, q, FilterList()) }
                for (m in results.mangas) {
                    if (m.url == url) continue
                    related.put(cardJson(m, id))
                    if (related.length() >= 20) break
                }
            }
        } catch (t: Throwable) { Log.e(TAG, "related $id", t) }

        val json = JSONObject().apply {
            put("provider", "mn:$id")
            put("contentId", url); put("contentUrl", url)
            put("title", title)
            put("description", desc)
            put("thumbnail", details.thumbnail_url)
            put("banner", details.thumbnail_url)
            put("year", JSONObject.NULL)
            if (!author.isNullOrBlank()) put("director", author)
            put("genres", JSONArray(details.getGenres() ?: emptyList<String>()))
            put("type", "Manga")
            put("isSerial", true)
            put("cast", JSONArray())
            put("related", related)
            put("episodes", episodes)
            // Same reason getMainPageJson carries one: "no chapters" and "the
            // extension threw" are different problems and used to look alike.
            failure?.let { put("error", "${sources[id]?.name ?: id}: $it") }
        }.toString()
        if (title.isNotEmpty()) {
            pageCache[cacheKey] = CacheEntry(System.currentTimeMillis(), json)
        }
        return json
    }

    /**
     * Resolves a chapter's page list to image URLs. [data] is the chapter's `mediaRef`
     * (the source-relative chapter url). Returns `{provider, headers, pages:[{index,imageUrl}]}`;
     * the shared [headers] (referer/UA) must be applied to every image request by the reader.
     */
    fun pageListJson(id: String, data: String): String {
        // "{}" reads to the app as "no pages", which is the one thing it was
        // never allowed to mean here — a source that failed to load said the
        // same as a chapter that is genuinely empty.
        val src = sourceFor(id)
            ?: return JSONObject()
                .put("error", MangaRuntime.lastError ?: "source unavailable: mn:$id")
                .toString()
        val http = src as? HttpSource
        var failure: String? = null
        val chapter = chapterFromRef(data)
        val pages = try { runBlocking { src.getPageList(chapter) } }
        catch (t: Throwable) {
            Log.e(TAG, "pages $id", t)
            failure = t.message ?: t.javaClass.simpleName
            emptyList()
        }

        val pagesArr = JSONArray()
        for (p in pages) {
            var img = p.imageUrl
            // Some sources defer the real image url to getImageUrl(page).
            if ((img.isNullOrEmpty()) && p.url.isNotEmpty() && http != null) {
                img = try { runBlocking { http.getImageUrl(p) } }
                catch (t: Throwable) { Log.e(TAG, "imageUrl $id", t); null }
            }
            if (img.isNullOrEmpty()) continue
            pagesArr.put(JSONObject().apply {
                put("index", p.index)
                put("imageUrl", img)
            })
        }
        // Route the images back through the extension.
        //
        // A page url is half a request: the extension finishes it in
        // `imageRequest` and in its own interceptor chain, which is where
        // MangaPlus decrypts and where a Cloudflare cookie gets attached.
        // Fetching the url from Dart skipped all of it, and a chapter rendered
        // as a column of "Tap to reload". See [MangaImageServer].
        if (http != null && pagesArr.length() > 0) {
            val urls = ArrayList<String>(pagesArr.length())
            for (i in 0 until pagesArr.length()) {
                pagesArr.optJSONObject(i)?.optString("imageUrl")
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { urls.add(it) }
            }
            MangaImageServer.start { sourceId -> sourceFor(sourceId) }
            val local = MangaImageServer.publish(id, urls)
            for (i in 0 until pagesArr.length()) {
                val page = pagesArr.optJSONObject(i) ?: continue
                val original = page.optString("imageUrl")
                val proxied = local[original] ?: continue
                // Kept so the reader can cache by the real identity of the
                // image: the local port changes between runs, the source url
                // does not.
                page.put("cacheKey", original)
                page.put("imageUrl", proxied)
            }
        }

        val headers = JSONObject()
        http?.headers?.forEach { (k, value) -> headers.put(k, value) }

        return JSONObject().apply {
            put("provider", "mn:$id")
            put("headers", headers)
            put("pages", pagesArr)
            // "0 pages" and "the extension threw" used to look identical.
            if (pagesArr.length() == 0) {
                put("error", "${sources[id]?.name ?: id}: ${failure ?: "no pages in this chapter"}")
            }
        }.toString()
    }

    // --- per-source settings (ConfigurableSource) ---

    /** Returns the source's preferences as a JSON array, or `[]` if none. */
    fun getPrefsJson(id: String): String {
        val src = sourceFor(id) ?: return "[]"
        if (src !is ConfigurableSource) return "[]"
        return try {
            MangaPreferences.extract(context, id, src)
        } catch (t: Throwable) {
            Log.e(TAG, "prefs $id: ${t.message}"); "[]"
        }
    }

    /** Persists a single preference value to the source's SharedPreferences. */
    fun setPrefJson(id: String, key: String, value: Any?, type: String): String {
        return try {
            MangaPreferences.write(context, id, key, value, type)
            "{\"ok\":true}"
        } catch (t: Throwable) {
            Log.e(TAG, "setPref $id: ${t.message}"); "{\"ok\":false}"
        }
    }
}
