package com.soplay.sozo.extensions

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/**
 * Fetches and normalises a Mihon / Tachiyomi / Aniyomi extension repository index.
 *
 * Repos publish the index in one of two encodings and the app must accept both:
 *
 *  - **`index.min.json`** — a plain JSON array, the format every fork shipped
 *    historically. Still used by e.g. `yuzono/anime-repo`.
 *  - **`index.pb`** — a **gzipped protobuf**, which is what Keiyoushi and
 *    `yuzono/manga-repo` publish today. `yuzono/manga-repo` has NO `index.min.json`
 *    at all and Keiyoushi's is now a two-entry "Outdated App" stub, so a
 *    JSON-only client silently installs zero (or one bogus) source from the two
 *    largest manga repos in existence. That is the whole reason this file exists.
 *
 * Both are normalised to the same JSON array so the repo managers stay format-blind:
 *
 * ```json
 * [{ "name", "pkg", "apk", "apkUrl", "iconUrl", "lang", "code", "version", "nsfw",
 *    "sources": [{ "name", "lang", "id", "baseUrl" }] }]
 * ```
 *
 * `apkUrl`/`iconUrl` are absolute when the index supplied them (protobuf always
 * does); for the JSON form they are left blank and the caller derives them from
 * the repo url, exactly as before.
 *
 * ### The protobuf schema
 *
 * There is no published `.proto`, so the wire format below was recovered by
 * decoding a live index. Field numbers are what matter; names are ours.
 *
 * ```proto
 * message RepoIndex {
 *   string name        = 1;   // "Yūzōnō"
 *   string shortName   = 2;
 *   string fingerprint = 3;   // signing-key SHA-256
 *   message Meta { string website = 1; string discord = 2; }
 *   Meta   meta        = 4;
 *   message List { repeated Extension extensions = 1; }
 *   List   list        = 101;
 * }
 * message Extension {
 *   string name       = 1;    // "AHottie"  (no "Tachiyomi: " prefix)
 *   string pkg        = 2;    // "eu.kanade.tachiyomi.extension.all.ahottie"
 *   message Urls { string apk = 1; string icon = 2; string jar = 501; }
 *   Urls   urls       = 3;
 *   string libVersion = 4;    // "1.6"
 *   uint32 versionCode= 5;    // 4
 *   string version    = 6;    // "1.6.4"  == "$libVersion.$versionCode"
 *   uint32 rating     = 7;    // 1 = safe, 2 = mixed, 3 = nsfw-only
 *   repeated Source sources = 8;
 * }
 * message Source {
 *   uint64 id      = 1;       // NOTE: numeric here, a decimal *string* in JSON
 *   string name    = 2;
 *   string lang    = 3;
 *   string baseUrl = 4;
 *   uint32 versionId = 5;     // optional
 * }
 * ```
 */
object ExtensionIndex {

    private const val TAG = "ExtensionIndex"
    private const val UA =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

    /** A repo index that could not be fetched at all (vs. one that parsed to nothing). */
    class FetchException(message: String) : Exception(message)

    /**
     * Downloads [url] and returns the normalised package array.
     *
     * Sibling fallback: if the URL is a `.min.json` that 404s or parses to an
     * obviously-stub index, the `.pb` sibling is tried, and vice versa. Repos
     * migrate between the two without changing the URL users have bookmarked.
     */
    fun fetch(url: String): JSONArray = withFingerprint(fetchIndex(url), url)

    private fun fetchIndex(url: String): JSONArray {
        val primary = runCatching { fetchOne(url) }.getOrElse {
            Log.e(TAG, "primary index failed: ${it.message}")
            null
        }
        if (primary != null && primary.length() > STUB_MAX) return primary

        val sibling = siblingUrl(url)
        if (sibling != null) {
            val alt = runCatching { fetchOne(sibling) }.getOrElse {
                Log.e(TAG, "sibling index failed: ${it.message}")
                null
            }
            // Only prefer the sibling when it is genuinely richer — a repo that
            // really does publish two entries must not be replaced by an empty one.
            if (alt != null && alt.length() > (primary?.length() ?: 0)) {
                Log.i(TAG, "using sibling index $sibling (${alt.length()} vs ${primary?.length() ?: 0})")
                return alt
            }
        }
        return primary ?: throw FetchException("index fetch failed: $url")
    }

