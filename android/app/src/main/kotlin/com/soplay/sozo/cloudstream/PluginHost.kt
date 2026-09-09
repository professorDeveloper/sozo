package com.soplay.sozo.cloudstream

import android.content.Context
import android.content.res.AssetManager
import android.content.res.Resources
import android.util.Log
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.AnimeLoadResponse
import com.lagradost.cloudstream3.Episode
import com.lagradost.cloudstream3.LiveStreamLoadResponse
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.MainPageRequest
import com.lagradost.cloudstream3.MovieLoadResponse
import com.lagradost.cloudstream3.SearchResponse
import com.lagradost.cloudstream3.TorrentLoadResponse
import com.lagradost.cloudstream3.TvSeriesLoadResponse
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.plugins.PluginManager as CsPluginManager
import com.lagradost.cloudstream3.utils.ExtractorLink
import com.lagradost.cloudstream3.utils.ExtractorLinkType
import dalvik.system.PathClassLoader
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * CloudStream plugin host (Android-only).
 *
 * Loads `.cs3` plugins like CloudStream's PluginManager (PathClassLoader(file,
 * appContext.classLoader) → manifest.json → loadClass(pluginClassName) →
 * newInstance → load(context) → registerMainAPI → APIHolder.allProviders) and
 * exposes the provider surface as JSON for the Flutter MethodChannel bridge.
 *
 * Runtime comes from `com.github.recloudstream.cloudstream:library` (MainAPI/
 * APIHolder/app HTTP/extractors/BasePlugin). `Plugin` (app-module class the
 * plugins subclass) is re-declared locally in com.lagradost.cloudstream3.plugins.
 * See docs/CLOUDSTREAM_INTEGRATION.md.
 *
 * Output shapes mirror the existing soplay models so the Flutter side maps onto
 * its current entities (provider card / detail+episodes / VideoSourceEntity /
 * subtitle). Stable id scheme `cs:<MainAPI.name>` + contentUrl=load-url so
 * my-list / continue-watching keep working.
 */
class PluginHost(private val appContext: Context) {

