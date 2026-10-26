package dev.giann.pocket_entry

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

/** The balance and selected quick categories in one horizontal widget. Taps open drafts only. */
class WideBalanceWidget : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE_BALANCE) {
            super.onReceive(context, intent)
            return
        }
        val result = goAsync()
        LedgerDisk.executor.execute {
            try { toggleVisibility(context) } catch (_: Exception) { /* Keep the current privacy state. */ }
            finally { result.finish() }
        }
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        ids.forEach { manager.updateAppWidget(it, views(context, it)) }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        manager.updateAppWidget(id, views(context, id))

    companion object {
        const val ACTION_TOGGLE_BALANCE = "dev.giann.pocket_entry.TOGGLE_WIDGET_BALANCE"
        private val cells = intArrayOf(R.id.wide_category_1, R.id.wide_category_2, R.id.wide_category_3, R.id.wide_category_4)
        private val icons = intArrayOf(R.id.wide_icon_1, R.id.wide_icon_2, R.id.wide_icon_3, R.id.wide_icon_4)
        private val names = intArrayOf(R.id.wide_name_1, R.id.wide_name_2, R.id.wide_name_3, R.id.wide_name_4)

        /** One global privacy setting, shared with Settings and every balance widget. */
        fun toggleVisibility(context: Context): Boolean {
            val visible = LedgerDisk.toggleWidgetBalanceVisible(context) ?: return false
            context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("balanceVisible", visible).apply()
            QuickEntryWidget.refresh(context)
            LedgerChannel.notifyChanged()
            return true
        }

        fun visibilityPending(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, WideBalanceWidget::class.java).setAction(ACTION_TOGGLE_BALANCE)
                .setData(Uri.Builder().scheme("pocketentry").authority("wide")
                    .appendPath("visibility").appendPath(widgetId.toString()).build())
            return PendingIntent.getBroadcast(context, widgetId * 32 + 31, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun pending(context: Context, widgetId: Int, index: Int, kind: String, id: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).setAction(QuickEntryPolicy.ACTION)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .setData(Uri.Builder().scheme("pocketentry").authority("wide")
                    .appendPath(kind).appendPath(id).appendQueryParameter("widget", widgetId.toString()).build())
            return PendingIntent.getActivity(context, widgetId * 32 + index + 8, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun views(context: Context, widgetId: Int, minWidthHint: Int? = null): RemoteViews {
            val prefs = context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE)
            val style = WidgetStyle.from(context, prefs.getString("visualStyle", "original"), prefs.getString("theme", "system"))
            val visible = prefs.getBoolean("balanceVisible", false)
            val synced = prefs.contains("balanceUpdatedAt")
            val count = prefs.getInt("activeWalletCount", 0)
            val amount = prefs.getLong("balanceCentavos", 0)
            // This is the same persisted selection and order as the existing quick-entry widget.
            val raw = prefs.getString("categories", QuickEntryWidget.defaultCategories)
            val categories = try { JSONArray(raw) } catch (_: Exception) { JSONArray(QuickEntryWidget.defaultCategories) }
            return RemoteViews(context.packageName, R.layout.wide_balance_widget).apply {
                val largeType = context.resources.configuration.fontScale > 1.2f
                val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
                val minWidth = minWidthHint ?: options
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 330)
                val hostWidth = minWidthHint ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth)
                if (hostWidth < 260) setTextViewText(R.id.wide_title, "Balance")
                if (largeType) {
                    setTextViewTextSize(R.id.wide_title, TypedValue.COMPLEX_UNIT_SP, 9f)
                    setTextViewTextSize(R.id.wide_balance, TypedValue.COMPLEX_UNIT_SP, 21f)
                    setTextViewTextSize(R.id.wide_scope, TypedValue.COMPLEX_UNIT_SP, 9f)
                    names.forEach { setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, 9f) }
                }
                setInt(R.id.wide_root, "setBackgroundResource", style.backgroundResource)
                setTextColor(R.id.wide_title, style.secondary)
                setTextColor(R.id.wide_balance, if (visible && amount < 0 && count > 0) style.danger else style.ink)
                setTextColor(R.id.wide_scope, style.secondary)
                setImageViewResource(R.id.wide_visibility_icon,
                    if (visible) R.drawable.widget_visibility else R.drawable.widget_visibility_off)
                setInt(R.id.wide_visibility_icon, "setColorFilter", style.secondary)
                setContentDescription(R.id.wide_visibility, if (visible) "Hide balance" else "Show balance")
                setViewVisibility(R.id.wide_visibility, if (synced) View.VISIBLE else View.GONE)
                setOnClickPendingIntent(R.id.wide_visibility, visibilityPending(context, widgetId))
                setTextColor(R.id.wide_add_label, style.accent)
                setTextColor(R.id.wide_empty_label, style.accent)
                setInt(R.id.wide_add, "setBackgroundResource", style.cellResource)
                setInt(R.id.wide_empty_add, "setBackgroundResource", style.cellResource)
                setImageViewResource(R.id.wide_add_icon, QuickEntryWidget.iconResource("income", style.dark))
                setTextViewText(R.id.wide_balance, when {
                    !synced || count == 0 -> "—"
                    !visible -> "••••"
                    else -> BalanceEntryWidget.money(amount)
                })
                setTextViewText(R.id.wide_scope, when {
                    !synced -> "Open to sync"
                    count == 0 -> "No wallets"
                    context.resources.configuration.fontScale > 1.2f -> "$count ${if (count == 1) "wallet" else "wallets"}"
                    else -> "$count active ${if (count == 1) "wallet" else "wallets"}"
                })
                setContentDescription(R.id.wide_header, when {
                    !synced -> "Tracked balance. Open Ponpon to sync."
                    count == 0 -> "Tracked balance. No active wallets."
                    !visible -> "Tracked balance. Amount hidden. $count active wallets."
                    else -> "Tracked balance ${BalanceEntryWidget.money(amount)} from $count active wallets."
                })
                val add = QuickEntryWidget.pending(context, widgetId, 0, null)
                setOnClickPendingIntent(R.id.wide_header, add)
                setOnClickPendingIntent(R.id.wide_add, add)
                setOnClickPendingIntent(R.id.wide_empty_add, add)
                setViewVisibility(R.id.wide_grid, if (categories.length() == 0) View.GONE else View.VISIBLE)
                setViewVisibility(R.id.wide_empty_add, if (categories.length() == 0) View.VISIBLE else View.GONE)
                for (index in cells.indices) {
                    val item = categories.optJSONObject(index)
                    val id = item?.optString("id")?.takeIf { it.matches(Regex("[a-zA-Z0-9_-]{1,80}")) }
                    if (id == null) {
                        setViewVisibility(cells[index], View.GONE)
                        continue
                    }
                    val name = item.optString("name").take(30)
                    val icon = item.optString("icon").ifBlank { id }
                    val kind = if (icon == "income" || id == "income") "income" else "expense"
                    setViewVisibility(cells[index], View.VISIBLE)
                    setInt(cells[index], "setBackgroundResource", style.categoryOutlineResource)
                    setImageViewResource(icons[index], QuickEntryWidget.iconResource(icon, style.dark))
                    setTextViewText(names[index], name)
                    setTextColor(names[index], QuickEntryWidget.categoryColor(icon, style.dark))
                    setContentDescription(cells[index], "Add $kind entry in $name. Choose a wallet to save.")
                    setOnClickPendingIntent(cells[index], pending(context, widgetId, index + 1, kind, id))
                }
            }
        }
    }
}
