package com.soplay.sozo

import java.net.URI

/**
 * Reading an HLS playlist for a download, and writing the copy that plays
 * from disk.
 *
 * Mirrors `DownloadTransferDataSource` on the Dart side — the same best
 * rendition, the same slices, the same file names — so a folder written by
 * either downloader plays, and verifies, under the other.
 */
object HlsDownloadPlaylist {
    /**
     * The best rendition in a master playlist.
     *
     * It took whichever was listed first, and packagers list the smallest
     * first so a player can start cheap and climb — so an episode watched at
     * 1080p was saved at 360p. Same rule as the Dart side (`parseHlsVariants`):
     * the packager's own `s1080p` name, else RESOLUTION's height, bitrate to
     * break a tie.
     */
    fun pickVariantUrl(playlist: String, baseUrl: String): String? {
        val lines = playlist.lines()
        var best: String? = null
        var bestHeight = 0
        var bestBandwidth = 0L
        for (i in 0 until lines.size - 1) {
            val tag = lines[i].trim()
            if (!tag.startsWith("#EXT-X-STREAM-INF")) continue
            val uri = lines[i + 1].trim()
            if (uri.isEmpty() || uri.startsWith("#")) continue
            val height = NAMED_HEIGHT.find(uri)?.groupValues?.get(1)?.toIntOrNull()
                ?: RESOLUTION.find(tag)?.groupValues?.get(1)?.toIntOrNull()
                ?: 0
            if (height <= 0) continue
            val bandwidth = BANDWIDTH.find(tag)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
            if (height > bestHeight || (height == bestHeight && bandwidth > bestBandwidth)) {
                best = resolveUrl(uri, baseUrl)
                bestHeight = height
                bestBandwidth = bandwidth
            }
        }
        if (best != null) return best
        // No heights at all: the highest bitrate that carries a picture.
        // "First" was the smallest here too — Apple's own sample lists
        // 232 kbps ahead of 1.9 Mbps.
        var topBandwidth = 0L
        for (i in lines.indices) {
            val tag = lines[i].trim()
            if (!tag.startsWith("#EXT-X-STREAM-INF")) continue
            val codecs = CODECS.find(tag)?.groupValues?.get(1)?.lowercase()
            if (codecs != null && isAudioOnly(codecs)) continue
            val bandwidth = BANDWIDTH.find(tag)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
            val uri = lines.drop(i + 1).map { it.trim() }
                .firstOrNull { it.isNotEmpty() && !it.startsWith("#") } ?: continue
            if (bandwidth > topBandwidth) {
                best = resolveUrl(uri, baseUrl)
                topBandwidth = bandwidth
            }
        }
        if (best != null) return best
        // Nothing to rank by: the first, as before.
        for (i in lines.indices) {
            if (!lines[i].startsWith("#EXT-X-STREAM-INF")) continue
            for (j in i + 1 until lines.size) {
                val line = lines[j].trim()
                if (line.isEmpty() || line.startsWith("#")) continue
                return resolveUrl(line, baseUrl)
            }
        }
        return null
    }

    data class ByteRange(val offset: Long, val length: Long)
    data class Segment(val url: String, val range: ByteRange?)
    data class AuxEntry(val uri: String, val isMap: Boolean, val key: String, val range: ByteRange?)

