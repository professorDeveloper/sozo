package com.soplay.sozo.manga

import com.soplay.sozo.ExtensionFailure

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.soplay.sozo.aniyomi.AniyomiRuntime
import dalvik.system.DexClassLoader
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Loads Mihon/Tachiyomi MANGA extension APKs at runtime and exposes their
 * [CatalogueSource]s. Structurally identical to [AniyomiRuntime] but keyed on the
 * manga metadata class (`tachiyomi.extension.class`) and the manga `source` tree.
 *
 * The Injekt singletons (NetworkHelper / JavaScriptEngine / Json / Application) are
 * shared with the anime runtime — manga and anime extensions link against the same
 * `eu.kanade.tachiyomi.network` layer — so we delegate bootstrap to [AniyomiRuntime].
 */
object MangaRuntime {

    private const val TAG = "MangaRuntime"
    private const val METADATA_SOURCE_CLASS = "tachiyomi.extension.class"

    // ConcurrentHashMap so the hot path below can read without holding the lock.
    // A plain HashMap here was also a correctness bug, not just a speed one:
    // callers read it concurrently with loadApk() writing to it.
    private val sourceCache = ConcurrentHashMap<String, CatalogueSource>()
    private val loadedApks = HashSet<String>()

    /** Last load/instantiate failure reason, surfaced to the UI for diagnosis. */
    @Volatile
    var lastError: String? = null
        private set

    /**
     * Forgets the given sources so the next lookup re-loads them from disk.
     *
     * Used after an extension update. The old apk's [DexClassLoader] cannot be
     * unloaded, but the replacement lands at a new path (its filename carries the
     * version), so it gets a fresh loader — this just stops the stale instances
     * from shadowing it.
     */
    fun evictSources(sourceIds: List<String>, apkPaths: List<String> = emptyList()) {
        synchronized(this) {
            sourceIds.forEach { sourceCache.remove(it) }
            loadedApks.removeAll(apkPaths.toSet())
            lastError = null
        }
    }

    /**
     * Returns the [CatalogueSource] whose id matches [sourceId], loading the APK once
     * and caching every source it declares. Returns null when the apk can't be
     * parsed/loaded or has no matching source.
     */
    fun source(context: Context, apkPath: String, pkg: String, sourceId: String): CatalogueSource? {
        // Fast path: already loaded by someone. Safe without the lock because the
        // map is concurrent and an entry is only ever published fully-built.
        sourceCache[sourceId]?.let { return it }
        // Shared Injekt singletons (NetworkHelper, JavaScriptEngine, Json, Application).
        AniyomiRuntime.bootstrap(context)

        // Everything below is inside the lock, including the final read.
        //
        // It used to check `loadedApks` before taking the lock and return early.
        // That was a race with a very visible symptom: the flag is set BEFORE the
        // dex load (deliberately, so a broken apk isn't retried forever), so a
        // second thread arriving mid-load saw "already loaded", read the
        // still-empty cache, and reported the source as unavailable — while the
        // first thread went on to load it successfully. MangaHost issues
        // getPopular and getLatest concurrently, so this fired constantly and
        // presented as "manga loads sometimes".
        //
        // Now a concurrent caller simply blocks until the load finishes and then
        // reads a populated cache.
        synchronized(this) {
            if (!loadedApks.contains(apkPath)) {
                // Mark loaded BEFORE attempting: a failure (bad apk, link error) must not
                // retry on every home reload.
                loadedApks.add(apkPath)
                try {
                    loadApk(context, apkPath, pkg)
                } catch (t: Throwable) {
                    lastError = "loadApk: ${t.javaClass.simpleName}: ${t.message}"
                    // Pass the throwable so the full stack + `Caused by:` chain is
                    // logged (the exact missing/changed symbol) — not just message.
                    Log.e(TAG, "loadApk failed for $apkPath", t)
                }
            }
            return sourceCache[sourceId]
        }
    }

    private fun loadApk(context: Context, apkPath: String, pkg: String) {
        val pm = context.packageManager
        val info = pm.getPackageArchiveInfo(apkPath, PackageManager.GET_META_DATA) ?: run {
            Log.e(TAG, "getPackageArchiveInfo null: $apkPath"); return
        }
        val appInfo = info.applicationInfo ?: return
        val classList = appInfo.metaData?.getString(METADATA_SOURCE_CLASS) ?: run {
            Log.e(TAG, "no $METADATA_SOURCE_CLASS metadata"); return
        }
        // Android (API 26+) refuses to DexClassLoad a writable file (W^X). The apk lives
        // in our writable filesDir, so mark it read-only before loading.
        try { File(apkPath).setReadOnly() } catch (_: Throwable) {}
        val optimizedDir = File(context.codeCacheDir, "manga_dex").apply { mkdirs() }
        val loader = DexClassLoader(apkPath, optimizedDir.absolutePath, null, javaClass.classLoader)

        for (raw in classList.split(";").map { it.trim() }.filter { it.isNotEmpty() }) {
            val className = if (raw.startsWith(".")) pkg + raw else raw
            val instance = try {
                val clazz = loader.loadClass(className)
                clazz.getDeclaredConstructor().newInstance()
            } catch (t: Throwable) {
                lastError = "instantiate $className: ${ExtensionFailure.describe(t)}"
                Log.e(TAG, "instantiate $className failed", t)
                continue
            }
            val sources = when (instance) {
                is SourceFactory -> try {
                    instance.createSources()
                } catch (t: Throwable) {
                    // A factory that throws here took every source in the apk with
                    // it. Previously this propagated out of loadApk and was
                    // reported as a generic apk failure, hiding which factory
                    // actually broke.
                    lastError = "createSources $className: ${t.javaClass.simpleName}: ${t.message}"
                    Log.e(TAG, "createSources $className failed", t)
                    continue
                }
                is Source -> listOf(instance)
                else -> {
                    // Used to be a silent `emptyList()`: an entry class that is
                    // neither shape vanished with no log and no lastError, which
                    // is indistinguishable from "the source has no content".
                    lastError = "unsupported entry class $className: ${instance.javaClass.name}"
                    Log.e(TAG, "unsupported entry class $className -> ${instance.javaClass.name}")
                    emptyList()
                }
            }
            val catalogues = sources.filterIsInstance<CatalogueSource>()
            if (catalogues.isEmpty() && sources.isNotEmpty()) {
                Log.w(TAG, "$className produced ${sources.size} source(s), none CatalogueSource")
            }
            catalogues.forEach { sourceCache[it.id.toString()] = it }
        }
    }
}
