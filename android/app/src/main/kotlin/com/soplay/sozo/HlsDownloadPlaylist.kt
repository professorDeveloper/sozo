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
        // Variants that state no height at all: the first, as before.
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

    fun buildLocalPlaylist(playlist: String, auxNames: Map<String, String>): String {
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
                else -> out.add("seg_${index++}.ts")
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

    private val NAMED_HEIGHT = Regex("[-_/]s(\\d{3,4})p\\b")
    private val RESOLUTION = Regex("RESOLUTION=\\d+x(\\d+)")
    private val BANDWIDTH = Regex("[^-]BANDWIDTH=(\\d+)")
    private val BYTE_RANGE = Regex("^\\s*\"?(\\d+)(?:@(\\d+))?")
    private val URI_ATTRIBUTE = Regex("URI=\"([^\"]*)\"")
    private val BYTE_RANGE_ATTRIBUTE = Regex(",?BYTERANGE=\"([^\"]*)\"")
}
