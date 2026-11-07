package com.soplay.sozo

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.file.Files
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** Saving an HLS download out of the app used to copy only its playlist. */
class HlsFileJoinTest {
    private val dir: File = Files.createTempDirectory("join").toFile()

    private fun index(text: String): File = File(dir, "index.m3u8").apply { writeText(text.trimIndent()) }

    private fun joined(plan: HlsFileJoin.Plan): ByteArray =
        ByteArrayOutputStream().also { HlsFileJoin.write(plan, it) }.toByteArray()

    private fun encrypted(plain: ByteArray, key: ByteArray, iv: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return cipher.doFinal(plain)
    }

    @Test
    fun `plain segments join in playlist order as ts`() {
        File(dir, "seg_0.ts").writeBytes(byteArrayOf(1, 2))
        File(dir, "seg_1.ts").writeBytes(byteArrayOf(3))
        val plan = HlsFileJoin.plan(
            index(
                """
                #EXTM3U
                #EXTINF:10,
                seg_0.ts
                #EXTINF:10,
                seg_1.ts
                #EXT-X-ENDLIST
                """,
            ),
        )
        assertEquals(".ts", plan.extension)
        assertArrayEquals(byteArrayOf(1, 2, 3), joined(plan))
    }

    @Test
    fun `aes-128 is decrypted, the iv coming from the sequence number when none is named`() {
        val key = ByteArray(16) { it.toByte() }
        File(dir, "key.bin").writeBytes(key)
        val iv = ByteBuffer.allocate(16).putLong(8, 7L).array()
        File(dir, "seg_0.ts").writeBytes(encrypted(byteArrayOf(9, 8, 7), key, iv))
        val explicit = ByteArray(16).also { it[15] = 5 }
        File(dir, "seg_1.ts").writeBytes(encrypted(byteArrayOf(6), key, explicit))
        val plan = HlsFileJoin.plan(
            index(
                """
                #EXTM3U
                #EXT-X-MEDIA-SEQUENCE:7
                #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
                seg_0.ts
                #EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x00000000000000000000000000000005
                seg_1.ts
                """,
            ),
        )
        assertArrayEquals(byteArrayOf(9, 8, 7, 6), joined(plan))
    }

    @Test
    fun `fragmented mp4 starts with its init section, once`() {
        File(dir, "init.mp4").writeBytes(byteArrayOf(0))
        File(dir, "seg_0.m4s").writeBytes(byteArrayOf(1))
        File(dir, "seg_1.m4s").writeBytes(byteArrayOf(2))
        val plan = HlsFileJoin.plan(
            index(
                """
                #EXTM3U
                #EXT-X-MAP:URI="init.mp4"
                seg_0.m4s
                #EXT-X-MAP:URI="init.mp4"
                seg_1.m4s
                """,
            ),
        )
        assertEquals(".mp4", plan.extension)
        assertArrayEquals(byteArrayOf(0, 1, 2), joined(plan))
    }

    @Test(expected = IllegalStateException::class)
    fun `refuses a separate audio track, which would come out silent`() {
        HlsFileJoin.plan(index("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nvideo.m3u8"))
    }

    @Test(expected = IllegalStateException::class)
    fun `refuses a download missing a segment`() {
        HlsFileJoin.plan(index("#EXTM3U\nseg_missing.ts"))
    }

    @Test(expected = IllegalStateException::class)
    fun `refuses sample-aes, which the file would still be encrypted with`() {
        HlsFileJoin.plan(index("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"k\"\nseg_0.ts"))
    }
}