    companion object {
        private const val TAG = "CloudStreamHost"
        // Chrome-mobile UA used by the interactive Cloudflare solver for cs: sources
        // (best-effort — cs plugins drive their own HTTP client). Mirrors the
        // Tachiyomi default so a single solved cookie tends to satisfy both.
        private const val CS_UA =
            "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    }

    private val loaded = HashMap<String, BasePlugin>()
    // internalName -> the MainAPI provider names it registered (for unload + dedup).
    private val pluginProviders = HashMap<String, List<String>>()
    // MainAPI.name -> plugin iconUrl (from plugins.json) for nicer provider icons.
    private val providerIcons = HashMap<String, String>()

    // Lazy-load registry: providerName -> where to load it from. Populated cheaply
    // on startup (no DexClassLoader) so the provider list is instant; the actual
    // .cs3 is loaded only when that provider is first used.
    data class Meta(
        val provider: String, val icon: String?, val internalName: String,
        val cs3Path: String, val repo: String? = null,
        /**
         * Source language, from the repo's plugin list (`language`).
         *
         * Taken there rather than from `MainAPI.lang`, which would be the exact
         * answer, because reading it means loading the .cs3 — and the whole
         * point of this metadata is that the provider list is built WITHOUT
         * loading a single plugin. The repo's own tag is what CloudStream
         * itself labels a plugin with, and French/Spanish/Arabic packs are the
         * ones that publish it accurately, which is precisely the case that
         * needs it. Empty means the repo did not say.
         */
        val lang: String = "",
    )
    private val metas = LinkedHashMap<String, Meta>()

    /** Register provider metadata WITHOUT loading the plugin (startup path). */
    fun registerMeta(
        provider: String, icon: String?, internalName: String,
        cs3Path: String, repo: String? = null, lang: String = "",
    ) {
        metas[provider] = Meta(provider, icon, internalName, cs3Path, repo, lang)
        if (!icon.isNullOrEmpty()) providerIcons[provider] = icon
    }

    /** Ensure the plugin backing a provider is loaded (lazy, on first use). */
    private fun ensurePluginLoaded(provider: String) {
        val m = metas[provider] ?: return
        if (loaded.containsKey(m.internalName)) return
        val f = File(m.cs3Path)
        if (f.exists()) loadCs3(f, m.internalName, m.icon, m.repo, m.lang)
    }

    private data class Manifest(
        val name: String?, val pluginClassName: String?,
        val version: Int?, val requiresResources: Boolean,
    )

    private fun readManifest(loader: ClassLoader): Manifest? {
        val stream = loader.getResourceAsStream("manifest.json") ?: return null
        val text = stream.bufferedReader().use { it.readText() }
        val o = JSONObject(text)
        return Manifest(
            name = o.optString("name").ifEmpty { null },
            pluginClassName = o.optString("pluginClassName").ifEmpty { null },
            version = if (o.has("version")) o.optInt("version") else null,
            requiresResources = o.optBoolean("requiresResources", false),
        )
    }

    /** Load a downloaded .cs3; returns the provider names it registered. */
    fun loadCs3(
        file: File, internalName: String, iconUrl: String? = null,
        repo: String? = null, lang: String = "",
    ): List<String> {
        // Already loaded this process → don't register twice (avoids duplicates).
        loaded[internalName]?.let { return pluginProviders[internalName] ?: emptyList() }
        return try {
            try { file.setReadOnly() } catch (_: Throwable) {}
            val loader = PathClassLoader(file.absolutePath, appContext.classLoader)
            val manifest = readManifest(loader) ?: run {
                Log.e(TAG, "no manifest.json in ${file.name}"); return emptyList()
            }
            val className = manifest.pluginClassName ?: run {
                Log.e(TAG, "no pluginClassName in ${file.name}"); return emptyList()
            }
            val before = APIHolder.allProviders.map { it.name }.toSet()

            val instance = loader.loadClass(className)
                .getDeclaredConstructor().newInstance() as BasePlugin
            instance.filename = file.absolutePath

            if (manifest.requiresResources) {
                val assets = AssetManager::class.java.getDeclaredConstructor().newInstance()
                AssetManager::class.java.getMethod("addAssetPath", String::class.java)
                    .invoke(assets, file.absolutePath)
                @Suppress("DEPRECATION")
                (instance as? Plugin)?.resources = Resources(
                    assets, appContext.resources.displayMetrics, appContext.resources.configuration
                )
            }
            if (instance is Plugin) instance.load(appContext) else instance.load()
            loaded[internalName] = instance
            // So a plugin walking PluginManager.getPluginsOnline() to find its
            // own .cs3 — the usual reason to call it — gets a real answer.
            CsPluginManager.record(internalName, file.absolutePath)

            val added = APIHolder.allProviders.map { it.name }.filter { it !in before }
            pluginProviders[internalName] = added
            added.forEach { metas[it] = Meta(it, iconUrl, internalName, file.absolutePath, repo, lang) }
            if (!iconUrl.isNullOrEmpty()) added.forEach { providerIcons[it] = iconUrl }
            Log.i(TAG, "loaded ${file.name}: providers=$added")
            added
        } catch (t: Throwable) {
            // Kept, not just logged.
            //
            // Every failure here used to become an empty list and a line in
            // logcat. The plugin installed, registered nothing, appeared
            // nowhere, and the app had nothing to say about it — which is
            // indistinguishable from the plugin having no sources. The commonest
            // cause is a NoClassDefFoundError for a CloudStream class that lives
            // in its app module rather than the `library` artifact this depends
            // on, and that is a sentence a user can act on.
            lastErrors[internalName] = describeLoadFailure(t)
            Log.e(TAG, "failed to load ${file.name}: ${Log.getStackTraceString(t)}")
            emptyList()
        }
    }

    /** The last load failure per plugin, for the UI to surface. */
    private val lastErrors = mutableMapOf<String, String>()

    fun lastError(internalName: String): String? = lastErrors[internalName]

    fun lastErrorsJson(): String = JSONObject(lastErrors as Map<*, *>).toString()

    /**
     * A one-line reason a person could act on.
     *
     * A stack trace is the right thing in logcat and the wrong thing in a
     * dialog. The three cases below are almost all of them in practice, and
     * they need different actions from the reader: an incompatible plugin, a
     * corrupt download, and everything else.
     */
    private fun describeLoadFailure(t: Throwable): String {
        val root = generateSequence(t) { it.cause }.last()
        val name = root.message?.trim().orEmpty()
        return when (root) {
            is NoClassDefFoundError, is ClassNotFoundException ->
                "This plugin needs a part of CloudStream that Sozo does not include" +
                    (if (name.isNotEmpty()) " ($name)" else "") + "."
            is NoSuchMethodError, is NoSuchFieldError, is AbstractMethodError ->
                "This plugin was built against a newer CloudStream than Sozo bundles" +
                    (if (name.isNotEmpty()) " ($name)" else "") + "."
            is java.util.zip.ZipException, is java.io.IOException ->
                "The plugin file could not be read — try removing and adding the repo again."
            else ->
                "${root.javaClass.simpleName}${if (name.isNotEmpty()) ": $name" else ""}"
        }
    }

    /** Remove providers by name (loaded or lazy) — used when a repo is removed. */
    fun removeProviders(names: List<String>) {
        if (names.isEmpty()) return
        val set = names.toSet()
        try { APIHolder.allProviders.removeAll { it.name in set } } catch (_: Throwable) {}
        names.forEach { providerIcons.remove(it); metas.remove(it) }
        // Drop any loaded plugins whose providers are now all gone.
        val internalNames = pluginProviders.filterValues { it.any { n -> n in set } }.keys.toList()
        internalNames.forEach {
            loaded.remove(it); pluginProviders.remove(it); CsPluginManager.forget(it)
        }
        Log.i(TAG, "removed providers=$names")
    }

    private fun apiByName(name: String): MainAPI? {
        val n = name.removePrefix("cs:")
        ensurePluginLoaded(n)
        return APIHolder.allProviders.firstOrNull { it.name == n }
    }

    private fun slugify(s: String): String =
        s.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')

    /**
     * Returns `{"baseUrl","userAgent"}` for the interactive Cloudflare solver.
     * baseUrl is the provider's [MainAPI.mainUrl]; the UA is a Chrome-mobile
     * string (cs is best-effort — plugins use their own HTTP client). Returns
     * `{}` when the provider isn't found or exposes no main url.
     */
    fun cloudflareInfo(providerName: String): String {
        val api = apiByName(providerName) ?: return "{}"
        val baseUrl = api.mainUrl
        if (baseUrl.isEmpty()) return "{}"
        return JSONObject().apply {
            put("baseUrl", baseUrl)
            put("userAgent", CS_UA)
        }.toString()
    }

    /** Provider list for Flutter — from lazy metadata (no plugins loaded yet). */
    fun providersJson(): String {
        val arr = JSONArray()
        for (m in metas.values) {
            arr.put(JSONObject().apply {
                put("id", "cs:${m.provider}")
                put("name", m.provider)
                // The other three hosts have always sent this; CloudStream was
                // the one that did not, so its providers arrived in the picker
                // with no language at all and could not be filtered.
                if (m.lang.isNotEmpty()) put("lang", m.lang)
                m.icon?.let { put("icon", it) }
                m.repo?.let { if (it.isNotEmpty()) put("repo", it) }
            })
        }
        return arr.toString()
    }

    /**
     * "Genres" for the home chip row = the provider's MainPageData categories.
     * `slug` carries the MainPageData.data so a tap re-uses getSectionJson (the
     * same path as a section's view-all).
     */
    fun getGenresJson(providerName: String): String {
        val api = apiByName(providerName)
        val arr = JSONArray()
        if (api != null) {
            for (mp in api.mainPage) {
                if (mp.name.isBlank()) continue
                arr.put(JSONObject().apply {
                    put("provider", "cs:${api.name}")
                    put("name", mp.name)
                    put("slug", mp.data) // getSection(data) resolves this category
                    put("image", "")
                })
            }
        }
        return arr.toString()
    }

    private fun cardJson(r: SearchResponse, apiName: String) = JSONObject().apply {
        put("provider", "cs:$apiName")
        put("externalId", r.url)
        put("title", r.name)
        put("slug", r.url)
        put("contentUrl", r.url)
        put("thumbnail", r.posterUrl)
        put("type", r.type?.name)
    }

    suspend fun getMainPageJson(providerName: String, page: Int): String {
        val api = apiByName(providerName) ?: run {
            Log.e(TAG, "getMainPage: provider '$providerName' not found (loaded=${APIHolder.allProviders.size})")
            return JSONObject(mapOf("provider" to providerName, "banner" to JSONArray(), "sections" to JSONArray())).toString()
        }
        val sections = JSONArray()
        val banner = JSONArray()
        if (api.mainPage.isEmpty()) {
            Log.w(TAG, "getMainPage ${api.name}: provider has no mainPage list")
            return JSONObject(mapOf("provider" to "cs:${api.name}", "banner" to banner, "sections" to sections)).toString()
        }
        // Home shows at most a handful of rows; capping the sections also caps the
        // number of getMainPage network calls we make per provider (perf).
        val maxSections = 5
        for (mp in api.mainPage) {
            if (sections.length() >= maxSections) break
            try {
                val resp = api.getMainPage(page, MainPageRequest(mp.name, mp.data, false))
                if (resp == null) { Log.w(TAG, "getMainPage ${api.name}: '${mp.name}' returned null"); continue }
                for (list in resp.items) {
                    if (sections.length() >= maxSections) break
                    val items = JSONArray()
                    for (sr in list.list) items.put(cardJson(sr, api.name))
                    if (items.length() == 0) continue
                    if (banner.length() == 0) {
                        var i = 0
                        while (i < items.length() && i < 12) { banner.put(items.get(i)); i++ }
                    }
                    val key = slugify(list.name)
                    sections.put(JSONObject().apply {
                        put("key", key)
                        put("label", list.name)
                        // slug = the MainPageData.data so view-all can re-request
                        // exactly this section (paginated) via getSectionJson.
                        put("viewAll", JSONObject().apply { put("type", "cs"); put("slug", mp.data) })
                        put("items", items)
                    })
                }
            } catch (t: Throwable) {
                // Log (don't swallow) — most empty-home failures are a plugin
                // referencing an app-module class our embedded `library` lacks
                // (NoClassDefFoundError), surfaced here per section.
                Log.e(TAG, "getMainPage ${api.name} '${mp.name}': ${t.javaClass.simpleName}: ${t.message}")
            }
        }
        Log.i(TAG, "getMainPage ${api.name}: ${sections.length()} sections, ${banner.length()} banner")
        return JSONObject().apply {
            put("provider", "cs:${api.name}"); put("banner", banner); put("sections", sections)
        }.toString()
    }

    /** View-all for one home section: re-request just that MainPageData, paginated. */
    suspend fun getSectionJson(providerName: String, data: String, page: Int): String {
        val api = apiByName(providerName)
        val items = JSONArray()
        if (api != null) {
            val mp = api.mainPage.firstOrNull { it.data == data }
            val name = mp?.name ?: data
            try {
                val resp = api.getMainPage(page, MainPageRequest(name, data, false))
                if (resp != null) {
                    for (list in resp.items) for (sr in list.list) items.put(cardJson(sr, api.name))
                }
            } catch (_: Throwable) { }
        }
        return JSONObject().apply {
            put("provider", providerName)
            put("items", items)
            put("page", page)
            put("totalPages", if (items.length() > 0) page + 1 else page)
        }.toString()
    }

    suspend fun searchJson(providerName: String, query: String, page: Int = 1): String {
        val api = apiByName(providerName)
        val items = JSONArray()
        // CloudStream's MainAPI.search(query) has no paging — return the full
        // result set on page 1 only; never advertise further pages.
        if (api != null && page == 1) {
            val results = try { api.search(query) } catch (t: Throwable) {
                Log.e(TAG, "search ${api.name}: ${t.javaClass.simpleName}: ${t.message}"); null
            } ?: emptyList()
            for (r in results) items.put(cardJson(r, api.name))
        }
        return JSONObject().apply {
            put("provider", providerName); put("items", items)
            put("query", query); put("page", page); put("totalPages", page)
        }.toString()
    }

    private fun formatDate(raw: Long): String? = try {
        val ms = if (raw < 10_000_000_000L) raw * 1000 else raw
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(ms))
    } catch (_: Throwable) { null }

