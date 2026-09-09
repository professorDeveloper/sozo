package com.soplay.sozo.drm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The conversion these tests cover fails silently when it is wrong: a
 * mis-encoded key is accepted by the CDM and surfaces much later as a decrypt
 * failure on the first segment, which reads as a broken stream rather than a
 * bad key.
 */
class ClearKeysTest {

    @Test
    fun `hex becomes unpadded base64url`() {
        // 0x00112233445566778899aabbccddeeff. Standard base64 would end "/w=="
        // here; base64url has no '/' and no padding, and the CDM rejects the
        // other spelling without saying why.
        val out = ClearKeys.hexToB64Url("00112233445566778899aabbccddeeff")!!
        assertEquals("ABEiM0RVZneImaq7zN3u_w", out)
        assertTrue("no padding", !out.contains("="))
        assertTrue("no plus", !out.contains("+"))
        assertTrue("no slash", !out.contains("/"))
    }

    @Test
    fun `case and common decoration are tolerated`() {
        val plain = ClearKeys.hexToB64Url("00112233445566778899aabbccddeeff")
        assertEquals(plain, ClearKeys.hexToB64Url("00112233445566778899AABBCCDDEEFF"))
        assertEquals(plain, ClearKeys.hexToB64Url("  00112233445566778899aabbccddeeff  "))
        assertEquals(plain, ClearKeys.hexToB64Url("0x00112233445566778899aabbccddeeff"))
        assertEquals(
            plain,
            ClearKeys.hexToB64Url("00112233-4455-6677-8899-aabbccddeeff"),
        )
    }

    @Test
    fun `input that is not hex is refused rather than mangled`() {
        // Null rather than a best guess: a key that was already base64 must not
        // be silently turned into a plausible-looking wrong one.
        assertNull(ClearKeys.hexToB64Url("ABEiM0RVZneImaq7zN3u_w"))
        assertNull(ClearKeys.hexToB64Url("zzzz"))
        assertNull(ClearKeys.hexToB64Url("abc"))
        assertNull(ClearKeys.hexToB64Url(""))
    }

    @Test
    fun `the EME response has the shape the CDM expects`() {
        val json = ClearKeys.emeJson(
            mapOf("00112233445566778899aabbccddeeff" to "ffeeddccbbaa99887766554433221100"),
        )
        assertEquals(
            """{"keys":[{"kty":"oct","kid":"ABEiM0RVZneImaq7zN3u_w","k":"_-7dzLuqmYh3ZlVEMyIRAA"}],"type":"temporary"}""",
            json,
        )
    }

    @Test
    fun `several keys all appear`() {
        val json = ClearKeys.emeJson(
            linkedMapOf(
                "00000000000000000000000000000001" to "00000000000000000000000000000002",
                "00000000000000000000000000000003" to "00000000000000000000000000000004",
            ),
        )
        assertEquals(2, json.split("\"kty\"").size - 1)
    }

    @Test
    fun `one bad key costs that key, not the stream`() {
        // A channel with two keys where an admin fat-fingered one should still
        // decrypt whatever the good key covers, rather than failing outright.
        val json = ClearKeys.emeJson(
            linkedMapOf(
                "00112233445566778899aabbccddeeff" to "ffeeddccbbaa99887766554433221100",
                "not-hex" to "also-not-hex",
            ),
        )
        assertEquals(1, json.split("\"kty\"").size - 1)
        assertTrue(json.contains("ABEiM0RVZneImaq7zN3u_w"))
    }

    @Test
    fun `no keys still produces valid json`() {
        // Never a malformed body: ExoPlayer parses this, and a JSON error is a
        // crash where an empty key set is a clean "cannot decrypt".
        assertEquals("""{"keys":[],"type":"temporary"}""", ClearKeys.emeJson(emptyMap()))
    }
}
