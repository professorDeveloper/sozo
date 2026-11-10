package com.soplay.sozo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * The player's media session, live while the player page is open: headset
 * and Bluetooth buttons reach the player, and the system knows what is
 * playing. Commands go to [onCommand] as (action, positionMs).
 */
class PlayerMediaSession(
    private val context: Context,
    private val onCommand: (String, Long?) -> Unit,
) {
    private var session: MediaSessionCompat? = null
    private val artLoader = Executors.newSingleThreadExecutor()
    private var artUrl: String? = null
    private var art: Bitmap? = null
    private var metadata = MediaMetadataCompat.Builder()

    private val callback = object : MediaSessionCompat.Callback() {
        override fun onPlay() = onCommand("play", null)
        override fun onPause() = onCommand("pause", null)
        override fun onStop() = onCommand("pause", null)
        override fun onSeekTo(pos: Long) = onCommand("seek", pos)
        override fun onFastForward() = onCommand("forward", null)
        override fun onRewind() = onCommand("rewind", null)
        override fun onSkipToNext() = onCommand("next", null)
        override fun onSkipToPrevious() = onCommand("prev", null)
    }

    fun start() {
        if (session != null) return
        session = MediaSessionCompat(context, "SozoPlayer").apply {
            setCallback(callback)
            isActive = true
        }
    }

    fun setMetadata(title: String, subtitle: String?, durationMs: Long, artworkUrl: String?) {
        val s = session ?: return
        metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
            .apply {
                if (!subtitle.isNullOrBlank()) {
                    putString(MediaMetadataCompat.METADATA_KEY_ARTIST, subtitle)
                    putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, subtitle)
                }
                if (durationMs > 0) putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            }
        if (artworkUrl != artUrl) {
            artUrl = artworkUrl
            art = null
            if (!artworkUrl.isNullOrBlank()) loadArt(artworkUrl)
        }
        art?.let { metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, it) }
        s.setMetadata(metadata.build())
    }

    fun setState(playing: Boolean, positionMs: Long, speed: Float, hasPrev: Boolean, hasNext: Boolean, seekable: Boolean) {
        val s = session ?: return
        var actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_STOP
        if (seekable) {
            actions = actions or PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_FAST_FORWARD or
                PlaybackStateCompat.ACTION_REWIND
        }
        if (hasPrev) actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        if (hasNext) actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_NEXT
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    positionMs,
                    if (playing) speed else 0f,
                    SystemClock.elapsedRealtime(),
                )
                .build()
        )
    }

    fun stop() {
        artUrl = null
        art = null
        session?.let {
            it.isActive = false
            it.setCallback(null)
            it.release()
        }
        session = null
    }

    fun dispose() {
        stop()
        artLoader.shutdownNow()
    }

    private fun loadArt(url: String) {
        artLoader.execute {
            val bitmap = runCatching { fetch(url) }.getOrNull() ?: return@execute
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (url != artUrl) return@post
                art = bitmap
                session?.setMetadata(
                    metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bitmap).build()
                )
            }
        }
    }

    private fun fetch(url: String): Bitmap? {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        return try {
            if (conn.responseCode !in 200..299) return null
            val bytes = conn.inputStream.use { it.readBytes() }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 512 && bounds.outHeight / (sample * 2) >= 512) sample *= 2
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        } finally {
            conn.disconnect()
        }
    }
}
