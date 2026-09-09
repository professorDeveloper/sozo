package com.soplay.sozo

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs

/**
 * The Android downloader.
 *
 * ## Why a foreground service at all
 *
 * A download that stops the moment somebody leaves the app is not a download.
 * Everything here exists so the transfer outlives the UI — which also means
 * nothing here can ask the UI a question, and every failure has to be recorded
 * somewhere Dart can read it later.
 *
 * ## The rule this file now holds
 *
 * **`completed` is never written unless the artefact is on disk and whole.**
 *
 * The previous version wrote it on the strength of the transfer having
 * returned. A transfer can return from a dozen places without a file behind it
 * — a socket closed clean at 80%, a segment served as an HTML error page, a
 * process killed between the last write and the rename — and every one of them
 * produced a row that said "Downloaded" and a tap that answered "File not
 * found", with no retry offered because the row was not `failed`.
 *
 * Three things hold the rule:
 *
 *  * nothing is written to its final name: `.part` first, rename on success,
 *  * a declared `Content-Length` that is not met is a failure, not a finish,
 *  * a multi-part download writes a manifest and is counted against it before
 *    it is allowed to say it is done.
 *
 * ## Android versions
 *
 * | API | What changes here |
 * |-----|-------------------|
 * | 24  | The floor. `stopForeground(Boolean)` is the only overload. |
 * | 26  | Notification channel required. |
 * | 29  | Foreground service TYPE required in the call, not only the manifest. |
 * | 31  | A service started from the background throws — caught, recorded, not crashed. |
 * | 33  | `POST_NOTIFICATIONS`. Denying it must NOT stop the download. |
 * | 34  | The manifest type and the call's type must agree, and the permission must be declared. |
 * | 35  | `dataSync` services are time-capped; `onTimeout` arrives and must be honoured. |
 */
class DownloadForegroundService : Service() {

