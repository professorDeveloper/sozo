package eu.kanade.tachiyomi.animesource.model

import java.io.Serializable

/**
 * A server offering an episode, before its individual video links are fetched.
 *
 * ## Why this exists
 *
 * Aniyomi 0.16 split video resolution in two. The old shape was one call —
 * `getVideoList(episode)` — that returned every quality from every mirror at
 * once, which meant an episode with six mirrors did six scrapes before the
 * player could show anything. The new shape returns a list of [Hoster] first
 * (cheap: names and urls) and fetches one hoster's videos only when it is
 * chosen.
 *
 * Extensions built against the newer API reference this class. Sozo did not
 * have it, so Dalvik failed to resolve it and the extension died on load —
 * silently, since the host catches and moves on. Same failure as the
 * CloudStream plugins: installed, registers nothing, appears nowhere.
 *
 * `videoList` is nullable on purpose, and that is the whole distinction: null
 * means "not fetched yet, ask the source", an empty list means "asked, and
 * this hoster has nothing".
 */
data class Hoster(
    val hosterUrl: String,
    val hosterName: String,
    val videoList: List<Video>? = null,
    val internalData: String = "",
) : Serializable {

    companion object {
        /**
         * What an extension puts in `hosterUrl` when it has no per-hoster
         * concept and returned videos directly.
         */
        const val NO_HOSTER_LIST = "no_hoster_list"

        /**
         * Wraps videos from an old-style source as a single hoster.
         *
         * Extensions call this to bridge their own old code to the new API, so
         * the name and shape have to match Aniyomi's exactly — it is invoked
         * by name from bytecode compiled elsewhere.
         */
        @JvmStatic
        fun List<Video>.toHosterList(): List<Hoster> = listOf(
            Hoster(
                hosterUrl = NO_HOSTER_LIST,
                hosterName = NO_HOSTER_LIST,
                videoList = this,
            ),
        )
    }
}

/**
 * What a paged fetch is asking for.
 *
 * Sources that expose seasons separately from episodes branch on this.
 */
enum class FetchType {
    Episodes,
    Seasons,
}
