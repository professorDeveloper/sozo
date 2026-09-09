package com.soplay.sozo.torrent

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import torrServer.TorrServer

/**
 * Runs TorrServer inside the app and tells Dart which port it landed on.
 *
 * ## Why a Go server and not a torrent library
 *
 * The obvious build is a BitTorrent client bound to the player: libtorrent4j
 * or jlibtorrent behind a platform channel, feeding pieces to ExoPlayer. It is
 * also weeks of work, because the hard part is not downloading the torrent —
 * it is serving a *seekable, range-capable HTTP stream* off a swarm that
 * delivers pieces out of order, while the user scrubs.
 *
 * TorrServer already is that. It is the tool the community recommends for
 * torrent streaming on desktop, and `com.github.recloudstream:torrentserver`
 * is it compiled for Android with gomobile — the same artifact CloudStream
 * ships. It exposes a small HTTP API on localhost, so from the app's point of
 * view a magnet becomes an ordinary `http://127.0.0.1:PORT/stream/...` URL that
 * the existing player opens with no changes at all.
 *
 * ## What stays here and what does not
 *
 * This class does the two things that genuinely need native code: loading the
 * Go runtime and starting the server. Everything else — adding a torrent,
 * polling its state, listing its files, dropping it — is plain HTTP against
 * that port, and lives in Dart (`core/torrent/torrent_engine.dart`) where it is
 * far easier to test and to keep in step with the UI.
 *
 * ## Lifetime
 *
 * The server is process-wide and survives Flutter engine restarts, so the port
 * is cached in [runningPort] rather than being started again — starting twice
 * would bind a second port and orphan the first. Nothing here calls
 * `stopTorrentServer()` on a normal exit: the upstream fork exists precisely
 * because Go's `os.Exit` paths crash the app, and stopping is the least-tested
 * of them. Cached data is cleared instead, on the next launch.
 */
object TorrentServerBridge {

    private const val TAG = "TorrentServer"
    private const val CHANNEL = "soplay/torrent"

    /** Subdirectory of the app cache the server owns outright. */
    private const val CACHE_DIR = "torrent_tmp"

    /** Port of the running server, or 0 when it has never been started. */
    private val runningPort = AtomicLong(0)

    /**
     * `startTorrentServer` blocks while the Go runtime comes up, and the AAR's
     * JNI is not safe to enter from several threads at once, so every call is
     * funnelled through one background thread.
     */
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "torrent-server").apply { isDaemon = true }
    }

    private var channel: MethodChannel? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> start(appContext, call.argument<String>("trackers"), result)
                    "port" -> result.success(runningPort.get().toInt())
                    // Where the server may spill its piece cache. Resolved
                    // natively rather than in Dart so both sides agree on one
                    // directory — the same one clearCache() wipes.
                    "cacheDir" -> result.success(cacheDir(appContext).absolutePath)
                    "clearCache" -> result.success(clearCache(appContext))
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    /**
     * Wipes everything the server cached. Called from Dart on app start, before
     * the server is running.
     *
     * Torrent pieces are written to the *cache* directory on purpose: they are
     * a scratch copy of something re-downloadable, they can reach tens of
     * gigabytes, and Android is allowed to evict them under storage pressure —
     * which is exactly the right behaviour. Clearing them at launch keeps a
     * few nights of watching from quietly filling the device.
     */
    fun clearCache(context: Context): Boolean = try {
        cacheDir(context).deleteRecursively()
    } catch (t: Throwable) {
        Log.w(TAG, "cache cleanup failed", t)
        false
    }

    private fun cacheDir(context: Context) = File(context.cacheDir, CACHE_DIR)

    private fun start(context: Context, trackers: String?, result: MethodChannel.Result) {
        val existing = runningPort.get()
        if (existing > 0) {
            result.success(existing.toInt())
            return
        }

        worker.execute {
            // Re-check on the worker: two Dart calls can arrive before the
            // first one has bound a port.
            val already = runningPort.get()
            if (already > 0) {
                post { result.success(already.toInt()) }
                return@execute
            }

            try {
                val dir = cacheDir(context)
                dir.mkdirs()

                // Loads libgojni and initialises the Go runtime. Must happen
                // before any torrServer call, and exactly once.
                go.Seq.load()

                // Port 0 asks the server to pick a free one. A fixed port is
                // what makes this crash on a device where something else
                // already holds it, and picking our own is the whole reason
                // the recloudstream fork exists.
                val port = TorrServer.startTorrentServer(dir.absolutePath, 0L)
                if (port <= 0) {
                    post { result.error("start_failed", "Server returned port $port", null) }
                    return@execute
                }

                // Attaching public trackers is not cosmetic: magnets from an
                // indexer usually carry only that site's announce URL, or none
                // at all, which leaves the swarm to DHT alone — slow to
                // bootstrap on mobile and disabled outright for private
                // torrents. The list comes from Dart so it stays in one place.
                if (!trackers.isNullOrBlank()) {
                    runCatching { TorrServer.addTrackers(trackers) }
                        .onFailure { Log.w(TAG, "addTrackers failed", it) }
                }

                runningPort.set(port)
                Log.i(TAG, "torrent server listening on 127.0.0.1:$port")
                post { result.success(port.toInt()) }
            } catch (t: Throwable) {
                Log.e(TAG, "failed to start torrent server", t)
                post { result.error("start_failed", t.message, null) }
            }
        }
    }

    /** Method channel replies must be delivered on the main thread. */
    private fun post(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}
