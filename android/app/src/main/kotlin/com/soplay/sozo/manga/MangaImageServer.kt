package com.soplay.sozo.manga

import com.soplay.sozo.ExtensionFailure

import android.util.Base64
import android.util.Log
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.runBlocking
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.util.concurrent.Executors

/**
 * Serves page images through the extension that produced them.
 *
 * ## Why the reader cannot just fetch the url
 *
 * A page's image url is not, in general, a url you can GET. What the extension
 * returns is one half of a request the extension itself completes: through
 * `imageRequest(page)` (its own headers, its own `Host`, its own `Accept`) and
 * then through its own OkHttp interceptor chain. Several sources decrypt there —
 * MangaPlus XORs the bytes against a key carried in the url FRAGMENT, which is
 * not even sent on the wire — and Cloudflare-gated sources need the cookie jar
 * the interceptor filled in.
 *
 * The reader fetched those urls directly from Dart, so none of that ran: pages
 * came back 403, or as bytes that are not an image. Both land on screen as the
 * same thing, a chapter of "Tap to reload".
 *
 * So the reader is given a local url instead. The bytes still arrive over HTTP
 * and `CachedNetworkImage` still caches them — the fetch just happens on the
 * other side of this socket, where the source object lives.
 *
 * Loopback only, and only an image the app itself put in [tokens]: an arbitrary
 * url from a request would make this an open proxy running inside the app's own
 * network identity.
 */
object MangaImageServer {

    private const val TAG = "MangaImageServer"

    private var server: ServerSocket? = null
    private val pool = Executors.newCachedThreadPool { r ->
        Thread(r, "manga-img").apply { isDaemon = true }
    }

    /** Image urls this app handed out, by source. Only these are fetchable. */
    private val allowed = HashMap<String, MutableSet<String>>()

    /** Resolves a source id to the loaded extension. Set once by [MangaHost]. */
    @Volatile
    private var resolver: ((String) -> Any?)? = null

    @Synchronized
    fun start(resolve: (String) -> Any?): Int {
        resolver = resolve
        server?.let { if (!it.isClosed) return it.localPort }
        val socket = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        server = socket
        pool.execute {
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (_: Throwable) {
                    break
                }
                pool.execute { serve(client) }
            }
        }
        Log.i(TAG, "listening on 127.0.0.1:${socket.localPort}")
        return socket.localPort
    }

    /** Records that [urls] belong to [sourceId], and returns their local urls. */
    @Synchronized
    fun publish(sourceId: String, urls: List<String>): Map<String, String> {
        val port = server?.localPort ?: return emptyMap()
        val set = allowed.getOrPut(sourceId) { LinkedHashSet() }
        // Bounded: a long reading session would otherwise grow this without end.
        if (set.size > 4000) set.clear()
        set.addAll(urls)
        val encodedSource = Base64.encodeToString(
            sourceId.toByteArray(),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        return urls.associateWith { url ->
            val encodedUrl = Base64.encodeToString(
                url.toByteArray(),
                Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
            )
            "http://127.0.0.1:$port/img?s=$encodedSource&u=$encodedUrl"
        }
    }

    @Synchronized
    private fun isAllowed(sourceId: String, url: String) =
        allowed[sourceId]?.contains(url) == true

    private fun serve(client: Socket) {
        client.use { socket ->
            socket.soTimeout = 30_000
            val input = socket.getInputStream().bufferedReader()
            val requestLine = input.readLine() ?: return
            // Headers are read and dropped: the request that matters is the one
            // the extension builds, not the one the image widget sent.
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
            }
            val out = socket.getOutputStream()
            val path = requestLine.split(' ').getOrNull(1) ?: return respond(out, 400, "bad request")
            val query = path.substringAfter('?', "")
            val params = query.split('&').mapNotNull {
                val i = it.indexOf('=')
                if (i <= 0) null else it.substring(0, i) to it.substring(i + 1)
            }.toMap()
            val sourceId = decode(params["s"]) ?: return respond(out, 400, "no source")
            val imageUrl = decode(params["u"]) ?: return respond(out, 400, "no url")
            if (!isAllowed(sourceId, imageUrl)) return respond(out, 403, "not published")

            val source = resolver?.invoke(sourceId) as? HttpSource
                ?: return respond(out, 503, "source not loaded")
            try {
                val page = Page(index = 0, url = "", imageUrl = imageUrl)
                val response = runBlocking { source.getImage(page) }
                response.use { r ->
                    val body = r.body
                    val type = body.contentType()?.toString() ?: "image/jpeg"
                    val bytes = body.bytes()
                    out.write(
                        ("HTTP/1.1 200 OK\r\n" +
                            "Content-Type: $type\r\n" +
                            "Content-Length: ${bytes.size}\r\n" +
                            "Cache-Control: no-store\r\n" +
                            "Connection: close\r\n\r\n").toByteArray(),
                    )
                    out.write(bytes)
                    out.flush()
                }
            } catch (t: Throwable) {
                Log.e(TAG, "image $imageUrl", t)
                respond(out, 502, ExtensionFailure.describe(t))
            }
        }
    }

    private fun decode(value: String?): String? = try {
        value?.let {
            String(Base64.decode(URLDecoder.decode(it, "UTF-8"), Base64.URL_SAFE))
        }?.takeIf { it.isNotEmpty() }
    } catch (_: Throwable) {
        null
    }

    private fun respond(out: OutputStream, code: Int, message: String) {
        try {
            val body = message.toByteArray()
            out.write(
                ("HTTP/1.1 $code X\r\n" +
                    "Content-Type: text/plain\r\n" +
                    "Content-Length: ${body.size}\r\n" +
                    "Connection: close\r\n\r\n").toByteArray(),
            )
            out.write(body)
            out.flush()
        } catch (_: Throwable) {
            // The reader gave up on this page; nothing to report to.
        }
    }
}
