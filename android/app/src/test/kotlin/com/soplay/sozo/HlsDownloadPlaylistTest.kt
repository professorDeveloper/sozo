package com.soplay.sozo

import com.soplay.sozo.HlsDownloadPlaylist.ByteRange
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the Android downloader reads out of a playlist. Every case here was a
 * download that finished and then would not play, or was the wrong copy.
 */
class HlsDownloadPlaylistTest {

    private val base = "https://cdn.test/v/"

    @Test
    fun `the best rendition, not the first one listed`() {
        val master = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360
            360.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
            1080.m3u8
            #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=9000000,BANDWIDTH=2500000,RESOLUTION=1280x720
            720.m3u8
        """.trimIndent()
        assertEquals("${base}1080.m3u8", HlsDownloadPlaylist.pickVariantUrl(master, base))
    }

    @Test
    fun `the packager's name beats a letterboxed resolution`() {
        val master = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x800
            index-s1080p-v1-a1.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x960
            index-s960p-v1-a1.m3u8
        """.trimIndent()
        assertEquals(
            "${base}index-s1080p-v1-a1.m3u8",
            HlsDownloadPlaylist.pickVariantUrl(master, base)
        )
    }

    @Test
    fun `without heights, the highest bitrate that has a picture`() {
        val master = """
            #EXTM3U
            #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=232370,CODECS="mp4a.40.2, avc1.4d4015"
            gear1/prog_index.m3u8
            #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1927833,CODECS="mp4a.40.2, avc1.4d401f"
            gear4/prog_index.m3u8
            #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=9000000,CODECS="mp4a.40.2"
            audio/prog_index.m3u8
        """.trimIndent()
        assertEquals("${base}gear4/prog_index.m3u8", HlsDownloadPlaylist.pickVariantUrl(master, base))
    }

    @Test
    fun `byte ranges become slices that continue from the last one`() {
        val playlist = """
            #EXTM3U
            #EXT-X-MAP:URI="main.mp4",BYTERANGE="700@0"
            #EXTINF:4,
            #EXT-X-BYTERANGE:1000@700
            main.mp4
            #EXTINF:4,
            #EXT-X-BYTERANGE:500
            main.mp4
            #EXTINF:4,
            other.ts
        """.trimIndent()
        val segments = HlsDownloadPlaylist.parseSegments(playlist, base)
        assertEquals(3, segments.size)
        assertEquals(ByteRange(700, 1000), segments[0].range)
        assertEquals(ByteRange(1700, 500), segments[1].range)
        assertNull(segments[2].range)
        assertEquals("${base}other.ts", segments[2].url)

        val aux = HlsDownloadPlaylist.auxiliaryEntries(playlist)
        assertEquals(1, aux.size)
        assertTrue(aux[0].isMap)
        assertEquals(ByteRange(0, 700), aux[0].range)

        val local = HlsDownloadPlaylist.buildLocalPlaylist(playlist, mapOf(aux[0].key to "init_0.mp4"))
        assertFalse(local.contains("BYTERANGE"))
        assertTrue(local.contains("#EXT-X-MAP:URI=\"init_0.mp4\""))
        assertTrue(local.contains("seg_0.ts"))
        assertTrue(local.contains("seg_2.ts"))
    }

    @Test
    fun `keys are saved beside the segments, and NONE is not a key`() {
        val playlist = """
            #EXTM3U
            #EXT-X-KEY:METHOD=AES-128,URI="https://keys.test/k1",IV=0x1
            #EXTINF:4,
            a.ts
            #EXT-X-KEY:METHOD=NONE
            #EXTINF:4,
            b.ts
        """.trimIndent()
        val aux = HlsDownloadPlaylist.auxiliaryEntries(playlist)
        assertEquals(listOf("https://keys.test/k1"), aux.map { it.uri })
        val local = HlsDownloadPlaylist.buildLocalPlaylist(playlist, mapOf(aux[0].key to "key_0.bin"))
        assertTrue(local.contains("#EXT-X-KEY:METHOD=AES-128,URI=\"key_0.bin\",IV=0x1"))
        assertTrue(local.contains("#EXT-X-KEY:METHOD=NONE"))
    }
}
