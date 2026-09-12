package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject
import java.io.Serializable

interface SManga : Serializable {

    var url: String

    var title: String

    var artist: String?

    var author: String?

    var description: String?

    var genre: String?

    var status: Int

    var thumbnail_url: String?

    var update_strategy: UpdateStrategy

    var initialized: Boolean

    /**
     * Scratch space an extension carries between its own parse steps.
     *
     * Added in extensions-lib 1.6 and absent from the 1.5-era models vendored
     * here. Extensions built against 1.6 call `getMemo()`/`setMemo()` from their
     * generated url, browse and details helpers, so without it those paths threw
     * NoSuchMethodError — on 22 of 40 sampled Keiyoushi extensions.
     *
     * A JsonObject, not a String, and not nullable: the type is part of the JVM
     * signature. Declaring it `String?` emitted `getMemo()Ljava/lang/String;`
     * while every extension calls `getMemo()Lkotlinx/serialization/json/JsonObject;`,
     * so adding the member changed nothing — the whole Keiyoushi "Generated"
     * family still threw, on browse and search rather than only on detail.
     */
    var memo: JsonObject

    fun getGenres(): List<String>? {
        if (genre.isNullOrBlank()) return null
        return genre?.split(", ")?.map { it.trim() }?.filterNot { it.isBlank() }?.distinct()
    }

    fun copyFrom(other: SManga) {
        if (other.author != null) {
            author = other.author
        }

        if (other.artist != null) {
            artist = other.artist
        }

        if (other.description != null) {
            description = other.description
        }

        if (other.genre != null) {
            genre = other.genre
        }

        if (other.thumbnail_url != null) {
            thumbnail_url = other.thumbnail_url
        }

        status = other.status

        update_strategy = other.update_strategy

        if (!initialized) {
            initialized = other.initialized
        }
    }

    fun copy() = create().also {
        it.url = url
        it.memo = memo
        it.title = title
        it.artist = artist
        it.author = author
        it.description = description
        it.genre = genre
        it.status = status
        it.thumbnail_url = thumbnail_url
        it.update_strategy = update_strategy
        it.initialized = initialized
    }

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6

        fun create(): SManga {
            return SMangaImpl()
        }

        private const val serialVersionUID = 1L
    }
}
