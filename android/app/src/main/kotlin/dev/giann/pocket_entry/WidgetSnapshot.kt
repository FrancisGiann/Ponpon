package dev.giann.pocket_entry

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Guarded cache update, shared by the activity and headless worker. */
object WidgetSnapshot {
    fun apply(context: Context, args: Map<*, *>) {
        val theme = args["theme"] as? String ?: "system"
        val visualStyle = WidgetStyle.normalize(args["visualStyle"] as? String)
        val private = args["privatePreview"] as? Boolean ?: true
        val visible = args["balanceWidgetVisible"] as? Boolean ?: false
        val balance = args["balanceCentavos"]
        val count = args["activeWalletCount"] as? Int
        val raw = args["categories"] as? List<*> ?: emptyList<Any>()
        val wideRows = args["wideCategories"] as? List<*> ?: emptyList<Any>()
        val walletRows = args["wallets"] as? List<*> ?: emptyList<Any>()
        @Suppress("UNCHECKED_CAST") val bills = args["billReminders"] as? List<Map<String, Any>> ?: emptyList()
        require(BillReminder.valid(bills) && theme in listOf("system", "light", "dark") && (balance is Long || balance is Int) && count != null && count in 0..20 && raw.size <= 4 && wideRows.size <= 4 && walletRows.size <= 20)
        val categories = JSONArray()
        for (row in raw) {
            require(row is Map<*, *>)
            val id = row["id"] as? String ?: ""; val name = row["name"] as? String ?: ""
            require(id.matches(Regex("[a-zA-Z0-9_-]{1,80}")) && name.isNotEmpty() && name.length <= 30)
            categories.put(JSONObject(row))
        }
        val wideCategories = JSONArray()
        for (row in wideRows) {
            require(row is Map<*, *>)
            val id = row["id"] as? String ?: ""
            val name = row["name"] as? String ?: ""
            val kind = row["kind"] as? String ?: ""
            val icon = row["icon"] as? String ?: "other"
            require(id.matches(Regex("[a-zA-Z0-9_-]{1,80}")) && name.isNotBlank() && name.length <= 30 && kind in listOf("expense", "income") && icon in listOf("food", "travel", "bills", "shopping", "school", "health", "fun", "home", "income", "other"))
            wideCategories.put(JSONObject(mapOf("id" to id, "name" to name, "icon" to icon, "kind" to kind)))
        }
        val wallets = JSONArray()
        val ids = mutableSetOf<String>()
        for (row in walletRows) {
            require(row is Map<*, *>)
            val id = row["id"] as? String ?: ""
            val name = row["name"] as? String ?: ""
            val amount = row["balanceCentavos"]
            require(id.matches(Regex("[a-zA-Z0-9_-]{1,80}")) && ids.add(id) && name.isNotBlank() && name.length <= 30 && (amount is Long || amount is Int))
            wallets.put(JSONObject(mapOf("id" to id, "name" to name, "balanceCentavos" to (amount as Number).toLong())))
        }
        require(walletRows.isEmpty() || walletRows.size == count)
        check(context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit()
            .putString("theme", theme).putString("visualStyle", visualStyle)
            .putBoolean("privatePreview", private).putString("categories", categories.toString()).putString("wideCategories", wideCategories.toString())
            .putBoolean("balanceVisible", visible).putLong("balanceCentavos", (balance as Number).toLong()).putString("wallets", wallets.toString())
            .putInt("activeWalletCount", count).putLong("balanceUpdatedAt", System.currentTimeMillis()).commit())
        QuickEntryWidget.refresh(context)
        BillReminder.configure(context, bills)
    }
}
