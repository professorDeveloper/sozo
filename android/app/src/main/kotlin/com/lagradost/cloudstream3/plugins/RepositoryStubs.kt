package com.lagradost.cloudstream3.plugins

import com.lagradost.cloudstream3.ui.settings.extensions.RepositoryData

/**
 * Stand-ins for CloudStream's repository layer. See
 * `../utils/CloudStreamAppStubs.kt` for why these stubs exist.
 *
 * These are reached by META plugins — ones that manage other plugins rather
 * than serve content — of which Ultima is the example in the phisher repo. It
 * lists the repos you have added and the plugins in them, to offer its own
 * combined view.
 *
 * They report an empty installation. Sozo keeps repositories in Hive, on the
 * Dart side (`features/extensions/data/`), and lets the viewer manage them in
 * its own Extensions screen; a plugin adding or removing repos behind that
 * would leave the app's list and the actual state disagreeing, with the app's
 * list being the one the viewer is looking at.
 */

/** One plugin as listed in a repository's plugins.json. */
data class SitePlugin(
    val internalName: String,
    val url: String,
)

/** A plugin together with the repository it came from. */
data class PluginWrapper(
    val plugin: SitePlugin,
    val repositoryData: RepositoryData,
)

object RepositoryManager {
    /**
     * Empty, not the viewer's real repositories.
     *
     * Handing a plugin the list would invite it to act on entries it cannot
     * see the state of — Sozo tracks which repos are enabled per content mode,
     * which CloudStream has no concept of.
     */
    @JvmStatic
    fun getRepositories(): Array<RepositoryData> = emptyArray()

    /** Empty for the same reason. */
    @JvmStatic
    suspend fun getRepoPlugins(repositoryUrl: String): List<PluginWrapper>? = emptyList()
}
