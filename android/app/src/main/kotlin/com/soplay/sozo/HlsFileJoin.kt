package com.soplay.sozo

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * One video file out of a finished HLS download.
 *
 * An HLS download is a folder: `index.m3u8` plus hundreds of segments. Saving
 * it to Downloads copied the playlist alone, so "Baththa.m3u8" arrived there at
 * 80 KB while the 655 MB film stayed in the app, and nothing could open it.
 *
 * MPEG-TS segments play one after another when joined byte for byte, and so do
 * fragmented MP4 ones behind their init section, so no remuxing is needed. What
 * joining cannot do is put a separate audio playlist into the picture's file,
 * so those are refused rather than saved silent.
 */
object HlsFileJoin {
    class Part(val file: File, val key: ByteArray?, val iv: ByteArray?)
    class Plan(val extension: String, val parts: List<Part>)

    /** Reads the local playlist. Throws, with the reason, when it cannot be one file. */
    fun plan(index: File): Plan {
        val dir = requireNotNull(index.parentFile) { "The download has no folder" }
        val lines = index.readLines().map { it.trim() }
        check(lines.none { it.startsWith("#EXT-X-STREAM-INF") }) {
            "This video keeps its sound in a separate track, so it cannot be saved as one file"
        }

        val parts = ArrayList<Part>()
        var sequence = 0L
        var key: ByteArray? = null
        var iv: ByteArray? = null
        var fragmented = false
        var lastMap: String? = null
        for (line in lines) {
            when {
                line.isEmpty() -> {}
                line.startsWith("#EXT-X-MEDIA-SEQUENCE:") ->
                    sequence = line.substringAfter(':').trim().toLongOrNull() ?: 0L
                line.startsWith("#EXT-X-KEY:") -> {
                    val method = METHOD.find(line)?.groupValues?.get(1)
                    check(method == "AES-128" || method == "NONE") {
                        "This video is protected, so it cannot be saved as one file"
                    }
                    if (method == "NONE") {
                        key = null
                        iv = null
                    } else {
                        key = keyOf(dir, line)
                        iv = IV.find(line)?.groupValues?.get(1)?.let(::hexBytes)
                    }
                }
                line.startsWith("#EXT-X-MAP:") -> {
                    val name = requireNotNull(URI_ATTRIBUTE.find(line)) {
                        "A part of the download is missing"
                    }.groupValues[1]
                    fragmented = true
                    if (name != lastMap) {
                        lastMap = name
                        // An init section under a key always names its IV.
                        parts.add(Part(existing(dir, name), key, iv))
                    }
                }
                line.startsWith("#") -> {}
                else -> {
                    parts.add(Part(existing(dir, line), key, if (key == null) null else iv ?: sequenceIv(sequence)))
                    sequence++
                }
            }
        }
        check(parts.isNotEmpty()) { "The download has no video in it" }
        return Plan(if (fragmented) ".mp4" else ".ts", parts)
    }

    fun write(plan: Plan, output: OutputStream) {
        for (part in plan.parts) {
            opened(part).use { it.copyTo(output, DEFAULT_BUFFER_SIZE) }
        }
    }

    private fun opened(part: Part): InputStream {
        val input = part.file.inputStream()
        val key = part.key ?: return input
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(part.iv ?: ByteArray(16)))
        return CipherInputStream(input, cipher)
    }

    private fun keyOf(dir: File, line: String): ByteArray {
        val name = requireNotNull(URI_ATTRIBUTE.find(line)) { "The download's key is missing" }.groupValues[1]
        val bytes = existing(dir, name).readBytes()
        check(bytes.size == 16) { "The download's key is not readable" }
        return bytes
    }

    private fun existing(dir: File, name: String): File {
        val file = File(dir, name)
        check(file.isFile) { "A part of the download is missing" }
        return file
    }

    /** With no IV named, the segment's sequence number is the IV. */
    private fun sequenceIv(sequence: Long): ByteArray =
        ByteBuffer.allocate(16).putLong(8, sequence).array()

    private fun hexBytes(hex: String): ByteArray {
        val clean = hex.padStart(32, '0')
        return ByteArray(16) { i -> clean.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    private val METHOD = Regex("METHOD=([A-Z0-9-]+)")
    private val IV = Regex("IV=0[xX]([0-9a-fA-F]+)")
    private val URI_ATTRIBUTE = Regex("URI=\"([^\"]*)\"")
}
