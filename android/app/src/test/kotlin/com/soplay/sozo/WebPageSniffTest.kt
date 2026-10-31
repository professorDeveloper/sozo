package com.soplay.sozo

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Telling a web page from media by its first bytes. The Content-Type used to
 * decide, and disguised HLS CDNs label real video `text/html`.
 */
class WebPageSniffTest {

    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

    @Test
    fun `MPEG-TS served as page-N html is media`() {
        // vidapi's page-0.html and anikoto's seg-2-f1-v1-a1.html, as served.
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(bytes(0x47, 0x40, 0x00, 0x30, 0x10, 0x00, 0x00, 0xB0)))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(bytes(0x47, 0x40, 0x00, 0x11)))
    }

    @Test
    fun `fMP4, Matroska and images are media`() {
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage("\u0000\u0000\u0000\u0018ftypmp42".toByteArray(Charsets.ISO_8859_1)))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(bytes(0x1A, 0x45, 0xDF, 0xA3, 0x9F)))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(bytes(0xFF, 0xD8, 0xFF, 0xE0)))
        // A comic page can be an SVG; it is not a web page.
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage("<?xml version=\"1.0\"?><svg>".toByteArray()))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage("<svg xmlns=\"http://www.w3.org/2000/svg\">".toByteArray()))
    }

    @Test
    fun `encrypted segments, which are random bytes, are media`() {
        val random = Random(7)
        repeat(2000) {
            assertFalse(HlsDownloadPlaylist.looksLikeWebPage(random.nextBytes(512)))
        }
    }

    @Test
    fun `an HTML page is refused whatever it is labelled`() {
        assertTrue(HlsDownloadPlaylist.looksLikeWebPage("<!DOCTYPE html><html><head>".toByteArray()))
        assertTrue(HlsDownloadPlaylist.looksLikeWebPage("<html lang=\"en\">".toByteArray()))
        assertTrue(HlsDownloadPlaylist.looksLikeWebPage("<HEAD><TITLE>403</TITLE>".toByteArray()))
        assertTrue(HlsDownloadPlaylist.looksLikeWebPage("<script>location='/'</script>".toByteArray()))
    }

    @Test
    fun `a BOM and leading blank lines do not hide a page`() {
        val page = bytes(0xEF, 0xBB, 0xBF) + "\r\n\n  \t<!doctype html>".toByteArray()
        assertTrue(HlsDownloadPlaylist.looksLikeWebPage(page))
    }

    @Test
    fun `only the bytes read so far count`() {
        val page = "<html>".toByteArray() + ByteArray(506)
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(page, 0))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(page, 3))
        assertTrue(HlsDownloadPlaylist.looksLikeWebPage(page, 6))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage(ByteArray(0)))
        assertFalse(HlsDownloadPlaylist.looksLikeWebPage("   ".toByteArray()))
    }
}
