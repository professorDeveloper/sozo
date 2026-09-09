package com.lagradost.cloudstream3.utils

import android.content.Context

/**
 * Stubs for the CloudStream classes that live in its APP module, not its
 * `library` artifact.
 *
 * ## Why these exist
 *
 * Sozo depends on `com.github.recloudstream.cloudstream:library`, which is the
 * plugin-facing half of CloudStream — `MainAPI`, the extractors, the data
 * types. Plugins are compiled against the whole app, so a plugin is free to
 * reference anything in it, and several popular ones do: StreamPlay reaches for
 * `MainActivity`, `PluginManager` and the AniList sync provider, none of which
 * ship in `library` and none of which Sozo has an equivalent of.
 *
 * Dalvik resolves a class the first time a code path touches it. So a plugin
 * that mentions one of these anywhere in its load path dies with
 * `NoClassDefFoundError` — and `PluginHost.loadCs3` catches every Throwable and
 * returns an empty list, so the plugin installs, registers nothing, and appears
 * nowhere. Nothing tells the viewer why. That is what "I installed StreamPlay
 * and it doesn't show up" was.
 *
 * ## What they promise
 *
 * Existence, and nothing else. Every member below no-ops or returns empty —
 * deliberately, because Sozo already has its own AniList and MyAnimeList
 * integration and must not have a plugin writing to a second one behind it.
 * A plugin that only mentions these keeps working; a plugin that depends on
 * them for its results gets nothing rather than a crash, which is the failure
 * mode a viewer can at least see past.
 *
 * The signatures were read off the plugin's own dex — the method and field
 * tables say exactly which members are referenced — rather than copied from
 * CloudStream, so what is here is what plugins actually ask for.
 */

/**
 * CloudStream's tiny event bus.
 *
 * A plugin subscribes to `afterPluginsLoadedEvent` to do work once every
 * plugin is up. Here nothing ever fires it, so a subscriber is simply never
 * called — which is correct: Sozo loads plugins one at a time on demand, so
 * there is no moment that "all plugins loaded" would describe.
 */
class Event<T> {
    private val listeners = mutableListOf<(T) -> Unit>()

    operator fun invoke(value: T) {
        // Copied before iterating: a listener that unsubscribes itself while
        // being notified is the ordinary case for a one-shot subscriber.
        listeners.toList().forEach { runCatching { it(value) } }
    }

    operator fun plusAssign(listener: (T) -> Unit) { listeners += listener }
    operator fun minusAssign(listener: (T) -> Unit) { listeners -= listener }
}

/**
 * CloudStream's localisable string.
 *
 * Plugins hold these as list titles and render them with `asString(context)`.
 */
open class UiText(private val value: String = "") {
    open fun asString(context: Context?): String = value
    override fun toString(): String = value
}

/** `txt("…")` is how plugins construct one. */
fun txt(value: String): UiText = UiText(value)
