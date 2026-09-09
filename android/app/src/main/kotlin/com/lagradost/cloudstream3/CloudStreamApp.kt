package com.lagradost.cloudstream3

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.util.Log
import java.lang.ref.WeakReference

/**
 * Clean-room stand-in for CloudStream's app-module `CloudStreamApp`.
 *
 * We embed only the CloudStream `library` artifact, which does **not** contain
 * this class — but its own HTTP layer (NiceHttp) and most plugins reference it.
 * With it missing, the very first `app.get(...)` inside a plugin threw
 * `NoClassDefFoundError` on an OkHttp worker thread, where nothing catches it,
 * and the whole app died:
 *
 *     Exception in NiceHttp: java.io.IOException canceled due to
 *     java.lang.NoClassDefFoundError: Lcom/lagradost/cloudstream3/CloudStreamApp;
 *     E AndroidRuntime: java.lang.NoClassDefFoundError: …CloudStreamApp;
 *
 * The class therefore has to exist and expose the same companion surface the
 * plugins were compiled against. [context] is the load-bearing member — it is
 * what NiceHttp wants — and it is set by [install] at startup.
 *
 * ## What is deliberately partial
 *
 * The real class extends `Application` and is the process's actual Application
 * object. Ours never is: soplay has its own. Extending [Application] anyway
 * keeps the type hierarchy plugins may reflect over intact, while [context]
 * points at the real application context.
 *
 * Key/value storage is backed by [com.lagradost.cloudstream3.utils.DataStore]
 * and supports primitives + JSON strings. A plugin storing an arbitrary data
 * class gets null back rather than a crash — see the note in DataStore.
 */
class CloudStreamApp : Application() {

    companion object {
        private const val TAG = "CloudStreamApp"

        /**
         * Set by the real app at startup. A WeakReference in upstream; we hold
         * the application context, which outlives everything anyway, so the
         * indirection would only add a null case that can never usefully be
         * handled.
         */
        private var _context: WeakReference<Context>? = null

        var context: Context?
            get() = _context?.get()
            set(value) {
                _context = value?.let { WeakReference(it) }
            }

        /** Plugins may install one; nothing in this app reads it. */
        var exceptionHandler: ((Throwable) -> Unit)? = null

        /**
         * The resumed activity, or null while none is.
         *
         * Tracked here because [CommonActivity] hands it to plugins and this app
         * has no Application subclass of its own to hang the callbacks off.
         */
        var currentActivity: Activity? = null
            private set

        private var lifecycleRegistered = false

        fun install(context: Context) {
            Companion.context = context.applicationContext
            registerActivityTracking(context.applicationContext)
        }

        private fun registerActivityTracking(context: Context) {
            if (lifecycleRegistered) return
            val app = context as? Application ?: return
            lifecycleRegistered = true
            app.registerActivityLifecycleCallbacks(
                object : Application.ActivityLifecycleCallbacks {
                    override fun onActivityResumed(activity: Activity) {
                        currentActivity = activity
                    }

                    override fun onActivityPaused(activity: Activity) {
                        if (currentActivity === activity) currentActivity = null
                    }

                    override fun onActivityCreated(a: Activity, b: android.os.Bundle?) = Unit
                    override fun onActivityStarted(a: Activity) = Unit
                    override fun onActivityStopped(a: Activity) = Unit
                    override fun onActivitySaveInstanceState(a: Activity, b: android.os.Bundle) = Unit
                    override fun onActivityDestroyed(a: Activity) {
                        if (currentActivity === a) currentActivity = null
                    }
                },
            )
        }

        tailrec fun Context.getActivity(): Activity? = when (this) {
            is Activity -> this
            is ContextWrapper -> baseContext.getActivity()
            else -> null
        }

        fun <T : Any> getKeyClass(path: String, valueType: Class<T>): T? {
            val ctx = context ?: return null
            return com.lagradost.cloudstream3.utils.DataStore.getKeyClass(ctx, path, valueType)
        }

        fun <T : Any> setKeyClass(path: String, value: T) {
            val ctx = context ?: return
            com.lagradost.cloudstream3.utils.DataStore.setKeyClass(ctx, path, value)
        }

        fun <T> setKey(path: String, value: T) {
            val ctx = context ?: return
            com.lagradost.cloudstream3.utils.DataStore.setKeyAny(ctx, path, value)
        }

        fun <T> setKey(folder: String, path: String, value: T) =
            setKey(com.lagradost.cloudstream3.utils.DataStore.getFolderName(folder, path), value)

        fun getKeys(folder: String): List<String>? {
            val ctx = context ?: return null
            return com.lagradost.cloudstream3.utils.DataStore.getKeys(ctx, folder)
        }

        fun removeKey(path: String) {
            val ctx = context ?: return
            com.lagradost.cloudstream3.utils.DataStore.removeKey(ctx, path)
        }

        fun removeKey(folder: String, path: String) =
            removeKey(com.lagradost.cloudstream3.utils.DataStore.getFolderName(folder, path))

        fun removeKeys(folder: String): Int? {
            val ctx = context ?: return null
            return com.lagradost.cloudstream3.utils.DataStore.removeKeys(ctx, folder)
        }

        /**
         * Opens [url] in the system browser.
         *
         * Upstream can also fall back to an in-app WebView tied to its own
         * fragment stack, which we have no equivalent of; the extra parameters
         * exist for signature compatibility and are ignored.
         */
        @JvmOverloads
        fun openBrowser(url: String, fallbackWebView: Boolean = false, fragment: Any? = null) {
            val ctx = context ?: return
            try {
                ctx.startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (t: Throwable) {
                Log.e(TAG, "openBrowser($url) failed: ${t.message}")
            }
        }
    }
}
