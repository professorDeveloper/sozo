package com.lagradost.cloudstream3.plugins

/**
 * What CloudStream records about an installed plugin.
 *
 * Plugins read `internalName` and `filePath` off these — usually to find their
 * own .cs3 on disk so they can load a resource out of it.
 */
data class PluginData(
    val internalName: String,
    val filePath: String,
)

/**
 * A stand-in for CloudStream's plugin registry. See
 * `utils/CloudStreamAppStubs.kt` for why these stubs exist at all.
 *
 * Sozo keeps its own registry in `com.soplay.sozo.cloudstream.PluginHost`, so
 * this is a facade over that rather than a second source of truth — two
 * registries disagreeing about what is installed is worse than one that a
 * plugin cannot see into.
 */
object PluginManager {

    /**
     * Filled by [PluginHostBridge] as plugins load.
     *
     * A plugin that walks this list to find its own file gets a correct answer
     * for anything already loaded, which is the case that matters: by the time
     * a plugin's own code runs, its own entry is in here.
     */
    private val installed = linkedMapOf<String, PluginData>()

    @JvmStatic
    fun getPluginsOnline(): Array<PluginData> = installed.values.toTypedArray()

    /**
     * Ignored.
     *
     * Unloading a plugin is the host's decision, not a plugin's — Sozo drops a
     * plugin's providers through `PluginHost.removeProviders` when its repo is
     * removed. Honouring this call would let one plugin unload another out from
     * under the source the viewer is currently watching.
     */
    @JvmStatic
    fun unloadPlugin(internalName: String) {
        // Deliberately empty; see above.
    }

    /** Called by the host when a .cs3 finishes loading. */
    @JvmStatic
    fun record(internalName: String, filePath: String) {
        installed[internalName] = PluginData(internalName, filePath)
    }

    /** Called by the host when a plugin's providers are dropped. */
    @JvmStatic
    fun forget(internalName: String) {
        installed.remove(internalName)
    }
}
