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
    /**
     * Ignored.
     *
     * CloudStream calls this to park the TV remote's focus on a given view.
     * Sozo's own focus handling is in `core/tv/`, and a plugin moving focus
     * from inside a callback would fight it — the visible result being focus
     * jumping while somebody is pressing a direction on the remote.
     */
    @JvmStatic
    @JvmOverloads
    fun setDefaultFocus(view: View?, unused: Any? = null, a: Int = 0, b: Int = 0) {
        // Deliberately empty; see above.
    }
}

/**
 * CloudStream's thread-safe list.
 *
 * Backed by a synchronized list rather than being a no-op: a plugin that adds
 * to one expects to read back what it added, and returning an always-empty
 * collection would be a silent wrong answer rather than a missing feature.
 */
class AtomicMutableList<T>(
    initial: Collection<T> = emptyList(),
) : MutableList<T> by java.util.Collections.synchronizedList(ArrayList(initial))
