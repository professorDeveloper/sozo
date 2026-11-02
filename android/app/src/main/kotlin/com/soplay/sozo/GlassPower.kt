package com.soplay.sozo

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.PowerManager
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * What the phone can actually spend on the glass
 * (lib/core/glass/glass_power.dart).
 *
 * This used to answer with one thing: `ActivityManager.isLowRamDevice`. That
 * is a flag the maker sets to say the phone shipped as an Android Go phone —
 * it is not a measurement, and it is the wrong question twice over. A 2019
 * mid-range phone with 6 GB and a GPU that cannot bend a bar sixty times a
 * second does not carry the flag, drew the refraction, and dropped frames; a
 * current 4 GB phone with a Vulkan 1.1 driver does carry it on some makers'
 * builds and lost the glass for nothing.
 *
 * So what is sent is what can be read off the phone, and the decision is
 * made in Dart where it can be tested ([GlassPowerReading.affordsRefraction]):
 *
 * - `read` → everything below, once at launch.
 * - `powerSave` → the one thing that changes while the app runs is pushed to
 *   Dart as it turns.
 *
 * | key | what it is | why the glass cares |
 * |---|---|---|
 * | `lowRam` | `isLowRamDevice` | kept: a Go phone is still a Go phone |
 * | `memoryBytes` | `MemoryInfo.totalMem` | the measurement the flag stands in for |
 * | `sdk` | `Build.VERSION.SDK_INT` | Impeller's Vulkan backend starts at 29 |
 * | `vulkan11` | Vulkan 1.1 in the driver | below it Impeller draws through GL ES, where a backdrop read per glass costs far more |
 * | `glEs` | `reqGlEsVersion`, major only | a GL ES 2 driver cannot run the shader at all |
 * | `refreshHz` | the panel's rate | the frame budget the step-down measures against |
 * | `powerSave` | `isPowerSaveMode` | the user has asked this phone to spend less |
 * | `cores` | `availableProcessors` | the one cheap hint at the class of chip |
 *
 * Which Impeller backend actually draws is still not said here: the engine
 * picks it after its own device checks and tells no one. `vulkan11` says
 * what the driver offers, which is the most the engine could have chosen;
 * whether a shader filter runs at all is asked of the renderer itself, in
 * Dart (`ImageFilter.isShaderFilterSupported`).
 */
class GlassPower(private val context: Context) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var saverWatch: BroadcastReceiver? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        watchPowerSave()
    }

    fun detach() {
        saverWatch?.let {
            // Unregistering one that was never registered throws, so this is
            // only tried for the receiver we are holding.
            runCatching { context.unregisterReceiver(it) }
        }
        saverWatch = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "read") {
            result.success(reading())
        } else {
            result.notImplemented()
        }
    }

    /**
     * Battery Saver is thrown in Settings or by the phone itself as the
     * battery runs down, with the app in front or behind, so it is the one
     * reading that is pushed rather than asked for. Dart also re-asks on
     * resume, which covers a build where this broadcast does not arrive.
     */
    private fun watchPowerSave() {
        val power = context.getSystemService(PowerManager::class.java) ?: return
        val watch = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                channel?.invokeMethod("powerSave", power.isPowerSaveMode)
            }
        }
        runCatching {
            context.registerReceiver(
                watch,
                IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
            )
            saverWatch = watch
        }
    }

    private fun reading(): Map<String, Any?> {
        val activities = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo().also {
            runCatching { activities?.getMemoryInfo(it) }
        }
        // reqGlEsVersion packs the major in its high half-word; the app only
        // cares whether it is 3 or better, which is where the shader stops
        // being a question of speed and becomes a question of possible.
        val glEs = activities?.deviceConfigurationInfo?.reqGlEsVersion ?: 0
        return mapOf(
            "lowRam" to (activities?.isLowRamDevice ?: false),
            "memoryBytes" to memory.totalMem,
            "sdk" to Build.VERSION.SDK_INT,
            "vulkan11" to hasVulkan11(),
            "glEs" to (glEs shr 16),
            "refreshHz" to refreshHz(),
            "powerSave" to isPowerSaving(),
            "cores" to Runtime.getRuntime().availableProcessors(),
        )
    }

    /**
     * Vulkan 1.1 in the driver, the version Flutter's Impeller Vulkan backend
     * asks for. `hasSystemFeature` with a version compares against what the
     * driver reports, so this is the driver's own word rather than a guess
     * from the API level.
     */
    private fun hasVulkan11(): Boolean = runCatching {
        context.packageManager.hasSystemFeature(
            PackageManager.FEATURE_VULKAN_HARDWARE_VERSION,
            VULKAN_1_1,
        )
    }.getOrDefault(false)

    /**
     * The default display's rate. Null rather than a made-up 60 when there is
     * no display to ask — on a phone with no display the glass is not being
     * drawn either, and Dart treats a missing rate as sixty hertz itself.
     */
    private fun refreshHz(): Double? = runCatching {
        context.getSystemService(DisplayManager::class.java)
            ?.getDisplay(Display.DEFAULT_DISPLAY)
            ?.refreshRate
            ?.toDouble()
    }.getOrNull()

    private fun isPowerSaving(): Boolean = runCatching {
        context.getSystemService(PowerManager::class.java)?.isPowerSaveMode ?: false
    }.getOrDefault(false)

    private companion object {
        const val CHANNEL = "soplay/glass_power"

        /** Vulkan 1.1.0, as `FEATURE_VULKAN_HARDWARE_VERSION` packs it. */
        const val VULKAN_1_1 = 0x00401000
    }
}
