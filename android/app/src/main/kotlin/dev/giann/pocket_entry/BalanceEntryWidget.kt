package dev.giann.pocket_entry

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.text.NumberFormat
import java.util.Locale

/** A derived snapshot only. Taps open a draft; no wallet or amount is injected. */
class BalanceEntryWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, views(context, it)) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, views(context, id))
    }

    companion object {
        fun money(centavos: Long): String {
            val whole = NumberFormat.getIntegerInstance(Locale.US).format(kotlin.math.abs(centavos) / 100)
            val fraction = (kotlin.math.abs(centavos) % 100).toString().padStart(2, '0')
            return "${if (centavos < 0) "−" else ""}₱$whole.$fraction"
        }

        fun views(context: Context, widgetId: Int): RemoteViews {
            val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
            val theme = prefs.getString("theme", "system")
            val systemDark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            val dark = theme == "dark" || theme == "system" && systemDark
            val visible = prefs.getBoolean("balanceVisible", false)
            val synced = prefs.contains("balanceUpdatedAt")
            val count = prefs.getInt("activeWalletCount", 0)
            val balance = prefs.getLong("balanceCentavos", 0)
            val amount = when {
                !synced || count == 0 -> "—"
                !visible -> "••••"
                else -> money(balance)
            }
            val scope = when {
                !synced -> "Open to sync"
                count == 0 -> "No active wallets"
                !visible -> "Amount hidden"
                else -> "$count active ${if (count == 1) "wallet" else "wallets"}"
            }
            val view = RemoteViews(context.packageName, R.layout.balance_entry_widget)
            val ink = Color.parseColor(if (dark) "#F7F3F1" else "#27212A")
            val muted = Color.parseColor(if (dark) "#BBB3BD" else "#6A606F")
            val accent = Color.parseColor(if (dark) "#E9CCE6" else "#5B315D")
            view.setInt(R.id.balance_widget_root, "setBackgroundResource", if (dark) R.drawable.widget_background_dark else R.drawable.widget_background)
            view.setTextColor(R.id.balance_widget_title, muted)
            view.setTextColor(R.id.balance_widget_amount, if (visible && balance < 0 && count > 0) Color.parseColor(if (dark) "#FFBAB3" else "#AA3429") else ink)
            view.setTextColor(R.id.balance_widget_scope, muted)
            view.setTextColor(R.id.balance_widget_add_label, accent)
            view.setTextColor(R.id.balance_widget_compact_action, accent)
            view.setTextViewText(R.id.balance_widget_amount, amount)
            view.setTextViewText(R.id.balance_widget_scope, scope)
            view.setInt(R.id.balance_widget_add, "setBackgroundResource", if (dark) R.drawable.widget_cell_plum_dark else R.drawable.widget_cell_plum_light)
            view.setImageViewResource(R.id.balance_widget_add_icon, QuickEntryWidget.iconResource("income", dark))
            val minHeight = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 128)
            val compactType = context.resources.configuration.fontScale > 1.2f && minHeight < 160
            view.setTextViewText(R.id.balance_widget_title, if (compactType) "Tracked" else "Tracked balance")
            view.setViewVisibility(R.id.balance_widget_scope, if (compactType) View.GONE else View.VISIBLE)
            view.setViewVisibility(R.id.balance_widget_add_icon, if (compactType) View.GONE else View.VISIBLE)
            view.setViewVisibility(R.id.balance_widget_add_label, if (compactType) View.GONE else View.VISIBLE)
            view.setViewVisibility(R.id.balance_widget_compact_action, if (compactType) View.VISIBLE else View.GONE)
            view.setTextViewText(R.id.balance_widget_compact_action, when {
                !synced -> "Open to sync\nAdd entry"
                count == 0 -> "No active wallets\nAdd entry"
                else -> "$count active ${if (count == 1) "wallet" else "wallets"}\nAdd entry"
            })
            val readout = when {
                !synced -> "Tracked balance. Open Ponpon to sync. Add an entry."
                count == 0 -> "Tracked balance. No active wallets. Add an entry."
                !visible -> "Tracked balance. Amount hidden. $count active wallets. Add an entry."
                else -> "Total tracked balance ${money(balance)} from $count active wallets, manual records. Add an entry."
            }
            view.setContentDescription(R.id.balance_widget_root, readout)
            val pending = QuickEntryWidget.pending(context, widgetId, 0, null)
            view.setOnClickPendingIntent(R.id.balance_widget_root, pending)
            view.setOnClickPendingIntent(R.id.balance_widget_add, pending)
            return view
        }
    }
}