    /**
     * Keiyoushi's legacy `index.min.json` is a 2-entry "Outdated App" placeholder.
     * Anything at or below this size is treated as "probably a stub, look for the
     * sibling" — the check is only a *hint*, the sibling still has to be bigger.
     */
    private const val STUB_MAX = 2

    private fun siblingUrl(url: String): String? {
        val clean = url.substringBefore('?')
        return when {
            clean.endsWith("index.pb", ignoreCase = true) ->
                clean.removeSuffix("index.pb") + "index.min.json"
            clean.endsWith("index.min.json", ignoreCase = true) ->
                clean.removeSuffix("index.min.json") + "index.pb"
            clean.endsWith("index.json", ignoreCase = true) ->
                clean.removeSuffix("index.json") + "index.pb"
            else -> null
        }
    }

    /**
     * Stamps the repo's signing-key fingerprint onto every package as
     * `fingerprint`, so the hosts can check each downloaded apk against it
     * ([ApkSignature]).
     *
     * The protobuf form carries the fingerprint itself (field 3). The JSON form
     * does not; Mihon-style repos publish it next to the index in `repo.json`
     * (`meta.signingKeyFingerprint`), which is fetched best-effort — a repo
     * without one installs exactly as it did before.
     */
    private fun withFingerprint(packages: JSONArray, url: String): JSONArray {
        if (packages.length() == 0) return packages
        val first = packages.optJSONObject(0)
        if (first != null && first.optString("fingerprint").isNotEmpty()) return packages
        val repoJson = url.substringBefore('?').substringBeforeLast('/') + "/repo.json"
        val fingerprint = runCatching {
            val bytes = httpGetBytes(repoJson) ?: return packages
            JSONObject(String(bytes, Charsets.UTF_8))
                .optJSONObject("meta")
                ?.optString("signingKeyFingerprint")
                .orEmpty()
        }.getOrDefault("")
        if (ApkSignature.normalize(fingerprint) == null) return packages
        for (i in 0 until packages.length()) {
            packages.optJSONObject(i)?.put("fingerprint", fingerprint)
        }
        return packages
    }

    private fun fetchOne(url: String): JSONArray {
        val raw = httpGetBytes(url) ?: throw FetchException("GET failed: $url")
        return parse(raw)
    }

    /**
     * Reads and normalises an index that already lives on disk — the
     * "Open with Sozo" path, where the file arrived through a `content://`
     * share and was copied into our cache by [RepoFileIntent].
     */
    fun parseFile(path: String): JSONArray {
        val f = java.io.File(path)
        if (!f.exists() || f.length() <= 0) throw FetchException("file missing: $path")
        return parse(f.readBytes())
    }

    /**
     * Normalises raw index bytes. Sniffs the encoding rather than trusting the
     * file extension: some mirrors serve `index.pb` un-gzipped, and CDNs
     * occasionally hand back a gzipped `.json`.
     */
    fun parse(raw: ByteArray): JSONArray {
        val bytes = if (isGzip(raw)) gunzip(raw) else raw
        if (bytes.isEmpty()) return JSONArray()

        // Skip UTF-8 BOM / whitespace before sniffing for JSON.
        var i = 0
        while (i < bytes.size && (bytes[i] == 0x20.toByte() || bytes[i] == 0x0A.toByte() ||
                    bytes[i] == 0x0D.toByte() || bytes[i] == 0x09.toByte() ||
                    bytes[i] == 0xEF.toByte() || bytes[i] == 0xBB.toByte() ||
                    bytes[i] == 0xBF.toByte())
        ) i++

        val first = if (i < bytes.size) bytes[i].toInt().toChar() else ' '
        return if (first == '[' || first == '{') {
            parseJson(String(bytes, Charsets.UTF_8))
        } else {
            parseProtobuf(bytes)
        }
    }

