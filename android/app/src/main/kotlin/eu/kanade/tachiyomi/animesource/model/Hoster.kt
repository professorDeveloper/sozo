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
 * `videoList` is nullable on purpose, and that is the whole distinction: null
 * means "not fetched yet, ask the source", an empty list means "asked, and
 * this hoster has nothing".
 *
 * Not a data class, and the four-argument constructor is spelled out rather
 * than left to default arguments. Extensions are compiled against Aniyomi's
 * own build, so Dalvik resolves whatever JVM constructor signature that build
 * emitted; extensions-lib 16 shipped both `(String, String, List, String)` and
 * `(String, String, List, String, boolean)`, and a default argument would give
 * us only the second. A missing one is a NoSuchMethodError at the moment the
 * user presses play.
 */
open class Hoster(
    val hosterUrl: String = "",
    val hosterName: String = "",
    val videoList: List<Video>? = null,
    val internalData: String = "",
    val lazy: Boolean = false,
) : Serializable {

    constructor(
        hosterUrl: String,
        hosterName: String,
        videoList: List<Video>?,
        internalData: String,
    ) : this(hosterUrl, hosterName, videoList, internalData, false)

    @Transient
    @Volatile
    var status: State = State.IDLE

    enum class State {
        IDLE,
        LOADING,
        READY,
        ERROR,
    }

    fun copy(
        hosterUrl: String = this.hosterUrl,
        hosterName: String = this.hosterName,
        videoList: List<Video>? = this.videoList,
        internalData: String = this.internalData,
        lazy: Boolean = this.lazy,
    ): Hoster = Hoster(hosterUrl, hosterName, videoList, internalData, lazy)

    companion object {
        /**
         * What an extension puts in `hosterName` when it has no per-hoster
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
                hosterUrl = "",
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
