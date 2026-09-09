package com.soplay.sozo

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File

/**
 * Copies a finished download out of the app's private storage and into the
 * device's shared Downloads folder.
 *
 * ## Why this exists
 *
 * Everything Sozo downloads lands under `getExternalFilesDir` — app-private
 * storage. That is the right place for it while the app owns it: no permission
 * is needed to write there, and Android cleans it up on uninstall.
 *
 * It is the wrong place the moment somebody wants to do anything else with the
 * file. Nothing else can see it: not the system file manager, not a USB cable,
 * not VLC, not the "share to" sheet of another app. People download an episode
 * for a flight, then find there is no way to get it onto a laptop, and the
 * honest answer used to be that the file is only reachable by uninstalling the
 * app, which deletes it.
 *
 * This copies rather than moves, and does so deliberately: the app's own
 * offline library keeps working from the private copy, so exporting cannot
 * break playback of something already downloaded. The cost is disk space, and
 * it is the user's choice to spend it.
 *
 * ## Why MediaStore rather than a path
 *
 * Since Android 10 an app cannot simply write into `/sdcard/Download` — scoped
 * storage forbids it and `WRITE_EXTERNAL_STORAGE` no longer grants it. The
 * MediaStore Downloads collection is the supported route and needs no runtime
 * permission at all. Below Android 10 there is no MediaStore Downloads
 * collection, so the legacy path is used instead; that branch is why the
 * manifest still declares the storage permission with a `maxSdkVersion`.
 */
object DownloadExporter {

    /**
     * Copies [sourcePath] into the public Downloads folder as [displayName].
     *
     * Returns the user-visible location on success. Throws on failure, so the
     * channel handler can report the real reason rather than a bare false —
     * "no space left on device" and "the file is gone" need different answers
     * from the person reading the message.
     */
    fun exportToDownloads(context: Context, sourcePath: String, displayName: String): String {
        val source = File(sourcePath)
        require(source.exists() && source.isFile) { "The downloaded file is no longer on disk" }

        val safeName = sanitise(displayName.ifBlank { source.name })
        val mime = mimeTypeOf(safeName)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            exportViaMediaStore(context, source, safeName, mime)
        } else {
            exportViaLegacyPath(source, safeName)
        }
    }

    private fun exportViaMediaStore(
        context: Context,
        source: File,
        name: String,
        mime: String
    ): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            // Into a Sozo subfolder, so a year of downloads is one folder
            // rather than scattered through everything else the device saved.
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Sozo")
            // Hidden from other apps until the copy is complete. Without this a
            // media scanner can index — and a player can open — a file that is
            // still being written, which looks like a corrupt download.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create the file in Downloads")

        try {
            resolver.openOutputStream(uri).use { output ->
                requireNotNull(output) { "Could not open Downloads for writing" }
                source.inputStream().use { it.copyTo(output, DEFAULT_BUFFER_SIZE) }
            }
        } catch (e: Exception) {
            // A half-written entry in the user's Downloads is worse than none:
            // it is visible, it is broken, and nothing else will clean it up.
            resolver.delete(uri, null, null)
            throw e
        }

        resolver.update(
            uri,
            ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
            null,
            null
        )
        return "Downloads/Sozo/$name"
    }

    private fun exportViaLegacyPath(source: File, name: String): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Sozo"
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create the Downloads/Sozo folder")
        }
        val target = uniqueFile(dir, name)
        source.inputStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output, DEFAULT_BUFFER_SIZE) }
        }
        return "Downloads/Sozo/${target.name}"
    }

    /**
     * `name.mkv`, `name (2).mkv`, … — the legacy path overwrites silently
     * otherwise, and two episodes with the same title would leave one file.
     * MediaStore does this itself on Q and above.
     */
    private fun uniqueFile(dir: File, name: String): File {
        val candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val stem = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "")
        var n = 2
        while (true) {
            val next = File(dir, if (ext.isEmpty()) "$stem ($n)" else "$stem ($n).$ext")
            if (!next.exists()) return next
            n++
        }
    }

    /**
     * Strips what a filesystem — or a file manager — will not accept.
     *
     * Episode titles arrive with colons and slashes in them ("S01:E04 — Part
     * 1/2"), and on the legacy path a slash silently turns one file into a
     * directory that does not exist.
     */
    private fun sanitise(name: String): String {
        val cleaned = name
            .replace(Regex("""[\\/:*?"<>|]"""), "-")
            .replace(Regex("""\s+"""), " ")
            .trim()
            .trimEnd('.')
        // Most filesystems cap a name at 255 bytes; leave room for the " (2)"
        // that uniqueFile may add.
        return if (cleaned.length <= 200) cleaned.ifBlank { "sozo-download" }
        else cleaned.take(200)
    }

    private fun mimeTypeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            // MKV is what most of these downloads actually are, and older
            // Android builds do not map the extension at all — an empty MIME
            // type makes MediaStore reject the insert outright.
            ?: when (ext) {
                "mkv" -> "video/x-matroska"
                "m3u8" -> "application/vnd.apple.mpegurl"
                "ts" -> "video/mp2t"
                else -> "application/octet-stream"
            }
    }
}
