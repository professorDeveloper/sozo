package com.soplay.sozo.preview

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.inspector.FrameExtractor
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

/**
 * Seek-bar frames for HLS, which [FramePreview] cannot give: the platform's
 * MediaMetadataRetriever does not read HLS at all, and most streams here are
 * HLS. Media3's FrameExtractor does — it is an ExoPlayer built for exactly
 * this, seeking to the keyframe nearest a position and handing back that frame.
 *
 * It takes no request headers, so the Dart side hands it a stream already
 * routed through the app's local proxy (which adds them), and the lightest
 * variant of it — a thumbnail needs one small rendition, not the ladder.
 *
 * Kept open between drags: opening HLS is a playlist and a segment before the
 * first frame, and scrubbing comes in runs. A new stream replaces it; a minute
 * without a request releases it.
 */
object HlsFramePreview {
    private const val TAG = "HlsFramePreview"
    // The card is drawn up to ~210pt wide; 240px was soft on a 3x screen.
    private const val MAX_W = 360
    private const val LINGER_MS = 60_000L

    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())
    private var extractor: FrameExtractor? = null
    private var url: String? = null
    private var generation = 0L
    private val release = Runnable { replace(null, null) }

    fun open(context: Context, url: String, sessionId: Long): Boolean {
        synchronized(lock) {
            if (sessionId < generation) return false
            generation = sessionId
            main.removeCallbacks(release)
            if (this.url == url && extractor != null) return true
        }
        return try {
            val built = FrameExtractor.Builder(context.applicationContext, MediaItem.fromUri(url))
                .setSeekParameters(SeekParameters.CLOSEST_SYNC)
                .build()
            synchronized(lock) {
                if (generation != sessionId) {
                    closeQuietly(built)
                    false
                } else {
                    replace(built, url)
                    true
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "hls preview unavailable: ${t.javaClass.simpleName}: ${t.message}")
            false
        }
    }

    fun frame(positionMs: Long, sessionId: Long): ByteArray? {
        val ex = synchronized(lock) {
            if (sessionId != generation) null else extractor
        } ?: return null
        return try {
            val frame = ex.getFrame(positionMs.coerceAtLeast(0L)).get(8, TimeUnit.SECONDS)
            if (synchronized(lock) { sessionId != generation }) null else encode(frame.bitmap)
        } catch (t: Throwable) {
            Log.w(TAG, "hls frame unavailable: ${t.javaClass.simpleName}")
            null
        }
    }

    /** A finger lifted: keep the stream for the next drag, for a while. */
    fun close(sessionId: Long) {
        synchronized(lock) {
            if (sessionId < generation) return
            generation = sessionId
        }
        main.removeCallbacks(release)
        main.postDelayed(release, LINGER_MS)
    }

    private fun replace(next: FrameExtractor?, nextUrl: String?) {
        val old = synchronized(lock) {
            val o = extractor
            extractor = next
            url = nextUrl
            o
        }
        if (old != null && old !== next) closeQuietly(old)
    }

    private fun closeQuietly(ex: FrameExtractor) {
        try { ex.close() } catch (_: Throwable) {}
    }

    private fun encode(bmp: Bitmap): ByteArray {
        val scaled = if (bmp.width > MAX_W && bmp.width > 0) {
            Bitmap.createScaledBitmap(
                bmp, MAX_W, (bmp.height.toLong() * MAX_W / bmp.width).toInt().coerceAtLeast(1), true,
            )
        } else bmp
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 78, out)
        if (scaled !== bmp) scaled.recycle()
        return out.toByteArray()
    }
}
