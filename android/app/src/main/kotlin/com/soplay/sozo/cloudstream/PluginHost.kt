package com.soplay.sozo.cloudstream

import android.content.Context
import android.content.res.AssetManager
import android.content.res.Resources
import android.util.Log
import com.soplay.sozo.ExtensionDns
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.CloudStreamApp
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
import kotlinx.coroutines.launch
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

    init {
        // CloudStream plugins call `app`, the library's own HTTP client, which
        // we do not build and cannot hand a Dns to. Reflection is the only way
        // in, and it is worth taking: without it the DNS setting would apply to
        // Aniyomi and Manga sources and silently not to CloudStream ones, with
        // nothing on screen to say which half it covered.
        applyDnsToLibraryClient()
    }

    /**
     * Points the library's shared client at [ExtensionDns].
     *
     * Best effort by design: the field is an implementation detail of a version
     * we pin but do not own. A failure here costs the setting on cs: sources
     * and nothing else, so it is logged rather than thrown.
     */
    private fun applyDnsToLibraryClient() {
        try {
            val appField = Class.forName("com.lagradost.cloudstream3.MainActivityKt")
                .getDeclaredMethod("getApp")
            val requests = appField.invoke(null) ?: return
            val clientField = requests.javaClass.methods
                .firstOrNull { it.name == "getBaseClient" && it.parameterTypes.isEmpty() }
                ?: return
            val client = clientField.invoke(requests) as? okhttp3.OkHttpClient ?: return
            val setter = requests.javaClass.methods.firstOrNull {
                it.name == "setBaseClient" && it.parameterTypes.size == 1
            } ?: return
            setter.invoke(requests, client.newBuilder().dns(ExtensionDns.dns).build())
            Log.i(TAG, "dns resolver applied to the library client")
        } catch (t: Throwable) {
            Log.w(TAG, "could not apply the dns resolver to the library client: ${t.javaClass.simpleName}")
        }
    }

    companion object {
        private const val TAG = "CloudStreamHost"

        // CloudStream's Qualities.Unknown: "no quality given", not 400 lines.
        private const val UNKNOWN_QUALITY = 400

        private const val LINK_CACHE_MS = 20 * 60 * 1000L
        private const val LINK_CACHE_ENTRIES = 40
        private const val GOOD_LINK_GRACE_MS = 2500L
        private const val ANY_LINK_GRACE_MS = 6000L
        private const val WAIT_CAP_MS = 90_000L
        private const val COLLECT_CAP_MS = 120_000L
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
        /** From the repo's plugin list: the plugin is typed NSFW there. */
        val nsfw: Boolean = false,
    )
    private val metas = LinkedHashMap<String, Meta>()

    /** Register provider metadata WITHOUT loading the plugin (startup path). */
    private val animeProviders = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    /** Records whether [provider] comes from an anime plugin (see RepoManager.isAnime). */
    fun markAnime(provider: String, anime: Boolean) {
        if (provider.isEmpty()) return
        if (anime) animeProviders.add(provider) else animeProviders.remove(provider)
    }

    fun registerMeta(
        provider: String, icon: String?, internalName: String,
        cs3Path: String, repo: String? = null, lang: String = "", nsfw: Boolean = false,
    ) {
        metas[provider] = Meta(provider, icon, internalName, cs3Path, repo, lang, nsfw)
        if (!icon.isNullOrEmpty()) providerIcons[provider] = icon
    }

    /** Ensure the plugin backing a provider is loaded (lazy, on first use). */
    private fun ensurePluginLoaded(provider: String) {
        val m = metas[provider] ?: return
        if (loaded.containsKey(m.internalName)) return
        val f = File(m.cs3Path)
        if (f.exists()) loadCs3(f, m.internalName, m.icon, m.repo, m.lang, m.nsfw)
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
        repo: String? = null, lang: String = "", nsfw: Boolean = false,
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
            // The resumed Activity when there is one, not the Application.
            //
            // Upstream hands Plugin.load() an Activity, and four plugins cast
            // it straight to AppCompatActivity to put up a settings dialog —
            // Aniworld, Jellyfin, MovieBox and ShowBox all died on
            // "android.app.Application cannot be cast to AppCompatActivity"
            // before they had registered anything. Loading is lazy and happens
            // on first use, so an Activity is normally resumed; the Application
            // stays as the fallback rather than refusing to load at all.
            val host = CloudStreamApp.currentActivity ?: appContext
            if (instance is Plugin) instance.load(host) else instance.load()
            loaded[internalName] = instance
            // So a plugin walking PluginManager.getPluginsOnline() to find its
            // own .cs3 — the usual reason to call it — gets a real answer.
            CsPluginManager.record(internalName, file.absolutePath)

            val added = APIHolder.allProviders.map { it.name }.filter { it !in before }
            pluginProviders[internalName] = added
            added.forEach { metas[it] = Meta(it, iconUrl, internalName, file.absolutePath, repo, lang, nsfw) }
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

    /** Installed here — known from its repo or already loaded — without loading it. */
    fun has(name: String): Boolean {
        val n = name.removePrefix("cs:")
        return metas.containsKey(n) ||
            APIHolder.allProviders.any { it.name == n }
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
                // The server keys CloudStream health by plugin, not by MainAPI name.
                put("internalName", m.internalName)
                // The other three hosts have always sent this; CloudStream was
                // the one that did not, so its providers arrived in the picker
                // with no language at all and could not be filtered.
                if (m.lang.isNotEmpty()) put("lang", m.lang)
                m.icon?.let { put("icon", it) }
                m.repo?.let { if (it.isNotEmpty()) put("repo", it) }
                // So the 18+ setting covers CloudStream as it does the others.
                if (m.nsfw) put("nsfw", true)
                // An anime plugin says so, like the Sozo anime sources do, so
                // the app treats its titles as anime: AniList tracking, the
                // airing card.
                if (animeProviders.contains(m.provider)) put("category", "anime")
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
        var sectionError: String? =
            if (api == null) (lastError(providerName) ?: "provider not loaded: $providerName")
            else null
        if (api != null) {
            val mp = api.mainPage.firstOrNull { it.data == data }
            val name = mp?.name ?: data
            try {
                val resp = api.getMainPage(page, MainPageRequest(name, data, false))
                if (resp != null) {
                    for (list in resp.items) for (sr in list.list) items.put(cardJson(sr, api.name))
                }
            } catch (t: Throwable) {
                if (sectionError == null) {
                    sectionError = "${t.javaClass.simpleName}: ${t.message}"
                }
                Log.e(TAG, "getMainPage ${api.name}", t)
            }
        }
        return JSONObject().apply {
            put("provider", providerName)
            put("items", items)
            // Otherwise "View all" on a plugin that threw looks exactly like a
            // section that genuinely has nothing in it.
            if (items.length() == 0) {
                sectionError?.let { put("error", "${api?.name ?: providerName}: $it") }
            }
            put("page", page)
            put("totalPages", if (items.length() > 0) page + 1 else page)
        }.toString()
    }

    suspend fun searchJson(providerName: String, query: String, page: Int = 1): String {
        val api = apiByName(providerName)
        val items = JSONArray()
        // CloudStream's MainAPI.search(query) has no paging — return the full
        // result set on page 1 only; never advertise further pages.
        var searchError: String? = null
        if (api != null && page == 1) {
            val results = try { api.search(query) } catch (t: Throwable) {
                searchError = "${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "search ${api.name}: ${t.javaClass.simpleName}: ${t.message}"); null
            } ?: emptyList()
            for (r in results) items.put(cardJson(r, api.name))
        }
        return JSONObject().apply {
            put("provider", providerName); put("items", items)
            // Same reasoning as getMainPageJson above: without this, a plugin
            // that threw is indistinguishable from a source that genuinely has
            // nothing matching the query — so the screen said "no results" and
            // offered spelling suggestions for a source that never ran.
            if (items.length() == 0) {
                searchError?.let { put("error", "${api?.name ?: providerName}: $it") }
            }
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
        // "{}" is what the app reads as "source unavailable". A plugin built
        // against a CloudStream older or newer than ours fails here with a
        // NoSuchMethodError that NAMES the missing member, and that was the one
        // string capable of explaining a dead provider — thrown away on every
        // detail open. lastErrors has been recorded since plugins loaded and
        // was never read by anything.
        val api = apiByName(providerName) ?: run {
            Log.e(TAG, "load: provider '$providerName' not found")
            return JSONObject()
                .put("error", lastError(providerName) ?: "provider not loaded: $providerName")
                .toString()
        }
        val failure: String
        val resp = try {
            failure = ""
            api.load(url)
        } catch (t: Throwable) {
            Log.e(TAG, "load ${api.name}", t)
            return JSONObject()
                .put("error", "${api.name}: ${t.javaClass.simpleName}: ${t.message ?: "failed"}")
                .toString()
        } ?: return JSONObject()
            .put("error", "${api.name}: details not found")
            .toString()
        @Suppress("UNUSED_EXPRESSION") failure
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
                // `episodes` is keyed by DubStatus. Taking the first key meant
                // taking whichever one the map happened to iterate first — for a
                // dual-audio title that could be a two-entry Dub list standing in
                // for a full Sub run, with the rest of the season simply absent.
                // The longest list is the one that represents the season.
                val list = resp.episodes.values.maxByOrNull { it.size } ?: emptyList()
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
                    ?: "${api.name}: no playable entry for this title (${resp.javaClass.simpleName})")
            }
        }.toString()
    }

    /** The library's shared client, the one plugins' own requests go through. */
    private fun libraryClient(): okhttp3.OkHttpClient? = try {
        val requests = Class.forName("com.lagradost.cloudstream3.MainActivityKt")
            .getDeclaredMethod("getApp").invoke(null)
        requests?.javaClass?.methods
            ?.firstOrNull { it.name == "getBaseClient" && it.parameterTypes.isEmpty() }
            ?.invoke(requests) as? okhttp3.OkHttpClient
    } catch (_: Throwable) {
        null
    }

    /**
     * One episode's links, gathered as the plugin produces them.
     *
     * Extractors call back as they finish, and a plugin that tries a WebView
     * sniff last can take a minute to return. Waiting for the whole call is
     * what made CloudStream episodes sit on a spinner long after a playable
     * link had arrived — CloudStream's own player starts on the first good link
     * and keeps collecting. So the collection runs on its own, and the call
     * that asked for it returns as soon as there is something worth playing.
     */
    private class LinkCollection(val startedAt: Long) {
        val sources = ArrayList<Pair<Int, JSONObject>>()
        val subs = ArrayList<com.lagradost.cloudstream3.SubtitleFile>()
        val seenUrls = HashSet<String>()
        val seenSubs = HashSet<String>()
        var firstLinkAt = 0L
        var bestRank = -1
        var interceptorToken: String? = null
        @Volatile var done = false
        @Volatile var error: String? = null
    }

    private val linkScope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO,
    )
    private val linkCollections = LinkedHashMap<String, LinkCollection>()

    // AudioFile is @Prerelease in the CloudStream library; the annotation is an
    // IDE hint with BINARY retention, so reading the list a plugin may have filled
    // costs nothing at runtime and is empty for every plugin that sets none.
    @OptIn(com.lagradost.cloudstream3.Prerelease::class)
    suspend fun loadLinksJson(providerName: String, data: String): String {
        val api = apiByName(providerName)
            ?: return JSONObject().apply {
                put("videoSources", JSONArray())
                put("subtitles", JSONArray())
                put("error", "$providerName: " +
                    (lastError(providerName) ?: "provider not loaded: $providerName"))
            }.toString()

        // Reopening an episode, a retry, the next visit within twenty minutes:
        // the links are already known, as CloudStream's own player keeps them.
        val key = "${api.name}\u0000$data"
        val now = System.currentTimeMillis()
        val collection = synchronized(linkCollections) {
            linkCollections[key]?.takeIf {
                now - it.startedAt < LINK_CACHE_MS && (!it.done || it.sources.isNotEmpty())
            } ?: LinkCollection(now).also {
                linkCollections[key] = it
                while (linkCollections.size > LINK_CACHE_ENTRIES) {
                    linkCollections.remove(linkCollections.keys.first())
                }
                startCollecting(api, data, it)
            }
        }

        // Wait for the first good link rather than for the last extractor:
        // once a high or adaptive link is in, a short grace lets a better one
        // that is about to land win; a lesser one gets a little longer; and the
        // whole wait is bounded, because a plugin that never returns used to
        // leave the player on a spinner for good.
        while (true) {
            val (done, count, firstAt, best) = synchronized(collection) {
                listOf(
                    if (collection.done) 1L else 0L,
                    collection.sources.size.toLong(),
                    collection.firstLinkAt,
                    collection.bestRank.toLong(),
                )
            }
            if (done == 1L) break
            val t = System.currentTimeMillis()
            if (count > 0) {
                val since = t - firstAt
                if (best >= 1000 && since >= GOOD_LINK_GRACE_MS) break
                if (since >= ANY_LINK_GRACE_MS) break
            }
            if (t - collection.startedAt >= WAIT_CAP_MS) break
            kotlinx.coroutines.delay(150)
        }
        return buildLinksJson(api, collection)
    }

    @OptIn(com.lagradost.cloudstream3.Prerelease::class)
    private fun startCollecting(api: MainAPI, data: String, c: LinkCollection) {
        linkScope.launch {
            try {
                kotlinx.coroutines.withTimeoutOrNull(COLLECT_CAP_MS) {
                    api.loadLinks(
                        data = data,
                        isCasting = false,
                        subtitleCallback = { sf ->
                            synchronized(c) {
                                if (sf.url.isNotEmpty() && c.seenSubs.add(sf.url)) c.subs.add(sf)
                            }
                        },
                        callback = { link -> collectLink(api, link, c) },
                    )
                } ?: run { c.error = "timed out after ${COLLECT_CAP_MS / 1000}s" }
            } catch (t: Throwable) {
                c.error = "${t.javaClass.simpleName}: ${t.message ?: "failed"}"
                Log.e(TAG, "loadLinks ${api.name}", t)
            } finally {
                c.done = true
                // With the elapsed time, because the two ways of getting zero
                // look identical in a log and nothing like each other in cause:
                // a fast empty answer is a title with no mirrors, and a
                // sixty-second one is WebViewResolver polling out its timeout.
                Log.i(
                    TAG,
                    "loadLinks ${api.name}: ${c.sources.size} source(s), " +
                        "${c.subs.size} sub(s) in ${System.currentTimeMillis() - c.startedAt}ms",
                )
            }
        }
    }

    @OptIn(com.lagradost.cloudstream3.Prerelease::class)
    private fun collectLink(api: MainAPI, link: ExtractorLink, c: LinkCollection) {
        // Torrents and magnets are passed through tagged as "torrent": the app
        // embeds a torrent server and the player turns such a link into a local
        // HTTP stream (see core/torrent/ and player_page.media.dart).
        //
        // Relative urls ("dl.php?id=…") are still dropped — ExoPlayer resolves
        // those as a local file path. So is a multi-part ExtractorLinkPlayList,
        // whose url is empty: its parts are separate files the player cannot
        // join, and offering only the first part would stop mid-film.
        val isTorrent = link.type == ExtractorLinkType.TORRENT ||
            link.type == ExtractorLinkType.MAGNET
        val addressable = link.url.startsWith("http", ignoreCase = true) ||
            (isTorrent && link.url.startsWith("magnet:", ignoreCase = true))
        if (!addressable) return
        synchronized(c) { if (!c.seenUrls.add(link.url)) return }

        // getAllHeaders() folds in the referer exactly the way CloudStream's
        // own player does. The User-Agent it falls back to is the library's,
        // not ours: the extractor fetched the page, and often a signed URL,
        // under that agent, and a CDN that binds its token to the agent 403s
        // the stream when the player presents a different one.
        val headers = LinkedHashMap(link.getAllHeaders())
        if (headers.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
            headers["User-Agent"] = com.lagradost.cloudstream3.USER_AGENT
        }

        // A plugin that needs to touch every request — cookies on segments,
        // decrypting subtitles — says so through getVideoInterceptor, and the
        // stream then plays through [CsStreamProxy], which applies it.
        var videoUrl = link.url
        var proxied = false
        if (!isTorrent) {
            val interceptor = try { api.getVideoInterceptor(link) } catch (_: Throwable) { null }
            val base = if (interceptor != null) libraryClient() else null
            if (interceptor != null && base != null) {
                val token = CsStreamProxy.register(base, interceptor, headers)
                val url = token?.let { CsStreamProxy.urlFor(it, link.url) }
                if (token != null && url != null) {
                    videoUrl = url
                    proxied = true
                    synchronized(c) { if (c.interceptorToken == null) c.interceptorToken = token }
                }
            }
        }

        // quality is a resolution int (e.g. 1080) or a Qualities sentinel.
        // Qualities.Unknown is 400, and it is what every link built without a
        // quality carries — most HLS masters. Read as a resolution it labelled
        // them "400p" and sorted an adaptive stream below a 480p file.
        val q = link.quality
        val known = q in 144..4320 && q != UNKNOWN_QUALITY
        val res = when {
            !known -> null
            q >= 2160 -> "4K"
            else -> "${q}p"
        }
        val nm = link.name.ifBlank { "Source" }
        val label = if (res != null) "$nm · $res" else nm
        val path = link.url.substringBefore('?').lowercase()
        val type = when {
            link.type == ExtractorLinkType.M3U8 -> "hls"
            link.type == ExtractorLinkType.DASH -> "dash"
            isTorrent -> "torrent"
            // An old-style link built without a type still says what it is.
            path.endsWith(".m3u8") -> "hls"
            path.endsWith(".mpd") -> "dash"
            else -> "http"
        }
        // An adaptive master of unknown height usually tops out at 1080p:
        // ahead of a fixed 720p file, behind a stated 1080p.
        val rank = when {
            known -> q
            type == "hls" || type == "dash" -> 1000
            else -> 0
        }

        val json = JSONObject().apply {
            put("quality", label)
            put("videoUrl", videoUrl)
            put("type", type)
            put("host", link.name)
            put("accessible", true)
            // The proxy sends the plugin's headers itself.
            put("headers", if (proxied) JSONObject() else JSONObject(headers as Map<*, *>))
            if (proxied) put("useLocalProxy", false)
            drmJson(link, headers)?.let { put("drm", it) }
            // Separate audio renditions the extractor says belong with this
            // video; a dual-audio release puts its dub here rather than in the
            // manifest.
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
        }
        synchronized(c) {
            c.sources.add(rank to json)
            if (c.firstLinkAt == 0L) c.firstLinkAt = System.currentTimeMillis()
            if (rank > c.bestRank) c.bestRank = rank
        }
    }

    /**
     * A DrmExtractorLink in the shape the player's DrmConfig reads.
     *
     * The player already plays ClearKey and Widevine channels; CloudStream
     * links that carried their keys were handed over as plain streams and
     * decoded to a black screen. ClearKey material arrives as base64url, the
     * EME form, and the player takes hex, which is how keys are published.
     */
    @OptIn(kotlin.uuid.ExperimentalUuidApi::class)
    private fun drmJson(link: ExtractorLink, headers: Map<String, String>): JSONObject? {
        val drm = link as? com.lagradost.cloudstream3.utils.DrmExtractorLink ?: return null
        val scheme = when (drm.uuid.toString().lowercase()) {
            "e2719d58-a985-b3c9-781a-b030af78d30e", "1077efec-c0b2-4d02-ace3-3c1e52e2fb4b" -> "clearkey"
            "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed" -> "widevine"
            "9a04f079-9840-4286-ab92-e65be0885f95" -> "playready"
            else -> return null
        }
        return JSONObject().apply {
            put("scheme", scheme)
            put("licenseUrl", drm.licenseUrl ?: "")
            put("licenseHeaders", JSONObject(headers as Map<*, *>))
            if (scheme == "clearkey") {
                val kid = drm.kid?.let(::b64UrlToHex)
                val k = drm.key?.let(::b64UrlToHex)
                if (kid != null && k != null) put("clearKeys", JSONObject().apply { put(kid, k) })
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun htmlText(s: String): String =
        if (android.os.Build.VERSION.SDK_INT >= 24) {
            android.text.Html.fromHtml(s, android.text.Html.FROM_HTML_MODE_LEGACY).toString()
        } else {
            android.text.Html.fromHtml(s).toString()
        }

    private fun b64UrlToHex(value: String): String? {
        val v = value.trim()
        if (v.matches(Regex("^[0-9a-fA-F]{32}$"))) return v.lowercase()
        return try {
            android.util.Base64.decode(
                v, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP,
            ).joinToString("") { "%02x".format(it) }
        } catch (_: Throwable) {
            null
        }
    }

    private fun buildLinksJson(api: MainAPI, c: LinkCollection): String {
        val (sources, subsSnapshot, token, done, error) = synchronized(c) {
            listOf(ArrayList(c.sources), ArrayList(c.subs), c.interceptorToken, c.done, c.error)
        }
        @Suppress("UNCHECKED_CAST")
        val collected = sources as ArrayList<Pair<Int, JSONObject>>
        @Suppress("UNCHECKED_CAST")
        val subFiles = subsSnapshot as ArrayList<com.lagradost.cloudstream3.SubtitleFile>

        // Best first. Extractors call back in whatever order they finish, so
        // the default used to be a race: a 360p mirror that resolved quickly
        // won over a 1080p one that took a moment longer. The sort is stable,
        // so sources of equal quality keep the provider's order.
        collected.sortByDescending { it.first }
        val videoSources = JSONArray()
        collected.forEachIndexed { i, entry ->
            // Copied: the same collection answers a later call too, and the
            // default flag must not stick to whatever was first last time.
            val o = JSONObject(entry.second.toString())
            o.put("isDefault", i == 0)
            videoSources.put(o)
        }

        val subs = JSONArray()
        val nameCounts = HashMap<String, Int>()
        for (sf in subFiles) {
            // "English" twice is two tracks the viewer cannot tell apart; the
            // names also arrive HTML-escaped from some sites.
            val base = htmlText(sf.lang).trim().ifEmpty { "Subtitle" }
            val n = (nameCounts[base] ?: 0) + 1
            nameCounts[base] = n
            val subHeaders = LinkedHashMap(sf.headers ?: emptyMap())
            if (subHeaders.isNotEmpty() && subHeaders.keys.none { it.equals("User-Agent", true) }) {
                subHeaders["User-Agent"] = com.lagradost.cloudstream3.USER_AGENT
            }
            // A plugin's interceptor covers its subtitles too — KissKH decrypts
            // its .txt captions there.
            val proxiedUrl = (token as String?)?.let { CsStreamProxy.urlFor(it, sf.url) }
            subs.put(JSONObject().apply {
                put("label", if (n == 1) base else "$base $n")
                put("file", proxiedUrl ?: sf.url)
                put("default", false)
                // A subtitle is fetched on its own, so it inherits none of the
                // stream's headers; plenty of sources 403 a track without the
                // Referer the extractor set.
                if (proxiedUrl == null && subHeaders.isNotEmpty()) {
                    put("headers", JSONObject(subHeaders as Map<*, *>))
                }
            })
        }

        val first = if (videoSources.length() > 0) videoSources.getJSONObject(0) else null
        // Shape matches MediaResolveModel.fromJson.
        return JSONObject().apply {
            put("videoUrl", first?.optString("videoUrl"))
            put("type", first?.optString("type"))
            put("headers", first?.optJSONObject("headers") ?: JSONObject())
            put("videoSources", videoSources)
            put("subtitles", subs)
            if (done != true) put("partial", true)
            // A plugin that threw and a title with no mirrors both produced an
            // empty list, so "this provider is broken" reached the player as
            // "no sources for this episode".
            if (videoSources.length() == 0) {
                put("error", "${api.name}: " +
                    ((error as String?) ?: "the provider returned no mirrors for this episode"))
            }
        }.toString()
    }
}
