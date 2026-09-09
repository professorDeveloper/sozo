package com.lagradost

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The contract CloudStream plugins compile against.
 *
 * ## Why this test exists
 *
 * Sozo depends on `recloudstream:library`, the plugin-facing half of
 * CloudStream. Plugins are built against the whole APP, so they freely
 * reference classes that live only in CloudStream's application module —
 * `MainActivity`, `PluginManager`, the AniList sync provider. Those are
 * stubbed under `com.lagradost.cloudstream3` so the references resolve.
 *
 * When one is missing, nothing says so. Dalvik resolves a class on first
 * touch, `PluginHost.loadCs3` catches every Throwable, and the result is a
 * plugin that installs, registers no providers and appears nowhere. That is
 * how StreamPlay — the largest extension in the phisher repo — was silently
 * dead: twenty-four classes it referenced did not exist here.
 *
 * Every name and signature below was read off the plugins' own dex files
 * (their method and field tables list exactly what they reference), across all
 * eighty extensions in that repo. So this is not a guess at a useful API — it
 * is the set those plugins actually call. Deleting a member because it "looks
 * unused" breaks plugin loading with no compile error and no test failure
 * anywhere else, which is what this file is here to prevent.
 *
 * Reflection rather than direct calls on purpose: the point is that the member
 * EXISTS under the exact name a plugin will look it up by, which a direct call
 * would not prove for anything Kotlin renames.
 */
class CloudStreamStubContractTest {

    private fun clazz(name: String): Class<*> =
        try {
            Class.forName(name)
        } catch (e: ClassNotFoundException) {
            throw AssertionError("Plugins reference $name — it must exist", e)
        }

    private fun requireMethod(name: String, method: String, vararg params: Class<*>) {
        val c = clazz(name)
        val found = c.methods.any { it.name == method } ||
            c.declaredMethods.any { it.name == method }
        assertTrue("$name must expose $method()", found)
    }

    private fun requireField(name: String, field: String) {
        val c = clazz(name)
        val found = c.fields.any { it.name == field } ||
            c.declaredFields.any { it.name == field }
        assertTrue("$name must expose the field $field", found)
    }

    // ---------------------------------------------------------------- app --

    @Test
    fun `MainActivity exposes the after-plugins-loaded event`() {
        // StreamPlay and several others subscribe to this during load(). A
        // missing MainActivity takes the whole plugin down with it.
        // The dex shows `MainActivity.Companion` as a FIELD on MainActivity —
        // which is how Kotlin compiles a companion object — and the getter on
        // the Companion type. Asserting an INSTANCE field here was wrong about
        // Kotlin, not about the stub.
        requireField("com.lagradost.cloudstream3.MainActivity", "Companion")
        requireMethod(
            "com.lagradost.cloudstream3.MainActivity\$Companion",
            "getAfterPluginsLoadedEvent",
        )
    }

    @Test
    fun `Event can be invoked and subscribed to`() {
        val c = clazz("com.lagradost.cloudstream3.utils.Event")
        assertTrue("Event must be invokable", c.methods.any { it.name == "invoke" })
        assertTrue(
            "plugins subscribe with += ",
            c.methods.any { it.name == "plusAssign" },
        )
    }

    @Test
    fun `UiText renders to a String`() {
        requireMethod("com.lagradost.cloudstream3.utils.UiText", "asString")
    }

    // ------------------------------------------------------------ plugins --

    @Test
    fun `PluginManager exposes the online plugin list`() {
        requireField("com.lagradost.cloudstream3.plugins.PluginManager", "INSTANCE")
        requireMethod("com.lagradost.cloudstream3.plugins.PluginManager", "getPluginsOnline")
        requireMethod("com.lagradost.cloudstream3.plugins.PluginManager", "unloadPlugin")
    }

    @Test
    fun `PluginData carries the two fields plugins read`() {
        // A plugin uses these to find its own .cs3 on disk and load a resource
        // out of it.
        requireMethod("com.lagradost.cloudstream3.plugins.PluginData", "getInternalName")
        requireMethod("com.lagradost.cloudstream3.plugins.PluginData", "getFilePath")
    }

    @Test
    fun `the repository types meta plugins walk are present`() {
        requireField("com.lagradost.cloudstream3.plugins.RepositoryManager", "INSTANCE")
        requireMethod("com.lagradost.cloudstream3.plugins.RepositoryManager", "getRepositories")
        requireMethod("com.lagradost.cloudstream3.plugins.SitePlugin", "getInternalName")
        requireMethod("com.lagradost.cloudstream3.plugins.SitePlugin", "getUrl")
        requireMethod("com.lagradost.cloudstream3.plugins.PluginWrapper", "getPlugin")
        requireMethod("com.lagradost.cloudstream3.plugins.PluginWrapper", "getRepositoryData")
        requireMethod(
            "com.lagradost.cloudstream3.ui.settings.extensions.RepositoryData", "getUrl",
        )
    }

