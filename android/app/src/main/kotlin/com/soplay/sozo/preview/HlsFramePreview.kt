package com.soplay.sozo.preview

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
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
            // The format said outright. Left to guess, Media3 reads the last
            // path segment, and an HLS address that does not end in .m3u8 —
            // `/playlist`, `/master.txt`, a query-string file — was opened as
            // a progressive file and failed on every frame.
            val item = MediaItem.Builder()
                .setUri(url)
                .setMimeType(MimeTypes.APPLICATION_M3U8)
                .build()
            val built = FrameExtractor.Builder(context.applicationContext, item)
                .setSeekParameters(SeekParameters.CLOSEST_SYNC)
                // Software decoders first. Playback already holds a hardware
                // one, some chips allow only one or two at a time, and a
                // 240p thumbnail rendition is nothing for the CPU.
                .setMediaCodecSelector { mime, secure, tunneling ->
                    MediaCodecSelector.DEFAULT
                        .getDecoderInfos(mime, secure, tunneling)
                        .sortedBy { it.hardwareAccelerated }
                }
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
        val pending = try {
            ex.getFrame(positionMs.coerceAtLeast(0L))
        } catch (t: Throwable) {
            Log.w(TAG, "hls frame request refused: ${t.javaClass.name}: ${t.message}")
            return null
        }
        return try {
            val frame = pending.get(5, TimeUnit.SECONDS)
            if (synchronized(lock) { sessionId != generation }) null else encode(frame.bitmap)
        } catch (t: java.util.concurrent.TimeoutException) {
            // The extractor runs its requests one after another; one left
            // running would hold every later frame behind it.
            pending.cancel(true)
            Log.w(TAG, "hls frame timed out at ${positionMs}ms")
            null
        } catch (t: Throwable) {
            // The future wraps the real failure; its class name alone said
            // nothing about why every frame was missing.
            val cause = (t as? java.util.concurrent.ExecutionException)?.cause ?: t
            Log.w(TAG, "hls frame unavailable: ${cause.javaClass.name}: ${cause.message}", cause)
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
