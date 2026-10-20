package dev.giann.pocket_entry

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SmallWidgetTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private fun size(view: View, width: Int, height: Int) {
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, width, height)
    }
    private fun capture(view: View, width: Int, height: Int, name: String) {
        val bitmap = Bitmap.createBitmap(width * 2, height * 2, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap); canvas.scale(2f, 2f); view.draw(canvas)
        val directory = File(requireNotNull(System.getProperty("pocket.previewDir"))); directory.mkdirs()
        File(directory, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    @Test fun providersAreSeparatePrivateAndOfferTwoByTwoWhileLargeWidgetIsUnchanged() {
        for (provider in listOf(CompactEntryWidget::class.java, BalanceEntryWidget::class.java)) {
            val info = context.packageManager.getReceiverInfo(ComponentName(context, provider), PackageManager.GET_META_DATA)
            assertFalse(info.exported)
            val xml = context.resources.getXml(info.metaData.getInt("android.appwidget.provider"))
            while (xml.next() != org.xmlpull.v1.XmlPullParser.START_TAG) { }
            val ns = "http://schemas.android.com/apk/res/android"
            assertEquals(2, xml.getAttributeIntValue(ns, "targetCellWidth", 0))
            assertEquals(2, xml.getAttributeIntValue(ns, "targetCellHeight", 0))
            xml.close()
        }
        val large = QuickEntryWidget.views(context, 1).apply(context, FrameLayout(context))
        assertEquals(View.VISIBLE, large.findViewById<View>(R.id.widget_header).visibility)
        val compact = QuickEntryWidget.views(context, 2, true).apply(context, FrameLayout(context))
        assertEquals(View.GONE, compact.findViewById<View>(R.id.widget_header).visibility)
    }
    @Test fun compactCategoriesRemainUsableAtMinimumSizeAndLargeType() {
        val original = Configuration(context.resources.configuration)
        for (scale in listOf(1f, 1.5f)) for (theme in listOf("light", "dark")) {
            val config = Configuration(original); config.fontScale = scale
            @Suppress("DEPRECATION")
            context.resources.updateConfiguration(config, context.resources.displayMetrics)
            context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit()
                .putString("theme", theme).putString("categories", QuickEntryWidget.defaultCategories).commit()
            for (width in listOf(128, 148, 180, 240)) {
                val view = QuickEntryWidget.views(context, 71, true).apply(context, FrameLayout(context))
                size(view, width, width)
                for (i in QuickEntryWidget.slots.indices) {
                    val cell = view.findViewById<View>(QuickEntryWidget.slots[i])
                    assertEquals(View.VISIBLE, cell.visibility)
                    assertTrue(cell.isClickable)
                    assertTrue("minimum target", cell.height >= 48 && cell.width >= 48)
                    val text = view.findViewById<TextView>(QuickEntryWidget.labels[i])
                    assertTrue("label bottom within cell", text.bottom <= cell.height)
                    assertTrue("line height within label", text.layout.getLineBottom(0) <= text.height)
                    assertTrue(cell.contentDescription.startsWith("Add "))
                }
                assertFalse(allText(view).contains("₱"))
                capture(view, width, width, "widget-compact-${width}-$theme-${if(scale > 1) "large-type" else "normal"}")
            }
        }
        @Suppress("DEPRECATION")
        context.resources.updateConfiguration(original, context.resources.displayMetrics)
    }
    @Test fun balanceIsHiddenByDefaultAndTappingOnlyOpensQuickAdd() {
        val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
        prefs.edit().clear().putLong("balanceUpdatedAt", 1).putLong("balanceCentavos", 632750).putInt("activeWalletCount", 3).commit()
        val view = BalanceEntryWidget.views(context, 76).apply(context, FrameLayout(context))
        size(view, 148, 148)
        assertEquals("••••", view.findViewById<TextView>(R.id.balance_widget_amount).text.toString())
        assertFalse(allText(view).contains("6327")); assertFalse(view.contentDescription.contains("₱"))
        assertTrue(view.isClickable)
        view.performClick()
        val intent = Shadows.shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity
        assertEquals(ComponentName(context, MainActivity::class.java), intent.component)
        assertEquals(QuickEntryPolicy.Route(null, null), QuickEntryPolicy.parse(intent.action, intent.dataString))
        assertFalse(intent.hasExtra("wallet")); assertFalse(intent.hasExtra("amount"))
        assertTrue(QuickEntryWidget.pending(context, 76, 0, null).isImmutable)
    }
    @Test fun visibilityToggleImmediatelyReplacesAnExistingShownRemoteView() {
        val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
        prefs.edit().clear().putLong("balanceUpdatedAt", 1).putLong("balanceCentavos", 632750)
            .putInt("activeWalletCount", 3).putBoolean("balanceVisible", true).commit()
        val view = BalanceEntryWidget.views(context, 80).apply(context, FrameLayout(context))
        assertEquals("₱6,327.50", view.findViewById<TextView>(R.id.balance_widget_amount).text.toString())
        assertTrue(view.contentDescription.contains("₱6,327.50"))
        prefs.edit().putBoolean("balanceVisible", false).commit()
        BalanceEntryWidget.views(context, 80).reapply(context, view)
        assertEquals("••••", view.findViewById<TextView>(R.id.balance_widget_amount).text.toString())
        assertFalse(view.contentDescription.contains("₱"))
    }
    @Test fun balancesDistinguishZeroNegativeNoWalletsAndUnsyncedAndRenderThemesAndScaling() {
        val original = Configuration(context.resources.configuration)
        for (scale in listOf(1f, 1.5f)) for (theme in listOf("light", "dark")) {
            val config = Configuration(original); config.fontScale = scale
            @Suppress("DEPRECATION")
            context.resources.updateConfiguration(config, context.resources.displayMetrics)
            for ((name, amount, count) in listOf(Triple("positive", 632750L, 3), Triple("negative", -12345L, 2), Triple("zero", 0L, 2), Triple("empty", 0L, 0), Triple("large", 99999999999L, 20), Triple("aggregate", 2001999999979980L, 20))) {
                val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
                prefs.edit().clear().putString("theme", theme).putLong("balanceUpdatedAt", 1).putLong("balanceCentavos", amount)
                    .putInt("activeWalletCount", count).putBoolean("balanceVisible", true).commit()
                for (width in listOf(128, 148, 180, 240)) {
                    val view = BalanceEntryWidget.views(context, 81).apply(context, FrameLayout(context))
                    size(view, width, width)
                    val text = view.findViewById<TextView>(R.id.balance_widget_amount)
                    assertEquals(if (count == 0) "—" else BalanceEntryWidget.money(amount), text.text.toString())
                    assertTrue(text.height > 0)
                    assertTrue("amount clipped: $name, $width, $scale, height=${text.height}, line=${text.layout.getLineBottom(text.layout.lineCount - 1)}, size=${text.textSize}", text.layout.getLineBottom(text.layout.lineCount - 1) <= text.height)
                    for (line in 0 until text.layout.lineCount) {
                        assertEquals(0, text.layout.getEllipsisCount(line))
                        assertTrue("amount width within label: $name, $width, $scale", text.layout.getLineWidth(line) <= text.width - text.paddingLeft - text.paddingRight + 1)
                    }
                    val add = view.findViewById<View>(R.id.balance_widget_add)
                    assertTrue(add.height >= 48 && add.width >= 48)
                    assertTrue("footer within root", add.bottom <= view.height - 8)
                    assertTrue(add.isClickable)
                    if (scale > 1) {
                        assertEquals("Tracked", view.findViewById<TextView>(R.id.balance_widget_title).text.toString())
                        val action = view.findViewById<TextView>(R.id.balance_widget_compact_action)
                        assertTrue(action.text.contains(if (count == 0) "No active wallets" else "$count active wallets"))
                        assertTrue(action.layout.getLineBottom(action.layout.lineCount - 1) <= action.height)
                        for (line in 0 until action.layout.lineCount) assertEquals(0, action.layout.getEllipsisCount(line))
                    }
                    if (width == 148) capture(view, width, width, "widget-balance-$name-$theme-${if(scale > 1) "large-type" else "normal"}")
                }
            }
        }
        @Suppress("DEPRECATION")
        context.resources.updateConfiguration(original, context.resources.displayMetrics)
        context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        val view = BalanceEntryWidget.views(context, 90).apply(context, FrameLayout(context))
        assertEquals("—", view.findViewById<TextView>(R.id.balance_widget_amount).text.toString())
        assertTrue(view.contentDescription.contains("sync"))
    }
    @Test fun compactEmptySelectionKeepsOneFullSizeQuickAdd() {
        context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit().putString("categories", "[]").commit()
        val view = QuickEntryWidget.views(context, 91, true).apply(context, FrameLayout(context)); size(view, 128, 128)
        assertEquals(View.GONE, view.findViewById<View>(R.id.category_grid).visibility)
        val add = view.findViewById<View>(R.id.widget_empty_add)
        assertTrue(add.isClickable && add.height >= 48)
        assertEquals(120, add.bottom)
    }
    private fun allText(view: View): String = if (view is TextView) view.text.toString() else if (view is android.view.ViewGroup) (0 until view.childCount).joinToString(" ") { allText(view.getChildAt(it)) } else ""
}
