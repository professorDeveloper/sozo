package com.soplay.sozo.manga

import android.content.Context
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.PreferenceManager
import androidx.preference.TwoStatePreference
import eu.kanade.tachiyomi.source.ConfigurableSource
import org.json.JSONArray
import org.json.JSONObject

/**
 * Extracts and persists a manga source's [ConfigurableSource] preferences.
 *
 * Tachiyomi sources expose settings by adding `androidx.preference.Preference`
 * objects to a [androidx.preference.PreferenceScreen] in `setupPreferenceScreen`,
 * and read their values from `SharedPreferences("source_<id>")`. We build a screen
 * bound to that same store, let the source populate it, then serialise each
 * preference to JSON for a Flutter settings UI. Writes go straight back to the
 * same SharedPreferences the source reads at request time.
 */
object MangaPreferences {

    /** Serialises the source's preferences to a JSON array for Flutter. */
    fun extract(context: Context, sourceId: String, src: ConfigurableSource): String =
        extractScreen(context, prefsName(sourceId)) { src.setupPreferenceScreen(it) }

    /**
     * The same serialisation for any source that fills a preference screen —
     * Aniyomi's anime sources use the identical androidx screen and the same
     * `source_<id>` store, so one reader serves both.
     */
    fun extractScreen(
        context: Context,
        prefsName: String,
        setup: (androidx.preference.PreferenceScreen) -> Unit,
    ): String {
        val pm = newManager(context, prefsName)
        val screen = pm.createPreferenceScreen(context)
        setup(screen)

        val arr = JSONArray()
        for (i in 0 until screen.preferenceCount) {
            val p = screen.getPreference(i)
            val key = p.key ?: continue
            val o = JSONObject().apply {
                put("key", key)
                put("title", p.title?.toString() ?: "")
                put("summary", p.summary?.toString() ?: "")
            }
            when (p) {
                is MultiSelectListPreference -> {
                    o.put("type", "multi")
                    o.put("entries", JSONArray(p.entries.map { it.toString() }))
                    o.put("entryValues", JSONArray(p.entryValues.map { it.toString() }))
                    o.put("value", JSONArray((p.values ?: emptySet()).toList()))
                }
                is ListPreference -> {
                    o.put("type", "list")
                    o.put("entries", JSONArray(p.entries.map { it.toString() }))
                    o.put("entryValues", JSONArray(p.entryValues.map { it.toString() }))
                    o.put("value", p.value ?: "")
                }
                is EditTextPreference -> {
                    o.put("type", "text")
                    o.put("value", p.text ?: "")
                }
                is TwoStatePreference -> { // SwitchPreferenceCompat + CheckBoxPreference
                    o.put("type", "switch")
                    o.put("value", p.isChecked)
                }
                else -> o.put("type", "info")
            }
            arr.put(o)
        }
        return arr.toString()
    }

    /** Writes a single preference value back to the source's SharedPreferences. */
    fun write(context: Context, sourceId: String, key: String, value: Any?, type: String) =
        writeTo(context, prefsName(sourceId), key, value, type)

    fun writeTo(context: Context, prefsName: String, key: String, value: Any?, type: String) {
        val editor = context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
        when (type) {
            "switch" -> editor.putBoolean(key, value as? Boolean ?: false)
            "multi" -> {
                val set = (value as? List<*>)?.map { it.toString() }?.toSet() ?: emptySet()
                editor.putStringSet(key, set)
            }
            else -> editor.putString(key, value?.toString() ?: "")
        }
        editor.apply()
    }

    private fun prefsName(sourceId: String) = "source_$sourceId"

    /**
     * The `PreferenceManager(Context)` constructor is library-internal; reflection
     * is the standard way to build a screen off the UI for headless extraction.
     */
    private fun newManager(context: Context, name: String): PreferenceManager {
        val ctor = PreferenceManager::class.java.getDeclaredConstructor(Context::class.java)
        ctor.isAccessible = true
        val pm = ctor.newInstance(context) as PreferenceManager
        pm.sharedPreferencesName = name
        pm.sharedPreferencesMode = Context.MODE_PRIVATE
        return pm
    }
}
