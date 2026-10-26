package dev.giann.pocket_entry

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

/** Draft actions only: recording still requires the app's explicit wallet save. */
class KindEntryWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ids.forEach { manager.updateAppWidget(it, views(context, it)) }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        manager.updateAppWidget(id, views(context, id))

    companion object {
        fun pending(context: Context, widgetId: Int, index: Int, authority: String, value: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).setAction(QuickEntryPolicy.ACTION)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .setData(Uri.Builder().scheme("pocketentry").authority(authority).appendPath(value)
                    .appendQueryParameter("widget", widgetId.toString()).build())
            return PendingIntent.getActivity(context, widgetId * 32 + index, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        fun views(context: Context, widgetId: Int): RemoteViews {
            val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
            val style = WidgetStyle.from(context, prefs.getString("visualStyle", "original"), prefs.getString("theme", "system"))
            return RemoteViews(context.packageName, R.layout.kind_entry_widget).apply {
                setInt(R.id.kind_root, "setBackgroundResource", style.backgroundResource)
                setTextColor(R.id.kind_title, style.ink)
                val minHeight = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 128)
                setViewVisibility(R.id.kind_title, if (minHeight < 160) View.GONE else View.VISIBLE)
                for ((index, id) in listOf(R.id.kind_expense, R.id.kind_income).withIndex()) {
                    setInt(id, "setBackgroundResource", style.cellResource)
                    setOnClickPendingIntent(id, pending(context, widgetId, index + 1, "kind", if (index == 0) "expense" else "income"))
                }
                setTextColor(R.id.kind_expense_label, style.accent)
                setTextColor(R.id.kind_income_label, style.accent)
            }
        }
    }
}

class WalletOverviewWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ids.forEach { manager.updateAppWidget(it, views(context, it)) }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        manager.updateAppWidget(id, views(context, id))

    companion object {
        val rows = intArrayOf(R.id.wallet_row_1, R.id.wallet_row_2, R.id.wallet_row_3)
        val names = intArrayOf(R.id.wallet_name_1, R.id.wallet_name_2, R.id.wallet_name_3)
        val amounts = intArrayOf(R.id.wallet_amount_1, R.id.wallet_amount_2, R.id.wallet_amount_3)
        fun views(context: Context, widgetId: Int): RemoteViews {
            val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
            val style = WidgetStyle.from(context, prefs.getString("visualStyle", "original"), prefs.getString("theme", "system"))
            val visible = prefs.getBoolean("balanceVisible", false)
            val synced = prefs.contains("balanceUpdatedAt")
            val wallets = try { JSONArray(prefs.getString("wallets", "[]")) } catch (_: Exception) { JSONArray() }
            val count = prefs.getInt("activeWalletCount", 0)
            val view = RemoteViews(context.packageName, R.layout.wallet_overview_widget)
            view.setInt(R.id.wallet_root, "setBackgroundResource", style.backgroundResource)
            view.setTextColor(R.id.wallet_title, style.ink)
            view.setTextColor(R.id.wallet_total, style.ink)
            view.setTextColor(R.id.wallet_hint, style.secondary)
            view.setImageViewResource(R.id.wallet_visibility_icon,
                if (visible) R.drawable.widget_visibility else R.drawable.widget_visibility_off)
            view.setInt(R.id.wallet_visibility_icon, "setColorFilter", style.secondary)
            view.setContentDescription(R.id.wallet_visibility, if (visible) "Hide balance" else "Show balance")
            view.setViewVisibility(R.id.wallet_visibility, if (synced) View.VISIBLE else View.GONE)
            view.setOnClickPendingIntent(R.id.wallet_visibility, WideBalanceWidget.visibilityPending(context, widgetId))
            view.setTextViewText(R.id.wallet_total, when {
                !synced || count == 0 -> "—"
                !visible -> "••••"
                else -> BalanceEntryWidget.money(prefs.getLong("balanceCentavos", 0))
            })
            view.setTextViewText(R.id.wallet_hint, when {
                !synced -> "Open Ponpon to sync"
                count == 0 -> "No active wallets · add one in Ponpon"
                !visible -> "Amounts hidden in Settings"
                else -> "$count active ${if (count == 1) "wallet" else "wallets"} · manual records"
            })
            val minHeight = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 300)
            val shown = minOf(if (minHeight < 260 || context.resources.configuration.fontScale > 1.2f) 2 else 3, wallets.length())
            for (index in rows.indices) {
                val wallet = wallets.optJSONObject(index)
                val id = wallet?.optString("id")?.takeIf { it.matches(Regex("[a-zA-Z0-9_-]{1,80}")) }
                if (index >= shown || id == null) { view.setViewVisibility(rows[index], View.GONE); continue }
                val name = wallet.optString("name").take(30)
                val amount = wallet.optLong("balanceCentavos", 0)
                view.setViewVisibility(rows[index], View.VISIBLE)
                view.setInt(rows[index], "setBackgroundResource", style.cellResource)
                view.setTextViewText(names[index], name)
                view.setTextColor(names[index], style.ink)
                view.setTextViewText(amounts[index], if (visible) BalanceEntryWidget.money(amount) else "••••")
                view.setTextColor(amounts[index], if (visible && amount < 0) style.danger else style.secondary)
                view.setContentDescription(rows[index], "$name. ${if (visible) BalanceEntryWidget.money(amount) else "Amount hidden"}. Add an entry to this wallet")
                view.setOnClickPendingIntent(rows[index], KindEntryWidget.pending(context, widgetId, index + 1, "wallet", id))
            }
            view.setViewVisibility(R.id.wallet_empty, if (shown == 0) View.VISIBLE else View.GONE)
            view.setTextColor(R.id.wallet_empty, style.secondary)
            view.setViewVisibility(R.id.wallet_more, if (wallets.length() > shown) View.VISIBLE else View.GONE)
            view.setTextViewText(R.id.wallet_more, "+${wallets.length() - shown} more in Ponpon")
            view.setTextColor(R.id.wallet_more, style.secondary)
            view.setOnClickPendingIntent(R.id.wallet_header, QuickEntryWidget.pending(context, widgetId, 0, null))
            return view
        }
    }
}
