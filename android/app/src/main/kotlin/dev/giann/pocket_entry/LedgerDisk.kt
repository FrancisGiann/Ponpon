package dev.giann.pocket_entry

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.Executors

/** One IO queue and OS lock for every Flutter engine. JSON and filenames stay
 * compatible; financial calculations remain entirely in the Dart domain. */
object LedgerDisk {
    const val MAX_BYTES = 5 * 1024 * 1024
    val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "ponpon-ledger-io").apply { isDaemon = true } }
    class Conflict : Exception()
    fun folder(context: Context): File = File(context.filesDir, "pocket_entry").also { check(it.isDirectory || it.mkdirs()) }
    @Synchronized private fun <T> locked(context: Context, operation: (File) -> T): T {
        val dir = folder(context)
        return RandomAccessFile(File(dir, "ledger.lock"), "rw").use { handle ->
            handle.channel.lock().use { operation(dir) }
        }
    }
    private fun revision(file: File): String {
        if (!file.exists()) return "missing"
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(32768)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    private fun bounded(file: File): ByteArray? = if (file.exists() && file.length() <= MAX_BYTES) file.readBytes() else null
    fun snapshot(context: Context): Map<String, Any?> = locked(context) { dir ->
        val current = File(dir, "ledger.json"); val previous = File(dir, "ledger.previous.json")
        mapOf("revision" to revision(current), "currentPresent" to current.exists(), "previousPresent" to previous.exists(), "current" to bounded(current), "previous" to bounded(previous))
    }
    private fun atomic(dir: File, name: String, bytes: ByteArray) {
        val stage = File(dir, "$name.next")
        FileOutputStream(stage).use { stream -> stream.write(bytes); stream.fd.sync() }
        check(stage.renameTo(File(dir, name))) { "Atomic save failed" }
    }
    private fun archiveUnreadable(dir: File, source: File) {
        val stage = File(dir, "ledger.unreadable.json.next")
        FileOutputStream(stage).use { output -> source.inputStream().use { it.copyTo(output) }; output.fd.sync() }
        check(stage.renameTo(File(dir, "ledger.unreadable.json")))
    }
    fun save(context: Context, expected: String, encoded: String, preserve: Boolean): String = locked(context) { dir ->
        val bytes = encoded.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_BYTES)
        val objectValue = JSONObject(encoded)
        require(objectValue.getString("application") == "pocket_entry" && objectValue.getJSONArray("entries").length() <= 20000)
        val current = File(dir, "ledger.json")
        if (revision(current) != expected) throw Conflict()
        if (current.exists()) {
            if (preserve) { val old = bounded(current); requireNotNull(old); atomic(dir, "ledger.previous.json", old) }
            else archiveUnreadable(dir, current)
        }
        atomic(dir, "ledger.json", bytes)
        revision(current)
    }
    fun ifCurrent(context: Context, expected: String, operation: () -> Unit): Boolean = locked(context) { dir ->
        if (revision(File(dir, "ledger.json")) != expected) false else { operation(); true }
    }
    /** Change only the existing widget-visibility preference under the same lock as ledger saves.
     * An unreadable or missing ledger is left untouched; no financial fields are synthesized. */
    fun toggleWidgetBalanceVisible(context: Context): Boolean? = locked(context) { dir ->
        val current = File(dir, "ledger.json")
        val old = bounded(current) ?: return@locked null
        val ledger = try { JSONObject(String(old, Charsets.UTF_8)) } catch (_: Exception) { return@locked null }
        if (ledger.optString("application") != "pocket_entry" || ledger.optString("currency") != "PHP" || ledger.optJSONArray("entries") == null) return@locked null
        val preferences = ledger.optJSONObject("preferences") ?: return@locked null
        val previousValue = preferences.opt("balanceWidgetVisible")
        if (previousValue != null && previousValue !is Boolean) return@locked null
        val visible = !(previousValue ?: false)
        preferences.put("balanceWidgetVisible", visible)
        val updated = ledger.toString().toByteArray(Charsets.UTF_8)
        require(updated.size <= MAX_BYTES)
        atomic(dir, "ledger.previous.json", old)
        atomic(dir, "ledger.json", updated)
        visible
    }
    fun allowanceEnabled(context: Context): Boolean = locked(context) { dir ->
        try { bounded(File(dir, "ledger.json"))?.let { JSONObject(String(it, Charsets.UTF_8)).optJSONObject("allowance")?.optBoolean("enabled", false) } == true }
        catch (_: Exception) { false }
    }
}