    private fun episodeJson(e: Episode, index: Int) = JSONObject().apply {
        put("episode", e.episode ?: (index + 1))
        put("label", e.name ?: "Episode ${e.episode ?: (index + 1)}")
        put("mediaRef", e.data)                 // → loadLinks(data)
        if (e.posterUrl != null) put("image", e.posterUrl)   // preview thumbnail
        if (e.season != null) put("season", e.season)
        if (!e.description.isNullOrEmpty()) put("overview", e.description)
        e.date?.let { d -> formatDate(d)?.let { put("airdate", it) } }
        e.runTime?.let { if (it > 0) put("runtime", "$it min") }
    }

    suspend fun loadJson(providerName: String, url: String): String {
        val api = apiByName(providerName) ?: run {
            Log.e(TAG, "load: provider '$providerName' not found"); return "{}"
        }
        val resp = try { api.load(url) } catch (t: Throwable) {
            Log.e(TAG, "load ${api.name}: ${t.javaClass.simpleName}: ${t.message}"); null
        } ?: return "{}"
        val episodes = JSONArray()
        var isSerial = false
        var unsupported: String? = null
        when (resp) {
            is TvSeriesLoadResponse -> {
                isSerial = true
                resp.episodes.forEachIndexed { i, e -> episodes.put(episodeJson(e, i)) }
            }
            is AnimeLoadResponse -> {
                isSerial = true
                val list = resp.episodes.values.firstOrNull() ?: emptyList()
                list.forEachIndexed { i, e -> episodes.put(episodeJson(e, i)) }
            }
            is MovieLoadResponse -> {
                // dataUrl is what loadLinks() expects; fall back to the page url
                // if a provider leaves it empty.
                val ref = resp.dataUrl.ifEmpty { resp.url }
                episodes.put(JSONObject().apply {
                    put("episode", 1); put("label", "Play"); put("mediaRef", ref)
                })
            }
            // Live TV channels. Structurally identical to a movie — one `dataUrl`
            // handed straight to loadLinks — but it is a SEPARATE response class,
            // and leaving it out of this `when` is why every Live TV plugin
            // (IPTVPlayer, QuickIPTV, PublicSportsIPTV, …) opened to a detail page
            // with no episodes and nothing to press: `load()` succeeded, the title
            // and poster rendered, and the playable entry was silently dropped.
            is LiveStreamLoadResponse -> {
                val ref = resp.dataUrl.ifEmpty { resp.url }
                episodes.put(JSONObject().apply {
                    put("episode", 1); put("label", "Watch live"); put("mediaRef", ref)
                })
            }
            // A torrent entry carries a magnet (or a .torrent url) instead of a
            // dataUrl. That used to be a dead end; the app now embeds a torrent
            // server, so the link is offered as the single playable episode and
            // the player turns it into a local stream on open.
            is TorrentLoadResponse -> {
                val ref = resp.magnet ?: resp.torrent
                if (ref.isNullOrBlank()) {
                    unsupported = "This torrent entry has no magnet or .torrent link."
                } else {
                    episodes.put(JSONObject().apply {
                        put("episode", 1)
                        put("label", resp.name.ifBlank { "Torrent" })
                        put("mediaRef", ref)
                    })
                }
            }
        }
        // Cast (actors) + related (recommendations) when the provider supplies them.
        val cast = JSONArray()
        (resp.actors ?: emptyList()).forEach { ad ->
            cast.put(JSONObject().apply {
                put("name", ad.actor.name)
                if (!ad.actor.image.isNullOrEmpty()) put("image", ad.actor.image)
                if (!ad.roleString.isNullOrEmpty()) put("character", ad.roleString)
            })
        }
        val related = JSONArray()
        (resp.recommendations ?: emptyList()).forEach { sr -> related.put(cardJson(sr, api.name)) }
        // Fallback: many providers leave recommendations empty — derive "similar"
        // from a title search so the section isn't blank.
        if (related.length() == 0) {
            try {
                val q = resp.name.replace(Regex("\\(.*?\\)"), "").trim()
                if (q.length >= 2) {
                    val results = api.search(q) ?: emptyList()
                    for (sr in results) {
                        if (sr.url == resp.url) continue
                        related.put(cardJson(sr, api.name))
                        if (related.length() >= 20) break
                    }
                }
            } catch (_: Throwable) { }
        }

        return JSONObject().apply {
            put("provider", "cs:${api.name}")
            put("contentId", resp.url); put("contentUrl", resp.url)
            put("title", resp.name); put("description", resp.plot)
            put("thumbnail", resp.posterUrl); put("banner", resp.backgroundPosterUrl)
            put("year", resp.year ?: JSONObject.NULL)
            resp.duration?.let { if (it > 0) put("duration", "$it min") }
            put("genres", JSONArray(resp.tags ?: emptyList<String>()))
            put("type", resp.type.name)
            put("isSerial", isSerial)
            put("cast", cast)
            put("related", related)
            put("episodes", episodes)
            // An empty episode list is never something the UI can act on, so
            // always say why. Previously this returned a valid-looking payload
            // with zero entries and the detail page just sat there.
            if (episodes.length() == 0) {
                put("error", unsupported
                    ?: "${'$'}{api.name}: no playable entry for this title (${'$'}{resp.javaClass.simpleName})")
            }
        }.toString()
    }

