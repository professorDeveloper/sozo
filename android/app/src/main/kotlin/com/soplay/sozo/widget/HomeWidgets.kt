package com.soplay.sozo.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.soplay.sozo.MainActivity
import com.soplay.sozo.R
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * The home screen widgets: what was being watched, the streak, and the next
 * episode's countdown.
 *
 * The app writes a snapshot — already in the viewer's language, posters
 * already cut to size and saved as files — and the widgets only draw it. A
 * widget cannot run Dart, and should not try: everything that changes with
 * time is worked out here from the snapshot instead. The countdown is the
 * system chronometer, so it ticks with the app closed; whether the streak is
 * at risk is read against the clock on each redraw.
 */
object HomeWidgets {
    private const val PREFS = "sozo_home_widget"
    private const val KEY_SNAPSHOT = "snapshot"

    const val EXTRA_ACTION = "sozo_widget_action"
    const val EXTRA_CONTENT_URL = "sozo_widget_content_url"
    const val EXTRA_PROVIDER = "sozo_widget_provider"
    const val EXTRA_EPISODE_INDEX = "sozo_widget_episode_index"

    /** The streak turns urgent from this hour when today has no watching yet. */
    private const val RISK_HOUR = 21

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_SNAPSHOT, json).apply()
        renderAll(context)
    }

    private fun snapshot(context: Context): JSONObject? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT, null) ?: return null
        return runCatching { JSONObject(raw) }.getOrNull()
    }

    fun renderAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for ((provider, medium) in listOf(
            ContinueWidgetSmall::class.java to false,
            ContinueWidgetMedium::class.java to true,
        )) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isNotEmpty()) render(context, manager, ids, medium)
        }
    }

    fun render(context: Context, manager: AppWidgetManager, ids: IntArray, medium: Boolean) {
        val snap = snapshot(context)
        for (id in ids) {
            val views = if (medium) medium(context, snap) else small(context, snap)
            runCatching { manager.updateAppWidget(id, views) }
        }
    }

    // --- the two sizes -------------------------------------------------------

    private fun small(context: Context, snap: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_continue_small)
        views.setOnClickPendingIntent(R.id.widget_root, open(context, "open", null, 0))
        val labels = snap?.optJSONObject("labels") ?: JSONObject()
        if (snap == null || snap.optBoolean("locked")) {
            showOnly(views, R.id.locked, listOf(R.id.poster, R.id.scrim, R.id.streak_chip, R.id.info, R.id.empty))
            views.setTextViewText(R.id.locked_text, labels.optString("locked", "Sozo"))
            views.setTextViewText(R.id.locked_hint, labels.optString("lockedHint"))
            return views
        }
        streak(views, snap, labels, chipOnPoster = true)
        val item = snap.optJSONArray("items")?.optJSONObject(0)
        if (item == null) {
            showOnly(views, R.id.empty, listOf(R.id.poster, R.id.scrim, R.id.info, R.id.locked))
            views.setViewVisibility(R.id.streak_chip, View.VISIBLE)
            views.setTextViewText(R.id.empty_text, labels.optString("empty"))
            return views
        }
        showOnly(views, R.id.info, listOf(R.id.empty, R.id.locked))
        views.setViewVisibility(R.id.poster, View.VISIBLE)
        views.setViewVisibility(R.id.scrim, View.VISIBLE)
        poster(views, R.id.poster, item, 480)
        views.setTextViewText(R.id.title, item.optString("title"))
        views.setTextViewText(R.id.subtitle, item.optString("subtitle"))
        progress(views, R.id.progress, item)
        views.setOnClickPendingIntent(R.id.widget_root, open(context, "continue", item, 1))
        return views
    }

    private fun medium(context: Context, snap: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_continue_medium)
        views.setOnClickPendingIntent(R.id.widget_root, open(context, "open", null, 0))
        val labels = snap?.optJSONObject("labels") ?: JSONObject()
        if (snap == null || snap.optBoolean("locked")) {
            showOnly(views, R.id.locked, listOf(R.id.content, R.id.empty))
            views.setTextViewText(R.id.locked_text, labels.optString("locked", "Sozo"))
            views.setTextViewText(R.id.locked_hint, labels.optString("lockedHint"))
            return views
        }
        views.setTextViewText(R.id.header, labels.optString("continue", "Sozo"))
        val atRisk = streak(views, snap, labels, chipOnPoster = false)

        val items = snap.optJSONArray("items")
        if (items == null || items.length() == 0) {
            showOnly(views, R.id.empty, listOf(R.id.content, R.id.locked))
            views.setTextViewText(R.id.empty_text, labels.optString("empty"))
            return views
        }
        showOnly(views, R.id.content, listOf(R.id.empty, R.id.locked))
        val slots = listOf(
            Slot(R.id.item_0, R.id.poster_0, R.id.progress_0, R.id.title_0, R.id.sub_0),
            Slot(R.id.item_1, R.id.poster_1, R.id.progress_1, R.id.title_1, R.id.sub_1),
            Slot(R.id.item_2, R.id.poster_2, R.id.progress_2, R.id.title_2, R.id.sub_2),
        )
        for ((i, slot) in slots.withIndex()) {
            val item = items.optJSONObject(i)
            if (item == null) {
                views.setViewVisibility(slot.root, View.INVISIBLE)
                continue
            }
            views.setViewVisibility(slot.root, View.VISIBLE)
            poster(views, slot.poster, item, 240)
            progress(views, slot.progress, item)
            views.setTextViewText(slot.title, item.optString("title"))
            views.setTextViewText(slot.sub, item.optString("subtitle"))
            views.setOnClickPendingIntent(slot.root, open(context, "continue", item, 10 + i))
        }

        // One line under the row: the streak's warning when it is in danger
        // tonight — that matters more than any countdown — else the next
        // episode.
        views.setViewVisibility(R.id.risk_row, View.GONE)
        views.setViewVisibility(R.id.next_row, View.GONE)
        if (atRisk) {
            views.setViewVisibility(R.id.risk_row, View.VISIBLE)
            val days = snap.optJSONObject("streak")?.optInt("current") ?: 0
            views.setTextViewText(
                R.id.risk_text,
                labels.optString("atRisk").replace("{}", days.toString()),
            )
            views.setOnClickPendingIntent(R.id.risk_row, open(context, "open", null, 20))
        } else {
            next(context, views, snap, labels)
        }
        return views
    }

    private data class Slot(val root: Int, val poster: Int, val progress: Int, val title: Int, val sub: Int)

    private fun showOnly(views: RemoteViews, shown: Int, hidden: List<Int>) {
        views.setViewVisibility(shown, View.VISIBLE)
        for (id in hidden) views.setViewVisibility(id, View.GONE)
    }

    // --- pieces ----------------------------------------------------------------

    /** The streak chip; returns whether the streak is at risk right now. */
    private fun streak(views: RemoteViews, snap: JSONObject, labels: JSONObject, chipOnPoster: Boolean): Boolean {
        val s = snap.optJSONObject("streak")
        val current = s?.optInt("current") ?: 0
        if (current <= 0) {
            views.setViewVisibility(R.id.streak_chip, View.GONE)
            return false
        }
        views.setViewVisibility(R.id.streak_chip, View.VISIBLE)
        val atRisk = isAtRisk(s?.optString("lastActiveDate"))
        views.setTextViewText(
            R.id.streak_text,
            if (chipOnPoster) current.toString() else labels.optString("days", "{}").replace("{}", current.toString()),
        )
        views.setInt(
            R.id.streak_chip,
            "setBackgroundResource",
            when {
                atRisk -> R.drawable.widget_chip_ember
                chipOnPoster -> R.drawable.widget_chip
                else -> 0
            },
        )
        views.setTextColor(R.id.streak_text, if (atRisk) 0xFF1A0A00.toInt() else 0xFFFFA94D.toInt())
        views.setImageViewResource(
            R.id.streak_icon,
            if (atRisk) R.drawable.ic_widget_flame_dark else R.drawable.ic_widget_flame,
        )
        return atRisk
    }

    /**
     * Whether the streak ends tonight: it last moved yesterday, and it is
     * late enough that the viewer should hear about it. The same rule as the
     * server's reminder, read against the phone's own clock.
     */
    private fun isAtRisk(lastActiveDate: String?): Boolean {
        if (lastActiveDate.isNullOrBlank()) return false
        val now = Calendar.getInstance()
        if (now.get(Calendar.HOUR_OF_DAY) < RISK_HOUR) return false
        val yesterday = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) }
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(yesterday.time)
        return lastActiveDate == day
    }

    private fun next(context: Context, views: RemoteViews, snap: JSONObject, labels: JSONObject) {
        val next = snap.optJSONObject("next") ?: return
        val airsAt = next.optLong("airsAt")
        if (airsAt <= 0) return
        val now = System.currentTimeMillis()
        // An episode that went out more than a day ago is old news.
        if (now - airsAt > 24 * 60 * 60 * 1000L) return
        views.setViewVisibility(R.id.next_row, View.VISIBLE)
        views.setTextViewText(
            R.id.next_text,
            "${labels.optString("next")} · ${next.optString("title")} ${next.optString("episode")}".trim(),
        )
        if (airsAt > now) {
            views.setViewVisibility(R.id.countdown, View.VISIBLE)
            views.setViewVisibility(R.id.next_now, View.GONE)
            // The chronometer counts toward a moment on the elapsed-time clock,
            // which keeps ticking while the phone sleeps.
            val base = SystemClock.elapsedRealtime() + (airsAt - now)
            views.setChronometer(R.id.countdown, base, null, true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                views.setChronometerCountDown(R.id.countdown, true)
            }
        } else {
            views.setViewVisibility(R.id.countdown, View.GONE)
            views.setViewVisibility(R.id.next_now, View.VISIBLE)
            views.setTextViewText(R.id.next_now, labels.optString("outNow"))
        }
        views.setOnClickPendingIntent(R.id.next_row, open(context, "next", null, 30))
    }

    private fun poster(views: RemoteViews, id: Int, item: JSONObject, maxSide: Int) {
        val path = item.optString("poster")
        val bitmap = if (path.isNotBlank()) decode(path, maxSide) else null
        if (bitmap != null) {
            views.setImageViewBitmap(id, bitmap)
        } else {
            views.setImageViewResource(id, R.drawable.ic_widget_play)
        }
    }

    /** A poster file, no larger than the widget will ever draw it. */
    private fun decode(path: String, maxSide: Int): Bitmap? = runCatching {
        val file = File(path)
        if (!file.isFile) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxSide && bounds.outHeight / (sample * 2) >= maxSide) {
            sample *= 2
        }
        BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()

    private fun progress(views: RemoteViews, id: Int, item: JSONObject) {
        val p = item.optDouble("progress", 0.0)
        if (p <= 0.0) {
            views.setViewVisibility(id, View.GONE)
            return
        }
        views.setViewVisibility(id, View.VISIBLE)
        views.setProgressBar(id, 1000, (p.coerceIn(0.0, 1.0) * 1000).toInt(), false)
    }

    /**
     * Opens the app on [action]. Each target gets its own request code, or the
     * system would hand every tap the first one's extras.
     */
    private fun open(context: Context, action: String, item: JSONObject?, request: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_ACTION, action)
            if (item != null) {
                putExtra(EXTRA_CONTENT_URL, item.optString("contentUrl"))
                putExtra(EXTRA_PROVIDER, item.optString("provider"))
                if (item.has("episodeIndex") && !item.isNull("episodeIndex")) {
                    putExtra(EXTRA_EPISODE_INDEX, item.optInt("episodeIndex"))
                }
            }
        }
        return PendingIntent.getActivity(
            context,
            4200 + request,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** The tap that opened the app, as the Dart side wants it; null if none. */
    fun actionOf(intent: Intent?): Map<String, Any?>? {
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return null
        return mapOf(
            "action" to action,
            "contentUrl" to intent.getStringExtra(EXTRA_CONTENT_URL),
            "provider" to intent.getStringExtra(EXTRA_PROVIDER),
            "episodeIndex" to if (intent.hasExtra(EXTRA_EPISODE_INDEX)) {
                intent.getIntExtra(EXTRA_EPISODE_INDEX, 0)
            } else {
                null
            },
        )
    }
}

class ContinueWidgetSmall : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        HomeWidgets.render(context, manager, ids, medium = false)
    }
}

class ContinueWidgetMedium : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        HomeWidgets.render(context, manager, ids, medium = true)
    }
}
