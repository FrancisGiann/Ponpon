package dev.giann.pocket_entry

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color

/** Shared, static appearance tokens used by all launcher widget providers. */
data class WidgetStyle(
    val name: String,
    val dark: Boolean,
    val backgroundResource: Int,
    val cellResource: Int,
    val categoryOutlineResource: Int,
    val backgroundColor: Int,
    val cellColor: Int,
    val ink: Int,
    val secondary: Int,
    val accent: Int,
    val danger: Int,
) {
    companion object {
        private val names = setOf("original", "powderBlue", "notebook", "midnight")

        fun normalize(value: String?): String = value?.takeIf { it in names } ?: "original"

        fun from(context: Context, name: String?, theme: String?): WidgetStyle {
            val style = normalize(name)
            val systemDark = context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            val dark = style == "midnight" || theme == "dark" || theme == "system" && systemDark
            val colors = when (style) {
                "powderBlue" -> if (dark) listOf("#142431", "#304F66", "#EDF7FF", "#B8CCD9", "#B7D9F1", "#FFBAB3")
                    else listOf("#EFF6FC", "#E1EDF5", "#173447", "#4B6274", "#244E6D", "#AA3429")
                "notebook" -> if (dark) listOf("#25231F", "#4B4030", "#F5ECDD", "#C9BCA7", "#E3C895", "#FFBAB3")
                    else listOf("#F6F1E5", "#F2E8D5", "#302A23", "#685C4D", "#55432B", "#AA3429")
                "midnight" -> listOf("#0C1420", "#243D5B", "#F0F5FF", "#B8C8DC", "#C1DCFF", "#FFBAB3")
                else -> if (dark) listOf("#232125", "#382E3C", "#F7F3F1", "#BBB3BD", "#E9CCE6", "#FFBAB3")
                    else listOf("#F6F4F1", "#F0E8F1", "#27212A", "#6A606F", "#5B315D", "#AA3429")
            }
            val root = when (style) {
                "powderBlue" -> if (dark) R.drawable.widget_background_powder_blue_dark else R.drawable.widget_background_powder_blue
                "notebook" -> if (dark) R.drawable.widget_background_notebook_dark else R.drawable.widget_background_notebook
                "midnight" -> R.drawable.widget_background_midnight
                else -> if (dark) R.drawable.widget_background_dark else R.drawable.widget_background
            }
            val cell = when (style) {
                "powderBlue" -> if (dark) R.drawable.widget_cell_powder_blue_dark else R.drawable.widget_cell_powder_blue
                "notebook" -> if (dark) R.drawable.widget_cell_notebook_dark else R.drawable.widget_cell_notebook
                "midnight" -> R.drawable.widget_cell_midnight
                else -> if (dark) R.drawable.widget_chip_dark else R.drawable.widget_chip
            }
            val categoryOutline = when (style) {
                "powderBlue" -> if (dark) R.drawable.widget_category_outline_powder_blue_dark else R.drawable.widget_category_outline_powder_blue
                "notebook" -> if (dark) R.drawable.widget_category_outline_notebook_dark else R.drawable.widget_category_outline_notebook
                "midnight" -> R.drawable.widget_category_outline_midnight
                else -> if (dark) R.drawable.widget_category_outline_dark else R.drawable.widget_category_outline
            }
            return WidgetStyle(
                style,
                dark,
                root,
                cell,
                categoryOutline,
                Color.parseColor(colors[0]),
                Color.parseColor(colors[1]),
                Color.parseColor(colors[2]),
                Color.parseColor(colors[3]),
                Color.parseColor(colors[4]),
                Color.parseColor(colors[5]),
            )
        }
    }
}
