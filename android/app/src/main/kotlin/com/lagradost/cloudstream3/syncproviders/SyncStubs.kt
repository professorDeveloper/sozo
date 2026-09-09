package com.lagradost.cloudstream3.syncproviders

import com.lagradost.cloudstream3.syncproviders.providers.AniListApi
import com.lagradost.cloudstream3.utils.UiText

/**
 * Stand-ins for CloudStream's account/sync layer. See
 * `utils/CloudStreamAppStubs.kt` for why these exist.
 *
 * Every one of them reports "nobody is signed in". That is not a placeholder
 * waiting to be filled — it is the intended answer. Sozo has its own AniList
 * and MyAnimeList integration under `lib/features/anilist` and
 * `lib/features/mal`, with its own tokens and its own list state. A plugin
 * writing progress through a second, invisible account would put a viewer's
 * list in two places that disagree, and the viewer would have no way to tell
 * which one their app was reading.
 *
 * So a plugin that offers "sync with AniList" finds no session and does
 * nothing, while everything it does for playback keeps working.
 */

/** Which service an id belongs to. */
enum class SyncIdName { Anilist, MyAnimeList, Trakt, Imdb, Tmdb, Simkl }

/** A signed-in account. Never produced here. */
data class AuthUser(
    val name: String? = null,
    val id: Int? = null,
)

open class SyncAPI {
    /** One of the viewer's lists — "Watching", "Completed", … */
    data class LibraryList(
        val name: UiText,
        val items: List<Any> = emptyList(),
    )

    /** Every list, which is how a plugin walks somebody's library. */
    data class LibraryMetadata(
        val allLibraryLists: List<LibraryList> = emptyList(),
    )
}

/**
 * Reads a service's library. Always empty, because [AuthUser] is always null.
 */
class SyncRepo(val api: Any? = null) {

    fun authUser(): AuthUser? = null

    /**
     * `Result.success(empty)` rather than a failure.
     *
     * A plugin that gets a failure here tends to surface an error to the
     * viewer — "could not load your list" — for a service Sozo never asked it
     * to read. An empty library is the truthful answer: through this plugin,
     * there is none.
     */
    suspend fun library(): Result<SyncAPI.LibraryMetadata> =
        Result.success(SyncAPI.LibraryMetadata())
}

/**
 * CloudStream's account registry.
 */
open class AccountManager {
    companion object {
        /**
         * A live object, not null: plugins call straight through
         * (`aniListApi.something()`) without a null check, so returning null
         * here trades a no-op for a NullPointerException inside the plugin.
         */
        @JvmStatic
        val aniListApi = AniListApi()
    }
}