    // ------------------------------------------------------- syncproviders --

    @Test
    fun `AccountManager hands out a non-null AniList client`() {
        // Plugins call straight through without a null check, so a null here
        // trades a no-op for a NullPointerException inside the plugin.
        requireMethod(
            "com.lagradost.cloudstream3.syncproviders.AccountManager\$Companion",
            "getAniListApi",
        )
        val companion = clazz("com.lagradost.cloudstream3.syncproviders.AccountManager\$Companion")
        val instance = clazz("com.lagradost.cloudstream3.syncproviders.AccountManager")
            .getField("Companion").get(null)
        val api = companion.getMethod("getAniListApi").invoke(instance)
        assertNotNull("aniListApi must never be null", api)
    }

    @Test
    fun `the sync library types are present`() {
        requireMethod("com.lagradost.cloudstream3.syncproviders.SyncRepo", "authUser")
        requireMethod(
            "com.lagradost.cloudstream3.syncproviders.SyncAPI\$LibraryList", "getItems",
        )
        requireMethod(
            "com.lagradost.cloudstream3.syncproviders.SyncAPI\$LibraryList", "getName",
        )
        requireMethod(
            "com.lagradost.cloudstream3.syncproviders.SyncAPI\$LibraryMetadata",
            "getAllLibraryLists",
        )
        for (name in listOf("Anilist", "MyAnimeList", "Trakt")) {
            requireField("com.lagradost.cloudstream3.syncproviders.SyncIdName", name)
        }
    }

    @Test
    fun `the AniList response shapes plugins destructure are present`() {
        val base = "com.lagradost.cloudstream3.syncproviders.providers.AniListApi"
        // Both title shapes: AniList returns `title` under two schemas
        // depending on the query, and missing either one is as fatal as
        // missing all of them.
        requireMethod("$base\$MediaTitle", "getRomaji")
        requireMethod("$base\$MediaTitle", "getEnglish")
        requireMethod("$base\$Title", "getRomaji")
        requireMethod("$base\$Title", "getEnglish")

        requireMethod("$base\$CoverImage", "getMedium")
        requireMethod("$base\$CoverImage", "getLarge")
        requireMethod("$base\$CoverImage", "getExtraLarge")
        requireMethod("$base\$MediaCoverImage", "getLarge")
        requireMethod("$base\$RecommendedMedia", "getId")
        requireMethod("$base\$RecommendedMedia", "getTitle")
        requireMethod("$base\$RecommendedMedia", "getCoverImage")
        requireMethod("$base\$Recommendation", "getMediaRecommendation")
        requireMethod("$base\$RecommendationEdge", "getNode")
        requireMethod("$base\$RecommendationConnection", "getEdges")
        requireMethod("$base\$LikePageInfo", "getHasNextPage")
        requireMethod("$base\$SeasonNextAiringEpisode", "getEpisode")
    }

    // -------------------------------------------------------------- utils --

    @Test
    fun `the odds and ends meta plugins reach for are present`() {
        requireField("com.lagradost.cloudstream3.utils.AppContextUtils", "INSTANCE")
        requireMethod("com.lagradost.cloudstream3.utils.AppContextUtils", "setDefaultFocus")
        requireMethod(
            "com.lagradost.cloudstream3.utils.DataStoreHelper\$ResumeWatchingResult", "getId",
        )
        requireMethod(
            "com.lagradost.cloudstream3.utils.DataStoreHelper\$ResumeWatchingResult",
            "getParentId",
        )
        requireField("com.lagradost.cloudstream3.ui.home.HomeViewModel", "Companion")
        requireMethod(
            "com.lagradost.cloudstream3.ui.home.HomeViewModel\$Companion", "getResumeWatching",
        )
    }

    @Test
    fun `AtomicMutableList actually stores what is added to it`() {
        // A no-op collection would be a silent wrong answer rather than a
        // missing feature — a plugin adds to one and expects to read it back.
        @Suppress("UNCHECKED_CAST")
        val list = clazz("com.lagradost.cloudstream3.utils.AtomicMutableList")
            .getDeclaredConstructor(Collection::class.java)
            .newInstance(emptyList<String>()) as MutableList<String>
        list.add("x")
        assertTrue("AtomicMutableList must retain its contents", list.contains("x"))
    }
}
