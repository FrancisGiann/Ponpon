package dev.giann.pocket_entry

import android.app.Activity
import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var ledgerChannel: LedgerChannel? = null
    private var initialRoute: QuickEntryPolicy.Route? = null
    private var initialBills = false
    private var permissionForBills = false
    private fun billsRoute(source: Intent?) = source?.action == BillReminder.OPEN && source?.dataString == BillReminder.URI
    private var fileResult: MethodChannel.Result? = null
    private var exportText: String? = null
    private var permissionResult: MethodChannel.Result? = null
    private val maxBytes = 5 * 1024 * 1024

    override fun onCreate(savedInstanceState: Bundle?) {
        val privatePreview = getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).getBoolean("privatePreview", true)
        if (privatePreview) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        initialBills = billsRoute(intent)
        initialRoute = route(intent)
        consumeIntent()
    }
    private fun route(source: Intent?): QuickEntryPolicy.Route? {
        val parsed = QuickEntryPolicy.parse(source?.action, source?.dataString) ?: return null
        val widget = parsed.widgetId
        if (widget != null) {
            if (!QuickEntryWidget.ownsWidget(this, widget)) return QuickEntryPolicy.Route(null, null)
        }
        return parsed
    }
    private fun consumeIntent() { intent?.action = Intent.ACTION_MAIN; intent?.data = null }
    override fun onResume() {
        super.onResume()
        val private = getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).getBoolean("privatePreview", true)
        if (private) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        LedgerDisk.executor.execute { try { AllowanceJobs.reconcile(applicationContext) } catch (_: Exception) { } }
        try { DailyReminder.reconcile(this) } catch (_: RuntimeException) { }
        try { BillReminder.reconcile(this) } catch (_: RuntimeException) { }
    }
    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
        val bills = billsRoute(intent)
        val entry = route(intent); consumeIntent()
        if (bills) {
            if (channel == null) initialBills = true else channel?.invokeMethod("quickEntry", mapOf("bills" to true))
        }
        else if (entry != null) channel?.invokeMethod("quickEntry", mapOf("categoryId" to entry.categoryId, "kind" to entry.kind, "walletId" to entry.walletId))
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        ledgerChannel = LedgerChannel(applicationContext, engine.dartExecutor.binaryMessenger)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.giann.pocket_entry/native")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPrivatePreview" -> {
                    if (call.argument<Boolean>("enabled") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "privatePath" -> { val folder = File(filesDir, "pocket_entry"); if (folder.isDirectory || folder.mkdirs()) result.success(folder.absolutePath) else result.error("storage", "Private storage is unavailable", null) }
                "initialEntry" -> { val entry = initialRoute; val bills = initialBills; initialRoute = null; initialBills = false; result.success(if (bills) mapOf("bills" to true) else entry?.let { mapOf("categoryId" to it.categoryId, "kind" to it.kind, "walletId" to it.walletId) }) }
                "reminderState" -> {
                    try { result.success(DailyReminder.reconcile(this)) }
                    catch (_: RuntimeException) { result.success(DailyReminder.state(this)) }
                }
                "setReminder" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    val minute = call.argument<Int>("minuteOfDay")
                    if (enabled == null || enabled && minute == null || minute != null && minute !in 0..1439) result.error("invalid", "Choose a valid reminder time", null)
                    else try { result.success(DailyReminder.configure(this, enabled, minute)) }
                    catch (_: RuntimeException) { result.error("reminder", "The reminder could not be scheduled. Try again.", null) }
                }
                "requestReminderPermission", "requestBillReminderPermission" -> {
                    val bills = call.method == "requestBillReminderPermission"
                    if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) result.success(if (bills) BillReminder.permitted(this) else DailyReminder.permitted(this))
                    else if (permissionResult != null) result.error("busy", "A notification choice is already open", null)
                    else { permissionForBills = bills; permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4103) }
                }
                "openNotificationSettings" -> {
                    try { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)); result.success(null) }
                    catch (_: Exception) { result.error("reminder", "Open Android Settings, then Ponpon notifications.", null) }
                }
                "syncAppearance" -> {
                    val theme = call.argument<String>("theme") ?: "system"
                    val visualStyle = WidgetStyle.normalize(call.argument<String>("visualStyle"))
                    val private = call.argument<Boolean>("privatePreview") ?: true
                    val balanceVisible = call.argument<Boolean>("balanceWidgetVisible") ?: false
                    val balance = call.argument<Any>("balanceCentavos")
                    val walletCount = call.argument<Int>("activeWalletCount")
                    val raw = call.argument<List<Map<String, String>>>("categories") ?: emptyList()
                    val bills = call.argument<List<Map<String, Any>>>("billReminders") ?: emptyList()
                    if (!BillReminder.valid(bills) || theme !in listOf("system", "light", "dark") || (balance !is Long && balance !is Int) || walletCount == null || walletCount !in 0..20 || raw.size > 4 || raw.any { !(it["id"] ?: "").matches(Regex("[a-zA-Z0-9_-]{1,80}")) || (it["name"] ?: "").isEmpty() || (it["name"] ?: "").length > 30 }) result.error("invalid", "Invalid widget configuration", null)
                    else {
                        if (private) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        try { WidgetSnapshot.apply(this, call.arguments as Map<*, *>); result.success(null) }
                        catch (_: RuntimeException) { result.error("storage", "Widget configuration could not be saved", null) }
                    }
                }
                "pinWidget" -> {
                    val manager = getSystemService(AppWidgetManager::class.java)
                    val provider = when {
                        call.argument<Boolean>("wideBalance") == true -> WideBalanceWidget::class.java
                        call.argument<Boolean>("walletOverview") == true -> WalletOverviewWidget::class.java
                        call.argument<Boolean>("incomeExpense") == true -> KindEntryWidget::class.java
                        call.argument<Boolean>("balance") == true -> BalanceEntryWidget::class.java
                        call.argument<Boolean>("compact") == true -> CompactEntryWidget::class.java
                        else -> QuickEntryWidget::class.java
                    }
                    result.success(manager.isRequestPinAppWidgetSupported && manager.requestPinAppWidget(ComponentName(this, provider), null, null))
                }
                "exportBackup" -> {
                    val text = call.argument<String>("text")
                    if (fileResult != null) result.error("busy", "A file choice is already open", null)
                    else if (text == null || text.toByteArray(Charsets.UTF_8).size > maxBytes) result.error("invalid", "Backup is too large", null)
                    else {
                        fileResult = result; exportText = text
                        val name = (call.argument<String>("name") ?: "Ponpon.json").replace(Regex("[^a-zA-Z0-9 ._-]"), "_").take(80)
                        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/json").putExtra(Intent.EXTRA_TITLE, name), 4101) }
                        catch (_: Exception) { finishFileError("A document picker is unavailable") }
                    }
                }
                "pickBackup" -> {
                    if (fileResult != null) result.error("busy", "A file choice is already open", null)
                    else {
                        fileResult = result
                        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/json").putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream")), 4102) }
                        catch (_: Exception) { finishFileError("A document picker is unavailable") }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        ledgerChannel?.close(); ledgerChannel = null
        super.cleanUpFlutterEngine(engine)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4103) { permissionResult?.success(if (permissionForBills) BillReminder.permitted(this) else DailyReminder.permitted(this)); permissionResult = null; permissionForBills = false }
    }
    private fun finishFileError(message: String) {
        fileResult?.error("document", message, null); fileResult = null; exportText = null
    }
    @Deprecated("Android callback required by the document-picker bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4101 && requestCode != 4102) return
        val result = fileResult ?: return // A process restart cancels this operation safely.
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(if (requestCode == 4101) false else null); fileResult = null; exportText = null; return }
        if (uri.scheme != "content") { finishFileError("Choose a file through the document picker"); return }
        val text = exportText; fileResult = null; exportText = null
        Thread {
            try {
                if (requestCode == 4101) {
                    requireNotNull(text)
                    val stream = contentResolver.openOutputStream(uri, "wt") ?: error("File could not be opened")
                    stream.use { it.write(text.toByteArray(Charsets.UTF_8)); it.flush() }
                    runOnUiThread { result.success(true) }
                } else {
                    val stream = contentResolver.openInputStream(uri) ?: error("File could not be opened")
                    val bytes = stream.use { input ->
                        val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                        while (true) { val n = input.read(buffer); if (n < 0) break; if (out.size() + n > maxBytes) error("Choose a backup smaller than 5 MB"); out.write(buffer, 0, n) }
                        out.toByteArray()
                    }
                    val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                    val decoded = decoder.decode(ByteBuffer.wrap(bytes)).toString()
                    runOnUiThread { result.success(decoded) }
                }
            } catch (_: Exception) { runOnUiThread { result.error("document", "Could not read or write this document", null) } }
        }.start()
    }
}
