package com.soplay.sozo

import android.Manifest
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.media.AudioManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.network.CloudflareKiller
import com.soplay.sozo.cloudstream.PluginHost
import com.soplay.sozo.cloudstream.RepoManager
import com.soplay.sozo.aniyomi.AniyomiHost
import com.soplay.sozo.aniyomi.AniyomiRepoManager
import com.soplay.sozo.manga.MangaHost
import com.soplay.sozo.manga.MangaRepoManager
import com.soplay.sozo.extensions.RepoFileIntent
import com.soplay.sozo.preview.FramePreview
import com.soplay.sozo.torrent.TorrentServerBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterFragmentActivity() {

    private val channelName = "soplay/pip"
    private val platformChannelName = "soplay/platform"
    private val downloadChannelName = "soplay/downloads"

    // Its own scope rather than borrowing the CloudStream one: exporting a
    // download is a multi-gigabyte byte copy, and sharing a scope with the
    // plugin host would mean cancelling one cancels the other.
    private val downloadScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val systemControlsChannelName = "soplay/system_controls"
    private val deeplinkSettingsChannelName = "soplay/deeplink_settings"
    private val actionBroadcastName = "com.soplay.sozo.PIP_ACTION"
    private val actionExtraId = "action_id"

    private var methodChannel: MethodChannel? = null
    private var platformChannel: MethodChannel? = null
    private var downloadChannel: MethodChannel? = null
    private var systemControlsChannel: MethodChannel? = null
    private var deeplinkSettingsChannel: MethodChannel? = null
    private var pipReceiver: BroadcastReceiver? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    // CloudStream plugin host (Android-only feature). Lazy so the runtime only
    // spins up if the feature is used.
    private val cloudstreamChannelName = "soplay/cloudstream"
    private var cloudstreamChannel: MethodChannel? = null
    private var previewChannel: MethodChannel? = null
    private val cloudstreamScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val pluginHost by lazy {
        // CloudflareKiller is constructed by plugins with no arguments, so it
        // can only get a Context from here. Installed alongside the host that
        // loads those plugins, which guarantees it happens before any of them
        // can run. Without it the killer degrades to a passthrough.
        CloudflareKiller.install(applicationContext)
        // NiceHttp — the HTTP layer inside the CloudStream library — reads
        // CloudStreamApp.context on the first request a plugin makes. Unset, it
        // throws NoClassDefFoundError on an OkHttp worker thread, which nothing
        // catches, and the process dies.
        CloudStreamApp.install(applicationContext)
        PluginHost(applicationContext)
    }
    private val repoManager by lazy { RepoManager(applicationContext, pluginHost) }

    private val aniyomiChannelName = "soplay/aniyomi"
    private var aniyomiChannel: MethodChannel? = null
    private val aniyomiHost by lazy { AniyomiHost(applicationContext) }
    private val aniyomiRepoManager by lazy { AniyomiRepoManager(applicationContext, aniyomiHost) }

    private val mangaChannelName = "soplay/manga"
    private var mangaChannel: MethodChannel? = null
    private val mangaHost by lazy { MangaHost(applicationContext) }
    private val mangaRepoManager by lazy { MangaRepoManager(applicationContext, mangaHost) }

    // Local HTTP bridge so a desktop soplay client on the same Wi-Fi can reach
    // the extension hosts. Opt-in via the soplay/bridge channel. See BridgeServer.
    private val bridgeChannelName = "soplay/bridge"
    private var bridgeChannel: MethodChannel? = null
    private val bridgePort = 8765
    private var bridgeServer: BridgeServer? = null

    // "Open with Sozo" on an extension index file (index.pb / index.min.json /
    // repo.json). Held until Dart asks for it — on a cold start the engine isn't
    // attached when the intent arrives.
    private val repoFileChannelName = "soplay/repo_file"
    private var repoFileChannel: MethodChannel? = null

    /// Owns the ExoPlayer instances that play encrypted streams. Held so the
    /// engine going away releases them — an ExoPlayer that outlives its texture
    /// keeps a decoder and a DRM session open, which on some devices is a
    /// hardware resource the next playback cannot get.
    private var drmPlayerHost: com.soplay.sozo.drm.DrmPlayerHost? = null
    @Volatile private var pendingRepoFile: String? = null

    companion object {
        const val ACTION_PLAY_PAUSE = "play_pause"
        const val ACTION_REWIND = "rewind"
        const val ACTION_FORWARD = "forward"
        const val ACTION_PREV = "prev"
        const val ACTION_NEXT = "next"

        const val REQ_PLAY_PAUSE = 1
        const val REQ_REWIND = 2
        const val REQ_FORWARD = 3
        const val REQ_PREV = 4
        const val REQ_NEXT = 5
        const val REQ_NOTIFICATIONS = 42
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updatePiPActions" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val hasPrev = call.argument<Boolean>("hasPrev") ?: false
                    val hasNext = call.argument<Boolean>("hasNext") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        applyPipActions(isPlaying, hasPrev, hasNext)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            platformChannelName
        )
        platformChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> result.success(isLeanbackDevice())
                "openExternalVideo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val title = call.argument<String>("title").orEmpty()
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    result.success(openExternalVideo(url, title, headers))
                }
                else -> result.notImplemented()
            }
        }

        downloadChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadChannelName
        )
        downloadChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "startDownload" -> {
                    val id = call.argument<String>("id").orEmpty()
                    val title = call.argument<String>("title").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    val localPath = call.argument<String>("localPath").orEmpty()
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val kind = call.argument<String>("kind").orEmpty().ifBlank { "video" }
                    val pageUrls = call.argument<List<String>>("pageUrls") ?: emptyList()
                    val isManga = kind == "manga"
                    // Manga has no single url; require the destination folder + page urls instead.
                    val missingArgs = if (isManga) {
                        id.isEmpty() || localPath.isEmpty() || pageUrls.isEmpty()
                    } else {
                        id.isEmpty() || url.isEmpty() || localPath.isEmpty()
                    }
                    if (missingArgs) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, DownloadForegroundService::class.java)
                        .setAction(DownloadForegroundService.ACTION_START)
                        .putExtra(DownloadForegroundService.EXTRA_ID, id)
                        .putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                        .putExtra(DownloadForegroundService.EXTRA_URL, url)
                        .putExtra(DownloadForegroundService.EXTRA_LOCAL_PATH, localPath)
                        .putExtra(DownloadForegroundService.EXTRA_KIND, kind)
                        .putExtra(
                            DownloadForegroundService.EXTRA_WIFI_ONLY,
                            call.argument<Boolean>("wifiOnly") ?: false
                        )
                        .putExtra(
                            DownloadForegroundService.EXTRA_PAGE_URLS_JSON,
                            JSONArray(pageUrls).toString()
                        )
                        .putExtra(
                            DownloadForegroundService.EXTRA_HEADERS_JSON,
                            JSONObject(headers).toString()
                        )
                    // Android 12+ throws when a foreground service is started
                    // from the background. Reported as `false` rather than left
                    // to crash: the queue can then record why nothing happened,
                    // instead of a download that silently never starts.
                    val started = try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        true
                    } catch (e: Exception) {
                        false
                    }
                    result.success(started)
                }
                "getDownloadStates" -> {
                    result.success(DownloadForegroundService.readStates(this))
                }
                // Free bytes on the volume the downloads live on.
                //
                // Dart has no portable API for this, and starting a two-gigabyte
                // download onto a phone with 40 MB left breaks far more than
                // this feature. `getUsableSpace` is what the app may actually
                // write, which is not the same as the partition's free space on
                // a device with a storage quota.
                "freeSpaceBytes" -> {
                    val dir = filesDir ?: cacheDir
                    result.success(dir?.usableSpace ?: 0L)
                }
                "cancelDownload" -> {
                    val id = call.argument<String>("id").orEmpty()
                    startService(
                        Intent(this, DownloadForegroundService::class.java)
                            .setAction(DownloadForegroundService.ACTION_CANCEL)
                            .putExtra(DownloadForegroundService.EXTRA_ID, id)
                    )
                    result.success(null)
                }
                "pauseDownload" -> {
                    val id = call.argument<String>("id").orEmpty()
                    startService(
                        Intent(this, DownloadForegroundService::class.java)
                            .setAction(DownloadForegroundService.ACTION_PAUSE)
                            .putExtra(DownloadForegroundService.EXTRA_ID, id)
                    )
                    result.success(null)
                }
                // Copies a finished download into the shared Downloads folder,
                // where a file manager, a USB cable or another player can
                // actually reach it. Off the main thread: this is a byte copy
                // of a file that is routinely several gigabytes, and doing it
                // on the UI thread would freeze the app for the duration.
                "exportToDownloads" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val name = call.argument<String>("name").orEmpty()
                    downloadScope.launch {
                        val outcome = runCatching {
                            DownloadExporter.exportToDownloads(applicationContext, path, name)
                        }
                        withContext(Dispatchers.Main) {
                            outcome
                                .onSuccess { result.success(it) }
                                .onFailure {
                                    result.error(
                                        "export_failed",
                                        it.message ?: "Could not save to Downloads",
                                        null
                                    )
                                }
                        }
                    }
                }
                "removeDownloadState" -> {
                    val id = call.argument<String>("id").orEmpty()
                    DownloadForegroundService.removeState(this, id)
                    result.success(null)
                }
                "cancelAllDownloads" -> {
                    startService(
                        Intent(this, DownloadForegroundService::class.java)
                            .setAction(DownloadForegroundService.ACTION_CANCEL_ALL)
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        systemControlsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            systemControlsChannelName
        )
        systemControlsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getVolume" -> result.success(getMusicVolume())
                "setVolume" -> {
                    val value = call.argument<Number>("value")?.toDouble() ?: 1.0
                    setMusicVolume(value)
                    result.success(getMusicVolume())
                }
                "getBrightness" -> result.success(getWindowBrightness())
                "setBrightness" -> {
                    val value = call.argument<Number>("value")?.toDouble() ?: 0.5
                    setWindowBrightness(value)
                    result.success(getWindowBrightness())
                }
                "resetBrightness" -> {
                    resetWindowBrightness()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        deeplinkSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deeplinkSettingsChannelName
        )
        deeplinkSettingsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openDefaultLinksSettings" -> {
                    result.success(openDefaultLinksSettings())
                }
                else -> result.notImplemented()
            }
        }

        cloudstreamChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            cloudstreamChannelName
        )
        cloudstreamChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "listProviders" -> csAsync(result) { pluginHost.providersJson() }
                "ensureLoaded" -> csAsync(result) {
                    repoManager.ensureLoaded(); pluginHost.providersJson()
                }
                "listRepos" -> csAsync(result) { repoManager.listReposJson() }
                "removeRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { repoManager.removeRepo(url) }
                }
                "addRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) {
                        repoManager.addRepo(url) { current, total ->
                            // Push live "N / M installed" to the Flutter install UI.
                            runOnUiThread {
                                cloudstreamChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "listRepoPlugins" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { repoManager.listRepoPluginsJson(url) }
                }
                "installPlugin" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val internalName = call.argument<String>("internalName").orEmpty()
                    csAsync(result) {
                        repoManager.installPlugin(url, internalName) { current, total ->
                            runOnUiThread {
                                cloudstreamChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "uninstallPlugin" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val internalName = call.argument<String>("internalName").orEmpty()
                    csAsync(result) { repoManager.uninstallPlugin(url, internalName).toString() }
                }
                "checkUpdates" -> {
                    csAsync(result) {
                        repoManager.checkUpdates { current, total ->
                            runOnUiThread {
                                cloudstreamChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "getMainPage" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { pluginHost.getMainPageJson(provider, page) }
                }
                "getGenres" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    csAsync(result) { pluginHost.getGenresJson(provider) }
                }
                "getSection" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { pluginHost.getSectionJson(provider, data, page) }
                }
                "search" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val query = call.argument<String>("query").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { pluginHost.searchJson(provider, query, page) }
                }
                "load" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { pluginHost.loadJson(provider, url) }
                }
                "loadLinks" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    csAsync(result) { pluginHost.loadLinksJson(provider, data) }
                }
                "cloudflareInfo" -> {
                    val id = call.argument<String>("id").orEmpty()
                    csAsync(result) { pluginHost.cloudflareInfo(id) }
                }
                else -> result.notImplemented()
            }
        }

        aniyomiChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            aniyomiChannelName
        )
        aniyomiChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "listProviders" -> csAsync(result) { aniyomiHost.providersJson(call.langs()) }
                "ensureLoaded" -> csAsync(result) {
                    aniyomiRepoManager.ensureLoaded(); aniyomiHost.providersJson(call.langs())
                }
                "listRepos" -> csAsync(result) { aniyomiRepoManager.listReposJson() }
                "removeRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { aniyomiRepoManager.removeRepo(url) }
                }
                "addRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) {
                        aniyomiRepoManager.addRepo(url) { current, total ->
                            runOnUiThread {
                                aniyomiChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "addRepoFile" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val name = call.argument<String>("name").orEmpty()
                    csAsync(result) {
                        aniyomiRepoManager.addRepoFile(path, name) { current, total ->
                            runOnUiThread {
                                aniyomiChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "checkUpdates" -> {
                    csAsync(result) {
                        aniyomiRepoManager.checkUpdates { current, total ->
                            runOnUiThread {
                                aniyomiChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "getMainPage" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { aniyomiHost.getMainPageJson(provider, page) }
                }
                "getSection" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { aniyomiHost.getSectionJson(provider, data, page) }
                }
                "getGenres" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    csAsync(result) { aniyomiHost.getGenresJson(provider) }
                }
                "search" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val query = call.argument<String>("query").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { aniyomiHost.searchJson(provider, query, page) }
                }
                "load" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { aniyomiHost.loadJson(provider, url) }
                }
                "loadLinks" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    csAsync(result) { aniyomiHost.loadLinksJson(provider, data) }
                }
                "cloudflareInfo" -> {
                    val id = call.argument<String>("id").orEmpty()
                    csAsync(result) { aniyomiHost.cloudflareInfo(id) }
                }
                else -> result.notImplemented()
            }
        }

        mangaChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mangaChannelName
        )
        mangaChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "listProviders" -> csAsync(result) { mangaHost.providersJson(call.langs()) }
                "ensureLoaded" -> csAsync(result) {
                    mangaRepoManager.ensureLoaded(); mangaHost.providersJson(call.langs())
                }
                "listRepos" -> csAsync(result) { mangaRepoManager.listReposJson() }
                "removeRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { mangaRepoManager.removeRepo(url) }
                }
                "addRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) {
                        mangaRepoManager.addRepo(url) { current, total ->
                            runOnUiThread {
                                mangaChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "addRepoFile" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val name = call.argument<String>("name").orEmpty()
                    csAsync(result) {
                        mangaRepoManager.addRepoFile(path, name) { current, total ->
                            runOnUiThread {
                                mangaChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "checkUpdates" -> {
                    csAsync(result) {
                        mangaRepoManager.checkUpdates { current, total ->
                            runOnUiThread {
                                mangaChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "getMainPage" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { mangaHost.getMainPageJson(provider, page) }
                }
                "getSection" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { mangaHost.getSectionJson(provider, data, page) }
                }
                "getGenres" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    csAsync(result) { mangaHost.getGenresJson(provider) }
                }
                "search" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val query = call.argument<String>("query").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { mangaHost.searchJson(provider, query, page) }
                }
                "load" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { mangaHost.loadJson(provider, url) }
                }
                "pageList" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    csAsync(result) { mangaHost.pageListJson(provider, data) }
                }
                "getPreferences" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    csAsync(result) { mangaHost.getPrefsJson(provider) }
                }
                "setPreference" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val key = call.argument<String>("key").orEmpty()
                    val type = call.argument<String>("type").orEmpty()
                    val value = call.argument<Any>("value")
                    csAsync(result) { mangaHost.setPrefJson(provider, key, value, type) }
                }
                "cloudflareInfo" -> {
                    val id = call.argument<String>("id").orEmpty()
                    csAsync(result) { mangaHost.cloudflareInfo(id) }
                }
                else -> result.notImplemented()
            }
        }

        repoFileChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            repoFileChannelName,
        )
        repoFileChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // Consume-once: the dialog must not reappear on every resume.
                "takePending" -> {
                    val pending = pendingRepoFile
                    pendingRepoFile = null
                    result.success(pending)
                }
                else -> result.notImplemented()
            }
        }

        drmPlayerHost = com.soplay.sozo.drm.DrmPlayerHost(
            applicationContext,
            flutterEngine.renderer,
            flutterEngine.dartExecutor.binaryMessenger,
        )

        previewChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soplay/preview",
        )
        previewChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val warmMs = (call.argument<Number>("warmMs") ?: -1).toLong()
                    cloudstreamScope.launch {
                        FramePreview.open(url, headers, warmMs)
                        withContext(Dispatchers.Main) { result.success(true) }
                    }
                }
                "frame" -> {
                    val posMs = (call.argument<Number>("posMs") ?: 0).toLong()
                    cloudstreamScope.launch {
                        val bytes = FramePreview.frame(posMs)
                        withContext(Dispatchers.Main) { result.success(bytes) }
                    }
                }
                // Off the platform thread like open/frame: close() can contend with a
                // still-running open(), and blocking here would freeze the whole UI.
                "close" -> {
                    cloudstreamScope.launch {
                        FramePreview.close()
                        withContext(Dispatchers.Main) { result.success(true) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        setupBridgeChannel(flutterEngine)
        // Restart the bridge if the user had "share sources to desktop" on.
        if (bridgePrefs().getBoolean("enabled", false)) startBridgeServer()
    }

    /** True on Android TV / Google TV / Fire TV, false on phones and tablets.
     *
     *  All three checks are OR'd on purpose: Fire TV has historically not
     *  reported UI_MODE_TYPE_TELEVISION, and some cheap TV boxes ship without
     *  FEATURE_LEANBACK while still declaring the leanback software feature.
     *  Anything that throws falls through to false, i.e. the phone path. */
    private fun isLeanbackDevice(): Boolean = try {
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature("android.software.leanback")
    } catch (_: Throwable) {
        false
    }

    /**
     * Hands a stream to whatever video app the user picks (VLC, MX Player, …).
     *
     * Returns false when nothing on the device can handle it, so Dart can show
     * a real message instead of the user staring at an unchanged screen.
     *
     * Headers are best-effort only. MX Player reads a "headers" String[] extra
     * (alternating key/value); VLC has no such contract and ignores it. Callers
     * must not assume a gated stream survives this trip — ExternalPlayer
     * warns up front instead.
     */
    private fun openExternalVideo(
        url: String,
        title: String,
        headers: Map<String, String>
    ): Boolean {
        if (url.isBlank()) return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(url), "video/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                if (title.isNotBlank()) putExtra("title", title)
                if (headers.isNotEmpty()) {
                    val flat = ArrayList<String>(headers.size * 2)
                    headers.forEach { (k, v) -> flat.add(k); flat.add(v) }
                    putExtra("headers", flat.toTypedArray())
                }
            }
            val chooser = Intent.createChooser(intent, title.ifBlank { "Play with" })
            if (intent.resolveActivity(packageManager) == null) return false
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun bridgePrefs() = getSharedPreferences("sozo_bridge", Context.MODE_PRIVATE)

    /** Control channel for the desktop-sharing bridge: enable/disable + status
     *  (the shareable `http://<lan-ip>:8765` link). */
    private fun setupBridgeChannel(flutterEngine: FlutterEngine) {
        bridgeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, bridgeChannelName)
        bridgeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(bridgeStatus())
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    bridgePrefs().edit().putBoolean("enabled", enabled).apply()
                    if (enabled) startBridgeServer() else stopBridgeServer()
                    result.success(bridgeStatus())
                }
                "getSharedProviders" -> result.success(sharedProvidersConfig())
                "setSharedProviders" -> {
                    val shareAll = call.argument<Boolean>("shareAll") ?: true
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    bridgePrefs().edit()
                        .putBoolean("share_all", shareAll)
                        .putStringSet("shared_ids", ids.toSet())
                        .apply()
                    result.success(sharedProvidersConfig())
                }
                else -> result.notImplemented()
            }
        }

        // Embedded TorrServer. Registers its own channel rather than adding
        // another handler here — the native side is only "load Go, bind a
        // port"; adding torrents and reading their state is plain HTTP from
        // Dart. See torrent/TorrentServerBridge.kt.
        TorrentServerBridge.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    /** Current share selection: `{shareAll, ids}`. `shareAll` (default true) means
     *  every provider is exposed; otherwise only the ids in the set are served. */
    private fun sharedProvidersConfig(): Map<String, Any?> {
        val prefs = bridgePrefs()
        return mapOf(
            "shareAll" to prefs.getBoolean("share_all", true),
            "ids" to (prefs.getStringSet("shared_ids", emptySet()) ?: emptySet()).toList(),
        )
    }

    /** The allow-list the [BridgeServer] filters by, or null when sharing all. */
    private fun sharedIdsOrNull(): Set<String>? {
        val prefs = bridgePrefs()
        if (prefs.getBoolean("share_all", true)) return null
        return (prefs.getStringSet("shared_ids", emptySet()) ?: emptySet()).toSet()
    }

    private fun bridgeStatus(): Map<String, Any?> {
        val running = bridgeServer != null
        val ip = localIpAddress()
        return mapOf(
            "enabled" to running,
            "port" to bridgePort,
            "ip" to ip,
            "link" to if (running && ip != null) "http://$ip:$bridgePort" else null,
        )
    }

    /** Start the local HTTP bridge so a same-Wi-Fi desktop client can reach the
     *  extension hosts on `http://<lan-ip>:8765`. */
    private fun startBridgeServer() {
        if (bridgeServer != null) return
        try {
            val server = BridgeServer(
                bridgePort,
                { pluginHost }, { repoManager },
                { aniyomiHost }, { aniyomiRepoManager },
                { mangaHost }, { mangaRepoManager },
                { sharedIdsOrNull() },
            )
            server.start()
            bridgeServer = server
        } catch (_: Throwable) {
        }
    }

    private fun stopBridgeServer() {
        try { bridgeServer?.stop() } catch (_: Throwable) {}
        bridgeServer = null
    }

    /** First site-local IPv4 (the Wi-Fi LAN address) for the shareable link. */
    private fun localIpAddress(): String? {
        try {
            val ifaces = java.net.NetworkInterface.getNetworkInterfaces()
            for (iface in ifaces) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.inetAddresses) {
                    if (addr.isLoopbackAddress) continue
                    if (addr is java.net.Inet4Address && addr.isSiteLocalAddress) {
                        return addr.hostAddress
                    }
                }
            }
        } catch (_: Throwable) {
        }
        return null
    }

    /** Run a suspend CloudStream call off the main thread, return JSON to Flutter. */
    private fun csAsync(result: MethodChannel.Result, block: suspend () -> String) {
        cloudstreamScope.launch {
            val out = try { block() } catch (t: Throwable) { null }
            withContext(Dispatchers.Main) {
                if (out != null) result.success(out)
                else result.error("cs_error", "CloudStream call failed", null)
            }
        }
    }

    private fun openDefaultLinksSettings(): Boolean {
        val pkgUri = Uri.parse("package:$packageName")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val intent = Intent(
                    Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
                    pkgUri
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return try {
            val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                pkgUri
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(fallback)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun getMusicVolume(): Double {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        return current.toDouble() / max.toDouble()
    }

    private fun setMusicVolume(value: Double) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val level = (value.coerceIn(0.0, 1.0) * max).roundToInt().coerceIn(0, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
    }

    private fun getWindowBrightness(): Double {
        val windowValue = window.attributes.screenBrightness
        if (windowValue >= 0f) return windowValue.toDouble().coerceIn(0.0, 1.0)
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                .toDouble()
                .div(255.0)
                .coerceIn(0.0, 1.0)
        } catch (_: Exception) {
            0.5
        }
    }

    private fun setWindowBrightness(value: Double) {
        runOnUiThread {
            val attrs = window.attributes
            attrs.screenBrightness = value.coerceIn(0.01, 1.0).toFloat()
            window.attributes = attrs
        }
    }

    private fun resetWindowBrightness() {
        runOnUiThread {
            val attrs = window.attributes
            attrs.screenBrightness = -1f
            window.attributes = attrs
        }
    }

    /**
     * The volumes downloads may be kept on, as JSON.
     *
     * `getExternalFilesDirs` returns the app's own directory on every mounted
     * volume: index 0 is the built-in "external" storage (which on a modern
     * phone is the same physical chip as internal), and anything after it is a
     * real SD card. Both are writable with no permission at all and are wiped
     * on uninstall, which is the correct lifetime for an offline library.
     *
     * `filesDir` is listed first and marked as the default: it is the only one
     * that can never be unmounted, and it is where every existing install
     * already keeps its downloads.
     */
    private fun describeVolumes(): String {
        val out = org.json.JSONArray()
        val seen = HashSet<String>()

        fun add(dir: java.io.File?, id: String, label: String, removable: Boolean, isDefault: Boolean) {
            if (dir == null) return
            if (!dir.exists() && !dir.mkdirs()) return
            if (!seen.add(dir.absolutePath)) return
            out.put(
                org.json.JSONObject()
                    .put("id", id)
                    .put("path", dir.absolutePath)
                    .put("label", label)
                    .put("freeBytes", dir.usableSpace)
                    .put("totalBytes", dir.totalSpace)
                    .put("removable", removable)
                    .put("isDefault", isDefault)
            )
        }

        add(filesDir, "app", "internal", removable = false, isDefault = true)

        val external = getExternalFilesDirs(null)
        for ((index, dir) in external.withIndex()) {
            if (dir == null) continue
            val removable = try {
                android.os.Environment.isExternalStorageRemovable(dir)
            } catch (_: Exception) {
                index > 0
            }
            add(
                dir,
                if (index == 0) "external" else "sdcard_$index",
                if (removable) "sdcard" else "external",
                removable = removable,
                isDefault = false
            )
        }
        return out.toString()
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.success(false)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_NOTIFICATIONS
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun applyPipActions(
        isPlaying: Boolean,
        hasPrev: Boolean,
        hasNext: Boolean
    ) {
        val actions = mutableListOf<RemoteAction>()

        if (hasPrev) {
            actions.add(
                makeAction(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    "Previous episode",
                    ACTION_PREV,
                    REQ_PREV
                )
            )
        }
        actions.add(
            makeAction(
                android.R.drawable.ic_media_rew,
                "Rewind 10",
                "Rewind 10 seconds",
                ACTION_REWIND,
                REQ_REWIND
            )
        )
        actions.add(
            makeAction(
                if (isPlaying)
                    android.R.drawable.ic_media_pause
                else
                    android.R.drawable.ic_media_play,
                if (isPlaying) "Pause" else "Play",
                if (isPlaying) "Pause" else "Play",
                ACTION_PLAY_PAUSE,
                REQ_PLAY_PAUSE
            )
        )
        actions.add(
            makeAction(
                android.R.drawable.ic_media_ff,
                "Forward 10",
                "Forward 10 seconds",
                ACTION_FORWARD,
                REQ_FORWARD
            )
        )
        if (hasNext) {
            actions.add(
                makeAction(
                    android.R.drawable.ic_media_next,
                    "Next",
                    "Next episode",
                    ACTION_NEXT,
                    REQ_NEXT
                )
            )
        }

        val params = PictureInPictureParams.Builder()
            .setActions(actions)
            .build()

        try {
            setPictureInPictureParams(params)
        } catch (_: Exception) {
            // Activity may not be in a state to receive PiP params yet
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun makeAction(
        iconRes: Int,
        title: String,
        contentDesc: String,
        actionId: String,
        requestCode: Int
    ): RemoteAction {
        val intent = Intent(actionBroadcastName)
            .setPackage(packageName)
            .putExtra(actionExtraId, actionId)
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            else
                PendingIntent.FLAG_UPDATE_CURRENT
        val pending = PendingIntent.getBroadcast(this, requestCode, intent, flags)
        val icon = Icon.createWithResource(this, iconRes)
        return RemoteAction(icon, title, contentDesc, pending)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerPipReceiver()
        // Cold start via "Open with Sozo". Parked rather than pushed: the Flutter
        // side isn't listening yet, so it pulls this on first frame.
        pendingRepoFile = RepoFileIntent.extract(applicationContext, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop, so a second "Open with Sozo" while running lands here.
        setIntent(intent)
        RepoFileIntent.extract(applicationContext, intent)?.let { payload ->
            pendingRepoFile = payload
            repoFileChannel?.invokeMethod("openRepoFile", payload)
        }
    }

    private fun registerPipReceiver() {
        if (pipReceiver != null) return
        pipReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != actionBroadcastName) return
                val actionId = intent.getStringExtra(actionExtraId) ?: return
                methodChannel?.invokeMethod("onPipAction", actionId)
            }
        }
        val filter = IntentFilter(actionBroadcastName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // The torrent server itself is deliberately left running: the Go fork
        // exists because its shutdown paths crash the process, and the activity
        // being destroyed does not mean playback is over (PiP, rotation).
        // Only the channel is detached.
        TorrentServerBridge.dispose()
        // Unlike the torrent server, these must go: a decoder and a DRM session
        // left open outlive the texture they were drawing into, and on devices
        // with one secure decoder that is the next playback failing to start.
        drmPlayerHost?.dispose()
        drmPlayerHost = null
        try { bridgeServer?.stop() } catch (_: Throwable) {}
        bridgeServer = null
        pipReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
            pipReceiver = null
        }
    }

    /**
     * The picker's language row, as the call carried it.
     *
     * Passed per call rather than stored on the Android side: it lives in Hive
     * and changes from a chip tap, and a second copy in SharedPreferences is a
     * second thing to keep in sync for no benefit. An absent or empty list is
     * the no-preference default and collapses exactly as this always did.
     */
    private fun MethodCall.langs(): List<String> =
        argument<List<*>>("languages")?.mapNotNull { it?.toString() } ?: emptyList()
}
