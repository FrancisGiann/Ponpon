package dev.giann.pocket_entry

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ActionWidgetsTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val prefs get() = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
    private fun render(views: android.widget.RemoteViews, width: Int, height: Int): View =
        views.apply(context, FrameLayout(context)).also {
            it.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
            it.layout(0, 0, width, height)
        }

    @Test fun kindButtonsOpenTheCorrectDraftAndFitCompactSizes() {
        for (width in listOf(128, 180, 240)) {
            val view = render(KindEntryWidget.views(context, 301), width, width)
            for ((id, kind) in listOf(R.id.kind_expense to "expense", R.id.kind_income to "income")) {
                val button = view.findViewById<View>(id)
                assertTrue(button.isClickable && button.width >= 48 && button.height >= 48)
                button.performClick()
                val intent = Shadows.shadowOf(context as android.app.Application).nextStartedActivity
                assertEquals(kind, QuickEntryPolicy.parse(intent.action, intent.dataString)?.kind)
                assertFalse(intent.hasExtra("amount"))
                assertFalse(intent.hasExtra("wallet"))
            }
        }
    }

    @Test fun overviewPreservesOrderedWalletsIncludingZeroAndRefreshesPrivacy() {
        prefs.edit().clear().commit()
        val wallets = listOf(
            mapOf("id" to "second", "name" to "Emergency household expenses", "balanceCentavos" to 12345L),
            mapOf("id" to "first", "name" to "Daily", "balanceCentavos" to 0L),
            mapOf("id" to "third", "name" to "Savings", "balanceCentavos" to -250L),
            mapOf("id" to "fourth", "name" to "Other", "balanceCentavos" to 0L),
        )
        WidgetSnapshot.apply(context, mapOf("balanceCentavos" to 12095L, "activeWalletCount" to 4,
            "balanceWidgetVisible" to false, "wallets" to wallets))
        val hidden = render(WalletOverviewWidget.views(context, 302), 300, 300)
        assertEquals("Emergency household expenses", hidden.findViewById<TextView>(R.id.wallet_name_1).text.toString())
        assertEquals("Daily", hidden.findViewById<TextView>(R.id.wallet_name_2).text.toString())
        assertEquals("••••", hidden.findViewById<TextView>(R.id.wallet_amount_2).text.toString())
        assertEquals("+1 more in Ponpon", hidden.findViewById<TextView>(R.id.wallet_more).text.toString())
        val narrow = render(WalletOverviewWidget.views(context, 302), 220, 260)
        val longName = narrow.findViewById<TextView>(R.id.wallet_name_1)
        assertEquals(1, longName.layout.lineCount)
        assertTrue(longName.layout.getLineBottom(0) <= longName.height)
        assertTrue(narrow.findViewById<View>(R.id.wallet_row_1).width >= 48)
        hidden.findViewById<View>(R.id.wallet_row_2).performClick()
        val intent = Shadows.shadowOf(context as android.app.Application).nextStartedActivity
        assertEquals("first", QuickEntryPolicy.parse(intent.action, intent.dataString)?.walletId)
        prefs.edit().putBoolean("balanceVisible", true).commit()
        WalletOverviewWidget.views(context, 302).reapply(context, hidden)
        assertEquals("₱0.00", hidden.findViewById<TextView>(R.id.wallet_amount_2).text.toString())
        assertEquals("−₱2.50", hidden.findViewById<TextView>(R.id.wallet_amount_3).text.toString())
    }

    @Test fun overviewHandlesEmptyStateAndLargeText() {
        val original = Configuration(context.resources.configuration)
        try {
            val config = Configuration(original).apply { fontScale = 1.5f }
            @Suppress("DEPRECATION") context.resources.updateConfiguration(config, context.resources.displayMetrics)
            WidgetSnapshot.apply(context, mapOf("balanceCentavos" to 0L, "activeWalletCount" to 0,
                "balanceWidgetVisible" to true, "wallets" to emptyList<Any>()))
            val empty = render(WalletOverviewWidget.views(context, 303), 250, 220)
            assertEquals("—", empty.findViewById<TextView>(R.id.wallet_total).text.toString())
            assertEquals(View.VISIBLE, empty.findViewById<View>(R.id.wallet_empty).visibility)
            assertEquals(View.GONE, empty.findViewById<View>(R.id.wallet_row_1).visibility)
            WidgetSnapshot.apply(context, mapOf("balanceCentavos" to 0L, "activeWalletCount" to 3,
                "balanceWidgetVisible" to true, "wallets" to listOf(
                    mapOf("id" to "a", "name" to "Long first wallet name", "balanceCentavos" to 0L),
                    mapOf("id" to "b", "name" to "Second", "balanceCentavos" to 0L),
                    mapOf("id" to "c", "name" to "Third", "balanceCentavos" to 0L))))
            val resized = render(WalletOverviewWidget.views(context, 303), 250, 220)
            assertEquals(View.VISIBLE, resized.findViewById<View>(R.id.wallet_row_2).visibility)
            assertEquals(View.GONE, resized.findViewById<View>(R.id.wallet_row_3).visibility)
            assertEquals("+1 more in Ponpon", resized.findViewById<TextView>(R.id.wallet_more).text.toString())
        } finally {
            @Suppress("DEPRECATION") context.resources.updateConfiguration(original, context.resources.displayMetrics)
        }
    }

    @Test fun wideWidgetKeepsFourCategoryDraftTargetsUsableAndPrivate() {
        val original = Configuration(context.resources.configuration)
        val categories = listOf(
            mapOf("id" to "custom_food", "name" to "Daily household expenses", "icon" to "health"),
            mapOf("id" to "travel", "name" to "Travel", "icon" to "travel"),
            mapOf("id" to "bills", "name" to "Bills", "icon" to "bills"),
            mapOf("id" to "income", "name" to "Income", "icon" to "income"),
        )
        try {
            for (scale in listOf(1f, 1.5f)) {
                val config = Configuration(original).apply { fontScale = scale }
                @Suppress("DEPRECATION") context.resources.updateConfiguration(config, context.resources.displayMetrics)
                WidgetSnapshot.apply(context, mapOf("balanceCentavos" to 0L, "activeWalletCount" to 2,
                    "balanceWidgetVisible" to false, "categories" to categories))
                assertEquals("health", JSONArray(prefs.getString("categories", "[]"))
                    .getJSONObject(0).getString("icon"))
                for (width in listOf(220, 250, 350)) {
                    val view = render(WideBalanceWidget.views(context, 330, width), width, 128)
                    assertEquals("••••", view.findViewById<TextView>(R.id.wide_balance).text.toString())
                    assertEquals(view.paddingTop, view.findViewById<View>(R.id.wide_top).top)
                    assertEquals("Bills", view.findViewById<TextView>(R.id.wide_name_3).text.toString())
                    assertEquals("Income", view.findViewById<TextView>(R.id.wide_name_4).text.toString())
                    assertNotNull(view.findViewById<ImageView>(R.id.wide_icon_1).drawable)
                    val first = view.findViewById<View>(R.id.wide_category_1)
                    val second = view.findViewById<View>(R.id.wide_category_2)
                    val third = view.findViewById<View>(R.id.wide_category_3)
                    assertEquals(first.top, second.top)
                    assertEquals(first.top, third.top)
                    val add = view.findViewById<View>(R.id.wide_add)
                    assertTrue(add.isClickable && add.width >= 48 && add.height >= 48)
                    val eye = view.findViewById<View>(R.id.wide_visibility)
                    assertTrue(eye.isClickable && eye.width >= 48 && eye.height >= 48)
                    assertEquals("Show balance", eye.contentDescription)
                    assertTrue("eye ${eye.right} > balance ${view.findViewById<View>(R.id.wide_header).right} at $width/$scale; title ${view.findViewById<TextView>(R.id.wide_title).text}",
                        eye.right <= view.findViewById<View>(R.id.wide_header).right)
                    assertTrue(add.left >= view.findViewById<View>(R.id.wide_header).right)
                    assertTrue(view.findViewById<View>(R.id.wide_grid).top > view.findViewById<View>(R.id.wide_top).top)
                    add.performClick()
                    val generic = Shadows.shadowOf(context as android.app.Application).nextStartedActivity
                    assertEquals(QuickEntryPolicy.Route(null, null),
                        QuickEntryPolicy.parse(generic.action, generic.dataString))
                    for (id in listOf(R.id.wide_category_1, R.id.wide_category_2, R.id.wide_category_3, R.id.wide_category_4)) {
                        val target = view.findViewById<View>(id)
                        assertTrue("wide target $id at $width/$scale", target.isClickable && target.width >= 48 && target.height >= 48)
                        assertTrue(target.bottom <= view.height - 8)
                    }
                    val label = view.findViewById<TextView>(R.id.wide_name_1)
                    assertTrue("label at $width/$scale: line ${label.layout.getLineBottom(0)}, height ${label.height}, row ${view.findViewById<View>(R.id.wide_category_1).height}",
                        label.layout.getLineBottom(0) <= label.height)
                    assertEquals("Add expense entry in Daily household expenses. Choose a wallet to save.",
                        view.findViewById<View>(R.id.wide_category_1).contentDescription)
                    view.findViewById<View>(R.id.wide_category_3).performClick()
                    val bills = Shadows.shadowOf(context as android.app.Application).nextStartedActivity
                    assertEquals(QuickEntryPolicy.Route("bills", 330, kind = "expense"),
                        QuickEntryPolicy.parse(bills.action, bills.dataString))
                    assertFalse(bills.hasExtra("amount"))
                    assertFalse(bills.hasExtra("wallet"))
                    view.findViewById<View>(R.id.wide_category_4).performClick()
                    val income = Shadows.shadowOf(context as android.app.Application).nextStartedActivity
                    assertEquals(QuickEntryPolicy.Route("income", 330, kind = "income"),
                        QuickEntryPolicy.parse(income.action, income.dataString))
                }
            }
            prefs.edit().putBoolean("balanceVisible", true).commit()
            val shown = render(WideBalanceWidget.views(context, 331), 250, 128)
            assertEquals("₱0.00", shown.findViewById<TextView>(R.id.wide_balance).text.toString())
            prefs.edit().putLong("balanceCentavos", -125L).commit()
            WideBalanceWidget.views(context, 331).reapply(context, shown)
            assertEquals("−₱1.25", shown.findViewById<TextView>(R.id.wide_balance).text.toString())
            prefs.edit().putInt("activeWalletCount", 0).commit()
            WideBalanceWidget.views(context, 331).reapply(context, shown)
            assertEquals("—", shown.findViewById<TextView>(R.id.wide_balance).text.toString())
            WidgetSnapshot.apply(context, mapOf("balanceCentavos" to 0L, "activeWalletCount" to 0,
                "balanceWidgetVisible" to true, "categories" to emptyList<Any>()))
            val empty = render(WideBalanceWidget.views(context, 331), 250, 128)
            assertEquals(View.GONE, empty.findViewById<View>(R.id.wide_grid).visibility)
            assertEquals(View.VISIBLE, empty.findViewById<View>(R.id.wide_empty_add).visibility)
            empty.findViewById<View>(R.id.wide_empty_add).performClick()
            val generic = Shadows.shadowOf(context as android.app.Application).nextStartedActivity
            assertEquals(QuickEntryPolicy.Route(null, null),
                QuickEntryPolicy.parse(generic.action, generic.dataString))
        } finally {
            @Suppress("DEPRECATION") context.resources.updateConfiguration(original, context.resources.displayMetrics)
            prefs.edit().clear().commit()
        }
    }
}
