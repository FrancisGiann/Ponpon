package dev.giann.pocket_entry

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Guarded cache update, shared by the activity and headless worker. */
object WidgetSnapshot {
    fun apply(context: Context, args: Map<*, *>) {
        val theme = args["theme"] as? String ?: "system"
        val private = args["privatePreview"] as? Boolean ?: true
        val visible = args["balanceWidgetVisible"] as? Boolean ?: false
        val balance = args["balanceCentavos"]
        val count = args["activeWalletCount"] as? Int
        val raw = args["categories"] as? List<*> ?: emptyList<Any>()
        @Suppress("UNCHECKED_CAST") val bills = args["billReminders"] as? List<Map<String, Any>> ?: emptyList()
        require(BillReminder.valid(bills) && theme in listOf("system", "light", "dark") && (balance is Long || balance is Int) && count != null && count in 0..20 && raw.size <= 4)
        val categories = JSONArray()
        for (row in raw) {
            require(row is Map<*, *>)
            val id = row["id"] as? String ?: ""; val name = row["name"] as? String ?: ""
            require(id.matches(Regex("[a-zA-Z0-9_-]{1,80}")) && name.isNotEmpty() && name.length <= 30)
            categories.put(JSONObject(row))
        }
        check(context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit()
            .putString("theme", theme).putBoolean("privatePreview", private).putString("categories", categories.toString())
            .putBoolean("balanceVisible", visible).putLong("balanceCentavos", (balance as Number).toLong())
            .putInt("activeWalletCount", count).putLong("balanceUpdatedAt", System.currentTimeMillis()).commit())
        QuickEntryWidget.refresh(context)
        BillReminder.configure(context, bills)
    }
}
