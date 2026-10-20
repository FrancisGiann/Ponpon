package dev.giann.pocket_entry

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle
import android.graphics.Color
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ScrollView

/** Debug-only native host for an empty test emulator. Never part of release. */
class WidgetProofActivity : Activity() {
    private lateinit var host: AppWidgetHost
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = AppWidgetHost(this, 19023)
        host.deleteHost()
        val manager = AppWidgetManager.getInstance(this)
        val dark = getSharedPreferences(QuickEntryWidget.PREFS, MODE_PRIVATE).getString("theme", "light") == "dark"
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(36), dp(16), dp(24))
            setBackgroundColor(Color.parseColor(if (dark) "#151416" else "#FFFFFF"))
        }
        fun label(text: String) = TextView(this).apply {
            this.text = text; textSize = 13f
            setTextColor(Color.parseColor(if (dark) "#F7F3F1" else "#27212A"))
            setPadding(0, dp(8), 0, dp(8))
        }
        fun widget(provider: Class<*>, width: Int, height: Int): android.view.View {
            val id = host.allocateAppWidgetId()
            check(manager.bindAppWidgetIdIfAllowed(id, ComponentName(this, provider))) { "Grant widget binding to the test host first." }
            val info = manager.getAppWidgetInfo(id)
            val view = host.createView(this, id, info)
            view.setPadding(0, 0, 0, 0)
            view.updateAppWidgetSize(null, width, height, width, height)
            val remote = when (provider) {
                BalanceEntryWidget::class.java -> BalanceEntryWidget.views(this, id)
                CompactEntryWidget::class.java -> QuickEntryWidget.views(this, id, true)
                else -> QuickEntryWidget.views(this, id)
            }
            manager.updateAppWidget(id, remote)
            view.updateAppWidget(remote)
            view.layoutParams = LinearLayout.LayoutParams(dp(width), dp(height))
            return view
        }
        content.addView(label("Synthetic widget proof · Android 35"))
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for (provider in listOf(CompactEntryWidget::class.java, BalanceEntryWidget::class.java)) {
            val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            column.addView(label(if (provider == CompactEntryWidget::class.java) "Quick entry · 2 × 2" else "Balance · 2 × 2"))
            column.addView(widget(provider, 148, 148))
            row.addView(column, LinearLayout.LayoutParams(dp(148), -2).apply { marginEnd = dp(12) })
        }
        content.addView(row)
        content.addView(label("Existing larger widget · 330 × 180 dp"))
        content.addView(widget(QuickEntryWidget::class.java, 330, 180))
        content.addView(label("Test AppWidgetHost · synthetic ledger only. Launcher placement and physical POCO checks are separate."))
        setContentView(ScrollView(this).apply { addView(content) })
    }
    override fun onStart() { super.onStart(); host.startListening() }
    override fun onStop() { host.stopListening(); super.onStop() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
