package dev.giann.pocket_entry

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class LedgerChannel(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private var closed = false
    private val owner = UUID.randomUUID().toString()
    private val channel = MethodChannel(messenger, "dev.giann.pocket_entry/ledger")
    companion object {
        private val main = Handler(Looper.getMainLooper())
        private val listeners = mutableMapOf<String, MethodChannel>()
        fun notifyChanged() {
            main.post { listeners.values.toList().forEach { it.invokeMethod("ledgerChanged", null) } }
        }
    }
    init {
        listeners[owner] = channel
        channel.setMethodCallHandler { call, result ->
            LedgerDisk.executor.execute {
                try {
                    val value: Any? = when (call.method) {
                        "privatePath" -> LedgerDisk.folder(this.context).absolutePath
                        "snapshot" -> LedgerDisk.snapshot(this.context)
                        "save" -> {
                            val revision = LedgerDisk.save(this.context,
                                requireNotNull(call.argument<String>("expectedRevision")),
                                requireNotNull(call.argument<String>("encoded")),
                                call.argument<Boolean>("preserveCurrent") == true)
                            try { AllowanceJobs.reconcile(this.context) } catch (_: RuntimeException) { }
                            main.post { listeners.filterKeys { it != owner }.values.toList().forEach { it.invokeMethod("ledgerChanged", null) } }
                            revision
                        }
                        "syncSnapshot" -> {
                            val args = call.arguments as? Map<*, *> ?: error("Invalid snapshot")
                            val revision = args["ledgerRevision"] as? String ?: error("Missing revision")
                            if (!LedgerDisk.ifCurrent(this.context, revision) { WidgetSnapshot.apply(this.context, args) }) throw LedgerDisk.Conflict()
                            try { AllowanceJobs.reconcile(this.context) } catch (_: RuntimeException) { }
                            null
                        }
                        else -> { main.post { if (!closed) result.notImplemented() }; return@execute }
                    }
                    main.post { if (!closed) result.success(value) }
                } catch (_: LedgerDisk.Conflict) { main.post { if (!closed) result.error("conflict", "Records changed; refresh before saving", null) } }
                catch (_: Exception) { main.post { if (!closed) result.error("storage", "Private records could not be read or saved", null) } }
            }
        }
    }
    fun close() { closed = true; listeners.remove(owner); channel.setMethodCallHandler(null) }
}
