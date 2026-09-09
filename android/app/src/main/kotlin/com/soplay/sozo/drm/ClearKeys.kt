package com.soplay.sozo.drm

/**
 * Turns published ClearKey material into the response ExoPlayer expects.
 *
 * ClearKey has no licence server: the keys are the licence. ExoPlayer still
 * runs the full MediaDrm handshake, so the keys have to be handed back in the
 * shape a licence server would have replied with — the EME "JSON Web Key Set"
 * from the Encrypted Media Extensions spec:
 *
 * ```json
 * {"keys":[{"kty":"oct","kid":"<base64url>","k":"<base64url>"}],"type":"temporary"}
 * ```
 *
 * Note base64**url**, unpadded. Standard base64 is rejected by the CDM without
 * a useful error — it surfaces much later as a decrypt failure on the first
 * segment, which reads as a broken stream rather than a malformed key.
 *
 * Input is hex, because hex is how these keys are published and pasted. A
 * channel list carries `kid:key` as 32 hex characters each; nobody writes them
 * base64url by hand, and asking an admin to convert is asking for a silent
 * typo in something that fails opaquely.
 */
object ClearKeys {

    /** The EME response for [keys], given as `hexKid to hexKey`. */
    fun emeJson(keys: Map<String, String>): String {
        val entries = keys.entries
            .mapNotNull { (kid, key) ->
                val k = hexToB64Url(kid) ?: return@mapNotNull null
                val v = hexToB64Url(key) ?: return@mapNotNull null
                """{"kty":"oct","kid":"$k","k":"$v"}"""
            }
        return """{"keys":[${entries.joinToString(",")}],"type":"temporary"}"""
    }

    /**
     * Hex to unpadded base64url, or null when the input is not hex.
     *
     * Null rather than a throw or a best guess: one malformed key among several
     * should cost that key, not the whole stream, and a key that was already
     * base64 must not be silently mangled into a plausible-looking wrong one.
     */
    fun hexToB64Url(hex: String): String? {
        val clean = hex.trim().removePrefix("0x").replace("-", "")
        if (clean.isEmpty() || clean.length % 2 != 0) return null
        val out = ByteArray(clean.length / 2)
        for (i in out.indices) {
            val hi = Character.digit(clean[i * 2], 16)
            val lo = Character.digit(clean[i * 2 + 1], 16)
            if (hi < 0 || lo < 0) return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return b64Url(out)
    }

    private const val ALPHABET =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    /**
     * Base64url, unpadded, written out rather than delegated.
     *
     * `android.util.Base64` would do this in one call and is a stub on the JVM,
     * so the conversion these keys depend on would have been the one thing in
     * the file with no test — and it is precisely the part that fails silently
     * when it is wrong. `java.util.Base64` is API 26 and the app ships to 24.
     * Twenty lines with a test beats either.
     */
    private fun b64Url(bytes: ByteArray): String {
        val sb = StringBuilder((bytes.size + 2) / 3 * 4)
        var i = 0
        while (i < bytes.size) {
            val remaining = bytes.size - i
            val b0 = bytes[i].toInt() and 0xFF
            val b1 = if (remaining > 1) bytes[i + 1].toInt() and 0xFF else 0
            val b2 = if (remaining > 2) bytes[i + 2].toInt() and 0xFF else 0

            sb.append(ALPHABET[b0 ushr 2])
            sb.append(ALPHABET[((b0 and 0x03) shl 4) or (b1 ushr 4)])
            // The tail is truncated, not padded: base64url as EME wants it.
            if (remaining > 1) sb.append(ALPHABET[((b1 and 0x0F) shl 2) or (b2 ushr 6)])
            if (remaining > 2) sb.append(ALPHABET[b2 and 0x3F])
            i += 3
        }
        return sb.toString()
    }
}