    /**
     * The media segments, with their slice when the playlist uses
     * `#EXT-X-BYTERANGE`. Read as plain urls, a byte-range playlist downloaded
     * its one big file once per segment — hundreds of copies of a film.
     */
    fun parseSegments(playlist: String, baseUrl: String): List<Segment> {
        val out = ArrayList<Segment>()
        val ends = HashMap<String, Long>()
        var pending: Pair<Long, Long?>? = null
        for (raw in playlist.lines()) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("#EXT-X-BYTERANGE:")) {
                pending = byteRangeOf(line.removePrefix("#EXT-X-BYTERANGE:"))
                continue
            }
            if (line.startsWith("#")) continue
            val url = resolveUrl(line, baseUrl)
            val p = pending
            val range = if (p != null) {
                val offset = p.second ?: ends[url] ?: 0L
                ends[url] = offset + p.first
                ByteRange(offset, p.first)
            } else {
                null
            }
            pending = null
            out.add(Segment(url, range))
        }
        return out
    }

    /** `length[@offset]`. */
    private fun byteRangeOf(raw: String): Pair<Long, Long?>? {
        val m = BYTE_RANGE.find(raw) ?: return null
        val length = m.groupValues[1].toLongOrNull() ?: return null
        if (length <= 0) return null
        return length to m.groupValues[2].toLongOrNull()
    }

    private fun auxKey(uri: String, range: String?) = if (range == null) uri else "$uri#$range"

    /** Key and init-segment references, each once, in order. */
    fun auxiliaryEntries(playlist: String): List<AuxEntry> {
        val out = ArrayList<AuxEntry>()
        val seen = HashSet<String>()
        for (raw in playlist.lines()) {
            val line = raw.trim()
            val isKey = line.startsWith("#EXT-X-KEY:")
            val isMap = line.startsWith("#EXT-X-MAP:")
            if (!isKey && !isMap) continue
            if (isKey && line.contains("METHOD=NONE")) continue
            val uri = URI_ATTRIBUTE.find(line)?.groupValues?.get(1)
            if (uri.isNullOrEmpty()) continue
            val rawRange = if (isMap) BYTE_RANGE_ATTRIBUTE.find(line)?.groupValues?.get(1) else null
            val key = auxKey(uri, rawRange)
            if (!seen.add(key)) continue
            val parsed = rawRange?.let { byteRangeOf(it) }
            out.add(AuxEntry(uri, isMap, key, parsed?.let { ByteRange(it.second ?: 0L, it.first) }))
        }
        return out
    }

    fun buildLocalPlaylist(
        playlist: String,
        auxNames: Map<String, String>,
        segmentName: (Int) -> String = { "seg_$it.ts" }
    ): String {
        var index = 0
        val out = ArrayList<String>()
        for (line in playlist.lines()) {
            val trimmed = line.trim()
            when {
                trimmed.isEmpty() -> out.add(trimmed)
                // Each slice is its own file now; the range would point past its end.
                trimmed.startsWith("#EXT-X-BYTERANGE:") -> {}
                trimmed.startsWith("#") -> {
                    val range = if (trimmed.startsWith("#EXT-X-MAP:")) {
                        BYTE_RANGE_ATTRIBUTE.find(trimmed)?.groupValues?.get(1)
                    } else {
                        null
                    }
                    val uri = URI_ATTRIBUTE.find(trimmed)?.groupValues?.get(1)
                    val local = uri?.let { auxNames[auxKey(it, range)] }
                    if (local == null) {
                        out.add(trimmed)
                    } else {
                        var rewritten = URI_ATTRIBUTE.replaceFirst(trimmed, "URI=\"$local\"")
                        if (range != null) rewritten = BYTE_RANGE_ATTRIBUTE.replaceFirst(rewritten, "")
                        out.add(rewritten)
                    }
                }
                else -> out.add(segmentName(index++))
            }
        }
        return out.joinToString("\n")
    }

    fun mapExtensionOf(url: String): String {
        val path = try {
            URI(url).path?.lowercase().orEmpty()
        } catch (_: Exception) {
            url.lowercase()
        }
        return listOf(".mp4", ".m4s", ".m4v", ".cmfv", ".ts").firstOrNull { path.endsWith(it) } ?: ".mp4"
    }

    fun baseUrlOf(url: String): String =
        url.substringBeforeLast("/", missingDelimiterValue = url) + "/"

    fun resolveUrl(path: String, baseUrl: String): String {
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        return try {
            URI(baseUrl).resolve(path).toString()
        } catch (_: Exception) {
            "$baseUrl$path"
        }
    }

    const val VIDEO_PLAYLIST = "video.m3u8"
    const val AUDIO_PLAYLIST = "audio.m3u8"

    data class AudioRendition(val url: String, val mediaTag: String, val streamTag: String)

    /**
     * The audio rendition [variantUrl] plays with, when [master] gives its
     * audio a playlist of its own: the group's DEFAULT=YES track, else its
     * first. Null when the audio is inside the variant's own segments.
     */
    fun audioRendition(master: String, baseUrl: String, variantUrl: String): AudioRendition? {
        val lines = master.lines().map { it.trim() }
        var streamTag: String? = null
        for (i in lines.indices) {
            if (!lines[i].startsWith("#EXT-X-STREAM-INF")) continue
            val uri = lines.drop(i + 1).firstOrNull { it.isNotEmpty() && !it.startsWith("#") } ?: continue
            if (resolveUrl(uri, baseUrl) == variantUrl) {
                streamTag = lines[i]
                break
            }
        }
        val group = streamTag?.let { AUDIO_GROUP.find(it)?.groupValues?.get(1) } ?: return null
        var chosen: String? = null
        for (line in lines) {
            if (!line.startsWith("#EXT-X-MEDIA:") || !line.contains("TYPE=AUDIO")) continue
            if (GROUP_ID.find(line)?.groupValues?.get(1) != group) continue
            if (URI_ATTRIBUTE.find(line) == null) continue
            if (chosen == null) chosen = line
            if (line.contains("DEFAULT=YES")) {
                chosen = line
                break
            }
        }
        val media = chosen ?: return null
        val uri = URI_ATTRIBUTE.find(media)!!.groupValues[1]
        return AudioRendition(resolveUrl(uri, baseUrl), media, streamTag)
    }

    /**
     * The master written beside a video and an audio playlist: the one audio
     * track, switched on, and the one variant. References to groups that were
     * not saved (subtitles, captions, other angles) are dropped, or a player
     * looks for a group that is not there.
     */
    fun localMaster(master: String, mediaTag: String, streamTag: String): String {
        val out = StringBuilder("#EXTM3U\n")
        for (raw in master.lines()) {
            val line = raw.trim()
            if (line.startsWith("#EXT-X-VERSION") || line.startsWith("#EXT-X-INDEPENDENT-SEGMENTS")) {
                out.append(line).append('\n')
            }
        }
        var media = URI_ATTRIBUTE.replaceFirst(mediaTag, "URI=\"$AUDIO_PLAYLIST\"")
        media = if (media.contains("DEFAULT=")) {
            media.replaceFirst(Regex("DEFAULT=(YES|NO)"), "DEFAULT=YES")
        } else {
            "$media,DEFAULT=YES"
        }
        out.append(media).append('\n')
        out.append(streamTag.replace(OTHER_GROUPS, "")).append('\n')
        out.append(VIDEO_PLAYLIST).append('\n')
        return out.toString()
    }

    private val AUDIO_GROUP = Regex("AUDIO=\"([^\"]*)\"")
    private val GROUP_ID = Regex("GROUP-ID=\"([^\"]*)\"")
    private val OTHER_GROUPS = Regex(",(SUBTITLES|CLOSED-CAPTIONS|VIDEO)=(\"[^\"]*\"|[A-Z]+)")

    private val NAMED_HEIGHT = Regex("[-_/]s(\\d{3,4})p\\b")
    private val RESOLUTION = Regex("RESOLUTION=\\d+x(\\d+)")
    private val BANDWIDTH = Regex("[^-]BANDWIDTH=(\\d+)")
    private val BYTE_RANGE = Regex("^\\s*\"?(\\d+)(?:@(\\d+))?")
    private val CODECS = Regex("CODECS=\"([^\"]*)\"")

    private fun isAudioOnly(codecs: String): Boolean =
        codecs.split(',').map { it.trim() }.filter { it.isNotEmpty() }.all {
            it.startsWith("mp4a") || it.startsWith("ac-3") || it.startsWith("ec-3") ||
                it.startsWith("opus") || it.startsWith("flac")
        }

    private val URI_ATTRIBUTE = Regex("URI=\"([^\"]*)\"")
    private val BYTE_RANGE_ATTRIBUTE = Regex(",?BYTERANGE=\"([^\"]*)\"")
}
