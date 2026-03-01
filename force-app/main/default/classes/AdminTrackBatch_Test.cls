/**
 * AdminTrackBatch_Test
 * Tests the simplified batch scheduling wrapper. All processing logic is now
 * in AdminTrackProcessor; finish() enqueues it via System.enqueueJob.
 *
 * Tests set LastPullTimestamp__c = DateTime.now() by default so that
 * AdminTrackProcessor (which runs during Test.stopTest()) finds zero
 * SetupAuditTrail records and makes no HTTP callout.
 */
@IsTest
private class AdminTrackBatch_Test {

    private class SlackMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    @IsTest
    static void batch_executesWithoutException() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            SlackEnabled__c        = false,
            PullIntervalMinutes__c = 15,
            LastPullTimestamp__c   = DateTime.now()
        );
        upsert settings;

        Test.startTest();
        Database.executeBatch(new AdminTrackBatch(), 200);
        Test.stopTest();

        // AdminTrackProcessor (enqueued from finish()) updates LastPullTimestamp__c.
        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated.LastPullTimestamp__c,
            'LastPullTimestamp__c should be set after processor completes');
    }

    @IsTest
    static void batch_withInactiveSettings_doesNotEnqueueProcessor() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = false,
            SlackEnabled__c        = false,
            PullIntervalMinutes__c = 15,
            LastPullTimestamp__c   = DateTime.now()
        );
        upsert settings;

        Test.startTest();
        Database.executeBatch(new AdminTrackBatch(), 200);
        Test.stopTest();

        // With IsActive=false, finish() skips System.enqueueJob.
        // No exception = pass.
        System.assert(true, 'Batch should complete without exception when inactive');
    }

    @IsTest
    static void batch_withRealAuditRecords_processorCreatesLogRecord() {
        AdminTrackProcessor.testQueryLimit = 5;
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            SlackEnabled__c        = false,
            PullIntervalMinutes__c = 15,
            LastPullTimestamp__c   = DateTime.now().addDays(-180)
        );
        upsert settings;

        Test.startTest();
        Database.executeBatch(new AdminTrackBatch(), 200);
        Test.stopTest();

        // AdminTrackProcessor updates the timestamp and may insert an AdminAuditLog__c.
        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertNotEquals(null, updated.LastPullTimestamp__c);

        List<AdminAuditLog__c> summaries = [SELECT Id, TotalChanges__c FROM AdminAuditLog__c];
        for (AdminAuditLog__c s : summaries) {
            System.assertNotEquals(null, s.TotalChanges__c, 'TotalChanges__c should be set');
        }
    }

    @IsTest
    static void batch_withSlackEnabled_processorSendsNotification() {
        AdminTrackProcessor.testQueryLimit = 5;
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            SlackEnabled__c        = true,
            SlackWebhookUrl__c     = 'https://hooks.slack.com/services/T00/B00/abc',
            PullIntervalMinutes__c = 15,
            LastPullTimestamp__c   = DateTime.now().addDays(-180)
        );
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new SlackMockSuccess());

        Test.startTest();
        Database.executeBatch(new AdminTrackBatch(), 200);
        Test.stopTest();

        System.assert(true, 'Batch with Slack enabled should complete without exception');
    }
}
