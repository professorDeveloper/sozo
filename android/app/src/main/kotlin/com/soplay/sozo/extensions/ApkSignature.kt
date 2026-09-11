package com.soplay.sozo.extensions

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.security.MessageDigest

/**
 * Checks a downloaded extension apk against the signing key its repo declares.
 *
 * Mihon-format repos publish the SHA-256 of the key every extension in them is
 * signed with — `meta.signingKeyFingerprint` in `repo.json`, field 3 of an
 * `index.pb`. Extensions are dex-loaded straight into this process, where they
 * can read everything the app can, so an apk that the repo's own key did not
 * sign (a hijacked CDN, a swapped mirror, a tampered download) must not load.
 *
 * A repo that declares no fingerprint — plain `index.min.json` repos, files
 * opened with "Open with Sozo" — has nothing to check against and is loaded as
 * before; see [ExtensionIndex] for where the fingerprint comes from.
 */
object ApkSignature {

    private const val TAG = "ApkSignature"

    /** Lower-case hex with separators removed, or null when [raw] is not a
     *  SHA-256. An unrecognised shape is ignored rather than enforced, so a repo
     *  that puts something else in the field cannot lock its users out. */
    fun normalize(raw: String?): String? {
        val hex = raw.orEmpty().replace(":", "").replace(" ", "").trim().lowercase()
        return if (hex.length == 64 && hex.all { it in '0'..'9' || it in 'a'..'f' }) hex else null
    }

    /** SHA-256 fingerprints of every certificate [apkPath] is signed with. */
    @Suppress("DEPRECATION")
    fun fingerprints(context: Context, apkPath: String): List<String> {
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info: PackageInfo = pm.getPackageArchiveInfo(apkPath, flags) ?: return emptyList()
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo
            when {
                signing == null -> info.signatures
                signing.hasMultipleSigners() -> signing.apkContentsSigners
                else -> signing.signingCertificateHistory
            }
        } else {
            info.signatures
        }
        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.orEmpty().map { sig ->
            digest.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }
    }

    /** True when [expected] is absent/unrecognised or matches one of the apk's
     *  signers; false only for a declared fingerprint the apk does not carry. */
    fun matches(context: Context, apkPath: String, expected: String?): Boolean {
        val want = normalize(expected) ?: return true
        val have = try {
            fingerprints(context, apkPath)
        } catch (t: Throwable) {
            Log.e(TAG, "signature read failed for $apkPath: ${t.message}")
            emptyList()
        }
        val ok = have.any { it == want }
        if (!ok) Log.e(TAG, "signature mismatch for $apkPath: want $want, have $have")
        return ok
    }
}
