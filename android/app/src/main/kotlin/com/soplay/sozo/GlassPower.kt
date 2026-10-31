package com.soplay.sozo

import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * What the phone can spend on the glass (lib/core/glass/glass_power.dart):
 * whether it calls itself a low-memory phone — an Android Go phone, the one
 * kind that draws the blur in place of the refraction.
 *
 * - `read` → {lowRam}.
 *
 * Which Impeller backend draws (Vulkan or OpenGL ES) is not said here: the
 * engine picks it after its own device checks and tells no one, and the
 * renderer's shaders already handle both.
 */
class GlassPower(private val context: Context) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "read") {
            val activities = context.getSystemService(ActivityManager::class.java)
            result.success(mapOf("lowRam" to (activities?.isLowRamDevice ?: false)))
        } else {
            result.notImplemented()
        }
    }

    private companion object {
        const val CHANNEL = "soplay/glass_power"
    }
}
