package com.soplay.sozo.aniyomi

import android.content.Context
import android.util.Log
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SAnimeImpl
import eu.kanade.tachiyomi.animesource.model.Hoster
import eu.kanade.tachiyomi.animesource.model.SEpisodeImpl
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class AniyomiHost(private val context: Context) {

    companion object {
        private const val TAG = "AniyomiHost"
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
    )

    private val sources = LinkedHashMap<String, SourceMeta>()

    /**
     * Why the last apk fetch failed, surfaced into `getMainPage`'s `error` field.
     * Distinct from [AniyomiRuntime.lastError], which covers dex loading — this
     * one covers never getting a usable file in the first place.
     */
    @Volatile
    private var lastError: String? = null

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
        )
    }

    fun removeSources(ids: List<String>) {
        ids.forEach { sources.remove(it) }
    }

    /**
     * Invalidates everything cached for the extension published at [apkUrl] so the
     * next use re-downloads it. Called by the updater after an upstream version bump.
     * Evicting the runtime cache matters as much as deleting the file — otherwise
     * the old code keeps being served from memory for the rest of the process.
     */
    fun dropCachedApk(apkUrl: String) {
        if (apkUrl.isEmpty()) return
        val affected = sources.values.filter { it.apkUrl == apkUrl }
        if (affected.isEmpty()) return
        AniyomiRuntime.evictSources(affected.map { it.id })
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
                put("id", "an:${s.id}")
                put("name", s.name)
                put("lang", s.lang)
                put("baseUrl", s.baseUrl)
                put("icon", s.iconUrl)
                put("nsfw", s.nsfw)
                put("repo", s.repoName)
                put("mode", "client")
                put("group", "aniyomi")
            })
        }
        return arr.toString()
    }

    // --- runtime: load source + convert to soplay JSON ---

    /**
     * Downloads the extension apk if it isn't cached, and returns it.
     *
     * Two things here are load-bearing (both were already fixed in `MangaHost`;
     * this is the anime twin catching up, and they are exactly why "Aniyomi
     * recommended won't load" was reproducible):
     *
     * 1. **The cache key includes the apk's filename**, which carries the version
     *    (`aniyomi-all.animeonsen-v14.10.apk`). Keyed on the package alone, a
     *    published extension update could never be picked up — the old file
     *    existed, so it was returned forever.
     *
     * 2. **The download lands on a temp file and is renamed only once complete.**
     *    Writing straight to the final path meant a dropped connection left a
     *    truncated apk that `exists() && length() > 0` happily accepted, and
     *    `AniyomiRuntime` then `setReadOnly()`s it — so the source was
     *    permanently broken with no way to recover short of clearing app data.
     */
    /** Where [meta]'s apk is (or would be) cached. Single source of truth for the name. */
    private fun cachedApkFile(meta: SourceMeta): File {
        val dir = File(context.filesDir, "aniyomi").apply { mkdirs() }
        val base = (meta.pkg.ifEmpty { meta.id }).replace('/', '_')
        val remoteName = meta.apkUrl.substringAfterLast('/').substringBefore('?')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .takeIf { it.isNotEmpty() && it != ".apk" }
        return File(dir, if (remoteName != null) "$base-$remoteName" else "$base.apk")
    }

    private fun ensureApk(meta: SourceMeta): File? {
        if (meta.apkUrl.isEmpty()) {
            lastError = "no apk url for ${meta.name}"
            return null
        }
        val file = cachedApkFile(meta)
        val dir = file.parentFile!!
        if (file.exists() && file.length() > 0) return file

        val tmp = File(dir, "${file.name}.part")
        return try {
            val conn = (URL(meta.apkUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; instanceFollowRedirects = true
                connectTimeout = 20000; readTimeout = 60000
                setRequestProperty("User-Agent", UA)
            }
            if (conn.responseCode !in 200..299) {
                lastError = "apk download ${conn.responseCode} for ${meta.name}"
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
                lastError = "apk truncated for ${meta.name} ($written/$expected bytes)"
                Log.e(TAG, "apk ${meta.apkUrl} truncated: $written/$expected bytes")
                tmp.delete()
                return null
            }
            if (written <= 0) {
                lastError = "apk empty for ${meta.name}"
                Log.e(TAG, "apk ${meta.apkUrl} empty"); tmp.delete(); return null
            }
            // Clear read-only in case a previous load marked an older file at this
            // path; renameTo onto a read-only target fails silently otherwise.
            if (file.exists()) {
                file.setWritable(true)
                file.delete()
            }
            if (!tmp.renameTo(file)) {
                lastError = "apk rename failed for ${meta.name}"
                Log.e(TAG, "apk rename failed for ${file.name}"); tmp.delete(); return null
            }
            Log.i(TAG, "apk downloaded ${file.name} ($written bytes)")
            file
        } catch (t: Throwable) {
            tmp.delete()
            lastError = "apk download ${t.javaClass.simpleName}: ${t.message}"
            Log.e(TAG, "apk download failed: ${t.javaClass.simpleName}: ${t.message}")
            null
        }
    }

    /**
     * Every video for an episode, across both Aniyomi source APIs.
     *
     * Aniyomi 0.16 split resolution in two: `getHosterList(episode)` returns
     * the servers, then `getVideoList(hoster)` returns one server's qualities.
     * The old single call is still there and still what most extensions
     * implement, so this asks for hosters FIRST and falls back.
     *
     * Order matters. A new-API extension inherits a `getVideoList(episode)`
     * that returns nothing — its real implementation is on the hoster path — so
     * calling the old one first got an empty list and stopped, which on screen
     * is a source that finds the episode and then offers no servers. Calling
     * the new one first and falling back covers both, because an old-API
     * extension has no getHosterList to find.
     *
     * Resolved reflectively rather than against the type: the shim's
     * AnimeHttpSource does not declare getHosterList, and a source object comes
     * from a class loader of its own. A NoSuchMethodException here is the
     * ordinary case for an old extension, not an error.
     */
    private fun fetchVideos(src: Any, episode: SEpisodeImpl, id: String): List<Video> {
        val viaHosters = try {
            val method = src.javaClass.methods.firstOrNull {
                it.name == "getHosterList" && it.parameterTypes.size >= 1
            }
            if (method == null) {
                null
            } else {
                @Suppress("UNCHECKED_CAST")
                val hosters = runBlocking {
                    suspendCallCompat(method, src, episode) as? List<Hoster>
                } ?: emptyList()
                // A hoster that already carries its videos needs no second
                // call; one that does not is asked for them individually.
                hosters.flatMap { hoster ->
                    hoster.videoList ?: fetchHosterVideos(src, hoster)
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "hosters $id: ${t.message}")
            null
        }

        if (!viaHosters.isNullOrEmpty()) return viaHosters

        return try {
            runBlocking { (src as AnimeHttpSource).getVideoList(episode) }
        } catch (t: Throwable) {
            Log.e(TAG, "videos $id: ${t.message}")
            emptyList()
        }
    }

    /** One hoster's qualities, when the hoster list did not carry them. */
    private fun fetchHosterVideos(src: Any, hoster: Hoster): List<Video> = try {
        val method = src.javaClass.methods.firstOrNull {
            it.name == "getVideoList" &&
                it.parameterTypes.firstOrNull()?.name?.endsWith("Hoster") == true
        } ?: return emptyList()
        @Suppress("UNCHECKED_CAST")
        runBlocking { suspendCallCompat(method, src, hoster) as? List<Video> } ?: emptyList()
    } catch (t: Throwable) {
        Log.e(TAG, "hoster videos ${hoster.hosterName}: ${t.message}")
        emptyList()
    }

    /**
     * Calls a Kotlin `suspend` method by reflection.
     *
     * A suspend function compiles to one taking an extra `Continuation`, so it
     * cannot be invoked with the arguments its source declares. `suspendCoroutine`
     * supplies the continuation; a function that returns without suspending
     * hands the value back directly, which is why the COROUTINE_SUSPENDED
     * sentinel has to be checked rather than assumed.
     */
    private suspend fun suspendCallCompat(
        method: java.lang.reflect.Method,
        target: Any,
        arg: Any,
    ): Any? = kotlin.coroutines.suspendCoroutine<Any?> { cont ->
        val result = method.invoke(target, arg, cont)
        if (result != kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED) {
            cont.resumeWith(Result.success(result))
        }
    }

    private fun sourceFor(id: String): AnimeCatalogueSource? {
        val meta = sources[id] ?: run {
            lastError = "source not installed: an:$id"
            return null
        }
        val apk = ensureApk(meta) ?: return null
        return AniyomiRuntime.source(context, apk.absolutePath, meta.pkg, meta.id)
    }

    /** Best available explanation for an empty result, or null when there is none. */
    private fun failureReason(id: String): String =
        AniyomiRuntime.lastError ?: lastError ?: "source unavailable: an:$id"

    private fun cardJson(a: SAnime, id: String) = JSONObject().apply {
        put("provider", "an:$id")
        put("externalId", a.url)
        put("title", a.title)
        put("slug", a.url)
        put("contentUrl", a.url)
        put("thumbnail", a.thumbnail_url)
        put("type", "Anime")
    }

    private fun newAnime(url: String) = SAnimeImpl().apply { this.url = url; title = "" }

    fun getMainPageJson(id: String, page: Int): String {
        val src = sourceFor(id)
        val sections = JSONArray()
        val banner = JSONArray()
        var queryError: String? = null
        if (src != null) {
            // popular + latest are independent → fetch concurrently. runCatching
            // INSIDE each job so one failing call can't cancel its sibling through
            // the shared parent scope.
            val popular: Result<AnimesPage>
            val latest: Result<AnimesPage?>
            runBlocking {
                val popJob = async(Dispatchers.IO) { runCatching { src.getPopularAnime(page) } }
                val latJob = async(Dispatchers.IO) {
                    runCatching { if (src.supportsLatest) src.getLatestUpdates(page) else null }
                }
                popular = popJob.await()
                latest = latJob.await()
            }

            popular.getOrNull()?.let { pop ->
                pop.animes.firstOrNull()?.let {
                    val t = runCatching { it.title }.getOrDefault("<unset>")
                    Log.i(TAG, "popular[0] title='$t' url='${it.url}'")
                }
                val items = JSONArray()
                for (a in pop.animes.take(30)) items.put(cardJson(a, id))
                if (items.length() > 0) {
                    var i = 0
                    while (i < items.length() && i < 12) { banner.put(items.get(i)); i++ }
                    sections.put(JSONObject().apply {
                        put("key", "popular"); put("label", "Popular")
                        put("viewAll", JSONObject().apply { put("type", "an"); put("slug", "popular") })
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
                for (a in lat.animes.take(30)) items.put(cardJson(a, id))
                if (items.length() > 0) sections.put(JSONObject().apply {
                    put("key", "latest"); put("label", "Latest")
                    put("viewAll", JSONObject().apply { put("type", "an"); put("slug", "latest") })
                    put("items", items)
                })
            }
            latest.exceptionOrNull()?.let { t ->
                if (queryError == null) queryError = "getLatest: ${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "getLatest $id", t)
            }
        }
        return JSONObject().apply {
            put("provider", "an:$id"); put("banner", banner); put("sections", sections)
            // Surface the real failure — otherwise the home is silently empty and
            // there is nothing on screen or in the logs tying it to a cause.
            if (src == null) {
                put("error", failureReason(id))
            } else if (sections.length() == 0 && queryError != null) {
                put("error", queryError)
            }
        }.toString()
    }

    fun getSectionJson(id: String, data: String, page: Int): String {
        val src = sourceFor(id)
        val items = JSONArray()
        var hasNext = false
        if (src != null) try {
            val pg = runBlocking {
                if (data == "latest" && src.supportsLatest) src.getLatestUpdates(page)
                else src.getPopularAnime(page)
            }
            for (a in pg.animes) items.put(cardJson(a, id))
            hasNext = pg.hasNextPage
        } catch (t: Throwable) { Log.e(TAG, "getSection $id: ${t.message}") }
        return JSONObject().apply {
            put("provider", "an:$id"); put("items", items); put("page", page)
            put("totalPages", if (hasNext) page + 1 else page)
        }.toString()
    }

    fun searchJson(id: String, query: String, page: Int = 1): String {
        val src = sourceFor(id)
        val items = JSONArray()
        var hasNext = false
        var error: String? = if (src == null) failureReason(id) else null
        if (src != null) try {
            val pg = runBlocking { src.getSearchAnime(page, query, AnimeFilterList()) }
            for (a in pg.animes) items.put(cardJson(a, id))
            hasNext = pg.hasNextPage
        } catch (t: Throwable) {
            error = "${t.javaClass.simpleName}: ${t.message}"
            Log.e(TAG, "search $id: ${t.message}")
        }
        return JSONObject().apply {
            put("provider", "an:$id"); put("items", items)
            put("query", query); put("page", page)
            put("totalPages", if (hasNext) page + 1 else page)
            // Lets the caller tell "this source is broken" from "0 matches" —
            // previously both arrived as an empty list.
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
        val src = sourceFor(id) as? AnimeHttpSource
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
        val src = sourceFor(id) ?: return "{}"
        val anime = newAnime(url)
        val details = try { runBlocking { src.getAnimeDetails(anime) } }
        catch (t: Throwable) { Log.e(TAG, "details $id: ${t.message}"); anime }
        val eps = try { runBlocking { src.getEpisodeList(anime) } }
        catch (t: Throwable) { Log.e(TAG, "episodes $id: ${t.message}"); emptyList() }
        // A single-episode entry is a movie; multiple episodes is a series.
        val isMovie = eps.size <= 1
        val episodes = JSONArray()
        eps.sortedBy { it.episode_number }.forEachIndexed { i, e ->
            val num = if (e.episode_number > 0) e.episode_number.toInt() else (i + 1)
            episodes.put(JSONObject().apply {
                put("episode", num)
                put("label", if (isMovie) "Play" else e.name.ifEmpty { "Episode $num" })
                put("mediaRef", e.url)
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
        // Aniyomi has no "recommendations" API, so derive a "similar" row from a
        // title search (same fallback CloudStream uses).
        val related = JSONArray()
        try {
            val q = title.replace(Regex("\\(.*?\\)"), "").trim()
            if (q.length >= 2) {
                val results = runBlocking { src.getSearchAnime(1, q, AnimeFilterList()) }
                for (a in results.animes) {
                    if (a.url == url) continue
                    related.put(cardJson(a, id))
                    if (related.length() >= 20) break
                }
            }
        } catch (t: Throwable) { Log.e(TAG, "related $id: ${t.message}") }
        return JSONObject().apply {
            put("provider", "an:$id")
            put("contentId", url); put("contentUrl", url)
            put("title", title)
            put("description", desc)
            put("thumbnail", details.thumbnail_url)
            put("banner", details.thumbnail_url)
            put("year", JSONObject.NULL)
            if (!author.isNullOrBlank()) put("director", author)
            put("genres", JSONArray(details.getGenres() ?: emptyList<String>()))
            put("type", if (isMovie) "Movie" else "Anime")
            put("isSerial", !isMovie)
            put("cast", JSONArray())
            put("related", related)
            put("episodes", episodes)
        }.toString()
    }

    fun loadLinksJson(id: String, data: String): String {
        val meta = sources[id]
        val src = sourceFor(id)
        val videoSources = JSONArray()
        val subs = JSONArray()
        val seen = HashSet<String>()
        val seenSub = HashSet<String>()
        if (src != null && meta != null) {
            val episode = SEpisodeImpl().apply { url = data; name = "" }
            val videos = fetchVideos(src, episode, id)
            for (v in videos) {
                val vu = v.videoUrl ?: continue
                if (vu.isEmpty() || !seen.add(vu)) continue
                val headers = JSONObject()
                v.headers?.forEach { (k, value) -> headers.put(k, value) }
                val isHls = vu.contains(".m3u8")
                videoSources.put(JSONObject().apply {
                    put("quality", v.quality.ifEmpty { "Source" })
                    put("videoUrl", vu)
                    put("type", if (isHls) "hls" else "http")
                    put("host", meta.name)
                    put("isDefault", videoSources.length() == 0)
                    put("accessible", true)
                    put("headers", headers)
                })
                for (t in v.subtitleTracks) {
                    if (t.url.isNotEmpty() && seenSub.add(t.url)) subs.put(JSONObject().apply {
                        put("label", t.lang); put("file", t.url); put("default", false)
                    })
                }
            }
        }
        val first = if (videoSources.length() > 0) videoSources.getJSONObject(0) else null
        return JSONObject().apply {
            put("videoUrl", first?.optString("videoUrl"))
            put("type", first?.optString("type"))
            put("headers", first?.optJSONObject("headers") ?: JSONObject())
            put("videoSources", videoSources)
            put("subtitles", subs)
        }.toString()
    }
}
