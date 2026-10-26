package dev.giann.pocket_entry

import java.net.URI

/** Links can open a draft, but never enter an amount or write data. */
object QuickEntryPolicy {
    const val ACTION = "dev.giann.pocket_entry.QUICK_ADD"
    data class Route(val categoryId: String?, val widgetId: Int?, val kind: String? = null, val walletId: String? = null)
    fun parse(action: String?, rawUri: String?): Route? {
        if (action != ACTION) return null
        if (rawUri == null) return Route(null, null)
        return try {
            val uri = URI(rawUri)
            if (uri.scheme != "pocketentry" || uri.host !in listOf("quick", "kind", "wallet", "wide") || uri.port != -1 || uri.userInfo != null || uri.fragment != null) return null
            val path = uri.path?.removePrefix("/") ?: return null
            val segments = path.split("/")
            val validId = Regex("[a-zA-Z0-9_-]{1,80}")
            if (segments.any { !it.matches(validId) }) return null
            if (uri.host == "wide") {
                if (segments.size != 2 || segments[0] !in listOf("income", "expense")) return null
            } else if (segments.size != 1 || uri.host == "kind" && segments[0] !in listOf("income", "expense")) return null
            val widget = uri.rawQuery?.let {
                if (!it.matches(Regex("widget=[0-9]{1,10}"))) return null
                it.removePrefix("widget=").toIntOrNull()?.takeIf { n -> n > 0 } ?: return null
            }
            when (uri.host) {
                "kind" -> Route(null, widget, kind = segments[0])
                "wallet" -> Route(null, widget, walletId = segments[0])
                "wide" -> Route(segments[1], widget, kind = segments[0])
                else -> Route(segments[0], widget)
            }
        } catch (_: Exception) { null }
    }
}
