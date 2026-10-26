package dev.giann.pocket_entry

import android.content.Context
import android.os.Looper
import android.widget.FrameLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetVisibilityTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val prefs get() = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)

    @Before fun reset() {
        LedgerDisk.folder(context).listFiles()?.forEach { it.delete() }
        prefs.edit().clear().commit()
    }

    private fun saveLedger() {
        val encoded = JSONObject()
            .put("application", "pocket_entry")
            .put("currency", "PHP")
            .put("entries", JSONArray().put(JSONObject().put("id", "synthetic-entry").put("centavos", 12345)))
            .put("preferences", JSONObject().put("balanceWidgetVisible", false).put("theme", "system"))
            .toString()
        LedgerDisk.save(context, LedgerDisk.snapshot(context)["revision"] as String, encoded, false)
        WidgetSnapshot.apply(context, mapOf(
            "balanceCentavos" to 12345L,
            "activeWalletCount" to 1,
            "balanceWidgetVisible" to false,
            "wallets" to listOf(mapOf("id" to "cash", "name" to "Cash", "balanceCentavos" to 12345L)),
            "categories" to listOf(mapOf("id" to "food", "name" to "Food", "icon" to "food")),
        ))
    }

    private fun ledger() = JSONObject(String(LedgerDisk.snapshot(context)["current"] as ByteArray))

    @Test fun eyeClickTogglesThePersistedGlobalPreferenceAndEveryBalanceWidget() {
        saveLedger()
        val originalEntries = ledger().getJSONArray("entries").toString()
        val beforeTap = LedgerDisk.snapshot(context)["revision"] as String
        val hidden = WideBalanceWidget.views(context, 501).apply(context, FrameLayout(context))
        val eye = hidden.findViewById<android.view.View>(R.id.wide_visibility)
        assertTrue(eye.isClickable)
        assertEquals("Show balance", eye.contentDescription)
        assertEquals("••••", hidden.findViewById<TextView>(R.id.wide_balance).text.toString())
        eye.performClick()
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        LedgerDisk.executor.submit { }.get(10, TimeUnit.SECONDS)
        assertTrue(ledger().getJSONObject("preferences").getBoolean("balanceWidgetVisible"))
        assertFalse(LedgerDisk.ifCurrent(context, beforeTap) { fail("Stale widget snapshot accepted") })
        assertEquals(originalEntries, ledger().getJSONArray("entries").toString())
        assertTrue(prefs.getBoolean("balanceVisible", false))
        assertFalse(JSONObject(LedgerDisk.folder(context).resolve("ledger.previous.json").readText())
            .getJSONObject("preferences").getBoolean("balanceWidgetVisible"))
        val wideShown = WideBalanceWidget.views(context, 501).apply(context, FrameLayout(context))
        assertEquals("Hide balance", wideShown.findViewById<android.view.View>(R.id.wide_visibility).contentDescription)
        assertEquals("₱123.45", wideShown.findViewById<TextView>(R.id.wide_balance).text.toString())
        val compactShown = BalanceEntryWidget.views(context, 502).apply(context, FrameLayout(context))
        assertEquals("₱123.45", compactShown.findViewById<TextView>(R.id.balance_widget_amount).text.toString())
        assertEquals("Hide balance", compactShown.findViewById<android.view.View>(R.id.balance_widget_visibility).contentDescription)
        val walletsShown = WalletOverviewWidget.views(context, 503).apply(context, FrameLayout(context))
        assertEquals("₱123.45", walletsShown.findViewById<TextView>(R.id.wallet_total).text.toString())
        assertEquals("₱123.45", walletsShown.findViewById<TextView>(R.id.wallet_amount_1).text.toString())

        compactShown.findViewById<android.view.View>(R.id.balance_widget_visibility).performClick()
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        LedgerDisk.executor.submit { }.get(10, TimeUnit.SECONDS)
        assertFalse(ledger().getJSONObject("preferences").getBoolean("balanceWidgetVisible"))
        assertFalse(prefs.getBoolean("balanceVisible", true))
        val compactHidden = BalanceEntryWidget.views(context, 502).apply(context, FrameLayout(context))
        assertEquals("••••", compactHidden.findViewById<TextView>(R.id.balance_widget_amount).text.toString())
        val walletsHidden = WalletOverviewWidget.views(context, 503).apply(context, FrameLayout(context))
        assertEquals("••••", walletsHidden.findViewById<TextView>(R.id.wallet_total).text.toString())
        assertEquals("••••", walletsHidden.findViewById<TextView>(R.id.wallet_amount_1).text.toString())
        assertEquals(originalEntries, ledger().getJSONArray("entries").toString())
        walletsHidden.findViewById<android.view.View>(R.id.wallet_visibility).performClick()
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        LedgerDisk.executor.submit { }.get(10, TimeUnit.SECONDS)
        assertTrue(ledger().getJSONObject("preferences").getBoolean("balanceWidgetVisible"))
        assertEquals("₱123.45", WideBalanceWidget.views(context, 501)
            .apply(context, FrameLayout(context)).findViewById<TextView>(R.id.wide_balance).text.toString())
    }

    @Test fun unreadableLedgerCannotBeReplacedByPrivacyTap() {
        LedgerDisk.folder(context).resolve("ledger.json").writeText("{broken")
        prefs.edit().putBoolean("balanceVisible", false).commit()
        assertFalse(WideBalanceWidget.toggleVisibility(context))
        assertEquals("{broken", LedgerDisk.folder(context).resolve("ledger.json").readText())
        assertFalse(prefs.getBoolean("balanceVisible", true))
    }
}
