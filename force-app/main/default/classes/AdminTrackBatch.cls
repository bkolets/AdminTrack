/**
 * AdminTrackBatch
 * Lightweight scheduling trigger — all SetupAuditTrail processing is
 * delegated to AdminTrackProcessor (Queueable). This class exists solely so
 * Database.scheduleBatch / System.scheduleBatch can fire AdminTrackProcessor
 * on a recurring schedule with sub-hourly minute intervals.
 *
 * finish() enqueues AdminTrackProcessor (when IsActive) then re-schedules
 * itself for the next interval.
 */
public without sharing class AdminTrackBatch implements Database.Batchable<SObject> {

    // ─── Batchable Interface ────────────────────────────────────────────────────

    public List<SObject> start(Database.BatchableContext ctx) {
        // Return an empty scope — all processing is handled by AdminTrackProcessor
        // which is enqueued from finish().
        return new List<SObject>();
    }

    public void execute(Database.BatchableContext ctx, List<SObject> scope) {
        // No-op: processing delegated to AdminTrackProcessor.
    }

    public void finish(Database.BatchableContext ctx) {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings != null && settings.IsActive__c) {
            System.enqueueJob(new AdminTrackProcessor());
        }
        rescheduleIfActive();
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private void rescheduleIfActive() {
        if (Test.isRunningTest()) {
            return;
        }
        try {
            AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
            if (settings == null || !settings.IsActive__c || settings.PullIntervalMinutes__c == null) {
                return;
            }
            if (AdminTrackSchedulerService.hasPendingJob()) {
                return;
            }
            Integer intervalMinutes = (Integer) settings.PullIntervalMinutes__c;
            System.scheduleBatch(
                new AdminTrackBatch(),
                AdminTrackSchedulerService.JOB_NAME,
                intervalMinutes,
                200
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AdminTrackBatch: failed to re-schedule next run — ' + ex.getMessage());
        }
    }
}
