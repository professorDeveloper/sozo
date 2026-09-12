package com.lagradost.cloudstream3.utils

import android.view.View

/**
 * Odds and ends from CloudStream's app module that plugins reach for. See
 * `CloudStreamAppStubs.kt` for why these stubs exist.
 */

object DataStoreHelper {
    /** One entry in CloudStream's "continue watching" row. */
    data class ResumeWatchingResult(
        val id: Int? = null,
        val parentId: Int? = null,
    )
}

object AppContextUtils {
    // No @JvmStatic: upstream declares these on a plain object, so plugin
    // bytecode calls them with invoke-virtual on INSTANCE. Marking them static
    // makes ART reject the call outright — IncompatibleClassChangeError, not a
    // fallback. See CommonActivity for the same lesson learned the hard way.
    /**
     * Ignored.
     *
     * CloudStream calls this to park the TV remote's focus on a given view.
     * Sozo's own focus handling is in `core/tv/`, and a plugin moving focus
     * from inside a callback would fight it — the visible result being focus
     * jumping while somebody is pressing a direction on the remote.
     */
    @JvmOverloads
    fun setDefaultFocus(view: View?, unused: Any? = null, a: Int = 0, b: Int = 0) {
        // Deliberately empty; see above.
    }
}

// AtomicMutableList used to be stubbed here. It is not any more: library v4.8.0
// ships its own, and APIHolder — the library's own code — calls
// `withLock(Function0)` on it and builds it from a List. Our version had
// neither, and two definitions of one class name means ART picks whichever
// landed in the lower-numbered dex. Ours did, so every provider would have
// died inside APIHolder.initAll with NoSuchMethodError.
