package com.soplay.sozo.drm

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.MediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * ExoPlayer behind a Flutter texture, for the streams libmpv cannot decrypt.
 *
 * ## Why a texture and not a PlatformView
 *
 * The obvious way to do this — and the way the app we compared against does it
 * — is a native view with its own control overlay on top, kept away from the
 * main player. That gets DRM playing quickly and costs everything else: the
 * gestures, the subtitle styling, the sleep timer, the episode panel, the
 * source switcher and the cast button are all attached to *our* player, and a
 * second screen has none of them. A viewer would tap a DRM channel and land
 * somewhere that looks like the app and behaves like a different one.
 *
 * Rendering into a `SurfaceTexture` instead makes this backend a `Texture`
 * widget, which is exactly the shape the other two backends already have. The
 * player page does not learn that DRM exists; it builds a controller and lays
 * its own UI over whatever comes back. That is the whole design.
 *
 * ## Why a second ExoPlayer when video_player already ships one
 *
 * `video_player_android` is an ExoPlayer, but its plugin API exposes no way to
 * attach a `DrmSessionManager` — the capability is in the engine and not in the
 * surface. Rather than fork the plugin, this drives media3 directly and is used
 * only for the streams that need it. Everything unencrypted keeps going through
 * the existing backends untouched.
 */
