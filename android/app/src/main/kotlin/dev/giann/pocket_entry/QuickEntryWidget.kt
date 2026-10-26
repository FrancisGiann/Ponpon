package dev.giann.pocket_entry

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

open class QuickEntryWidget : AppWidgetProvider() {
    protected open val compact = false
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, views(context, it, compact)) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, views(context, id, compact))
    }
    override fun onDeleted(context: Context, ids: IntArray) {
        // No per-widget ledger or wallet state exists to delete.
    }
    companion object {
        const val PREFS = "pocket_native"
        val slots = intArrayOf(R.id.category_one, R.id.category_two, R.id.category_three, R.id.category_four)
        val labels=intArrayOf(R.id.category_one_name,R.id.category_two_name,R.id.category_three_name,R.id.category_four_name)
        val icons=intArrayOf(R.id.category_one_icon,R.id.category_two_icon,R.id.category_three_icon,R.id.category_four_icon)
        private val lightIcons=mapOf("food" to R.drawable.category_food_light, "travel" to R.drawable.category_travel_light, "bills" to R.drawable.category_bills_light, "shopping" to R.drawable.category_shopping_light, "school" to R.drawable.category_school_light, "health" to R.drawable.category_health_light, "fun" to R.drawable.category_fun_light, "home" to R.drawable.category_home_light, "income" to R.drawable.category_income_light, "other" to R.drawable.category_other_light)
        private val darkIcons=mapOf("food" to R.drawable.category_food_dark, "travel" to R.drawable.category_travel_dark, "bills" to R.drawable.category_bills_dark, "shopping" to R.drawable.category_shopping_dark, "school" to R.drawable.category_school_dark, "health" to R.drawable.category_health_dark, "fun" to R.drawable.category_fun_dark, "home" to R.drawable.category_home_dark, "income" to R.drawable.category_income_dark, "other" to R.drawable.category_other_dark)
        fun iconResource(icon:String?, dark:Boolean):Int=(if(dark)darkIcons else lightIcons)[icon] ?: (if(dark)R.drawable.category_other_dark else R.drawable.category_other_light)
        fun categoryTone(icon: String?): String = when(icon) {
            "food", "home" -> "plum"
            "travel", "school" -> "blue"
            "bills", "shopping" -> "amber"
            "health", "income" -> "green"
            "fun" -> "rose"
            else -> "slate"
        }
        fun categoryColor(icon:String?, dark:Boolean):Int = Color.parseColor(when(categoryTone(icon)) {
            "plum" -> if(dark) "#E9CCE6" else "#5B315D"
            "blue" -> if(dark) "#BBD7FF" else "#285B8C"
            "amber" -> if(dark) "#EFCF9C" else "#84551C"
            "green" -> if(dark) "#ADE2C8" else "#246D53"
            "rose" -> if(dark) "#FFBAB3" else "#AA3429"
            "slate" -> if(dark) "#BBB3BD" else "#6A606F"
            else -> if(dark) "#BBB3BD" else "#6A606F"
        })
        fun categoryBackground(icon:String?, dark:Boolean):Int = when(categoryTone(icon)) {
            "plum" -> if(dark) R.drawable.widget_cell_plum_dark else R.drawable.widget_cell_plum_light
            "blue" -> if(dark) R.drawable.widget_cell_blue_dark else R.drawable.widget_cell_blue_light
            "amber" -> if(dark) R.drawable.widget_cell_amber_dark else R.drawable.widget_cell_amber_light
            "green" -> if(dark) R.drawable.widget_cell_green_dark else R.drawable.widget_cell_green_light
            "rose" -> if(dark) R.drawable.widget_cell_rose_dark else R.drawable.widget_cell_rose_light
            "slate" -> if(dark) R.drawable.widget_cell_slate_dark else R.drawable.widget_cell_slate_light
            else -> if(dark) R.drawable.widget_chip_dark else R.drawable.widget_chip
        }
        val defaultCategories = "[{\"id\":\"food\",\"name\":\"Food\",\"icon\":\"food\"},{\"id\":\"travel\",\"name\":\"Travel\",\"icon\":\"travel\"},{\"id\":\"bills\",\"name\":\"Bills\",\"icon\":\"bills\"},{\"id\":\"shopping\",\"name\":\"Shopping\",\"icon\":\"shopping\"}]"
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (provider in listOf(QuickEntryWidget::class.java, CompactEntryWidget::class.java, BalanceEntryWidget::class.java, KindEntryWidget::class.java, WalletOverviewWidget::class.java, WideBalanceWidget::class.java)) {
                manager.getAppWidgetIds(ComponentName(context, provider)).forEach {
                    manager.updateAppWidget(it, when (provider) {
                        BalanceEntryWidget::class.java -> BalanceEntryWidget.views(context, it)
                        KindEntryWidget::class.java -> KindEntryWidget.views(context, it)
                        WalletOverviewWidget::class.java -> WalletOverviewWidget.views(context, it)
                        WideBalanceWidget::class.java -> WideBalanceWidget.views(context, it)
                        else -> views(context, it, provider == CompactEntryWidget::class.java)
                    })
                }
            }
        }
        fun ownsWidget(context: Context, widgetId: Int): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return listOf(QuickEntryWidget::class.java, CompactEntryWidget::class.java, BalanceEntryWidget::class.java, KindEntryWidget::class.java, WalletOverviewWidget::class.java, WideBalanceWidget::class.java).any {
                manager.getAppWidgetIds(ComponentName(context, it)).contains(widgetId)
            }
        }
        fun pending(context: Context, widgetId: Int, index: Int, category: String?): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).setAction(QuickEntryPolicy.ACTION)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (category != null) intent.data = Uri.Builder().scheme("pocketentry").authority("quick").appendPath(category).appendQueryParameter("widget", widgetId.toString()).build()
            else intent.data = null
            return PendingIntent.getActivity(context, widgetId * 8 + index, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        fun views(context: Context, widgetId: Int, compact: Boolean = false): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val theme = prefs.getString("theme", "system")
            val style = WidgetStyle.from(context, prefs.getString("visualStyle", "original"), theme)
            val dark = style.dark
            val largeType = context.resources.configuration.fontScale > 1.2f
            val layout = if (compact) {
                if (largeType) R.layout.compact_entry_widget_large_type else R.layout.compact_entry_widget
            } else if (largeType) R.layout.quick_entry_widget_large_type else R.layout.quick_entry_widget
            val view = RemoteViews(context.packageName, layout)
            view.setViewVisibility(R.id.widget_hint, if(largeType) View.GONE else View.VISIBLE)
            view.setInt(R.id.widget_root, "setBackgroundResource", style.backgroundResource)
            view.setTextColor(R.id.widget_title, style.ink)
            view.setTextColor(R.id.widget_hint, style.secondary)
            view.setOnClickPendingIntent(R.id.widget_header, pending(context, widgetId, 0, null))
            val categories = try { JSONArray(prefs.getString("categories", defaultCategories)) } catch (_: Exception) { JSONArray(defaultCategories) }
            slots.forEachIndexed { index, slot ->
                val c = categories.optJSONObject(index)
                val id = c?.optString("id")?.takeIf { it.matches(Regex("[a-zA-Z0-9_-]{1,80}")) }
                if (id == null) view.setViewVisibility(slot, View.GONE)
                else {
                    val name = c.optString("name").take(30)
                    view.setViewVisibility(slot, View.VISIBLE)
                    val label = when {
                        compact && id == "school_supplies" && name == "School supplies" -> "School"
                        compact && !largeType && id == "shopping" && name == "Shopping" -> "Shop"
                        else -> name
                    }
                    view.setTextViewText(labels[index], label)
                    view.setImageViewResource(icons[index],iconResource(c.optString("icon"),dark))
                    view.setContentDescription(slot, "Add $name entry")
                    view.setTextColor(labels[index], if (style.name == "original") categoryColor(c.optString("icon"),dark) else style.accent)
                    view.setInt(slot, "setBackgroundResource", if (style.name == "original") categoryBackground(c.optString("icon"),dark) else style.cellResource)
                    view.setOnClickPendingIntent(slot, pending(context, widgetId, index + 1, id))
                }
            }
            view.setViewVisibility(R.id.category_grid,if(categories.length()>0)View.VISIBLE else View.GONE)
            view.setViewVisibility(R.id.widget_empty_add,if(categories.length()==0)View.VISIBLE else View.GONE)
            view.setInt(R.id.widget_empty_add,"setBackgroundResource",if (style.name == "original") { if(dark)R.drawable.widget_chip_dark else R.drawable.widget_chip } else style.cellResource)
            view.setTextColor(R.id.widget_empty_label,style.accent)
            view.setOnClickPendingIntent(R.id.widget_empty_add,pending(context,widgetId,5,null))
            view.setViewVisibility(R.id.widget_row_1,if(categories.length()>0)View.VISIBLE else View.GONE)
            view.setViewVisibility(R.id.widget_row_2,if(categories.length()>2)View.VISIBLE else View.GONE)
            view.setTextViewText(R.id.widget_hint, if (categories.length() == 0) "Tap to add an entry" else "Tap a category")
            return view
        }
    }
}
