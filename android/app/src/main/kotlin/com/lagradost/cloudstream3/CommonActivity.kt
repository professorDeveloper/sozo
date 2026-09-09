package com.lagradost.cloudstream3

import android.app.Activity
import android.util.DisplayMetrics
import android.view.KeyEvent
import android.widget.Toast

/**
 * Clean-room stand-in for CloudStream's app-module `CommonActivity`.
 *
 * Plugins are compiled against CloudStream's APP module, not just the `library`
 * artifact we embed, and this is by a wide margin the app-module class they
 * reach for most. Scanning the dex of all 79 plugins in the Phisher repo — the
 * repo this app ships as a recommended source — 16 of them reference
 * `Lcom/lagradost/cloudstream3/CommonActivity;`, and for 11 it is the *only*
 * class they need that we did not provide. Without it those plugins die at link
 * time with `NoClassDefFoundError` and the source just looks broken, usually as
 * an empty home page rather than as an error.
 *
 * The Android TV app hit this first and vendored the same class; this is the
 * mobile counterpart, differing only in where it gets the foreground activity.
 *
 * An `object`, because plugin bytecode calls `CommonActivity.INSTANCE.getActivity()`.
 *
 * [activity] delegates to [CloudStreamApp.currentActivity] rather than keeping a
 * reference of its own, so there is one source of truth for the resumed activity
 * and not a second copy to get out of date.
 *
 * Deliberately NOT provided, because each drags in machinery this app does not
 * have: `getCastSession` (Google Cast) and the `UiText` overloads
 * (cloudstream3.ui.result.UiText). A plugin needing those will still fail to
 * link — the same way [plugins.Plugin] documents its own omission — and that is
 * a smaller failure than pretending to support casting.
 */
object CommonActivity {

    /** The resumed activity, or null while none is. */
    @JvmStatic
    var activity: Activity?
        get() = CloudStreamApp.currentActivity
        set(_) {
            // One source of truth: the lifecycle callbacks CloudStreamApp
            // registers. Plugins that assign here are telling us what we know.
        }

    /** Upstream signature. A no-op for the same reason the setter above is. */
    @JvmStatic
    fun setActivityInstance(newActivity: Activity?) = Unit

    /** Key events upstream routes to the player; nothing here consumes them yet. */
    @JvmStatic
    var keyEventListener: ((Pair<KeyEvent?, Boolean>) -> Boolean)? = null

    @JvmStatic
    var isInPIPMode: Boolean = false

    @JvmStatic
    var isPipDesired: Boolean = false

    @JvmStatic
    fun showToast(message: String?, duration: Int? = null) =
        showToast(activity, message, duration)

    @JvmStatic
    fun showToast(act: Activity?, message: String?, duration: Int? = null) {
        val text = message?.takeIf { it.isNotBlank() } ?: return
        val host = act ?: activity ?: return
        host.runOnUiThread {
            Toast.makeText(host, text, duration ?: Toast.LENGTH_SHORT).show()
        }
    }

    @JvmStatic
    val displayMetrics: DisplayMetrics?
        get() = CloudStreamApp.context?.resources?.displayMetrics

    @JvmStatic
    val screenWidth: Int
        get() = displayMetrics?.widthPixels ?: 0

    @JvmStatic
    val screenHeight: Int
        get() = displayMetrics?.heightPixels ?: 0
}
