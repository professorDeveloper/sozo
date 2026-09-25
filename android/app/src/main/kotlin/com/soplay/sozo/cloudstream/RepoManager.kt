package com.soplay.sozo.cloudstream

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloads CloudStream repos and feeds the `.cs3` files to [PluginHost].
 *
 * Accepts:
 *   - a direct `repo.json` URL  ( {name, pluginLists:[plugins.json url, ...]} )
 *   - a direct `plugins.json` URL ( [ {name, internalName, url(.cs3), version, ...} ] )
 *   - a CloudStream shortcode (resolved via l.cloudstream.app → repo url)
 *
 * `.cs3` files are cached under filesDir/cs3/<internalName>@<version>.cs3 so a
 * version bump re-downloads. This is the Android-only feature backing the
 * `soplay/cloudstream` MethodChannel. Runtime testing happens on device.
 */
class RepoManager(private val context: Context, private val host: PluginHost) {

    companion object {
        private const val TAG = "CloudStreamRepo"
        private const val UA =
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
    }

    private val cs3Dir: File = File(context.filesDir, "cs3").apply { mkdirs() }
    private val prefs = context.getSharedPreferences("cloudstream", Context.MODE_PRIVATE)
    @Volatile private var ensured = false

    private fun savedRepos(): MutableList<String> {
        val raw = prefs.getString("repos", "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw); MutableList(arr.length()) { arr.getString(it) }
        } catch (_: Throwable) { mutableListOf() }
    }

    private fun persist(repos: List<String>) {
        prefs.edit().putString("repos", JSONArray(repos).toString()).apply()
    }

    // Persisted provider metadata per repo: { repoInput: [{provider,icon,internalName,cs3Path,lang}] }
    private fun loadMeta(): JSONObject =
        try { JSONObject(prefs.getString("meta", "{}") ?: "{}") } catch (_: Throwable) { JSONObject() }

    private fun saveMeta(o: JSONObject) {
        prefs.edit().putString("meta", o.toString()).apply()
    }

    /**
     * Make saved repos' providers available — WITHOUT loading every .cs3.
     * We only register cached metadata (name/icon/path); each plugin is loaded
     * lazily on first use. Falls back to a full load for repos saved before
     * metadata existed.
     */
    // Synchronized: a source call that arrives first (a widget or notification
    // tap, before the source list has loaded) now loads it too, and a second
    // caller must wait for the registry rather than see `ensured` early.
    @Synchronized
    fun ensureLoaded() {
        if (ensured) return
        ensured = true
        val meta = loadMeta()
        val names = loadNames()
        for (repo in savedRepos()) {
            val repoName = names.optString(repo).ifEmpty { fallbackName(repo) }
            val entries = meta.optJSONArray(repo)
            if (entries == null) {
                // Legacy repo without metadata → load once (also persists metadata).
                try { addRepoInternal(repo) } catch (t: Throwable) { Log.e(TAG, "ensureLoaded $repo: ${t.message}") }
                continue
            }
            for (i in 0 until entries.length()) {
                val e = entries.optJSONObject(i) ?: continue
                host.registerMeta(
                    e.optString("provider"),
                    e.optString("icon").ifEmpty { null },
                    e.optString("internalName"),
                    e.optString("cs3Path"),
                    repoName,
                    // Absent for repos installed before the field existed. They
                    // pick it up on the next repo update rather than being
                    // force-reinstalled: a missing language filters nothing out
                    // (see langMatches), so the cost of waiting is zero.
                    e.optString("lang"),
                    e.optBoolean("nsfw", false),
                )
                host.markAnime(e.optString("provider"), e.optBoolean("anime", false))
            }
        }
    }

    /**
     * Which plugins are installed from which repo: `{repoUrl: [internalName]}`.
     * Read from saved metadata, no network — a backup takes it so a restore can
     * reinstall exactly these rather than every plugin each repo offers.
     */
    fun installedPluginsJson(): String {
        val meta = loadMeta()
        val out = JSONObject()
        for (repo in savedRepos()) {
            val names = LinkedHashSet<String>()
            meta.optJSONArray(repo)?.let { arr ->
                for (i in 0 until arr.length()) {
                    val n = arr.optJSONObject(i)?.optString("internalName").orEmpty()
                    if (n.isNotEmpty()) names.add(n)
                }
            }
            out.put(repo, JSONArray(names.toList()))
        }
        return out.toString()
    }

