/**
 * AdminTrackProcessor
 * Queueable that queries SetupAuditTrail, filters changes via exclusion rules,
 * sends a Slack summary, inserts an AdminAuditLog__c record, and updates
 * LastPullTimestamp__c. Invoked by AdminTrackBatch.finish() and runNow().
 *
 * SetupAuditTrail records cannot be serialized across batch transactions, so
 * all processing is done here in a single Queueable transaction where the
 * query and callout both work correctly.
 */
public without sharing class AdminTrackProcessor implements Queueable, Database.AllowsCallouts {

    private static final Integer DEFAULT_LOOKBACK_DAYS = 7;
    private static final Integer MAX_SAMPLE_CHANGES    = 2000;

    /**
     * When set in a test, limits the SetupAuditTrail query to a small number of
     * records so tests can exercise the full code path without timing issues.
     */
    @TestVisible
    private static Integer testQueryLimit = null;

    public void execute(QueueableContext ctx) {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();

        // Note: IsActive__c is intentionally NOT checked here. AdminTrackBatch.finish()
        // guards the enqueue with an IsActive check. Omitting the check here allows
        // runNow() to work regardless of whether the scheduler is active.
        DateTime since = (settings != null && settings.LastPullTimestamp__c != null)
            ? settings.LastPullTimestamp__c
            : DateTime.now().addDays(-DEFAULT_LOOKBACK_DAYS);
        DateTime now = DateTime.now();

        String query =
            'SELECT Id, Action, Section, CreatedById, CreatedDate, Display, ' +
            'CreatedBy.Username, DelegateUser ' +
            'FROM SetupAuditTrail ' +
            'WHERE CreatedDate > :since ' +
            'ORDER BY CreatedDate ASC';

        if (testQueryLimit != null) {
            query += ' LIMIT ' + testQueryLimit;
        }

        List<SetupAuditTrail> trails = Database.query(query);

        System.debug(LoggingLevel.INFO,
            'AdminTrackProcessor: querying since ' + since + ', found ' + trails.size() + ' entries.');

        Integer totalNew      = 0;
        Integer totalExcluded = 0;
        List<Map<String, String>> sampleChanges = new List<Map<String, String>>();

        for (SetupAuditTrail trail : trails) {
            if (AdminTrackService.shouldExclude(trail.Action, trail.Section, trail.CreatedById)) {
                totalExcluded++;
            } else {
                totalNew++;
                if (sampleChanges.size() < MAX_SAMPLE_CHANGES) {
                    sampleChanges.add(new Map<String, String>{
                        'section'   => trail.Section,
                        'action'    => trail.Action,
                        'display'   => trail.Display,
                        'date'      => String.valueOf(trail.CreatedDate),
                        'username'  => trail.CreatedBy?.Username,
                        'delegated' => trail.DelegateUser
                    });
                }
            }
        }

        System.debug(LoggingLevel.INFO,
            'AdminTrackProcessor: ' + totalNew + ' new, ' + totalExcluded + ' excluded.');

        if (totalNew > 0) {
            // Callout must precede DML in the same transaction
            Boolean slackSent = SlackNotificationService.sendSummary(
                totalNew, totalExcluded, since, now, sampleChanges
            );

            insert new AdminAuditLog__c(
                BatchRunDate__c  = now,
                WindowStart__c   = since,
                WindowEnd__c     = now,
                TotalChanges__c  = totalNew,
                ExcludedCount__c = totalExcluded,
                Details__c       = serializeDetails(sampleChanges),
                SentToSlack__c   = slackSent,
                SlackSentDate__c = slackSent ? DateTime.now() : null
            );
        }

        if (settings == null) {
            settings = new AdminTrackSettings__c();
        }
        settings.LastPullTimestamp__c = now;
        upsert settings;
    }

    private static String serializeDetails(List<Map<String, String>> changes) {
        if (changes == null || changes.isEmpty()) {
            return '[]';
        }
        String serialized = JSON.serialize(changes);
        if (serialized.length() <= 131000) {
            return serialized;
        }
        Integer size = changes.size();
        while (serialized.length() > 131000 && size > 1) {
            size = (size * 3) / 4;
            List<Map<String, String>> trimmed = new List<Map<String, String>>();
            for (Integer i = 0; i < size; i++) {
                trimmed.add(changes[i]);
            }
            serialized = JSON.serialize(trimmed);
        }
        return serialized;
    }
}
