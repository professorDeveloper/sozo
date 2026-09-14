package com.soplay.sozo.manga

import android.content.Context
import android.util.Log
import com.soplay.sozo.extensions.ExtensionIndex
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL

/**
 * Manages manga extension repositories (Mihon/Tachiyomi `index.min.json` or
 * `index.pb` — see [ExtensionIndex]). Mirror of
 * `AniyomiRepoManager`, except every source in the repo is registered — a manga repo is
 * manga-only, so there is no anime/manga name filter to apply. Prefs namespace: "manga".
 */
class MangaRepoManager(private val context: Context, private val host: MangaHost) {

    companion object {
        private const val TAG = "MangaRepo"
    }

    private val prefs = context.getSharedPreferences("manga", Context.MODE_PRIVATE)

    @Volatile private var ensured = false

    init {
        host.refreshMissingApk = { sourceId ->
            synchronized(this) {
                val metadata = loadMeta()
                val repo = savedRepos().firstOrNull { key ->
                    val entries = metadata.optJSONArray(key) ?: JSONArray()
                    !key.startsWith("file:") && (0 until entries.length()).any {
                        entries.optJSONObject(it)?.optString("id") == sourceId
                    }
                }
                if (repo != null) addRepoInternal(repo)
            }
        }
    }

    private fun savedRepos(): MutableList<String> {
        val raw = prefs.getString("repos", "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw); MutableList(arr.length()) { arr.getString(it) }
        } catch (_: Throwable) {
            mutableListOf()
        }
    }

    private fun persist(repos: List<String>) {
        prefs.edit().putString("repos", JSONArray(repos).toString()).apply()
    }

    private fun loadMeta(): JSONObject =
        try { JSONObject(prefs.getString("meta", "{}") ?: "{}") } catch (_: Throwable) { JSONObject() }

    private fun saveMeta(o: JSONObject) {
        prefs.edit().putString("meta", o.toString()).apply()
    }

    private fun loadNames(): JSONObject =
        try { JSONObject(prefs.getString("names", "{}") ?: "{}") } catch (_: Throwable) { JSONObject() }

    private fun saveNames(o: JSONObject) {
        prefs.edit().putString("names", o.toString()).apply()
    }

