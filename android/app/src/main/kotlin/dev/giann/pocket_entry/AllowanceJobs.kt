package dev.giann.pocket_entry

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

/** Bounded, offline bookkeeping. Android chooses execution time; foreground
 * catch-up remains essential, especially after force-stop or battery limits. */
object AllowanceJobs {
    const val PERIODIC_ID = 6301
    const val RECOVERY_ID = 6302
    val intervalMillis = TimeUnit.HOURS.toMillis(6)
    fun reconcile(context: Context, recoverNow: Boolean = false) {
        val jobs = context.getSystemService(JobScheduler::class.java)
        if (!LedgerDisk.allowanceEnabled(context)) {
            jobs.cancel(PERIODIC_ID); jobs.cancel(RECOVERY_ID); return
        }
        val service = ComponentName(context, AllowanceJobService::class.java)
        // Do not reset the execution window on every ordinary entry save.
        if (jobs.getPendingJob(PERIODIC_ID) == null) {
            check(jobs.schedule(JobInfo.Builder(PERIODIC_ID, service)
                .setPeriodic(intervalMillis, TimeUnit.HOURS.toMillis(1))
                .setPersisted(true).build()) == JobScheduler.RESULT_SUCCESS)
        }
        if (recoverNow && jobs.getPendingJob(RECOVERY_ID) == null) {
            check(jobs.schedule(JobInfo.Builder(RECOVERY_ID, service)
                .setMinimumLatency(0).setBackoffCriteria(30000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .build()) == JobScheduler.RESULT_SUCCESS)
        }
    }
}

class AllowanceWakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return
        val pending = goAsync()
        LedgerDisk.executor.execute {
            try { AllowanceJobs.reconcile(context.applicationContext, recoverNow = true) }
            catch (_: Exception) { /* Launch/resume is the durable fallback. */ }
            finally { pending.finish() }
        }
    }
}

class AllowanceJobService : JobService() {
    private var engine: FlutterEngine? = null
    private var ledgerChannel: LedgerChannel? = null
    private var active: JobParameters? = null
    private val main = Handler(Looper.getMainLooper())
    private val timeout = Runnable { active?.let { finish(it, true) } }

    override fun onStartJob(params: JobParameters): Boolean {
        if (active != null) return false
        active = params
        try {
            val worker = FlutterEngine(applicationContext)
            engine = worker
            ledgerChannel = LedgerChannel(applicationContext, worker.dartExecutor.binaryMessenger)
            MethodChannel(worker.dartExecutor.binaryMessenger, "dev.giann.pocket_entry/allowance_job")
                .setMethodCallHandler { call, result ->
                    if (call.method == "complete") {
                        val success = call.argument<Boolean>("success") == true
                        result.success(null)
                        main.post { finish(params, !success) }
                    } else result.notImplemented()
                }
            main.postDelayed(timeout, 30000)
            worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(), "allowanceBackground"))
        } catch (_: Exception) { main.post { finish(params, true) } }
        return true
    }
    private fun disposeWorker() {
        main.removeCallbacks(timeout)
        ledgerChannel?.close(); ledgerChannel = null
        engine?.destroy(); engine = null
    }
    private fun finish(params: JobParameters, retry: Boolean) {
        if (active !== params) return
        active = null
        disposeWorker()
        jobFinished(params, retry)
    }
    override fun onStopJob(params: JobParameters): Boolean {
        if (active?.jobId == params.jobId) { active = null; disposeWorker() }
        // A committed occurrence is idempotent even if Android stops before its
        // acknowledgement. An interrupted atomic stage never replaces current.
        return true
    }
    override fun onDestroy() { active = null; disposeWorker(); super.onDestroy() }
}