    private val notificationManager by lazy {
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startTask(intent)
            ACTION_CANCEL -> stopTask(intent.getStringExtra(EXTRA_ID).orEmpty(), STOP_CANCEL)
            ACTION_PAUSE -> stopTask(intent.getStringExtra(EXTRA_ID).orEmpty(), STOP_PAUSE)
            ACTION_CANCEL_ALL -> cancelAllTasks()
        }
        // START_NOT_STICKY, not START_STICKY. A restart with a null intent used
        // to bring the service back with nothing to do, so it sat in the
        // foreground holding a notification for a download that no longer
        // existed. Dart restarts what was interrupted at launch, which is the
        // one place that knows what "interrupted" means.
        return START_NOT_STICKY
    }

    /**
     * Android 15 caps how long a `dataSync` service may run.
     *
     * The cap is real and the download does not get to argue with it. What it
     * gets to do is stop cleanly: the partial file stays, the row says paused
     * rather than failed, and the next launch resumes from the bytes already
     * written. Ignoring this means the system kills the process and the row is
     * left claiming to be downloading forever.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        activeTasks.keys.forEach { id -> stopTask(id, STOP_PAUSE) }
        stopForegroundCompat()
        stopSelf()
    }

    private fun startTask(intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID).orEmpty()
        val artefactPath = intent.getStringExtra(EXTRA_LOCAL_PATH).orEmpty()
        val kind = intent.getStringExtra(EXTRA_KIND).takeUnless { it.isNullOrBlank() } ?: KIND_VIDEO
        val url = intent.getStringExtra(EXTRA_URL).orEmpty()
        val pageUrls = parseStringArray(intent.getStringExtra(EXTRA_PAGE_URLS_JSON).orEmpty())
        val wifiOnly = intent.getBooleanExtra(EXTRA_WIFI_ONLY, false)

        if (id.isEmpty() || artefactPath.isEmpty()) return
        if (kind == KIND_MANGA) {
            if (pageUrls.isEmpty()) return
        } else if (url.isEmpty()) {
            return
        }
        // A resume issued while the previous task is still stopping used to be
        // dropped here in silence: the row sat at `pending` for ever and the
        // only way out was to remove and re-add the download. A task that has
        // already been told to stop is not a reason to refuse the next start —
        // its own worker will see the token and exit.
        val running = activeTasks[id]
        if (running != null && !running.get()) return
        if (running != null) {
            // Let the outgoing worker finish writing its terminal state before
            // this one overwrites it, or a pause can land after the restart and
            // freeze the row at `paused` while bytes are moving.
            waitForTaskToClear(id)
        }

        val title = intent.getStringExtra(EXTRA_TITLE).takeUnless { it.isNullOrBlank() }
            ?: "Downloading"
        val headers = parseHeaders(intent.getStringExtra(EXTRA_HEADERS_JSON).orEmpty())

        // Checked here as well as in Dart. The service outlives the app, so a
        // queue that left Wi-Fi after starting would keep spending mobile data
        // with nothing on screen able to stop it.
        if (wifiOnly && !isOnUnmeteredNetwork()) {
            updateState(id, title, url, artefactPath, STATUS_PAUSED, 0, 0, 0, "waiting for Wi-Fi")
            return
        }

        val token = AtomicBoolean(false)
        activeTasks[id] = token
        // `pending` until a worker actually picks it up. The pool holds two, so
        // marking everything `downloading` at submit time made a queue of
        // twenty look like twenty running transfers — and made pausing one of
        // them look like it had done nothing.
        updateState(id, title, url, artefactPath, STATUS_PENDING, 0, 0, 0, null)

        if (!enterForeground(title)) {
            // Android 12+ refuses a foreground service started from the
            // background. Recorded rather than crashed: the row can then say
            // so, and the next launch — with the app in front — starts it.
            activeTasks.remove(id)
            updateState(
                id, title, url, artefactPath, STATUS_FAILED, 0, 0, 0,
                "the system would not allow a background download to start"
            )
            return
        }

        executor.execute {
            try {
                if (token.get()) {
                    finishStopped(id, title, url, artefactPath)
                    return@execute
                }
                updateState(id, title, url, artefactPath, STATUS_DOWNLOADING, 0, 0, 0, null)
                val result = when (kind) {
                    KIND_MANGA -> downloadPages(id, title, artefactPath, pageUrls, headers, token)
                    KIND_HLS -> downloadHls(id, title, url, artefactPath, headers, token)
                    else -> downloadFile(id, title, url, artefactPath, headers, token)
                }
                when {
                    token.get() -> finishStopped(id, title, url, artefactPath)
                    else -> finishCompleted(id, title, url, artefactPath, kind, result)
                }
            } catch (e: Exception) {
                if (token.get()) {
                    finishStopped(id, title, url, artefactPath)
                } else {
                    updateState(
                        id, title, url, artefactPath, STATUS_FAILED, 0, 0, 0,
                        e.message ?: e.javaClass.simpleName
                    )
                    notificationManager.cancel(notificationId(id))
                }
            } finally {
                stopReasons.remove(id)
                activeTasks.remove(id)
                if (activeTasks.isEmpty()) {
                    stopForegroundCompat()
                    stopSelf()
                } else {
                    notificationManager.notify(
                        SUMMARY_NOTIFICATION_ID,
                        buildSummaryNotification("${activeTasks.size} downloads running")
                    )
                }
            }
        }
    }

    /**
     * Blocks until [id] is no longer registered, or the wait runs out.
     *
     * Bounded because a worker wedged on a socket read must not hold up the
     * restart for ever — after the budget the new task starts anyway, and the
     * old one's token is already set so it writes nothing more of consequence.
     */
    private fun waitForTaskToClear(id: String) {
        val deadline = System.currentTimeMillis() + TASK_CLEAR_TIMEOUT_MS
        while (activeTasks.containsKey(id) && System.currentTimeMillis() < deadline) {
            try {
                Thread.sleep(50)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
    }

    /** What a transfer produced, before anything is allowed to call it done. */
    private data class Transferred(
        val completedUnits: Long,
        val totalUnits: Long,
        val sizeBytes: Long
    )

    // --- one file ------------------------------------------------------------

    private fun downloadFile(
        id: String,
        title: String,
        url: String,
        artefactPath: String,
        headers: Map<String, String>,
        token: AtomicBoolean
    ): Transferred {
        val target = File(artefactPath)
        target.parentFile?.mkdirs()
        val part = File("$artefactPath.part")

        // Resume from the partial, never from the finished name: a file at the
        // final name is a download that already succeeded.
        var written = if (part.exists()) part.length() else 0L
        val connection = openConnection(url, headers, written)
        val code = connection.responseCode
        rejectFailedResponse(code, connection)
        rejectNonMedia(connection)

        val append = written > 0 && code == HttpURLConnection.HTTP_PARTIAL
        if (!append) {
            part.delete()
            written = 0L
        }

        val declared = connection.getHeaderFieldLong("Content-Length", -1L)
        val total = if (declared > 0) written + declared else 0L
        updateState(id, title, url, artefactPath, STATUS_DOWNLOADING, written, total, written, null)
        updateProgressNotification(id, title, written, total)

        connection.inputStream.use { input ->
            FileOutputStream(part, append).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    if (token.get()) {
                        output.flush()
                        return Transferred(written, total, written)
                    }
                    val read = input.read(buffer)
                    if (read == -1) break
                    output.write(buffer, 0, read)
                    written += read
                    updateState(
                        id, title, url, artefactPath, STATUS_DOWNLOADING,
                        written, total, written, null
                    )
                    updateProgressNotification(id, title, written, total)
                }
                output.flush()
            }
        }

        if (written <= 0L) throw IOException("nothing was written")
        // The server said how long it was and we have less. The connection
        // closed clean, which from inside the read loop is indistinguishable
        // from success — and this is the check that tells them apart.
        if (total > 0L && written < total) {
            throw IOException("incomplete: $written of $total bytes")
        }

        target.delete()
        if (!part.renameTo(target)) throw IOException("could not finish the file")
        return Transferred(written, written, written)
    }

    // --- playlist ------------------------------------------------------------

    private fun downloadHls(
        id: String,
        title: String,
        url: String,
        artefactPath: String,
        headers: Map<String, String>,
        token: AtomicBoolean
    ): Transferred {
        val target = File(artefactPath)
        val folder = target.parentFile ?: throw IOException("no folder for the playlist")
        folder.mkdirs()

        var playlistUrl = url
        var playlist = readText(url, headers)
        if (playlist.contains("#EXT-X-STREAM-INF")) {
            playlistUrl = pickVariantUrl(playlist, baseUrlOf(url))
                ?: throw IOException("no variant in the master playlist")
            playlist = readText(playlistUrl, headers)
        }

        val segments = parseSegments(playlist, baseUrlOf(playlistUrl))
        if (segments.isEmpty()) throw IOException("no segments in the playlist")

        var bytes = 0L
        for (i in segments.indices) {
            if (token.get()) return Transferred(i.toLong(), segments.size.toLong(), bytes)
            val segment = File(folder, "seg_$i.ts")
            // A zero-length or missing segment is re-fetched. The old code
            // trusted any file that existed, so a segment truncated by a killed
            // process was never fetched again and the episode played to that
            // point and stopped.
            if (!segment.exists() || segment.length() == 0L) {
                fetchPart(segments[i], segment, headers, token)
            }
            bytes += segment.length()
            updateState(
                id, title, url, artefactPath, STATUS_DOWNLOADING,
                (i + 1).toLong(), segments.size.toLong(), bytes, null
            )
            updateProgressNotification(id, title, (i + 1).toLong(), segments.size.toLong())
        }

        // The manifest first, the playlist last. The playlist is what the
        // verifier treats as "this download exists", so a crash between the two
        // leaves something that still reads as incomplete.
        writeManifest(folder, KIND_HLS, segments.size, bytes)
        target.writeText(buildLocalPlaylist(playlist))
        return Transferred(segments.size.toLong(), segments.size.toLong(), bytes)
    }

    // --- pages ---------------------------------------------------------------

    private fun downloadPages(
        id: String,
        title: String,
        folderPath: String,
        pageUrls: List<String>,
        headers: Map<String, String>,
        token: AtomicBoolean
    ): Transferred {
        val folder = File(folderPath)
        folder.mkdirs()
        if (pageUrls.isEmpty()) throw IOException("the chapter has no pages")

        var bytes = 0L
        for (i in pageUrls.indices) {
            if (token.get()) return Transferred(i.toLong(), pageUrls.size.toLong(), bytes)
            val page = File(folder, "p_${i.toString().padStart(3, '0')}${imageExtensionFrom(pageUrls[i])}")
            if (!page.exists() || page.length() == 0L) {
                fetchPart(pageUrls[i], page, headers, token)
            }
            bytes += page.length()
            updateState(
                id, title, "", folderPath, STATUS_DOWNLOADING,
                (i + 1).toLong(), pageUrls.size.toLong(), bytes, null
            )
            updateProgressNotification(id, title, (i + 1).toLong(), pageUrls.size.toLong())
        }

        writeManifest(folder, KIND_MANGA, pageUrls.size, bytes)
        return Transferred(pageUrls.size.toLong(), pageUrls.size.toLong(), bytes)
    }

    // --- finishing -----------------------------------------------------------

    /**
     * Writes `completed` — and only after checking there is something to open.
     *
     * This is the whole point of the rewrite. A completion that cannot be
     * opened is worse than a failure: a failure offers a retry, and a lying
     * completion offers a viewer on a plane a toast saying "File not found".
     */
    private fun finishCompleted(
        id: String,
        title: String,
        url: String,
        artefactPath: String,
        kind: String,
        result: Transferred
    ) {
        val artefact = File(artefactPath)
        val whole = when (kind) {
            KIND_MANGA -> artefact.isDirectory && countParts(artefact, "p_") > 0
            else -> artefact.isFile && artefact.length() > 0L
        }
        if (!whole) {
            updateState(
                id, title, url, artefactPath, STATUS_FAILED, 0, 0, 0,
                "the download finished with nothing on disk"
            )
            notificationManager.cancel(notificationId(id))
            return
        }
        val size = if (result.sizeBytes > 0) result.sizeBytes else sizeOf(artefact)
        updateState(
            id, title, url, artefactPath, STATUS_COMPLETED,
            result.completedUnits, result.totalUnits, size, null
        )
        notificationManager.notify(
            notificationId(id),
            buildDoneNotification(title, "Downloaded")
        )
    }

    /**
     * The terminal state for a download stopped on purpose.
     *
     * A pause keeps what is on disk and reports it, so the list can say
     * "paused at 42%" rather than resetting to zero — which is what the
     * cancel-only path did, and which made a pause indistinguishable from
     * starting over.
     */
    private fun finishStopped(id: String, title: String, url: String, artefactPath: String) {
        val paused = stopReasons[id] == STOP_PAUSE
        if (!paused) {
            updateState(id, title, url, artefactPath, STATUS_CANCELLED, 0, 0, 0, null)
            notificationManager.cancel(notificationId(id))
            return
        }

        val state = JSONObject(readStates(this)).optJSONObject(id)
        val part = File("$artefactPath.part")
        // Trust the file over the counter: the counter is written per buffer
        // and the process can die between the write and the record, but the
        // bytes on disk are the bytes the next Range request must skip.
        val onDisk = when {
            part.exists() -> part.length()
            File(artefactPath).isFile -> File(artefactPath).length()
            else -> state?.optLong(KEY_COMPLETED, 0L) ?: 0L
        }
        val total = state?.optLong(KEY_TOTAL, 0L) ?: 0L
        updateState(id, title, url, artefactPath, STATUS_PAUSED, onDisk, total, onDisk, null)
        notificationManager.notify(notificationId(id), buildPausedNotification(id, title, onDisk, total))
    }

    // --- http ----------------------------------------------------------------

    /** One part, with a short backoff so a blip does not cost the episode. */
    private fun fetchPart(
        url: String,
        file: File,
        headers: Map<String, String>,
        token: AtomicBoolean
    ) {
        val part = File("${file.path}.part")
        var lastError: Exception? = null
        for (attempt in 0 until PART_ATTEMPTS) {
            if (token.get()) return
            try {
                file.parentFile?.mkdirs()
                val connection = openConnection(url, headers, 0L)
                rejectFailedResponse(connection.responseCode, connection)
                rejectNonMedia(connection)
                connection.inputStream.use { input ->
                    FileOutputStream(part, false).use { output ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            if (token.get()) return
                            val read = input.read(buffer)
                            if (read == -1) break
                            output.write(buffer, 0, read)
                        }
                        output.flush()
                    }
                }
                if (part.length() <= 0L) throw IOException("empty part")
                file.delete()
                if (!part.renameTo(file)) throw IOException("could not finish a part")
                return
            } catch (e: Exception) {
                lastError = e
                part.delete()
                // 400ms, 800ms, 1600ms.
                try {
                    Thread.sleep(400L shl attempt)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return
                }
            }
        }
        throw lastError ?: IOException("could not fetch $url")
    }

    private fun readText(url: String, headers: Map<String, String>): String {
        val connection = openConnection(url, headers, 0L)
        rejectFailedResponse(connection.responseCode, connection)
        return connection.inputStream.bufferedReader().use { it.readText() }
    }

    private fun openConnection(
        url: String,
        headers: Map<String, String>,
        rangeStart: Long
    ): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 20_000
        connection.readTimeout = 30_000
        connection.instanceFollowRedirects = true
        headers.forEach { (key, value) ->
            if (key.isNotBlank() && value.isNotBlank()) {
                connection.setRequestProperty(key, value)
            }
        }
        if (rangeStart > 0L) connection.setRequestProperty("Range", "bytes=$rangeStart-")
        return connection
    }

    /**
     * A status the caller can act on.
     *
     * `HttpURLConnection` throws `FileNotFoundException` for a 404 and nothing
     * at all for a 403 with a body — so an unchecked 403 used to be saved as
     * the video. Naming the code is what lets Dart tell "the link expired" from
     * "the connection dropped".
     */
    private fun rejectFailedResponse(code: Int, connection: HttpURLConnection) {
        if (code in 200..299) return
        connection.disconnect()
        throw IOException("HTTP $code")
    }

    /**
     * Refuses an answer that is not media.
     *
     * A challenge page or an error page served as 200 used to be written to
     * `video.mp4`: the download completed, the row said "Downloaded", and the
     * player failed on a file that was HTML.
     */
    private fun rejectNonMedia(connection: HttpURLConnection) {
        val type = connection.contentType?.lowercase().orEmpty()
        if (type.isEmpty()) return
        if (type.startsWith("text/html") ||
            type.startsWith("application/xhtml") ||
            type.startsWith("text/plain")
        ) {
            connection.disconnect()
            throw IOException("not media: the server answered with $type")
        }
    }

    private fun isOnUnmeteredNetwork(): Boolean {
        return try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
                ?: return false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (_: Exception) {
            // Unknown counts as allowed: a queue that silently never starts is
            // worse than a download somebody did not expect, because nothing on
            // screen explains it.
            true
        }
    }

    // --- playlists -----------------------------------------------------------

    private fun pickVariantUrl(playlist: String, baseUrl: String): String? {
        val lines = playlist.lines()
        for (i in lines.indices) {
            if (!lines[i].startsWith("#EXT-X-STREAM-INF")) continue
            for (j in i + 1 until lines.size) {
                val line = lines[j].trim()
                if (line.isEmpty() || line.startsWith("#")) continue
                return resolveUrl(line, baseUrl)
            }
        }
        return null
    }

    private fun parseSegments(playlist: String, baseUrl: String): List<String> =
        playlist.lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { resolveUrl(it, baseUrl) }

    private fun buildLocalPlaylist(playlist: String): String {
        var index = 0
        return playlist.lines().joinToString("\n") { line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) trimmed else "seg_${index++}.ts"
        }
    }

    private fun baseUrlOf(url: String): String =
        url.substringBeforeLast("/", missingDelimiterValue = url) + "/"

    private fun resolveUrl(path: String, baseUrl: String): String {
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        return try {
            URI(baseUrl).resolve(path).toString()
        } catch (_: Exception) {
            "$baseUrl$path"
        }
    }

    // --- disk ----------------------------------------------------------------

    /**
     * The record a multi-part download leaves so it can be verified later.
     *
     * Without it, "is this whole" cannot be answered after the fact — which is
     * how a half-downloaded episode came back as `completed` on the next
     * launch.
     */
    private fun writeManifest(folder: File, kind: String, parts: Int, bytes: Long) {
        val json = JSONObject()
            .put("kind", kind)
            .put("parts", parts)
            .put("bytes", bytes)
            .put("writtenAt", System.currentTimeMillis())
        File(folder, MANIFEST_NAME).writeText(json.toString())
    }

    private fun countParts(folder: File, prefix: String): Int =
        folder.listFiles()?.count { it.isFile && it.name.startsWith(prefix) && it.length() > 0 } ?: 0

    private fun sizeOf(artefact: File): Long =
        if (artefact.isDirectory) {
            artefact.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        } else {
            artefact.length()
        }

    private fun parseHeaders(raw: String): Map<String, String> {
        if (raw.isBlank()) return emptyMap()
        return try {
            val json = JSONObject(raw)
            json.keys().asSequence().associateWith { json.optString(it) }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun parseStringArray(raw: String): List<String> {
        if (raw.isBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { array.optString(it) }.filter { it.isNotBlank() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun imageExtensionFrom(url: String): String {
        val path = try {
            URI(url).path?.lowercase().orEmpty()
        } catch (_: Exception) {
            url.lowercase()
        }
        return when {
            path.endsWith(".png") -> ".png"
            path.endsWith(".webp") -> ".webp"
            path.endsWith(".gif") -> ".gif"
            else -> ".jpg"
        }
    }

    // --- control -------------------------------------------------------------

    /**
     * Stops a running download, recording WHY.
     *
     * Pause and cancel interrupt the transfer the same way — the loop checks
     * one flag — but they mean opposite things afterwards. A cancelled download
     * is over; a paused one is a partial file the next start continues from.
     */
    private fun stopTask(id: String, reason: String) {
        if (id.isBlank()) return
        stopReasons[id] = reason
        activeTasks[id]?.set(true)
    }

    private fun cancelAllTasks() {
        activeTasks.forEach { (id, token) ->
            stopReasons[id] = STOP_CANCEL
            token.set(true)
        }
    }

    // --- state ---------------------------------------------------------------

    private fun updateState(
        id: String,
        title: String,
        url: String,
        artefactPath: String,
        status: String,
        completedUnits: Long,
        totalUnits: Long,
        sizeBytes: Long,
        error: String?
    ) {
        synchronized(stateLock) {
            val json = JSONObject(readStates(this))
            val item = JSONObject()
                .put("id", id)
                .put("title", title)
                .put("url", url)
                .put("localPath", artefactPath)
                .put("status", status)
                .put(KEY_COMPLETED, completedUnits)
                .put(KEY_TOTAL, totalUnits)
                .put("sizeBytes", sizeBytes)
            if (error != null) item.put("error", error)
            json.put(id, item)
            prefs(this).edit().putString(PREF_STATES, json.toString()).apply()
        }
    }

    // --- notifications -------------------------------------------------------

    /**
     * Enters the foreground, or reports that it could not.
     *
     * API 29 wants the type in the CALL as well as the manifest; API 31 refuses
     * the whole thing when the app is in the background; API 34 rejects a call
     * whose type is not declared. `ServiceCompat` handles the first, the catch
     * handles the second, and the manifest handles the third.
     */
    private fun enterForeground(title: String): Boolean = try {
        ServiceCompat.startForeground(
            this,
            SUMMARY_NOTIFICATION_ID,
            buildSummaryNotification(title),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
        )
        true
    } catch (e: Exception) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            e is ForegroundServiceStartNotAllowedException
        ) {
            false
        } else {
            // Anything else is worth surfacing as a failed start rather than
            // taking the process down.
            false
        }
    }

    private fun updateProgressNotification(
        id: String,
        title: String,
        completed: Long,
        total: Long
    ) {
        // Throttled: the transfer updates per buffer, and the shade cannot
        // usefully redraw a thousand times a second — it just costs binder
        // traffic on the same thread the download runs on.
        val now = System.currentTimeMillis()
        val last = lastNotifiedAt[id] ?: 0L
        if (now - last < NOTIFY_INTERVAL_MS) return
        lastNotifiedAt[id] = now
        notificationManager.notify(
            SUMMARY_NOTIFICATION_ID,
            buildProgressNotification(id, title, completed, total)
        )
    }

    private fun buildSummaryNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Sozo downloads")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .build()

    private fun buildProgressNotification(
        id: String,
        title: String,
        completed: Long,
        total: Long
    ): Notification {
        val percent = if (total > 0L) ((completed * 100L) / total).toInt().coerceIn(0, 100) else 0
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(if (total > 0L) "$percent%" else "Downloading")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, total <= 0L)
            .setContentIntent(openAppIntent())
            // Pausing from the shade rather than only from the app: the shade
            // is where somebody is when they notice a download eating their
            // data on the train.
            .addAction(
                android.R.drawable.ic_media_pause,
                "Pause",
                controlIntent(ACTION_PAUSE, id)
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Cancel",
                controlIntent(ACTION_CANCEL, id)
            )
            .build()
    }

    private fun buildPausedNotification(
        id: String,
        title: String,
        completed: Long,
        total: Long
    ): Notification {
        val percent = if (total > 0L) ((completed * 100L) / total).toInt().coerceIn(0, 100) else 0
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(if (total > 0L) "Paused at $percent%" else "Paused")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setProgress(100, percent, false)
            .setOngoing(false)
            .setContentIntent(openAppIntent())
            .build()
    }

    private fun buildDoneNotification(title: String, text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()

    private fun controlIntent(action: String, id: String): PendingIntent {
        val intent = Intent(this, DownloadForegroundService::class.java)
            .setAction(action)
            .putExtra(EXTRA_ID, id)
        return PendingIntent.getService(
            this,
            // Distinct per action AND per download, or the second one would
            // reuse the first's extras and pause the wrong episode.
            abs((action + id).hashCode() % 1_000_000),
            intent,
            pendingIntentFlags()
        )
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(this, 0, intent, pendingIntentFlags())
    }

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW
        )
        notificationManager.createNotificationChannel(channel)
    }

    private fun stopForegroundCompat() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
    }

    companion object {
        const val ACTION_START = "com.soplay.sozo.download.START"
        const val ACTION_CANCEL = "com.soplay.sozo.download.CANCEL"
        const val ACTION_PAUSE = "com.soplay.sozo.download.PAUSE"
        const val ACTION_CANCEL_ALL = "com.soplay.sozo.download.CANCEL_ALL"

        // Why a task was stopped. Both trip the same flag inside the transfer
        // loop; only what happens afterwards differs.
        private const val STOP_CANCEL = "cancel"
        private const val STOP_PAUSE = "pause"

        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_URL = "url"
        const val EXTRA_LOCAL_PATH = "local_path"
        const val EXTRA_HEADERS_JSON = "headers_json"
        const val EXTRA_KIND = "kind"
        const val EXTRA_PAGE_URLS_JSON = "page_urls_json"
        const val EXTRA_WIFI_ONLY = "wifi_only"

        // Kinds, matching DownloadKind on the Dart side byte for byte.
        const val KIND_VIDEO = "video"
        const val KIND_HLS = "hls"
        const val KIND_MANGA = "manga"

        private const val STATUS_PENDING = "pending"
        private const val STATUS_DOWNLOADING = "downloading"
        private const val STATUS_PAUSED = "paused"
        private const val STATUS_COMPLETED = "completed"
        private const val STATUS_FAILED = "failed"
        private const val STATUS_CANCELLED = "cancelled"

        private const val KEY_COMPLETED = "completedUnits"
        private const val KEY_TOTAL = "totalUnits"

        const val MANIFEST_NAME = "manifest.json"

        private const val MAX_CONCURRENT = 2
        private const val TASK_CLEAR_TIMEOUT_MS = 4_000L
        private const val PART_ATTEMPTS = 3
        private const val NOTIFY_INTERVAL_MS = 500L

        private const val CHANNEL_ID = "soplay_downloads"
        private const val SUMMARY_NOTIFICATION_ID = 2100
        private const val PREF_NAME = "soplay_downloads"
        private const val PREF_STATES = "download_states"

        /**
         * Two at a time, matching the queue on the Dart side.
         *
         * It was an unbounded cached pool: queueing ten episodes started ten
         * transfers, which on a phone means ten streams fighting over one
         * connection — everything crawls, the episode somebody actually wanted
         * finishes last, and pausing one of them changes nothing anyone can
         * see because the other nine keep going.
         */
        private val executor = Executors.newFixedThreadPool(MAX_CONCURRENT)
        private val activeTasks = ConcurrentHashMap<String, AtomicBoolean>()
        private val stopReasons = ConcurrentHashMap<String, String>()
        private val lastNotifiedAt = ConcurrentHashMap<String, Long>()
        private val stateLock = Any()

        fun readStates(context: Context): String =
            prefs(context).getString(PREF_STATES, "{}") ?: "{}"

        fun removeState(context: Context, id: String) {
            if (id.isBlank()) return
            synchronized(stateLock) {
                val json = JSONObject(readStates(context))
                json.remove(id)
                prefs(context).edit().putString(PREF_STATES, json.toString()).apply()
            }
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

        private fun notificationId(id: String): Int = 3000 + abs(id.hashCode() % 100000)
    }
}