    // AudioFile is @Prerelease in the CloudStream library; the annotation is an
    // IDE hint with BINARY retention, so reading the list a plugin may have filled
    // costs nothing at runtime and is empty for every plugin that sets none.
    @OptIn(com.lagradost.cloudstream3.Prerelease::class)
    suspend fun loadLinksJson(providerName: String, data: String): String {
        val api = apiByName(providerName)
        // (quality, source) pairs so the list can be ordered before it is emitted.
        val collected = ArrayList<Pair<Int, JSONObject>>()
        val subs = JSONArray()
        val seenUrls = HashSet<String>()
        val seenSubs = HashSet<String>()
        if (api != null) {
            try {
                api.loadLinks(
                    data = data,
                    isCasting = false,
                    subtitleCallback = { sf: com.lagradost.cloudstream3.SubtitleFile ->
                        if (sf.url.isNotEmpty() && seenSubs.add(sf.url)) {
                            subs.put(JSONObject().apply {
                                put("label", sf.lang); put("file", sf.url); put("default", false)
                                // A subtitle is fetched on its own, so it inherits none of
                                // the stream's headers. Plenty of CloudStream sources hand
                                // out tracks that 403 without the Referer the extractor
                                // set, and SubtitleFile has carried those headers since
                                // v4.7 — dropping them is why a provider could return
                                // subtitles and the player still show none.
                                sf.headers?.takeIf { it.isNotEmpty() }?.let {
                                    put("headers", JSONObject(it as Map<*, *>))
                                }
                            })
                        }
                    },
                    callback = { link: ExtractorLink ->
                        // Torrents and magnets used to be dropped here: they are not
                        // streams, and handing one to ExoPlayer produced a bare "Source
                        // error". They are now passed through tagged as "torrent",
                        // because the app embeds a torrent server and the player
                        // resolves such a link into a local HTTP stream before opening
                        // it (see core/torrent/ and player_page.media.dart).
                        //
                        // Relative urls ("dl.php?id=…") are still dropped — ExoPlayer
                        // resolves those as a local file path.
                        val isTorrent = link.type == ExtractorLinkType.TORRENT ||
                                link.type == ExtractorLinkType.MAGNET
                        val addressable = link.url.startsWith("http", ignoreCase = true) ||
                                (isTorrent && link.url.startsWith("magnet:", ignoreCase = true))
                        if (addressable && seenUrls.add(link.url)) {
                            // getAllHeaders() folds in the referer exactly the way
                            // CloudStream's own player does, instead of us overwriting a
                            // Referer an extractor had deliberately set.
                            val headers = JSONObject(link.getAllHeaders() as Map<*, *>)
                            // quality is a resolution int (e.g. 1080) or a Qualities
                            // sentinel; build a readable, distinct "<host> · <res>p".
                            val q = link.quality
                            val res = if (q in 144..4320) "${q}p" else null
                            val nm = link.name.ifBlank { "Source" }
                            val label = if (res != null) "$nm · $res" else nm
                            collected.add((if (q in 144..4320) q else 0) to JSONObject().apply {
                                put("quality", label)
                                put("videoUrl", link.url)
                                // DASH used to fall into the `else` branch and be handed
                                // over as a plain progressive file, so every .mpd source
                                // failed to open.
                                put("type", when (link.type) {
                                    ExtractorLinkType.M3U8 -> "hls"
                                    ExtractorLinkType.DASH -> "dash"
                                    // The Dart side recognises a magnet by its scheme
                                    // anyway, but naming the type keeps the source list
                                    // honest about what it is offering.
                                    ExtractorLinkType.TORRENT,
                                    ExtractorLinkType.MAGNET -> "torrent"
                                    else -> "http"
                                })
                                put("host", link.name)
                                put("accessible", true)
                                put("headers", headers)
                                // Separate audio renditions the extractor says belong with
                                // this video. A dual-audio release puts its dub here rather
                                // than in the manifest, so discarding them left the player
                                // with one track and nothing to switch to.
                                if (link.audioTracks.isNotEmpty()) {
                                    put("audioTracks", JSONArray().apply {
                                        link.audioTracks.forEach { a ->
                                            put(JSONObject().apply {
                                                put("url", a.url)
                                                a.headers?.takeIf { it.isNotEmpty() }?.let {
                                                    put("headers", JSONObject(it as Map<*, *>))
                                                }
                                            })
                                        }
                                    })
                                }
                            })
                        }
                    }
                )
            } catch (t: Throwable) {
                Log.e(TAG, "loadLinks ${api.name}: ${t.javaClass.simpleName}: ${t.message}")
            }
            Log.i(TAG, "loadLinks ${api.name}: ${collected.size} source(s), ${subs.length()} sub(s)")
        }
        // Best first. Extractors call back in whatever order they finish, so the
        // default source used to be a race: a 360p mirror that resolved quickly
        // won over a 1080p one that took a moment longer. CloudStream's own
        // player orders by quality for the same reason. The sort is stable, so
        // sources of equal quality keep the order the provider produced them in.
        collected.sortByDescending { it.first }
        val videoSources = JSONArray()
        collected.forEachIndexed { i, entry ->
            entry.second.put("isDefault", i == 0)
            videoSources.put(entry.second)
        }
        // Shape matches MediaResolveModel.fromJson (videoUrl/type/headers + videoSources + subtitles).
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