    fun listReposJson(): String {
        val names = loadNames()
        val arr = JSONArray()
        for (r in savedRepos()) {
            arr.put(JSONObject().apply {
                put("url", r)
                put("name", names.optString(r).ifEmpty { fallbackName(r) })
            })
        }
        return arr.toString()
    }

    fun removeRepo(input: String): String {
        val key = input.trim()
        val meta = loadMeta()
        val entries = meta.optJSONArray(key)
        if (entries != null) {
            val providers = (0 until entries.length())
                .mapNotNull { entries.optJSONObject(it)?.optString("provider") }
                .filter { it.isNotEmpty() }
            host.removeProviders(providers)
            meta.remove(key); saveMeta(meta)
        }
        // Delete the .cs3 files as well, not just the bookkeeping.
        //
        // removeRepo only cleared prefs, so "remove the repo and add it again" —
        // the remedy the load failure itself suggests — re-read the very same
        // file off disk and failed the same way.
        if (entries != null) {
            for (i in 0 until entries.length()) {
                val stem = entries.optJSONObject(i)?.optString("internalName")
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { safeFileStem(it) }
                    ?: continue
                cs3Dir.listFiles()?.forEach { f ->
                    if (f.name.startsWith("$stem@")) f.delete()
                }
            }
        }
        val names = loadNames(); names.remove(key); saveNames(names)
        val repos = savedRepos()
        repos.remove(key)
        persist(repos)
        return JSONObject().apply { put("repos", JSONArray(repos)) }.toString()
    }