    private fun isGzip(b: ByteArray) =
        b.size >= 2 && b[0] == 0x1f.toByte() && b[1] == 0x8b.toByte()

    private fun gunzip(b: ByteArray): ByteArray =
        GZIPInputStream(b.inputStream()).use { it.readBytes() }

    // --- JSON form -----------------------------------------------------------

    private fun parseJson(body: String): JSONArray {
        val root = runCatching { JSONArray(body) }.getOrNull()
            ?: runCatching { JSONObject(body).optJSONArray("packages") }.getOrNull()
            ?: return JSONArray()

        val out = JSONArray()
        for (i in 0 until root.length()) {
            val pkg = root.optJSONObject(i) ?: continue
            out.put(JSONObject().apply {
                put("name", pkg.optString("name"))
                put("pkg", pkg.optString("pkg"))
                put("apk", pkg.optString("apk"))
                // Blank → caller derives "<repoBase>/apk/<apk>" as it always has.
                put("apkUrl", "")
                put("iconUrl", "")
                put("lang", pkg.optString("lang"))
                put("code", pkg.optInt("code", 0))
                put("version", pkg.optString("version"))
                put("nsfw", pkg.optInt("nsfw", 0) == 1)
                put("sources", pkg.optJSONArray("sources") ?: JSONArray())
            })
        }
        return out
    }

    // --- protobuf form -------------------------------------------------------

    private fun parseProtobuf(bytes: ByteArray): JSONArray {
        val out = JSONArray()
        var fingerprint = ""
        val reader = PbReader(bytes)
        while (reader.hasMore()) {
            val (field, wire) = reader.readTag() ?: break
            if (field == 3 && wire == 2) {
                fingerprint = reader.readString()
            } else if (field == 101 && wire == 2) {
                val listBytes = reader.readBytes()
                val listReader = PbReader(listBytes)
                while (listReader.hasMore()) {
                    val (f, w) = listReader.readTag() ?: break
                    if (f == 1 && w == 2) {
                        parseExtension(listReader.readBytes())?.let { out.put(it) }
                    } else {
                        listReader.skip(w)
                    }
                }
            } else {
                reader.skip(wire)
            }
        }
        Log.i(TAG, "protobuf index: ${out.length()} packages")
        if (fingerprint.isNotEmpty()) {
            for (i in 0 until out.length()) out.optJSONObject(i)?.put("fingerprint", fingerprint)
        }
        return out
    }

    private fun parseExtension(bytes: ByteArray): JSONObject? {
        var name = ""
        var pkg = ""
        var apkUrl = ""
        var iconUrl = ""
        var version = ""
        var code = 0
        var rating = 0
        val sources = JSONArray()

        val r = PbReader(bytes)
        while (r.hasMore()) {
            val (f, w) = r.readTag() ?: break
            when {
                f == 1 && w == 2 -> name = r.readString()
                f == 2 && w == 2 -> pkg = r.readString()
                f == 3 && w == 2 -> {
                    val u = PbReader(r.readBytes())
                    while (u.hasMore()) {
                        val (uf, uw) = u.readTag() ?: break
                        when {
                            uf == 1 && uw == 2 -> apkUrl = u.readString()
                            uf == 2 && uw == 2 -> iconUrl = u.readString()
                            else -> u.skip(uw)
                        }
                    }
                }
                f == 5 && w == 0 -> code = r.readVarint().toInt()
                f == 6 && w == 2 -> version = r.readString()
                f == 7 && w == 0 -> rating = r.readVarint().toInt()
                f == 8 && w == 2 -> parseSource(r.readBytes())?.let { sources.put(it) }
                else -> r.skip(w)
            }
        }
        if (pkg.isEmpty() && name.isEmpty()) return null

        return JSONObject().apply {
            put("name", name)
            put("pkg", pkg)
            // The protobuf carries absolute urls, so the filename is only a hint;
            // keep it for logging/cache-key purposes.
            put("apk", apkUrl.substringAfterLast('/').substringBefore('?'))
            put("apkUrl", apkUrl)
            put("iconUrl", iconUrl)
            // Extension-level lang isn't in the protobuf; "all" when the sources
            // disagree, otherwise their common language.
            put("lang", commonLang(sources))
            put("code", code)
            put("version", version)
            // 3 = adult-only. 2 means "general catalogue that also indexes adult
            // titles" (MangaDex, Comick) — Tachiyomi does not flag those nsfw
            // either, so neither do we.
            put("nsfw", rating >= 3)
            put("sources", sources)
        }
    }

