package com.soplay.sozo.preview

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * A single seek-preview decoder for progressive files, driven frame by frame by
 * the Dart side, which also fills the background grid through it.
 * A blocked setDataSource must not create a growing collection of retrievers as
 * the user scrubs. All native work shares one try-lock; close only schedules the
 * release, so it never waits on a network/codec call.
 */
object FramePreview {
    private const val TAG = "FramePreview"
    // The card is drawn up to ~210pt wide; 240px was soft on a 3x screen.
    private const val MAX_W = 360
    private val work = ReentrantLock()
    private val state = Any()
    private val generation = AtomicLong(0)
    private data class Session(
        val generation: Long,
        val url: String,
        val headers: Map<String, String>,
        val retriever: MediaMetadataRetriever,
    )
    private var active: Session? = null
    private val retired = ArrayList<MediaMetadataRetriever>()
    private val cleanupScheduled = AtomicBoolean(false)

    // Kept between drags, as HlsFramePreview keeps its extractor. Reading a
    // file's index is most of what a frame costs on a slow host, and released
    // when the finger lifted, every drag read it again.
    private const val LINGER_MS = 60_000L
    private val main = Handler(Looper.getMainLooper())
    private val release = Runnable { retireActive() }

    /** What was asked for last: an open that took its time still counts for it. */
    private var wanted: Pair<String, Map<String, String>>? = null
    private val cleanup = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "preview-release").apply { isDaemon = true }
    }

    private fun accept(sessionId: Long): Boolean = synchronized(state) {
        if (sessionId < generation.get()) false else {
            generation.set(sessionId)
            true
        }
    }

    @Suppress("UNUSED_PARAMETER")
    fun open(url: String, headers: Map<String, String>, warmMs: Long = -1L,
             sessionId: Long = generation.get() + 1): Boolean {
        if (!accept(sessionId)) return false
        synchronized(state) { wanted = url to headers }
        main.removeCallbacks(release)
        if (!work.tryLock()) return false
        try {
            val reused = synchronized(state) {
                val existing = active
                if (existing != null && existing.url == url && existing.headers == headers) {
                    active = existing.copy(generation = sessionId)
                    true
                } else {
                    false
                }
            }
            if (reused) return true
            synchronized(state) {
                active?.let { retired.add(it.retriever) }
                active = null
            }
            releaseRetired()
            if (generation.get() != sessionId) return false
            val retriever = MediaMetadataRetriever()
            try {
                if (headers.isEmpty()) retriever.setDataSource(url)
                else retriever.setDataSource(url, headers)
                val installed = synchronized(state) {
                    if (wanted != url to headers) false else {
                        active = Session(generation.get(), url, headers.toMap(), retriever)
                        true
                    }
                }
                if (!installed) releaseQuietly(retriever)
                return installed
            } catch (error: Throwable) {
                Log.w(TAG, "preview unavailable: ${error.javaClass.simpleName}")
                releaseQuietly(retriever)
                return false
            }
        } finally {
            work.unlock()
        }
    }

    fun frame(positionMs: Long, maxW: Int = MAX_W,
              sessionId: Long = generation.get()): ByteArray? {
        if (sessionId != generation.get() || !work.tryLock()) return null
        return try {
            val current = synchronized(state) { active } ?: return null
            if (current.generation != sessionId) return null
            val bytes = extract(current.retriever, positionMs.coerceAtLeast(0L), maxW.coerceIn(1, MAX_W))
            if (sessionId == generation.get()) bytes else null
        } catch (error: Throwable) {
            Log.w(TAG, "preview frame unavailable: ${error.javaClass.simpleName}")
            null
        } finally {
            work.unlock()
        }
    }

    fun close(sessionId: Long = generation.get() + 1) {
        synchronized(state) {
            if (sessionId < generation.get()) return
            generation.set(sessionId)
        }
        main.removeCallbacks(release)
        main.postDelayed(release, LINGER_MS)
    }

    private fun retireActive() {
        synchronized(state) {
            wanted = null
            active?.let { retired.add(it.retriever) }
            active = null
        }
        scheduleCleanup()
    }

    private fun scheduleCleanup() {
        if (synchronized(state) { retired.isEmpty() } || !cleanupScheduled.compareAndSet(false, true)) return
        cleanup.execute {
            try { work.withLock { releaseRetired() } }
            finally {
                cleanupScheduled.set(false)
                if (synchronized(state) { retired.isNotEmpty() }) scheduleCleanup()
            }
        }
    }

    /** Called only while owning [work], including before a replacement opens. */
    private fun releaseRetired() {
        val pending = synchronized(state) { retired.toList().also { retired.clear() } }
        pending.forEach { releaseQuietly(it) }
    }

    private fun releaseQuietly(retriever: MediaMetadataRetriever?) {
        try { retriever?.release() } catch (_: Throwable) {}
    }

    /** Extract + JPEG-encode one frame from [r]. */
    private fun extract(
        r: MediaMetadataRetriever,
        positionMs: Long,
        maxW: Int = MAX_W,
    ): ByteArray? {
        val timeUs = positionMs * 1000L
        // Request a small output bitmap. The platform still controls the internal
        // decoder resolution; demand-driven lifetime avoids competing during playback.
        val bmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            r.getScaledFrameAtTime(
                timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxW, maxW,
            )
        } else {
            r.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } ?: return null
        val scaled = scaleTo(bmp, maxW)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 78, out)
        if (scaled !== bmp) scaled.recycle()
        bmp.recycle()
        return out.toByteArray()
    }

    private fun scaleTo(bmp: Bitmap, maxW: Int): Bitmap {
        if (bmp.width <= maxW || bmp.width == 0) return bmp
        val h = (bmp.height.toLong() * maxW / bmp.width).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bmp, maxW, h, true)
    }
}