    private fun httpGet(url: String): String? = try {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"; instanceFollowRedirects = true
            connectTimeout = 20000; readTimeout = 30000
            setRequestProperty("User-Agent", UA)
        }
        val code = conn.responseCode
        if (code in 200..299) conn.inputStream.bufferedReader().use { it.readText() }
        else { Log.e(TAG, "GET $url -> $code"); null }
    } catch (t: Throwable) { Log.e(TAG, "GET $url failed: ${t.message}"); null }

    private data class RepoInfo(val name: String?, val pluginListUrls: List<String>)

    /** repo.json {name, pluginLists:[...]} OR a direct plugins.json array. */
    private fun fetchRepo(repoUrl: String): RepoInfo {
        val body = httpGet(repoUrl) ?: return RepoInfo(null, emptyList())
        val trimmed = body.trimStart()
        if (trimmed.startsWith("[")) return RepoInfo(null, listOf(repoUrl)) // direct plugins.json
        return try {
            val o = JSONObject(body)
            val name = o.optString("name").ifEmpty { null }
            val arr = o.optJSONArray("pluginLists")
            val urls = if (arr != null) (0 until arr.length()).map { arr.getString(it) } else emptyList()
            RepoInfo(name, urls)
        } catch (t: Throwable) { Log.e(TAG, "parse repo.json failed: ${t.message}"); RepoInfo(null, emptyList()) }
    }

    // Persisted display names: { repoInput: "Repo Name" }
    private fun loadNames(): JSONObject =
        try { JSONObject(prefs.getString("names", "{}") ?: "{}") } catch (_: Throwable) { JSONObject() }
    private fun saveNames(o: JSONObject) { prefs.edit().putString("names", o.toString()).apply() }

    /**
     * The on-disk name for a plugin. `internalName` comes from the repo's
     * `plugins.json`, so it is remote input: a value like `../../shared_prefs/x`
     * would otherwise write the download outside `cs3/`. Real plugin names are
     * plain identifiers and come through unchanged, so existing caches still hit.
     */
    private fun safeFileStem(internalName: String): String =
        internalName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trimStart('.')
            .ifEmpty { "plugin" }

    private fun downloadCs3(internalName: String, version: Int, url: String): File? {
        val stem = safeFileStem(internalName)
        val file = File(cs3Dir, "$stem@$version.cs3")
        if (file.exists() && file.length() > 0) return file
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; instanceFollowRedirects = true
                connectTimeout = 20000; readTimeout = 60000
                setRequestProperty("User-Agent", UA)
            }
            if (conn.responseCode !in 200..299) { Log.e(TAG, "cs3 $url -> ${conn.responseCode}"); return null }
            // Downloaded beside the real name, then renamed.
            //
            // Writing straight to the final path meant a download interrupted
            // halfway left a truncated zip there — and the cache check above
            // only asks whether the file exists and is non-empty, so that
            // corrupt file was handed back on every retry from then on. The
            // plugin could never load again, and the advice the failure gives
            // ("remove and add the repo again") does not delete it either.
            val part = File(cs3Dir, "${file.name}.part")
            part.delete()
            conn.inputStream.use { input -> part.outputStream.use { input.copyTo(it) } }
            if (part.length() <= 0L) { part.delete(); return null }
            file.delete()
            if (!part.renameTo(file)) { part.delete(); return null }
            // drop stale versions of the same plugin
            cs3Dir.listFiles()?.forEach { f ->
                if (f.name.startsWith("$stem@") && f.name != file.name) f.delete()
            }
            file
        } catch (t: Throwable) { Log.e(TAG, "download cs3 failed: ${t.message}"); null }
    }

    private val File.outputStream get() = java.io.FileOutputStream(this)

    /**
     * Add a repo (url or shortcode): download all plugins, load them, and return
     * the registered provider names. Synchronous network — call off the main thread.
     */
    fun addRepo(input: String, progress: ((Int, Int) -> Unit)? = null): JSONObject {
        val result = addRepoInternal(input, progress)
        if (result.optInt("pluginCount") > 0) {
            val repos = savedRepos()
            val v = input.trim()
            if (!repos.contains(v)) { repos.add(v); persist(repos) }
        }
        return result
    }

    private fun fallbackName(url: String): String {
        val gh = Regex("github(?:usercontent)?\\.com/([^/]+)/([^/]+)").find(url)
        if (gh != null) return "${gh.groupValues[1]}/${gh.groupValues[2]}"
        return try { java.net.URL(url).host ?: url } catch (_: Throwable) { url }
    }

    private data class PluginRef(
        val url: String, val internalName: String, val version: Int, val iconUrl: String?,
        /** The repo's own `language` tag for this plugin; "" when it omits one. */
        val lang: String = "",
        /** Whether the repo lists the plugin under CloudStream's NSFW type. */
        val nsfw: Boolean = false,
        /** Whether it is an anime source: Anime, AnimeMovie or OVA among its types. */
        val anime: Boolean = false,
    )

    private fun isAnime(p: JSONObject): Boolean {
        val types = p.optJSONArray("tvTypes") ?: return false
        for (i in 0 until types.length()) {
            when (types.optString(i)) { "Anime", "AnimeMovie", "OVA" -> return true }
        }
        return false
    }

    /**
     * Whether a plugins.json entry is adult: CloudStream has no flag of its
     * own for it, only an `NSFW` among the plugin's `tvTypes`. Read from the
     * list rather than the loaded plugin for the language's reason — the
     * provider list is built without loading one.
     */
    private fun isNsfw(p: JSONObject): Boolean {
        val types = p.optJSONArray("tvTypes") ?: return false
        for (i in 0 until types.length()) {
            if (types.optString(i).equals("NSFW", ignoreCase = true)) return true
        }
        return false
    }

    private fun addRepoInternal(input: String, progress: ((Int, Int) -> Unit)? = null): JSONObject {
        val repoUrl = input.trim()
        val info = fetchRepo(repoUrl)
        val providers = JSONArray()
        val metaEntries = JSONArray()
        var pluginCount = 0

        // Gather every plugin descriptor first so the total is known up front and
        // we can report "downloaded N / M" progress to the install UI.
        val all = ArrayList<PluginRef>()
        for (listUrl in info.pluginListUrls) {
            val body = httpGet(listUrl) ?: continue
            val plugins = try { JSONArray(body) } catch (t: Throwable) { continue }
            for (i in 0 until plugins.length()) {
                val p = plugins.optJSONObject(i) ?: continue
                val url = p.optString("url").ifEmpty { continue }
                val internalName = p.optString("internalName").ifEmpty { p.optString("name", "plugin$i") }
                val version = if (p.has("version")) p.optInt("version") else 0
                val iconUrl = p.optString("iconUrl").ifEmpty { null }
                all.add(PluginRef(url, internalName, version, iconUrl, p.optString("language"), isNsfw(p), isAnime(p)))
            }
        }

        val total = all.size
        val repoName = info.name ?: fallbackName(repoUrl)
        progress?.invoke(0, total)
        for ((index, ref) in all.withIndex()) {
            val file = downloadCs3(ref.internalName, ref.version, ref.url)
            if (file != null) {
                pluginCount++
                // Load now to discover provider names (one-time on add); persist
                // metadata so future launches can lazy-load without this cost.
                host.loadCs3(file, ref.internalName, ref.iconUrl, repoName, ref.lang, ref.nsfw).forEach { name ->
                    providers.put(name)
                    host.markAnime(name, ref.anime)
                    metaEntries.put(JSONObject().apply {
                        put("provider", name)
                        if (ref.iconUrl != null) put("icon", ref.iconUrl)
                        put("internalName", ref.internalName)
                        put("cs3Path", file.absolutePath)
                        if (ref.lang.isNotEmpty()) put("lang", ref.lang)
                        if (ref.nsfw) put("nsfw", true)
                        if (ref.anime) put("anime", true)
                    })
                }
            }
            progress?.invoke(index + 1, total)
        }
        // Persist this repo's provider metadata for lazy loading on next launch.
        val meta = loadMeta(); meta.put(input.trim(), metaEntries); saveMeta(meta)
        // Persist a friendly display name (from repo.json, else derived from url).
        if (pluginCount > 0) {
            val names = loadNames(); names.put(input.trim(), info.name ?: fallbackName(repoUrl)); saveNames(names)
        }
        Log.i(TAG, "addRepo($repoUrl): $pluginCount plugins, providers=$providers")
        return JSONObject().apply {
            put("repo", repoUrl); put("pluginCount", pluginCount); put("providers", providers)
        }
    }

    /**
     * List every plugin advertised by a repo WITHOUT downloading anything, each
     * flagged with whether it is currently installed. Lets the user pick only the
     * plugins they want instead of installing the whole repo. Network — off-main.
     */
    fun listRepoPluginsJson(input: String): String {
        val repoUrl = input.trim()
        val info = fetchRepo(repoUrl)
        val repoName = info.name ?: fallbackName(repoUrl)
        val installed = HashSet<String>()
        loadMeta().optJSONArray(repoUrl)?.let { arr ->
            for (i in 0 until arr.length()) {
                val n = arr.optJSONObject(i)?.optString("internalName").orEmpty()
                if (n.isNotEmpty()) installed.add(n)
            }
        }
        val out = JSONArray()
        val seen = HashSet<String>()
        for (listUrl in info.pluginListUrls) {
            val body = httpGet(listUrl) ?: continue
            val plugins = try { JSONArray(body) } catch (_: Throwable) { continue }
            for (i in 0 until plugins.length()) {
                val p = plugins.optJSONObject(i) ?: continue
                if (p.optString("url").isEmpty()) continue
                val internalName =
                    p.optString("internalName").ifEmpty { p.optString("name", "plugin$i") }
                if (!seen.add(internalName)) continue
                out.put(JSONObject().apply {
                    put("internalName", internalName)
                    put("name", p.optString("name").ifEmpty { internalName })
                    put("version", if (p.has("version")) p.optInt("version") else 0)
                    put("iconUrl", p.optString("iconUrl"))
                    put("description", p.optString("description"))
                    put("language", p.optString("language"))
                    put("tvTypes", p.optJSONArray("tvTypes") ?: JSONArray())
                    put("installed", installed.contains(internalName))
                })
            }
        }
        return JSONObject().apply {
            put("repo", repoUrl)
            put("name", repoName)
            put("plugins", out)
        }.toString()
    }

    /** Install a single plugin from a repo by its internalName. Saves the repo and
     *  merges the plugin's providers into metadata. Network — call off-main. */
    fun installPlugin(
        input: String,
        internalName: String,
        progress: ((Int, Int) -> Unit)? = null,
    ): JSONObject {
        val repoUrl = input.trim()
        val info = fetchRepo(repoUrl)
        val repoName = info.name ?: fallbackName(repoUrl)
        var ref: PluginRef? = null
        for (listUrl in info.pluginListUrls) {
            val body = httpGet(listUrl) ?: continue
            val plugins = try { JSONArray(body) } catch (_: Throwable) { continue }
            for (i in 0 until plugins.length()) {
                val p = plugins.optJSONObject(i) ?: continue
                val url = p.optString("url").ifEmpty { continue }
                val nm = p.optString("internalName").ifEmpty { p.optString("name", "plugin$i") }
                if (nm == internalName) {
                    val version = if (p.has("version")) p.optInt("version") else 0
                    ref = PluginRef(
                        url, nm, version, p.optString("iconUrl").ifEmpty { null },
                        p.optString("language"), isNsfw(p), isAnime(p),
                    )
                    break
                }
            }
            if (ref != null) break
        }
        val r = ref
            ?: return JSONObject().apply { put("pluginCount", 0); put("providers", JSONArray()) }

        progress?.invoke(0, 1)
        val file = downloadCs3(r.internalName, r.version, r.url)
        val providers = JSONArray()
        if (file != null) {
            host.loadCs3(file, r.internalName, r.iconUrl, repoName, r.lang, r.nsfw).forEach {
                providers.put(it)
                host.markAnime(it, r.anime)
            }
            val meta = loadMeta()
            val existing = meta.optJSONArray(repoUrl) ?: JSONArray()
            val merged = JSONArray()
            for (i in 0 until existing.length()) {
                val e = existing.optJSONObject(i) ?: continue
                if (e.optString("internalName") != r.internalName) merged.put(e)
            }
            for (i in 0 until providers.length()) {
                merged.put(JSONObject().apply {
                    put("provider", providers.getString(i))
                    if (r.iconUrl != null) put("icon", r.iconUrl)
                    put("internalName", r.internalName)
                    put("cs3Path", file.absolutePath)
                    if (r.lang.isNotEmpty()) put("lang", r.lang)
                    if (r.nsfw) put("nsfw", true)
                    if (r.anime) put("anime", true)
                })
            }
            meta.put(repoUrl, merged); saveMeta(meta)
            val repos = savedRepos()
            if (!repos.contains(repoUrl)) { repos.add(repoUrl); persist(repos) }
            val names = loadNames(); names.put(repoUrl, repoName); saveNames(names)
        }
        progress?.invoke(1, 1)
        Log.i(TAG, "installPlugin($internalName): providers=$providers")
        return JSONObject().apply {
            put("pluginCount", if (file != null) 1 else 0)
            put("providers", providers)
        }
    }

    /** Uninstall a single plugin (by internalName): drop its providers, delete the
     *  cached .cs3, and prune metadata. Removes the repo entirely if it becomes
     *  empty so it disappears from the installed-sources list. */
    fun uninstallPlugin(input: String, internalName: String): JSONObject {
        val repoUrl = input.trim()
        val meta = loadMeta()
        val entries = meta.optJSONArray(repoUrl) ?: JSONArray()
        val remaining = JSONArray()
        val removed = ArrayList<String>()
        for (i in 0 until entries.length()) {
            val e = entries.optJSONObject(i) ?: continue
            if (e.optString("internalName") == internalName) {
                e.optString("provider").takeIf { it.isNotEmpty() }?.let { removed.add(it) }
            } else {
                remaining.put(e)
            }
        }
        if (removed.isNotEmpty()) host.removeProviders(removed)
        try {
            val stem = safeFileStem(internalName)
            cs3Dir.listFiles()?.forEach { f -> if (f.name.startsWith("$stem@")) f.delete() }
        } catch (_: Throwable) {}

        val repoEmpty = remaining.length() == 0
        if (repoEmpty) {
            meta.remove(repoUrl); saveMeta(meta)
            val names = loadNames(); names.remove(repoUrl); saveNames(names)
            val repos = savedRepos(); repos.remove(repoUrl); persist(repos)
        } else {
            meta.put(repoUrl, remaining); saveMeta(meta)
        }
        Log.i(TAG, "uninstallPlugin($internalName): removed=$removed repoEmpty=$repoEmpty")
        return JSONObject().apply {
            put("ok", true)
            put("removed", JSONArray(removed))
            put("repoEmpty", repoEmpty)
        }
    }

    /**
     * Re-fetch every saved repo and re-download any plugin whose repo version is
     * newer than the installed one (parsed from the cached `@<version>.cs3` name).
     * Updates metadata + reloads the plugin. Returns the updated provider names.
     */
    fun checkUpdates(progress: ((Int, Int) -> Unit)? = null): JSONObject {
        val meta = loadMeta()
        val names = loadNames()
        val updated = JSONArray()
        val repos = savedRepos()
        progress?.invoke(0, repos.size)
        for ((rIndex, repo) in repos.withIndex()) {
            val info = fetchRepo(repo)
            val latest = HashMap<String, PluginRef>()
            for (listUrl in info.pluginListUrls) {
                val body = httpGet(listUrl) ?: continue
                val plugins = try { JSONArray(body) } catch (_: Throwable) { continue }
                for (i in 0 until plugins.length()) {
                    val p = plugins.optJSONObject(i) ?: continue
                    val url = p.optString("url").ifEmpty { continue }
                    val internalName = p.optString("internalName").ifEmpty { p.optString("name", "plugin$i") }
                    val version = if (p.has("version")) p.optInt("version") else 0
                    val iconUrl = p.optString("iconUrl").ifEmpty { null }
                    latest[internalName] = PluginRef(
                        url, internalName, version, iconUrl, p.optString("language"), isNsfw(p), isAnime(p),
                    )
                }
            }
            val repoName = names.optString(repo).ifEmpty { info.name ?: fallbackName(repo) }
            val entries = meta.optJSONArray(repo)
            if (entries != null) {
                val downloaded = HashSet<String>()
                for (i in 0 until entries.length()) {
                    val e = entries.optJSONObject(i) ?: continue
                    val internalName = e.optString("internalName")
                    val ref = latest[internalName] ?: continue
                    // Every check, not only an update: the flag is new, and a
                    // plugin installed before it would otherwise wait for its
                    // next release to be recognised as adult.
                    e.put("nsfw", ref.nsfw)
                    e.put("anime", ref.anime)
                    host.markAnime(e.optString("provider"), ref.anime)
                    val installedVer = e.optString("cs3Path")
                        .substringAfterLast('@', "").substringBefore(".cs3").toIntOrNull() ?: 0
                    if (ref.version <= installedVer) continue
                    val file = if (downloaded.add(internalName)) {
                        downloadCs3(ref.internalName, ref.version, ref.url)
                    } else {
                        File(cs3Dir, "${safeFileStem(ref.internalName)}@${ref.version}.cs3").takeIf { it.exists() }
                    }
                    if (file != null) {
                        e.put("cs3Path", file.absolutePath)
                        // Backfills the language onto repos installed before the
                        // field existed, which is what makes "wait for the next
                        // update" an honest answer in ensureLoaded rather than
                        // "reinstall everything".
                        if (ref.lang.isNotEmpty()) e.put("lang", ref.lang)
                        host.loadCs3(file, ref.internalName, ref.iconUrl, repoName, ref.lang, ref.nsfw)
                        updated.put(e.optString("provider"))
                    }
                }
            }
            progress?.invoke(rIndex + 1, repos.size)
        }
        saveMeta(meta)
        Log.i(TAG, "checkUpdates: ${updated.length()} updated")
        return JSONObject().apply { put("updated", updated); put("count", updated.length()) }
    }
}
