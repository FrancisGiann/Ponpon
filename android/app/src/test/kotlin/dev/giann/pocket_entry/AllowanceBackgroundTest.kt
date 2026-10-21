package dev.giann.pocket_entry

import android.app.job.JobScheduler
import android.content.Context
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AllowanceBackgroundTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val dir get() = LedgerDisk.folder(context)
    private val jobs get() = context.getSystemService(JobScheduler::class.java)
    private fun encoded(enabled: Boolean = true, marker: String = "first") = JSONObject()
        .put("application", "pocket_entry").put("entries", org.json.JSONArray())
        .put("marker", marker).put("allowance", JSONObject().put("enabled", enabled)).toString()
    private fun revision() = LedgerDisk.snapshot(context)["revision"] as String
    @Before fun reset() { dir.listFiles()?.forEach { it.delete() }; jobs.cancelAll() }

    @Test fun atomicSaveKeepsPreviousAndStaleReaderCannotOverwrite() {
        val first = encoded(); val second = encoded(marker = "second")
        val missing = revision(); val firstRevision = LedgerDisk.save(context, missing, first, false)
        LedgerDisk.save(context, firstRevision, second, true)
        try { LedgerDisk.save(context, firstRevision, encoded(marker = "stale"), true); fail("Stale writer accepted") }
        catch (_: LedgerDisk.Conflict) { }
        assertEquals(second, File(dir, "ledger.json").readText())
        assertEquals(first, File(dir, "ledger.previous.json").readText())
    }
    @Test fun simultaneousEnginesOnlyOneCanCommitTheSameRevision() {
        val expected = LedgerDisk.save(context, revision(), encoded(), false)
        val start = CountDownLatch(1); val pool = Executors.newFixedThreadPool(2)
        try {
            val results = (1..2).map { index -> pool.submit<Boolean> {
                start.await()
                try { LedgerDisk.save(context, expected, encoded(marker = "writer$index"), true); true }
                catch (_: LedgerDisk.Conflict) { false }
            } }
            start.countDown()
            assertEquals(1, results.count { it.get(10, TimeUnit.SECONDS) })
            assertTrue(JSONObject(File(dir, "ledger.json").readText()).getString("marker").startsWith("writer"))
        } finally { pool.shutdownNow() }
    }
    @Test fun interruptedStageIsIgnoredAndNextSaveRetainsValidPrevious() {
        val old = encoded(); val expected = LedgerDisk.save(context, revision(), old, false)
        File(dir, "ledger.json.next").writeText("{interrupted")
        assertEquals(old, String(LedgerDisk.snapshot(context)["current"] as ByteArray))
        LedgerDisk.save(context, expected, encoded(marker = "retry"), true)
        assertEquals(old, File(dir, "ledger.previous.json").readText())
        assertFalse(File(dir, "ledger.json.next").exists())
    }
    @Test fun explicitRecoveryArchivesDamageWithoutReplacingPreviousBackup() {
        File(dir, "ledger.json").writeText("damaged bytes")
        File(dir, "ledger.previous.json").writeText(encoded(marker = "backup"))
        LedgerDisk.save(context, revision(), encoded(marker = "restored"), false)
        assertEquals("damaged bytes", File(dir, "ledger.unreadable.json").readText())
        assertEquals("backup", JSONObject(File(dir, "ledger.previous.json").readText()).getString("marker"))
    }
    @Test fun staleSnapshotCannotChangeWidgetCache() {
        val old = LedgerDisk.save(context, revision(), encoded(), false)
        LedgerDisk.save(context, old, encoded(marker = "latest"), true)
        var changed = false
        assertFalse(LedgerDisk.ifCurrent(context, old) { changed = true })
        assertFalse(changed)
        assertTrue(LedgerDisk.ifCurrent(context, revision()) { changed = true })
        assertTrue(changed)
    }
    @Test fun enabledScheduleUsesPersistedBoundedJobWithNoNetworkOrExactAlarm() {
        LedgerDisk.save(context, revision(), encoded(), false)
        AllowanceJobs.reconcile(context)
        val job = jobs.getPendingJob(AllowanceJobs.PERIODIC_ID)!!
        assertTrue(job.isPeriodic); assertTrue(job.isPersisted)
        assertEquals(TimeUnit.HOURS.toMillis(6), job.intervalMillis)
        assertEquals(android.app.job.JobInfo.NETWORK_TYPE_NONE, job.networkType)
        AllowanceJobs.reconcile(context)
        assertEquals(1, jobs.allPendingJobs.size)
        assertSame(job, jobs.getPendingJob(AllowanceJobs.PERIODIC_ID))
    }
    @Test fun disableCancelsPeriodicAndRecoveryAndRestartReconcilesEnabledLedger() {
        var version = LedgerDisk.save(context, revision(), encoded(), false)
        AllowanceJobs.reconcile(context, recoverNow = true)
        assertEquals(2, jobs.allPendingJobs.size)
        jobs.cancelAll() // Simulate lost scheduling state; ledger is authoritative.
        AllowanceJobs.reconcile(context, recoverNow = true)
        assertEquals(2, jobs.allPendingJobs.size)
        version = LedgerDisk.save(context, version, encoded(enabled = false), true)
        AllowanceJobs.reconcile(context, recoverNow = true)
        assertTrue(jobs.allPendingJobs.isEmpty())
        assertNotEquals("missing", version)
    }
    @Test fun missingOrUnreadableLedgerDoesNotScheduleFinancialWork() {
        AllowanceJobs.reconcile(context, recoverNow = true)
        assertTrue(jobs.allPendingJobs.isEmpty())
        File(dir, "ledger.json").writeText("broken")
        AllowanceJobs.reconcile(context, recoverNow = true)
        assertTrue(jobs.allPendingJobs.isEmpty())
    }
}
