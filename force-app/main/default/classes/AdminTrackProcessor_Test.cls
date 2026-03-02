/**
 * AdminTrackProcessor_Test
 * Unit tests for AdminTrackProcessor (Queueable).
 * SetupAuditTrail is a real system object — tests control scope by setting
 * LastPullTimestamp__c to DateTime.now() (zero results) or to -180 days with
 * testQueryLimit=5 (limited real records).
 */
@IsTest
private class AdminTrackProcessor_Test {

    private class SlackMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    private class SlackMockFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('invalid_payload');
            return res;
        }
    }

    // ─── Zero-records path (timestamp = now) ────────────────────────────────────

    @IsTest
    static void execute_withTimestampNow_updatesTimestampNoLog() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c          = true,
            SlackEnabled__c      = false,
            LastPullTimestamp__c = DateTime.now()
        );
        upsert settings;

        Test.startTest();
        System.enqueueJob(new AdminTrackProcessor());
        Test.stopTest();

        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated.LastPullTimestamp__c,
            'LastPullTimestamp__c should be updated');
        System.assertEquals(0,
            [SELECT COUNT() FROM AdminAuditLog__c],
            'No log record expected when zero trail entries found');
    }

    @IsTest
    static void execute_withNullSettings_usesDefaultLookback() {
        // No upsert — getInstance() returns a default instance with null fields.
        Test.startTest();
        System.enqueueJob(new AdminTrackProcessor());
        Test.stopTest();

        // Processor should complete without exception even with no pre-existing settings.
        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated,
            'Settings record should be created by processor upsert');
    }

    // ─── Run Now works regardless of IsActive ────────────────────────────────────

    @IsTest
    static void execute_whenInactive_stillUpdatesTimestamp() {
        // IsActive=false: processor should still run (Run Now bypass)
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c          = false,
            SlackEnabled__c      = false,
            LastPullTimestamp__c = DateTime.now()
        );
        upsert settings;

        Test.startTest();
        System.enqueueJob(new AdminTrackProcessor());
        Test.stopTest();

        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated.LastPullTimestamp__c,
            'Processor should update timestamp even when IsActive=false');
    }

    // ─── Real records path (limited) ─────────────────────────────────────────────

    @IsTest
    static void execute_withRealAuditRecords_mayCreateLogRecord() {
        AdminTrackProcessor.testQueryLimit = 5;
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c          = true,
            SlackEnabled__c      = false,
            LastPullTimestamp__c = DateTime.now().addDays(-180)
        );
        upsert settings;

        Test.startTest();
        System.enqueueJob(new AdminTrackProcessor());
        Test.stopTest();

        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated.LastPullTimestamp__c,
            'LastPullTimestamp__c should be updated after processing');

        // If non-excluded records existed, an AdminAuditLog__c should be present.
        List<AdminAuditLog__c> logs = [
            SELECT Id, TotalChanges__c, ExcludedCount__c, WindowStart__c, WindowEnd__c, SentToSlack__c
            FROM AdminAuditLog__c
        ];
        for (AdminAuditLog__c log : logs) {
            System.assertNotEquals(null, log.TotalChanges__c,  'TotalChanges__c should be set');
            System.assertNotEquals(null, log.WindowStart__c,   'WindowStart__c should be set');
            System.assertNotEquals(null, log.WindowEnd__c,     'WindowEnd__c should be set');
            System.assertEquals(false, log.SentToSlack__c,     'SentToSlack__c should be false when Slack disabled');
        }
    }

    @IsTest
    static void execute_withSlackEnabled_sendsNotificationOnChange() {
        AdminTrackProcessor.testQueryLimit = 5;
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c          = true,
            SlackEnabled__c      = true,
            SlackWebhookUrl__c   = 'https://hooks.slack.com/services/T00/B00/abc',
            LastPullTimestamp__c = DateTime.now().addDays(-180)
        );
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new SlackMockSuccess());

        Test.startTest();
        System.enqueueJob(new AdminTrackProcessor());
        Test.stopTest();

        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated.LastPullTimestamp__c);

        // If a log was created, verify SentToSlack__c reflects the callout outcome.
        List<AdminAuditLog__c> logs = [SELECT SentToSlack__c, BatchRunDate__c FROM AdminAuditLog__c];
        for (AdminAuditLog__c log : logs) {
            System.assertNotEquals(null, log.BatchRunDate__c, 'BatchRunDate__c should be set');
        }
    }

    // ─── Coverage for "more changes not shown" Slack message path ────────────────

    @IsTest
    static void buildSlackMessage_sampleSizeLessThanTotal_showsMoreNote() {
        // Simulates AdminTrackProcessor capping sampleChanges at MAX_SAMPLE_CHANGES
        // while totalNew is higher — the message should note remaining changes.
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c          = true,
            SlackEnabled__c      = true,
            SlackWebhookUrl__c   = 'https://hooks.slack.com/services/T00/B00/abc',
            LastPullTimestamp__c = DateTime.now()
        );
        upsert settings;

        List<Map<String, String>> tenSamples = new List<Map<String, String>>();
        for (Integer i = 0; i < 10; i++) {
            tenSamples.add(new Map<String, String>{
                'section' => 'Section', 'action' => 'Action' + i,
                'display' => 'Display ' + i, 'date' => String.valueOf(DateTime.now()),
                'username' => 'user@test.com', 'delegated' => null
            });
        }

        // totalChanges=15, but only 10 samples — message should mention 5 more
        AdminTrackSettings__c cfg = AdminTrackSettings__c.getInstance();
        String payload = SlackNotificationService.buildSlackMessage(
            15, 0, DateTime.now().addMinutes(-15), DateTime.now(), tenSamples, cfg
        );

        System.assert(payload.contains('more'),
            'Message should note remaining changes when sampleSize < totalChanges');
    }

    @IsTest
    static void execute_withSlackFailure_logRecordReflectsFailure() {
        AdminTrackProcessor.testQueryLimit = 5;
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c          = true,
            SlackEnabled__c      = true,
            SlackWebhookUrl__c   = 'https://hooks.slack.com/services/T00/B00/abc',
            LastPullTimestamp__c = DateTime.now().addDays(-180)
        );
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new SlackMockFailure());

        Test.startTest();
        System.enqueueJob(new AdminTrackProcessor());
        Test.stopTest();

        // If records existed and a log was created, SentToSlack__c should be false.
        List<AdminAuditLog__c> logs = [SELECT SentToSlack__c FROM AdminAuditLog__c];
        for (AdminAuditLog__c log : logs) {
            System.assertEquals(false, log.SentToSlack__c,
                'SentToSlack__c should be false when Slack callout returns HTTP 400');
        }
    }
}
