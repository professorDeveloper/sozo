package com.lagradost.cloudstream3.ui.home

import com.lagradost.cloudstream3.utils.DataStoreHelper

/**
 * A stand-in for CloudStream's home screen model. See
 * `../../utils/CloudStreamAppStubs.kt` for why these stubs exist.
 *
 * A meta plugin reads `getResumeWatching()` to build its own "continue" row.
 * It returns nothing here on purpose: Sozo's watch history lives in Hive with
 * its own schema and its own privacy rules — incognito, private lists, the
 * sign-out purge — and none of that has a counterpart a plugin could honour.
 * Handing it out through this door would route around every one of them.
 */
class HomeViewModel {
    companion object {
        @JvmStatic
        suspend fun getResumeWatching(): List<DataStoreHelper.ResumeWatchingResult> =
            emptyList()
    }
}