    private fun parseSource(bytes: ByteArray): JSONObject? {
        var id = 0L
        var name = ""
        var lang = ""
        var baseUrl = ""
        val r = PbReader(bytes)
        while (r.hasMore()) {
            val (f, w) = r.readTag() ?: break
            when {
                f == 1 && w == 0 -> id = r.readVarint()
                f == 2 && w == 2 -> name = r.readString()
                f == 3 && w == 2 -> lang = r.readString()
                f == 4 && w == 2 -> baseUrl = r.readString()
                else -> r.skip(w)
            }
        }
        if (id == 0L) return null
        return JSONObject().apply {
            // Source ids exceed Long.MAX_VALUE's *signed* range in principle, and
            // the rest of the app keys sources by this exact decimal string, so
            // render unsigned rather than letting a negative sneak through.
            put("id", java.lang.Long.toUnsignedString(id))
            put("name", name)
            put("lang", lang)
            put("baseUrl", baseUrl)
        }
    }

    private fun commonLang(sources: JSONArray): String {
        var lang: String? = null
        for (i in 0 until sources.length()) {
            val l = sources.optJSONObject(i)?.optString("lang").orEmpty()
            if (l.isEmpty()) continue
            if (lang == null) lang = l else if (lang != l) return "all"
        }
        return lang ?: "all"
    }

    /** Minimal protobuf wire reader — enough for the index schema, nothing more. */
    private class PbReader(private val buf: ByteArray) {
        private var pos = 0

        fun hasMore() = pos < buf.size

        /** Returns `(fieldNumber, wireType)`, or null at a malformed tail. */
        fun readTag(): Pair<Int, Int>? {
            if (!hasMore()) return null
            val key = runCatching { readVarint() }.getOrElse { return null }
            return Pair((key ushr 3).toInt(), (key and 7L).toInt())
        }

        fun readVarint(): Long {
            var result = 0L
            var shift = 0
            while (pos < buf.size) {
                val b = buf[pos++].toInt()
                result = result or ((b and 0x7F).toLong() shl shift)
                if (b and 0x80 == 0) return result
                shift += 7
                if (shift > 63) throw IllegalStateException("varint overflow")
            }
            throw IllegalStateException("truncated varint")
        }

        fun readBytes(): ByteArray {
            val len = readVarint().toInt()
            if (len < 0 || pos + len > buf.size) throw IllegalStateException("truncated field")
            val out = buf.copyOfRange(pos, pos + len)
            pos += len
            return out
        }

        fun readString(): String = String(readBytes(), Charsets.UTF_8)

        fun skip(wire: Int) {
            when (wire) {
                0 -> readVarint()
                1 -> pos += 8
                2 -> readBytes()
                5 -> pos += 4
                else -> throw IllegalStateException("unsupported wire type $wire")
            }
        }
    }

    // --- transport -----------------------------------------------------------

    private fun httpGetBytes(url: String): ByteArray? = try {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = true
            connectTimeout = 20_000
            readTimeout = 30_000
            setRequestProperty("User-Agent", UA)
            // Let the server gzip if it wants; we sniff the magic bytes anyway
            // and `index.pb` is gzipped *content*, not transfer-encoding.
            setRequestProperty("Accept-Encoding", "identity")
        }
        val code = conn.responseCode
        if (code in 200..299) {
            conn.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                input.copyTo(out)
                out.toByteArray()
            }
        } else {
            Log.e(TAG, "GET $url -> $code")
            null
        }
    } catch (t: Throwable) {
        Log.e(TAG, "GET $url failed: ${t.message}")
        null
    }
}
