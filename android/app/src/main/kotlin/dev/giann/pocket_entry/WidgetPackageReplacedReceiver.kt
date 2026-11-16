package dev.giann.pocket_entry

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Rebuilds persisted launcher RemoteViews after an app upgrade changes resource IDs. */
class WidgetPackageReplacedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        QuickEntryWidget.refresh(context.applicationContext)
    }
}
