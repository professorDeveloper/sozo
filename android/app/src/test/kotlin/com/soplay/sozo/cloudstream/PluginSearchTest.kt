package com.soplay.sozo.cloudstream

import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.SearchResponse
import com.lagradost.cloudstream3.SearchResponseList
import com.lagradost.cloudstream3.newMovieSearchResponse
import com.lagradost.cloudstream3.newSearchResponseList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which search overload the host asks a CloudStream plugin through.
 *
 * MovieBox (phisher98) implements only `search(query, page)`, and MainAPI's
 * one-argument `search(query)` is `throw NotImplementedError()` in library
 * 4.8 — so every MovieBox search failed with "NotImplementedError: An
 * operation is not implemented." These run against the real library MainAPI,
 * so a library bump that changes either default shows up here.
 */
class PluginSearchTest {

    /** Builds the cards; the library's builders hang off a MainAPI. */
    private object Maker : MainAPI() {
        override var name = "Maker"
    }

    private fun card(name: String): SearchResponse =
        Maker.newMovieSearchResponse(name, "https://example.test/$name")

    /** Implements only the paged overload, like MovieBox. */
    private class PagedOnly(private val pages: Map<Int, SearchResponseList>) : MainAPI() {
        override var name = "PagedOnly"
        val asked = mutableListOf<Int>()
        override suspend fun search(query: String, page: Int): SearchResponseList? {
            asked += page
            return pages[page]
        }
    }

    /** Written before paging existed: only `search(query)`. */
    private class Legacy(private val results: List<SearchResponse>?) : MainAPI() {
        override var name = "Legacy"
        var calls = 0
        override suspend fun search(query: String): List<SearchResponse>? {
            calls++
            return results
        }
    }

    @Test
    fun `the library still throws from the one-argument search of a paged-only plugin`() {
        // The precondition for the fix. If a library bump makes this default
        // delegate to the paged one, the host's choice stops mattering.
        val api = PagedOnly(emptyMap())
        val thrown = runCatching { runBlocking { api.search("hellsing") } }.exceptionOrNull()
        assertTrue("expected NotImplementedError, got $thrown", thrown is NotImplementedError)
    }

    @Test
    fun `a paged-only plugin is searched, and its own hasNext is kept`() = runBlocking {
        val api = PagedOnly(
            mapOf(
                1 to newSearchResponseList(listOf(card("Hellsing"), card("Hellsing Ultimate")), true),
                2 to newSearchResponseList(listOf(card("Hellsing: The Dawn")), false),
            ),
        )
        val first = searchPage(api, "hellsing", 1)!!
        assertEquals(listOf("Hellsing", "Hellsing Ultimate"), first.items.map { it.name })
        assertTrue(first.hasNext)

        val second = searchPage(api, "hellsing", 2)!!
        assertEquals(listOf("Hellsing: The Dawn"), second.items.map { it.name })
        assertFalse(second.hasNext)
        assertEquals(listOf(1, 2), api.asked)
    }

    @Test
    fun `a legacy plugin still answers page one, through the library default`() = runBlocking {
        val api = Legacy(listOf(card("Naruto")))
        val first = searchPage(api, "naruto", 1)!!
        assertEquals(listOf("Naruto"), first.items.map { it.name })
        // The default never claims more, so the screen offers no page two.
        assertFalse(first.hasNext)
        assertEquals(1, api.calls)
    }

    @Test
    fun `a legacy plugin is not asked for page two, which would be page one again`() = runBlocking {
        val api = Legacy(listOf(card("Naruto")))
        assertNull(searchPage(api, "naruto", 2))
        assertEquals(0, api.calls)
    }

    @Test
    fun `a legacy plugin answering null is no results, not a crash`() = runBlocking {
        assertNull(searchPage(Legacy(null), "nothing", 1))
    }

    @Test
    fun `override detection tells the two shapes apart`() {
        assertTrue(implementsPagedSearch(PagedOnly(emptyMap())))
        assertFalse(implementsPagedSearch(Legacy(emptyList())))
    }
}
