package com.soplay.sozo

import com.soplay.sozo.aniyomi.AniyomiHost
import com.soplay.sozo.aniyomi.AniyomiRepoManager
import com.soplay.sozo.cloudstream.PluginHost
import com.soplay.sozo.cloudstream.RepoManager
import com.soplay.sozo.manga.MangaHost
import com.soplay.sozo.manga.MangaRepoManager
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoHTTPD.IHTTPSession
import fi.iki.elonen.NanoHTTPD.Response
import fi.iki.elonen.NanoHTTPD.newFixedLengthResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray

/**
 * Local HTTP bridge that exposes the on-device CloudStream / Aniyomi / Manga
 * extension hosts over HTTP, so a **desktop** (Windows) soplay client can reach
 * the same DEX-plugin providers when this app runs on a local Android emulator
 * or a connected device. Real Android → real DexClassLoader + WebView, so every
 * `.cs3` / extension APK behaves exactly like on a phone.
 *
 * Each route mirrors a MethodChannel method 1:1 and returns the identical JSON:
 * ```
 * GET /<sys>/<method>?provider=&page=&data=&query=&url=&id=&key=&value=&type=
 * <sys> = cloudstream | aniyomi | manga
 * ```
 * Hosts are provided as suppliers so their (lazy) runtimes only spin up on the
 * first request. Debug-only: [MainActivity] starts this behind `BuildConfig.DEBUG`.
 */
class BridgeServer(
    port: Int,
    private val cs: () -> PluginHost,
    private val csRepo: () -> RepoManager,
    private val ani: () -> AniyomiHost,
    private val aniRepo: () -> AniyomiRepoManager,
    private val mn: () -> MangaHost,
    private val mnRepo: () -> MangaRepoManager,
    // Allow-list of provider ids the user chose to share, or null to share every
    // provider. Read fresh per request so toggling a source on the phone takes
    // effect on the desktop's next "Refresh" without restarting the bridge.
    private val sharedIds: () -> Set<String>? = { null },
) : NanoHTTPD("0.0.0.0", port) {

    /** Keep only the providers the user opted to share (by `id`). A null
     *  allow-list (share-all) or a parse failure passes the JSON through. */
    private fun filterProviders(json: String?): String? {
        val allow = sharedIds() ?: return json
        if (json == null) return null
        return try {
            val arr = JSONArray(json)
            val out = JSONArray()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (allow.contains(o.optString("id"))) out.put(o)
            }
            out.toString()
        } catch (_: Throwable) {
            json
        }
    }

    override fun serve(session: IHTTPSession): Response {
        return try {
            val json = runBlocking(Dispatchers.IO) { dispatch(session) }
            newFixedLengthResponse(Response.Status.OK, "application/json; charset=utf-8", json)
                .apply { addHeader("Access-Control-Allow-Origin", "*") }
        } catch (t: Throwable) {
            val msg = (t.message ?: "bridge error").replace("\"", "'")
            newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR,
                "application/json; charset=utf-8",
                "{\"error\":\"$msg\"}",
            )
        }
    }

    private suspend fun dispatch(s: IHTTPSession): String {
        val parts = s.uri.trim('/').split('/')
        if (parts.size < 2) return "{\"ok\":true,\"service\":\"sozo-bridge\"}"
        val sys = parts[0]
        val m = parts[1]
        val q = s.parameters
        fun p(k: String): String = q[k]?.firstOrNull().orEmpty()
        fun pi(k: String): Int = p(k).toIntOrNull() ?: 1

        // The caller's source-language row, `languages=fr,es`. Absent is the
        // no-preference default and collapses same-named sources exactly as
        // this always did — the TV app can adopt the parameter whenever it
        // grows a language picker of its own, and until then nothing changes
        // for it.
        fun langs(): List<String> =
            p("languages").split(',').map { it.trim() }.filter { it.isNotEmpty() }

        val out: String? = when (sys) {
            "cloudstream" -> when (m) {
                "listProviders" -> filterProviders(cs().providersJson())
                "ensureLoaded" -> { csRepo().ensureLoaded(); filterProviders(cs().providersJson()) }
                "listRepos" -> csRepo().listReposJson()
                "addRepo" -> csRepo().addRepo(p("url")) { _, _ -> }.toString()
                "removeRepo" -> csRepo().removeRepo(p("url"))
                "getGenres" -> cs().getGenresJson(p("provider"))
                "getMainPage" -> cs().getMainPageJson(p("provider"), pi("page"))
                "getSection" -> cs().getSectionJson(p("provider"), p("data"), pi("page"))
                "search" -> cs().searchJson(p("provider"), p("query"), pi("page"))
                "load" -> cs().loadJson(p("provider"), p("url"))
                "loadLinks" -> cs().loadLinksJson(p("provider"), p("data"))
                "cloudflareInfo" -> cs().cloudflareInfo(p("id"))
                else -> null
            }
            "aniyomi" -> when (m) {
                "listProviders" -> filterProviders(ani().providersJson(langs()))
                "ensureLoaded" -> { aniRepo().ensureLoaded(); filterProviders(ani().providersJson(langs())) }
                "listRepos" -> aniRepo().listReposJson()
                "addRepo" -> aniRepo().addRepo(p("url")) { _, _ -> }.toString()
                "removeRepo" -> aniRepo().removeRepo(p("url"))
                "getGenres" -> ani().getGenresJson(p("provider"))
                "getMainPage" -> ani().getMainPageJson(p("provider"), pi("page"))
                "getSection" -> ani().getSectionJson(p("provider"), p("data"), pi("page"))
                "search" -> ani().searchJson(p("provider"), p("query"), pi("page"))
                "load" -> ani().loadJson(p("provider"), p("url"))
                "loadLinks" -> ani().loadLinksJson(p("provider"), p("data"))
                "cloudflareInfo" -> ani().cloudflareInfo(p("id"))
                else -> null
            }
            "manga" -> when (m) {
                "listProviders" -> filterProviders(mn().providersJson(langs()))
                "ensureLoaded" -> { mnRepo().ensureLoaded(); filterProviders(mn().providersJson(langs())) }
                "listRepos" -> mnRepo().listReposJson()
                "addRepo" -> mnRepo().addRepo(p("url")) { _, _ -> }.toString()
                "removeRepo" -> mnRepo().removeRepo(p("url"))
                "getGenres" -> mn().getGenresJson(p("provider"))
                "getMainPage" -> mn().getMainPageJson(p("provider"), pi("page"))
                "getSection" -> mn().getSectionJson(p("provider"), p("data"), pi("page"))
                "search" -> mn().searchJson(p("provider"), p("query"), pi("page"))
                "load" -> mn().loadJson(p("provider"), p("url"))
                "pageList" -> mn().pageListJson(p("provider"), p("data"))
                "getPreferences" -> mn().getPrefsJson(p("provider"))
                "setPreference" -> mn().setPrefJson(p("provider"), p("key"), p("value"), p("type"))
                "cloudflareInfo" -> mn().cloudflareInfo(p("id"))
                else -> null
            }
            else -> null
        }
        return out ?: "{\"error\":\"unknown route: /$sys/$m\"}"
    }
}
