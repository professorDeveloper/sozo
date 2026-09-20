package com.soplay.sozo.tiles

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Decodes one rectangle of a page at a time.
 *
 * A manga page is decoded once, scaled to the column it is drawn in, and then
 * zoomed — so zooming in magnifies a bitmap that was already thrown away at
 * screen width. On a dense page, a double-page spread or anything with small
 * lettering, that is the difference between reading it and not. Decoding the
 * whole page at full size instead is not an option: a long webtoon strip is
 * tens of thousands of pixels tall, and one of those in ARGB_8888 is hundreds
 * of megabytes.
 *
 * [BitmapRegionDecoder] is the way out. It keeps the file open and decodes any
 * rectangle of it on demand, at any sample size, without ever holding the whole
 * image — which is exactly the shape of "give me the part that is on screen,
 * sharp".
 *
 * Every call runs on whatever thread the caller is on. The Dart side puts them
 * on a background isolate's channel; decoding a region of a large JPEG is tens
 * of milliseconds and is not something to do on the platform thread.
 */
object PageTiles {
    private const val TAG = "PageTiles"

    private class Entry(val decoder: BitmapRegionDecoder, val width: Int, val height: Int)

    private val open = ConcurrentHashMap<Long, Entry>()
    private val nextHandle = AtomicLong(1)

    /**
     * Opens [path] and reports its true pixel size.
     *
     * Null when the file is not an image this decoder can take. That is not an
     * error worth surfacing — the caller keeps drawing the page the ordinary
     * way and simply does not offer a sharp zoom.
     */
    fun open(path: String): Map<String, Any>? {
        val file = File(path)
        if (!file.isFile || file.length() <= 0L) return null
        return try {
            val decoder = file.inputStream().use { stream ->
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    BitmapRegionDecoder.newInstance(stream)
                } else {
                    BitmapRegionDecoder.newInstance(stream, false)
                }
            } ?: return null
            val handle = nextHandle.getAndIncrement()
            open[handle] = Entry(decoder, decoder.width, decoder.height)
            mapOf("handle" to handle, "width" to decoder.width, "height" to decoder.height)
        } catch (t: Throwable) {
            // A GIF, a WEBP the platform will not region-decode, a truncated
            // file. All of them mean "no sharp zoom here", none of them mean
            // the page cannot be shown.
            Log.i(TAG, "cannot region-decode $path: ${t.message}")
            null
        }
    }

    /**
     * One rectangle of an open page, as PNG bytes.
     *
     * [sampleSize] is passed through to the decoder, which rounds it down to a
     * power of two itself. The rect is clamped to the image: a viewport that
     * hangs off the edge is the normal state at the end of a pan, and a decoder
     * handed an out-of-bounds rect throws rather than clipping.
     *
     * Null rather than a throw for anything that goes wrong, for the same
     * reason as [open].
     */
    fun region(
        handle: Long,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        sampleSize: Int,
    ): ByteArray? {
        val entry = open[handle] ?: return null
        val rect = Rect(
            left.coerceIn(0, entry.width),
            top.coerceIn(0, entry.height),
            right.coerceIn(0, entry.width),
            bottom.coerceIn(0, entry.height),
        )
        if (rect.width() <= 0 || rect.height() <= 0) return null
        return try {
            val options = BitmapFactory.Options().apply {
                inSampleSize = if (sampleSize < 1) 1 else sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val bitmap = synchronized(entry.decoder) {
                entry.decoder.decodeRegion(rect, options)
            } ?: return null
            try {
                ByteArrayOutputStream().use { out ->
                    // PNG: a tile is drawn on top of the page it came from, so a
                    // JPEG's ringing would show as a visible seam at its edges.
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    out.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "region decode failed: ${t.message}")
            null
        }
    }

    /**
     * Closes one page.
     *
     * The decoder holds a file descriptor and a native buffer, so leaving it to
     * the collector means a reader that has scrolled through two hundred pages
     * is holding two hundred of both.
     */
    fun close(handle: Long) {
        val entry = open.remove(handle) ?: return
        try {
            synchronized(entry.decoder) { entry.decoder.recycle() }
        } catch (_: Throwable) {
        }
    }

    /** Closes everything. Called when the reader leaves. */
    fun closeAll() {
        for (handle in open.keys.toList()) close(handle)
    }
}
