/**
 * AdminTrackSchedulerService
 * Manages the scheduled job lifecycle: schedule, abort, and status query.
 * Uses Database.scheduleBatch (not System.schedule) so sub-hourly minute
 * intervals are fully supported. The batch re-schedules itself in finish().
 * Called from the adminTrackSetup LWC via @AuraEnabled methods.
 *
 * All DML operations on AdminTrackSettings__c enforce CRUD permissions before
 * executing. SOQL results on AdminAuditLog__c are stripped via stripInaccessible.
 */
public with sharing class AdminTrackSchedulerService {

    public static final String JOB_NAME = 'AdminTrack_Scheduler';

    private static final Set<Integer> VALID_INTERVALS = new Set<Integer>{ 5, 15, 30, 60 };

    // ─── AuraEnabled Methods (called by LWC) ────────────────────────────────────

    /**
     * Schedules the AdminTrackBatch to run after intervalMinutes, then
     * self-reschedules on each finish(). Aborts any pending jobs first.
     * Valid values: 5, 15, 30, 60 minutes.
     */
    @AuraEnabled
    public static void scheduleJob(Integer intervalMinutes) {
        if (intervalMinutes == null || !VALID_INTERVALS.contains(intervalMinutes)) {
            throw new AuraHandledException(
                'Invalid interval. Allowed values are 5, 15, 30, or 60 minutes.');
        }

        // Persist settings before aborting so finish() won't re-schedule
        // with stale data if a job is mid-flight
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings == null) {
            settings = new AdminTrackSettings__c();
        }
        settings.IsActive__c            = true;
        settings.PullIntervalMinutes__c = intervalMinutes;
        upsertSettings(settings);

        abortExistingJob();

        System.scheduleBatch(new AdminTrackBatch(), JOB_NAME, intervalMinutes, 200);
    }

    /**
     * Deactivates the scheduler: sets IsActive__c = false first (so any
     * currently-running batch won't re-schedule from finish()), then aborts
     * any pending jobs.
     */
    @AuraEnabled
    public static void deactivateJob() {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings == null) {
            settings = new AdminTrackSettings__c();
        }
        settings.IsActive__c = false;
        upsertSettings(settings);
        abortExistingJob();
    }

    /**
     * Runs the processor immediately (ad-hoc, no rescheduling).
     * Uses a Queueable instead of a batch job so SetupAuditTrail records
     * are queried and processed in the same transaction as the callout.
     */
    @AuraEnabled
    public static void runNow() {
        System.enqueueJob(new AdminTrackProcessor());
    }

    /**
     * Returns current job status for the LWC.
     * Keys: isActive (Boolean), nextRunTime (String), intervalMinutes (Integer)
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getJobStatus() {
        Map<String, Object> status = new Map<String, Object>{
            'isActive'        => false,
            'nextRunTime'     => null,
            'intervalMinutes' => null,
            'scheduledJobs'   => new List<Map<String, Object>>(),
            'processorRuns'   => new List<Map<String, Object>>()
        };

        // Pending scheduled batch (Holding/Queued/Preparing)
        List<AsyncApexJob> pendingJobs = [
            SELECT Id, Status, CronTriggerId
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AdminTrackBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!pendingJobs.isEmpty()) {
            status.put('isActive', true);
            if (pendingJobs[0].CronTriggerId != null) {
                List<CronTrigger> cts = [
                    SELECT NextFireTime
                    FROM CronTrigger
                    WHERE Id = :pendingJobs[0].CronTriggerId
                    LIMIT 1
                ];
                if (!cts.isEmpty() && cts[0].NextFireTime != null) {
                    status.put('nextRunTime',
                        cts[0].NextFireTime.format('yyyy-MM-dd HH:mm:ss z'));
                }
            }
        }

        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings != null) {
            if (settings.PullIntervalMinutes__c != null) {
                status.put('intervalMinutes', (Integer) settings.PullIntervalMinutes__c);
            }
            if (settings.IsActive__c) {
                status.put('isActive', true);
            }
        }

        // ─── Scheduled jobs (CronTrigger) ───────────────────────────────────────
        List<Map<String, Object>> scheduledJobs = new List<Map<String, Object>>();
        for (CronTrigger ct : [
            SELECT Id, State, NextFireTime, PreviousFireTime,
                   CronJobDetail.Name, CreatedBy.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            LIMIT 5
        ]) {
            scheduledJobs.add(new Map<String, Object>{
                'id'           => ct.Id,
                'name'         => ct.CronJobDetail.Name,
                'state'        => ct.State,
                'nextFireTime' => ct.NextFireTime != null
                                    ? ct.NextFireTime.format('MM/dd/yyyy h:mm a z') : '—',
                'prevFireTime' => ct.PreviousFireTime != null
                                    ? ct.PreviousFireTime.format('MM/dd/yyyy h:mm a z') : '—',
                'createdBy'    => ct.CreatedBy.Name
            });
        }
        status.put('scheduledJobs', scheduledJobs);

        // ─── Recent processor runs (AdminAuditLog__c) — FLS enforced via stripInaccessible
        List<AdminAuditLog__c> rawLogs = [
            SELECT Id, BatchRunDate__c, WindowStart__c, WindowEnd__c,
                   TotalChanges__c, ExcludedCount__c, SentToSlack__c
            FROM AdminAuditLog__c
            ORDER BY BatchRunDate__c DESC
            LIMIT 5
        ];
        List<AdminAuditLog__c> accessibleLogs = (List<AdminAuditLog__c>)
            Security.stripInaccessible(AccessType.READABLE, rawLogs).getRecords();

        List<Map<String, Object>> processorRuns = new List<Map<String, Object>>();
        for (AdminAuditLog__c log : accessibleLogs) {
            processorRuns.add(new Map<String, Object>{
                'id'       => log.Id,
                'runDate'  => log.BatchRunDate__c != null
                                ? log.BatchRunDate__c.format('MM/dd/yyyy h:mm a z') : '—',
                'window'   => (log.WindowStart__c != null
                                ? log.WindowStart__c.format('MM/dd/yy h:mm a') : '—')
                            + ' → '
                            + (log.WindowEnd__c != null
                                ? log.WindowEnd__c.format('MM/dd/yy h:mm a') : '—'),
                'changes'  => log.TotalChanges__c  != null ? (Integer) log.TotalChanges__c  : 0,
                'excluded' => log.ExcludedCount__c != null ? (Integer) log.ExcludedCount__c : 0,
                'slackSent'=> log.SentToSlack__c
            });
        }
        status.put('processorRuns', processorRuns);

        return status;
    }

    /**
     * Returns current Slack settings for the LWC configuration form.
     */
    @AuraEnabled
    public static Map<String, Object> getSlackSettings() {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        return new Map<String, Object>{
            'slackEnabled'         => settings != null ? settings.SlackEnabled__c          : false,
            'slackWebhookUrl'      => settings != null ? (settings.SlackWebhookUrl__c      ?? '') : '',
            'slackMessageTemplate' => settings != null ? (settings.SlackMessageTemplate__c ?? '') : '',
            'slackMaxDetails'      => settings != null && settings.SlackMaxDetails__c != null
                                        ? (Integer) settings.SlackMaxDetails__c
                                        : 25
        };
    }

    /**
     * Persists Slack configuration entered via the LWC.
     */
    @AuraEnabled
    public static void saveSlackSettings(
        Boolean slackEnabled,
        String  slackWebhookUrl,
        String  slackMessageTemplate,
        Integer slackMaxDetails
    ) {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings == null) {
            settings = new AdminTrackSettings__c();
        }
        settings.SlackEnabled__c         = slackEnabled;
        settings.SlackWebhookUrl__c      = slackWebhookUrl;
        settings.SlackMessageTemplate__c = slackMessageTemplate;
        settings.SlackMaxDetails__c      = (slackMaxDetails != null && slackMaxDetails > 0)
                                            ? Math.min(slackMaxDetails, 2000)
                                            : 25;
        upsertSettings(settings);

        if (slackEnabled == true && SlackNotificationService.isValidWebhookUrl(slackWebhookUrl)) {
            SlackNotificationService.sendConfirmationAsync(slackWebhookUrl);
        }
    }

    // ─── Internal Helpers ───────────────────────────────────────────────────────

    /**
     * Enforces CRUD before upserting AdminTrackSettings__c.
     * New records require isCreateable(); existing records require isUpdateable().
     * Throws AuraHandledException if the running user lacks the necessary permission.
     */
    private static void upsertSettings(AdminTrackSettings__c settings) {
        if (settings.Id == null) {
            if (!Schema.sObjectType.AdminTrackSettings__c.isCreateable()) {
                throw new AuraHandledException(
                    'Insufficient permissions: create access required on AdminTrackSettings__c.');
            }
        } else {
            if (!Schema.sObjectType.AdminTrackSettings__c.isUpdateable()) {
                throw new AuraHandledException(
                    'Insufficient permissions: update access required on AdminTrackSettings__c.');
            }
        }
        upsert settings;
    }

    /**
     * Aborts any pending AdminTrack scheduled batch jobs.
     * System.scheduleBatch creates both a CronTrigger (name-keyed) and an
     * AsyncApexJob, so we abort via CronTrigger first to release the name
     * reservation, then sweep any remaining AsyncApexJob entries.
     */
    public static void abortExistingJob() {
        // Abort CronTrigger-based scheduled batches (System.scheduleBatch entries)
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            try { System.abortJob(ct.Id); } catch (Exception ex) { /* already gone */ }
        }

        // Also sweep any directly queued/holding AsyncApexJob entries
        for (AsyncApexJob job : [
            SELECT Id FROM AsyncApexJob
            WHERE ApexClass.Name = 'AdminTrackBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing')
        ]) {
            try { System.abortJob(job.Id); } catch (Exception ex) { /* already gone */ }
        }
    }

    /**
     * Returns true if a pending AdminTrackBatch job already exists.
     * Used by AdminTrackBatch.finish() to avoid double-scheduling.
     */
    public static Boolean hasPendingJob() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AdminTrackBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing')
        ] > 0;
    }
}
