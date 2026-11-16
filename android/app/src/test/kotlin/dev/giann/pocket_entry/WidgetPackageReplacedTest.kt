package dev.giann.pocket_entry

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.RemoteViews
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetPackageReplacedTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    @Test fun packageReplacementRebuildsEveryCachedWidgetUsingSavedOpaqueStyle() {
        val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
        val manager = AppWidgetManager.getInstance(context)
        val shadow = Shadows.shadowOf(manager)
        val roots = listOf(
            QuickEntryWidget::class.java to (R.layout.quick_entry_widget to R.id.widget_root),
            CompactEntryWidget::class.java to (R.layout.compact_entry_widget to R.id.widget_root),
            BalanceEntryWidget::class.java to (R.layout.balance_entry_widget to R.id.balance_widget_root),
            WideBalanceWidget::class.java to (R.layout.wide_balance_widget to R.id.wide_root),
            KindEntryWidget::class.java to (R.layout.kind_entry_widget to R.id.kind_root),
            WalletOverviewWidget::class.java to (R.layout.wallet_overview_widget to R.id.wallet_root),
        )
        val ids = mutableListOf<Pair<Int, Int>>()
        try {
            prefs.edit().clear().putString("theme", "light").putString("visualStyle", "adventure")
                .putString("categories", QuickEntryWidget.defaultCategories).commit()
            roots.forEach { (provider, layoutAndRoot) ->
                val (layout, rootId) = layoutAndRoot
                val widgetId = shadow.createWidgets(provider, layout, 1).single()
                ids += widgetId to rootId

                // Model an old cached RemoteViews whose background drawable ID no longer resolves.
                manager.updateAppWidget(widgetId, RemoteViews(context.packageName, layout).apply {
                    setInt(rootId, "setBackgroundResource", 0)
                })
                assertEquals("${provider.simpleName} stale background", null, shadow.getViewFor(widgetId)
                    .findViewById<View>(rootId).background)
            }

            WidgetPackageReplacedReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

            ids.forEach { (widgetId, rootId) ->
                val root = shadow.getViewFor(widgetId).findViewById<View>(rootId)
                assertNotNull("widget $widgetId background was not refreshed", root.background)
                val drawable = root.background as GradientDrawable
                assertEquals(Color.parseColor("#F4ECD8"), drawable.color!!.defaultColor)
                drawable.setBounds(0, 0, 4, 4)
                val pixel = android.graphics.Bitmap.createBitmap(4, 4, android.graphics.Bitmap.Config.ARGB_8888)
                drawable.draw(android.graphics.Canvas(pixel))
                assertEquals("widget $widgetId background must be opaque", 255, Color.alpha(pixel.getPixel(2, 2)))
                pixel.recycle()
            }
            assertEquals("adventure", prefs.getString("visualStyle", null))
        } finally {
            prefs.edit().clear().commit()
        }
    }
}