@UnstableApi
class DrmPlayerHost(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) {
    companion object {
        private const val TAG = "DrmPlayer"
        const val METHOD_CHANNEL = "soplay/drm_player"
        const val EVENT_CHANNEL = "soplay/drm_player/events"

        /** ExoPlayer's own ids for the schemes we accept from Dart. */
        private fun uuidFor(scheme: String?) = when (scheme?.lowercase()) {
            "widevine" -> C.WIDEVINE_UUID
            "playready" -> C.PLAYREADY_UUID
            "clearkey" -> C.CLEARKEY_UUID
            else -> null
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val sessions = mutableMapOf<Long, Session>()

    private var events: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(::onCall)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(args: Any?) {
                    events = null
                }
            },
        )
    }

    /** One playing stream: its player, its texture, and the surface between. */
    private inner class Session(
        val id: Long,
        val entry: TextureRegistry.SurfaceTextureEntry,
        val player: ExoPlayer,
        val surface: Surface,
    ) {
        fun release() {
            player.release()
            surface.release()
            entry.release()
        }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> main.post { create(call, result) }
                "play" -> withSession(call, result) { it.player.play() }
                "pause" -> withSession(call, result) { it.player.pause() }
                "seekTo" -> withSession(call, result) {
                    it.player.seekTo((call.argument<Number>("position") ?: 0).toLong())
                }
                "setSpeed" -> withSession(call, result) {
                    it.player.setPlaybackSpeed(
                        (call.argument<Number>("speed") ?: 1).toFloat(),
                    )
                }
                "setVolume" -> withSession(call, result) {
                    it.player.volume = (call.argument<Number>("volume") ?: 1).toFloat()
                }
                "setLooping" -> withSession(call, result) {
                    it.player.repeatMode =
                        if (call.argument<Boolean>("looping") == true) {
                            Player.REPEAT_MODE_ALL
                        } else {
                            Player.REPEAT_MODE_OFF
                        }
                }
                "position" -> withSession(call, result, reply = { it.player.currentPosition })
                "dispose" -> main.post {
                    val id = (call.argument<Number>("id") ?: -1).toLong()
                    sessions.remove(id)?.release()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            // A control is a button under someone's thumb. The failure is
            // always the same shape — the session went away — and surfacing it
            // as a platform exception turns a tap into a crash report.
            Log.e(TAG, "${call.method} failed", t)
            result.error("drm", t.message ?: call.method, null)
        }
    }

    private fun withSession(
        call: MethodCall,
        result: MethodChannel.Result,
        reply: ((Session) -> Any?)? = null,
        action: ((Session) -> Unit)? = null,
    ) {
        main.post {
            val id = (call.argument<Number>("id") ?: -1).toLong()
            val session = sessions[id]
            if (session == null) {
                // Not an error: Dart disposes on one path while a pending
                // control lands on another, and every one of those would
                // otherwise be a red banner over a player that closed cleanly.
                result.success(null)
                return@post
            }
            action?.invoke(session)
            result.success(reply?.invoke(session) ?: true)
        }
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url").orEmpty()
        if (url.isEmpty()) {
            result.error("drm", "no url", null)
            return
        }
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        val drm = call.argument<Map<String, Any?>>("drm").orEmpty()
        val uuid = uuidFor(drm["scheme"] as? String)
        if (uuid == null) {
            // Refused here rather than attempted and failed. A device without
            // the module for this scheme produces a decrypt error four seconds
            // into a black screen, which reads as a dead stream; saying so up
            // front lets the caller offer a different mirror instead.
            result.error("drm", "unsupported scheme ${drm["scheme"]}", null)
            return
        }

        val http = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(headers)

        @Suppress("UNCHECKED_CAST")
        val clearKeys = (drm["clearKeys"] as? Map<String, String>).orEmpty()
        @Suppress("UNCHECKED_CAST")
        val licenseHeaders = (drm["licenseHeaders"] as? Map<String, String>).orEmpty()

        // Built by hand rather than through MediaItem.DrmConfiguration, because
        // ClearKey has no licence server to point a uri at. Its keys ARE the
        // licence, and the only way to hand them over is a callback that
        // answers the request locally — which the uri-based configuration has
        // no way to express.
        val callback: MediaDrmCallback = if (uuid == C.CLEARKEY_UUID) {
            LocalMediaDrmCallback(ClearKeys.emeJson(clearKeys).toByteArray())
        } else {
            HttpMediaDrmCallback(drm["licenseUrl"] as? String, http).apply {
                licenseHeaders.forEach { (k, v) -> setKeyRequestProperty(k, v) }
            }
        }

        val drmManager = DefaultDrmSessionManager.Builder()
            .setUuidAndExoMediaDrmProvider(uuid, FrameworkMediaDrm.DEFAULT_PROVIDER)
            .setMultiSession(drm["multiSession"] == true)
            .build(callback)

        val item = MediaItem.Builder().setUri(url).build()

        val player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(context)
                    .setDataSourceFactory(http)
                    .setDrmSessionManagerProvider { drmManager },
            )
            .build()

        val entry = textures.createSurfaceTexture()
        val surface = Surface(entry.surfaceTexture())
        player.setVideoSurface(surface)

        val session = Session(entry.id(), entry, player, surface)
        sessions[session.id] = session
        player.addListener(listenerFor(session))

        player.setMediaItem(item)
        player.prepare()
        result.success(mapOf("id" to session.id, "textureId" to entry.id()))
    }

    private fun listenerFor(session: Session) = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) = emitState(session)
        override fun onIsPlayingChanged(isPlaying: Boolean) = emitState(session)
        override fun onVideoSizeChanged(size: VideoSize) = emitState(session)

        override fun onPlayerError(error: PlaybackException) {
            Log.e(TAG, "playback failed", error)
            // The message names the DRM cause where there is one. "Playback
            // error" on an encrypted stream is indistinguishable from a dead
            // link, and someone will retry a dead link forever.
            send(
                mapOf(
                    "id" to session.id,
                    "event" to "error",
                    "message" to (error.errorCodeName + ": " + (error.message ?: "")),
                ),
            )
        }
    }

    private fun emitState(session: Session) {
        val p = session.player
        send(
            mapOf(
                "id" to session.id,
                "event" to "state",
                "playing" to p.isPlaying,
                "buffering" to (p.playbackState == Player.STATE_BUFFERING),
                "ended" to (p.playbackState == Player.STATE_ENDED),
                "ready" to (p.playbackState != Player.STATE_IDLE),
                "position" to p.currentPosition,
                "duration" to if (p.duration == C.TIME_UNSET) 0L else p.duration,
                "buffered" to p.bufferedPosition,
                "width" to p.videoSize.width,
                "height" to p.videoSize.height,
            ),
        )
    }

    private fun send(payload: Map<String, Any?>) {
        main.post { events?.success(payload) }
    }

    /** Releases everything — the engine is going away. */
    fun dispose() {
        main.post {
            sessions.values.forEach { it.release() }
            sessions.clear()
        }
    }
}