    @Synchronized
    fun ensureLoaded() {
        if (ensured) return
        ensured = true
        val meta = loadMeta()
        val names = loadNames()
        for (repo in savedRepos()) {
            val repoName = names.optString(repo).ifEmpty { fallbackName(repo) }
            val entries = meta.optJSONArray(repo) ?: continue
            for (i in 0 until entries.length()) {
                val e = entries.optJSONObject(i) ?: continue
                host.registerMeta(e, repoName)
            }
        }
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

    @Synchronized
    fun removeRepo(input: String): String {
        val key = input.trim()
        val meta = loadMeta()
        val entries = meta.optJSONArray(key)
        if (entries != null) {
            val ids = (0 until entries.length())
                .mapNotNull { entries.optJSONObject(it)?.optString("id") }
                .filter { it.isNotEmpty() }
            host.removeSources(ids)
            meta.remove(key); saveMeta(meta)
        }
        val names = loadNames(); names.remove(key); saveNames(names)
        val repos = savedRepos(); repos.remove(key); persist(repos)
        return JSONObject().apply { put("repos", JSONArray(repos)) }.toString()
    }

    @Synchronized
    fun addRepo(input: String, progress: ((Int, Int) -> Unit)? = null): JSONObject {
        val result = addRepoInternal(input, progress)
        if (result.optInt("sourceCount") > 0) {
            val repos = savedRepos()
            val v = input.trim()
            if (!repos.contains(v)) { repos.add(v); persist(repos) }
        }
        return result
    }

    /**
     * Installs an index that was handed to us as a local file ("Open with Sozo").
     *
     * Keyed on a synthetic `file:<name>` id rather than a path: the cache copy is
     * transient, so a real path would break `removeRepo` the moment the cache is
     * cleared, and would also let the same import land twice under two paths.
     */
    @Synchronized
    fun addRepoFile(
        path: String,
        displayName: String,
        progress: ((Int, Int) -> Unit)? = null,
    ): JSONObject {
        val key = "file:" + (displayName.ifEmpty { path.substringAfterLast('/') })
        val packages = ExtensionIndex.parseFile(path)
        val result = install(key, key.removePrefix("file:"), packages, iconBaseFor(""), progress)
        if (result.optInt("sourceCount") > 0) {
            val repos = savedRepos()
            if (!repos.contains(key)) { repos.add(key); persist(repos) }
        }
        return result
    }

    private fun addRepoInternal(input: String, progress: ((Int, Int) -> Unit)? = null): JSONObject {
        val repoUrl = input.trim()
        // Handles both `index.min.json` and the gzipped-protobuf `index.pb` that
        // Keiyoushi / yuzono-manga now publish, and falls back to whichever
        // sibling the repo actually has.
        val packages = ExtensionIndex.fetch(repoUrl)
        return install(repoUrl, fallbackName(repoUrl), packages, iconBaseFor(repoUrl), progress)
    }

    private fun iconBaseFor(repoUrl: String) =
        if (repoUrl.isEmpty()) "" else repoUrl.substringBeforeLast('/')

    /** Registers every source in [packages] under [repoKey]. Shared by url and file installs. */
    private fun install(
        repoKey: String,
        repoName: String,
        packages: JSONArray,
        iconBase: String,
        progress: ((Int, Int) -> Unit)? = null,
    ): JSONObject {
        val repoUrl = repoKey
        val metaEntries = JSONArray()
        val providers = JSONArray()
        var sourceCount = 0

        val total = packages.length()
        progress?.invoke(0, total)
        for (i in 0 until total) {
            val pkg = packages.optJSONObject(i) ?: continue
            val apkName = pkg.optString("apk")
            val pkgName = pkg.optString("pkg")
            val nsfw = pkg.optBoolean("nsfw", false)
            // The protobuf index carries absolute urls; the JSON one only carries
            // a filename, so derive it from the repo base as before.
            val apkRemote = pkg.optString("apkUrl").ifEmpty {
                if (apkName.isEmpty()) "" else apkUrl(repoUrl, apkName)
            }
            val iconRemote = pkg.optString("iconUrl").ifEmpty {
                if (pkgName.isEmpty()) "" else "$iconBase/icon/$pkgName.png"
            }
            val sources = pkg.optJSONArray("sources") ?: JSONArray()
            for (j in 0 until sources.length()) {
                val src = sources.optJSONObject(j) ?: continue
                val name = src.optString("name")
                val entry = JSONObject().apply {
                    put("id", src.optString("id"))
                    put("name", name)
                    put("lang", src.optString("lang"))
                    put("baseUrl", src.optString("baseUrl"))
                    put("pkg", pkgName)
                    put("className", pkg.optString("name"))
                    put("apkUrl", apkRemote)
                    put("fingerprint", pkg.optString("fingerprint"))
                    put("iconUrl", iconRemote)
                    put("nsfw", nsfw)
                }
                metaEntries.put(entry)
                host.registerMeta(entry, repoName)
                providers.put(name)
                sourceCount++
            }
            progress?.invoke(i + 1, total)
        }

        require(sourceCount > 0) { "Repository contains no usable sources; existing sources were kept" }
        val meta = loadMeta(); meta.put(repoKey, metaEntries); saveMeta(meta)
        if (sourceCount > 0) {
            val names = loadNames(); names.put(repoKey, repoName); saveNames(names)
        }
        Log.i(TAG, "addRepo($repoKey): $sourceCount sources")
        return JSONObject().apply {
            put("repo", repoKey); put("sourceCount", sourceCount); put("providers", providers)
        }
    }

    /**
     * Re-fetches every saved repo index and reports which installed extensions
     * have a newer apk upstream — the manga twin of CloudStream's `checkUpdates`.
     *
     * "Newer" is decided by the apk **filename**, which carries the version
     * (`tachiyomi-all.comick-v1.4.211.apk`). Comparing version strings would mean
     * parsing four different upstream conventions; the filename is what the cache
     * is keyed on anyway, so if it changed, the cached apk is stale by definition.
     *
     * Applying an update is just re-registering the metadata with the new url and
     * dropping the stale apk — the new one is fetched lazily on next use, exactly
     * like a first install.
     */
    @Synchronized
    fun checkUpdates(
        apply: Boolean = true,
        progress: ((Int, Int) -> Unit)? = null,
    ): JSONObject {
        val repos = savedRepos()
        val updated = JSONArray()
        val names = loadNames()
        progress?.invoke(0, repos.size)

        repos.forEachIndexed { idx, repo ->
            // A file-imported repo has no upstream to poll.
            if (repo.startsWith("file:")) { progress?.invoke(idx + 1, repos.size); return@forEachIndexed }
            val packages = try {
                ExtensionIndex.fetch(repo)
            } catch (t: Throwable) {
                Log.e(TAG, "checkUpdates fetch $repo: ${t.message}")
                progress?.invoke(idx + 1, repos.size)
                return@forEachIndexed
            }
            if (packages.length() == 0) { progress?.invoke(idx + 1, repos.size); return@forEachIndexed }

            val installedByPkg = HashMap<String, JSONObject>()
            val meta = loadMeta()
            val entries = meta.optJSONArray(repo) ?: JSONArray()
            for (i in 0 until entries.length()) {
                val e = entries.optJSONObject(i) ?: continue
                installedByPkg[e.optString("pkg")] = e
            }

            val iconBase = iconBaseFor(repo)
            for (i in 0 until packages.length()) {
                val pkg = packages.optJSONObject(i) ?: continue
                val pkgName = pkg.optString("pkg")
                val existing = installedByPkg[pkgName]
                val apkRemote = pkg.optString("apkUrl").ifEmpty {
                    val n = pkg.optString("apk")
                    if (n.isEmpty()) "" else apkUrl(repo, n)
                }
                if (apkRemote.isEmpty() || apkRemote == existing?.optString("apkUrl")) continue

                updated.put(JSONObject().apply {
                    put("pkg", pkgName)
                    put("name", pkg.optString("name"))
                    put("version", pkg.optString("version"))
                    put("repo", repo)
                })
                if (apply) {
                    existing?.optString("apkUrl")?.let(host::dropCachedApk)
                    val iconRemote = pkg.optString("iconUrl").ifEmpty {
                        if (pkgName.isEmpty()) "" else "$iconBase/icon/$pkgName.png"
                    }
                    val sources = pkg.optJSONArray("sources") ?: JSONArray()
                    val repoName = names.optString(repo).ifEmpty { fallbackName(repo) }
                    for (j in 0 until sources.length()) {
                        val src = sources.optJSONObject(j) ?: continue
                        val entry = JSONObject().apply {
                            put("id", src.optString("id"))
                            put("name", src.optString("name"))
                            put("lang", src.optString("lang"))
                            put("baseUrl", src.optString("baseUrl"))
                            put("pkg", pkgName)
                            put("className", pkg.optString("name"))
                            put("apkUrl", apkRemote)
                            put("fingerprint", pkg.optString("fingerprint"))
                            put("iconUrl", iconRemote)
                            put("nsfw", pkg.optBoolean("nsfw", false))
                        }
                        host.registerMeta(entry, repoName)
                        // Persist so the new url survives a restart.
                        val oldIndex = (0 until entries.length()).firstOrNull {
                            entries.optJSONObject(it)?.optString("id") == src.optString("id")
                        }
                        if (oldIndex == null) entries.put(entry) else entries.put(oldIndex, entry)
                    }
                    meta.put(repo, entries); saveMeta(meta)
                }
            }
            progress?.invoke(idx + 1, repos.size)
        }

        Log.i(TAG, "checkUpdates: ${updated.length()} extension(s) updated")
        return JSONObject().apply {
            put("updated", updated)
            put("count", updated.length())
        }
    }

    private fun apkUrl(repoUrl: String, apk: String): String {
        val base = repoUrl.substringBeforeLast('/')
        return "$base/apk/$apk"
    }

    private fun fallbackName(url: String): String {
        val gh = Regex("github(?:usercontent)?\\.com/([^/]+)/([^/]+)").find(url)
        if (gh != null) return "${gh.groupValues[1]}/${gh.groupValues[2]}"
        return try { URL(url).host ?: url } catch (_: Throwable) { url }
    }
}
