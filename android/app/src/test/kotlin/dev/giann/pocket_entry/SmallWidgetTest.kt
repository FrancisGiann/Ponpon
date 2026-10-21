package dev.giann.pocket_entry

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.GradientDrawable
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
    @Test fun cachedStyleIsSharedByAllProvidersAndUnknownValuesFallBackToOriginal() {
        val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
        val payload = { style: String? ->
            buildMap<String, Any> {
                put("theme", "light")
                if (style != null) put("visualStyle", style)
                put("privatePreview", true)
                put("balanceWidgetVisible", true)
                put("balanceCentavos", -12345L)
                put("activeWalletCount", 2)
                put("categories", listOf(mapOf("id" to "food", "name" to "Food", "icon" to "food")))
                put("billReminders", emptyList<Map<String, Any>>())
            }
        }
        val expected = listOf(
            "original" to android.graphics.Color.parseColor("#F6F4F1"),
            "powderBlue" to android.graphics.Color.parseColor("#EFF6FC"),
            "notebook" to android.graphics.Color.parseColor("#F6F1E5"),
            "midnight" to android.graphics.Color.parseColor("#0C1420"),
        )
        for ((styleName, backgroundColor) in expected) {
            prefs.edit().clear().commit()
            WidgetSnapshot.apply(context, payload(styleName))
            assertEquals(styleName, prefs.getString("visualStyle", null))
            val views = listOf(
                QuickEntryWidget.views(context, 210),
                QuickEntryWidget.views(context, 211, compact = true),
            ).map { it.apply(context, FrameLayout(context)) }
            val balance = BalanceEntryWidget.views(context, 212).apply(context, FrameLayout(context))
            val roots = views.map { it.findViewById<View>(R.id.widget_root) } +
                balance.findViewById<View>(R.id.balance_widget_root)
            for (root in roots) {
                val color = (root.background as GradientDrawable).color!!.defaultColor
                assertEquals(styleName, backgroundColor, color)
            }
            val balanceAmount = balance.findViewById<TextView>(R.id.balance_widget_amount)
            assertEquals("−₱123.45", balanceAmount.text.toString())
        }
        for (missingOrUnknown in listOf(null, "futureStyle")) {
            prefs.edit().clear().commit()
            WidgetSnapshot.apply(context, payload(missingOrUnknown))
            assertEquals("original", prefs.getString("visualStyle", null))
            assertEquals("original", WidgetStyle.normalize(missingOrUnknown))
        }
    }
    @Test fun allStylesKeepLongLabelsAndBalancesReadableAcrossWidgetSizes() {
        val original = Configuration(context.resources.configuration)
        val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
        val labels = listOf(
            "Daily household essentials",
            "After-school transportation",
            "Emergency medical supplies",
            "Learning and school materials",
        )
        val categories = """
            [{"id":"home","name":"${labels[0]}","icon":"home"},
             {"id":"travel","name":"${labels[1]}","icon":"travel"},
             {"id":"health","name":"${labels[2]}","icon":"health"},
             {"id":"school","name":"${labels[3]}","icon":"school"}]
        """.trimIndent().replace("\n", "")
        val styleThemes = listOf(
            "original" to "light", "original" to "dark",
            "powderBlue" to "light", "powderBlue" to "dark",
            "notebook" to "light", "notebook" to "dark",
            "midnight" to "light", "midnight" to "dark",
        )
        try {
            for (scale in listOf(1f, 1.5f)) {
                val config = Configuration(original).apply { fontScale = scale }
                @Suppress("DEPRECATION")
                context.resources.updateConfiguration(config, context.resources.displayMetrics)
                for ((style, theme) in styleThemes) {
                    prefs.edit().clear()
                        .putString("theme", theme)
                        .putString("visualStyle", style)
                        .putString("categories", categories)
                        .putLong("balanceUpdatedAt", 1)
                        .putLong("balanceCentavos", -12345L)
                        .putInt("activeWalletCount", 2)
                        .commit()
                    val tokens = WidgetStyle.from(context, style, theme)
                    assertEquals(style, tokens.name)
                    assertEquals(style == "midnight" || theme == "dark", tokens.dark)

                    val compact = QuickEntryWidget.views(context, 290, compact = true)
                        .apply(context, FrameLayout(context))
                    size(compact, 128, 128)
                    for (index in QuickEntryWidget.slots.indices) {
                        val cell = compact.findViewById<View>(QuickEntryWidget.slots[index])
                        val label = compact.findViewById<TextView>(QuickEntryWidget.labels[index])
                        assertTrue("compact target too small: $style/$theme/$scale", cell.width >= 48 && cell.height >= 48)
                        assertTrue("compact target is not clickable", cell.isClickable)
                        assertEquals("Add ${labels[index]} entry", cell.contentDescription)
                        assertEquals(1, label.layout.lineCount)
                        assertTrue("long compact label should ellipsize", label.layout.getEllipsisCount(0) > 0)
                        assertTrue("compact label clipped vertically", label.layout.getLineBottom(0) <= label.height)
                        assertTrue("compact label extends past its cell", label.bottom <= cell.height)
                    }
                    capture(compact, 128, 128, "029-style-widget-compact-$style-$theme-$scale")

                    prefs.edit().putBoolean("balanceVisible", false).commit()
                    val hidden = BalanceEntryWidget.views(context, 291)
                        .apply(context, FrameLayout(context))
                    size(hidden, 128, 128)
                    val hiddenAmount = hidden.findViewById<TextView>(R.id.balance_widget_amount)
                    val hiddenAdd = hidden.findViewById<View>(R.id.balance_widget_add)
                    assertEquals("••••", hiddenAmount.text.toString())
                    assertFalse(hidden.contentDescription.contains("₱"))
                    assertFalse(allText(hidden).contains("123"))
                    assertTrue(hiddenAmount.layout.lineCount in 1..2)
                    for (line in 0 until hiddenAmount.layout.lineCount) {
                        assertEquals(0, hiddenAmount.layout.getEllipsisCount(line))
                        assertTrue(hiddenAmount.layout.getLineBottom(line) <= hiddenAmount.height)
                    }
                    assertTrue(hiddenAdd.width >= 48 && hiddenAdd.height >= 48 && hiddenAdd.isClickable)
                    capture(hidden, 128, 128, "029-style-widget-balance-hidden-$style-$theme-$scale")

                    prefs.edit().putBoolean("balanceVisible", true).commit()
                    val negative = BalanceEntryWidget.views(context, 292)
                        .apply(context, FrameLayout(context))
                    size(negative, 128, 128)
                    val negativeAmount = negative.findViewById<TextView>(R.id.balance_widget_amount)
                    assertEquals("−₱123.45", negativeAmount.text.toString())
                    assertTrue(negative.contentDescription.contains("−₱123.45"))
                    assertTrue(negativeAmount.layout.lineCount in 1..2)
                    for (line in 0 until negativeAmount.layout.lineCount) {
                        assertEquals(0, negativeAmount.layout.getEllipsisCount(line))
                        assertTrue("negative amount clipped", negativeAmount.layout.getLineBottom(line) <= negativeAmount.height)
                    }
                    capture(negative, 128, 128, "029-style-widget-balance-negative-$style-$theme-$scale")

                    val large = QuickEntryWidget.views(context, 293)
                        .apply(context, FrameLayout(context))
                    size(large, 330, 180)
                    for (index in QuickEntryWidget.slots.indices) {
                        val cell = large.findViewById<View>(QuickEntryWidget.slots[index])
                        val label = large.findViewById<TextView>(QuickEntryWidget.labels[index])
                        assertTrue("large target too small: $style/$theme/$scale", cell.width >= 48 && cell.height >= 48)
                        assertTrue(cell.isClickable)
                        assertEquals("Add ${labels[index]} entry", cell.contentDescription)
                        assertEquals(1, label.layout.lineCount)
                        assertTrue("large label clipped vertically", label.layout.getLineBottom(0) <= label.height)
                        assertTrue(label.bottom <= cell.height)
                        assertTrue("long large label should ellipsize", label.layout.getEllipsisCount(0) > 0)
                    }
                    assertFalse(allText(large).contains("123"))
                    capture(large, 330, 180, "029-style-widget-quick-large-$style-$theme-$scale")
                }
            }
        } finally {
            @Suppress("DEPRECATION")
            context.resources.updateConfiguration(original, context.resources.displayMetrics)
            prefs.edit().clear().commit()
        }
    }
    private fun allText(view: View): String = if (view is TextView) view.text.toString() else if (view is android.view.ViewGroup) (0 until view.childCount).joinToString(" ") { allText(view.getChildAt(it)) } else ""
}
