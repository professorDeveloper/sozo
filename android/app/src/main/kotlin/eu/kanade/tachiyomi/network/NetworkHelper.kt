package eu.kanade.tachiyomi.network

import android.content.Context
import android.webkit.WebSettings
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import okhttp3.Cache
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

class NetworkHelper(context: Context) {

    init {
        // Resolve the real WebView user agent once, before the client is built.
        resolveDefaultUserAgent(context)
    }

    val cookieJar = AndroidCookieJar()

    val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.MINUTES)
        .cache(
            Cache(
                directory = File(context.cacheDir, "aniyomi_network_cache"),
                maxSize = 5L * 1024 * 1024,
            ),
        )
        .addInterceptor(UncaughtExceptionInterceptor())
        .addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider))
        // No IgnoreGzipInterceptor here, deliberately.
        //
        // [IgnoreGzipInterceptor] exists for an EXTENSION to install right
        // before its own BrotliInterceptor; Mihon's own default client does not
        // carry it. Ours did, and it cost twice over. MangaDex asserts the
        // default client is clean — `check(interceptors.none { it is
        // IgnoreGzipInterceptor })` — so building its client threw
        // IllegalStateException and the source failed on every call, popular,
        // latest and search alike. And for every other source it stripped
        // `Accept-Encoding: gzip` while nothing downstream decoded Brotli, so
        // each page came back uncompressed.
        .addInterceptor(CloudflareInterceptor(context, cookieJar, ::defaultUserAgentProvider))
        .build()

    val downloadClient = client.newBuilder().callTimeout(20, TimeUnit.MINUTES).build()

    @Deprecated("The regular client handles Cloudflare by default")
    @Suppress("UNUSED")
    val cloudflareClient: OkHttpClient = client

    companion object {
        /**
         * Fallback only. Cloudflare fingerprints the browser (TLS, JS environment)
         * and compares it against the claimed user agent, so a hardcoded string
         * that no longer matches any real Chrome is exactly what makes the
         * challenge unsolvable — the WebView solves it, the cookie is issued for
         * the real agent, and the OkHttp request then presents a different one.
         * Kept only for the window before [resolveDefaultUserAgent] runs.
         */
        private const val FALLBACK_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

        @Volatile
        private var resolvedUserAgent: String? = null

        /**
         * Adopt the device's own WebView user agent, minus the "; wv" token that
         * marks an embedded WebView and is itself a bot signal. This is what makes
         * the OkHttp request and the WebView that solved the challenge look like
         * the same client, which is the whole point — cf_clearance is bound to the
         * agent it was issued for.
         */
        fun resolveDefaultUserAgent(context: Context) {
            if (resolvedUserAgent != null) return
            resolvedUserAgent = try {
                WebSettings.getDefaultUserAgent(context)
                    .replace("; wv", "")
                    .replace(Regex("\\s+"), " ")
                    .trim()
                    .takeIf { it.isNotBlank() }
            } catch (_: Throwable) {
                // getDefaultUserAgent needs a usable WebView; on a device where it
                // is missing or updating this throws. Fall back rather than crash.
                null
            }
        }

        fun defaultUserAgentProvider(): String = resolvedUserAgent ?: FALLBACK_USER_AGENT
    }
}
