package com.soplay.sozo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build

/**
 * Audio focus and ACTION_AUDIO_BECOMING_NOISY for the players that do not
 * handle them themselves (libmpv). Events go to [onEvent] as the wire names
 * the Dart AudioFocusPolicy reads: gain, loss, loss_transient, duck, noisy.
 */
class AudioFocusHelper(
    private val context: Context,
    private val onEvent: (String) -> Unit,
) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var hasFocus = false
    private var request: AudioFocusRequest? = null
    private var noisyReceiver: BroadcastReceiver? = null

    private val listener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasFocus = true
                onEvent("gain")
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                hasFocus = false
                onEvent("loss")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> onEvent("loss_transient")
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> onEvent("duck")
        }
    }

    fun request(): Boolean {
        if (hasFocus) return true
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = request ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                .setOnAudioFocusChangeListener(listener)
                .build()
                .also { request = it }
            audio.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        hasFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasFocus
    }

    fun abandon() {
        if (!hasFocus) return
        hasFocus = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            request?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(listener)
        }
    }

    fun watchNoisy() {
        if (noisyReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) onEvent("noisy")
            }
        }
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        noisyReceiver = receiver
    }

    fun release() {
        abandon()
        noisyReceiver?.let { runCatching { context.unregisterReceiver(it) } }
        noisyReceiver = null
    }
}
