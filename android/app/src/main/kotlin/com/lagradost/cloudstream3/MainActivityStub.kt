package com.lagradost.cloudstream3

import com.lagradost.cloudstream3.utils.Event

/**
 * A stand-in for CloudStream's Activity, present only so plugins that reference
 * it can be loaded. See `utils/CloudStreamAppStubs.kt` for why.
 *
 * It is not an Activity and must never be started. Sozo's Activity is
 * `com.soplay.sozo.MainActivity`; this class shares only a name with
 * CloudStream's, in CloudStream's package, because that is the name the
 * plugins were compiled against.
 */
class MainActivity {
    companion object {
        /**
         * Never fired.
         *
         * CloudStream loads every plugin at startup and then announces it.
         * Sozo loads a plugin when somebody selects its source, so there is no
         * point at which "all plugins are loaded" is true. A plugin that only
         * subscribes here keeps working; one that waits on it to do its own
         * setup will not, and that is worth knowing rather than papering over.
         */
        @JvmStatic
        val afterPluginsLoadedEvent = Event<Boolean>()

        /**
         * Never fired either, and for the same reason: Sozo keeps its own
         * library and never announces CloudStream's. Present because a plugin
         * that subscribes to one it cannot find does not degrade — it fails to
         * link, and takes the whole provider with it.
         */
        @JvmStatic
        val bookmarksUpdatedEvent = Event<Boolean>()

        /** See [bookmarksUpdatedEvent]. */
        @JvmStatic
        val reloadLibraryEvent = Event<Boolean>()
    }
}
