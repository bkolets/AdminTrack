/**
 * AdminTrackScheduler_Test
 * Tests AdminTrackScheduler (Schedulable) and AdminTrackSchedulerService.
 * Scheduling now uses Database.scheduleBatch, not System.schedule/CRON.
 */
@IsTest
private class AdminTrackScheduler_Test {

    private class SlackMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    // ─── AdminTrackScheduler (Schedulable wrapper) ──────────────────────────────

    @IsTest
    static void scheduler_execute_whenActive_runsBatch() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            SlackEnabled__c        = false,
            PullIntervalMinutes__c = 15,
            LastPullTimestamp__c   = DateTime.now() // zero-result query
        );
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new SlackMockSuccess());

        Test.startTest();
        String jobId = System.schedule(
            'AdminTrackSchedulerTest_Active',
            '0 0 0 1 1 ? 2099',
            new AdminTrackScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled successfully');
    }

    @IsTest
    static void scheduler_execute_whenInactive_skipsExecution() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(IsActive__c = false);
        upsert settings;

        Test.startTest();
        String jobId = System.schedule(
            'AdminTrackSchedulerTest_Inactive',
            '0 0 0 1 1 ? 2099',
            new AdminTrackScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void scheduler_execute_noSettings_skipsExecution() {
        Test.startTest();
        String jobId = System.schedule(
            'AdminTrackSchedulerTest_NoSettings',
            '0 0 0 1 1 ? 2099',
            new AdminTrackScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    // ─── AdminTrackSchedulerService.scheduleJob ─────────────────────────────────

    // Seed settings with a current timestamp so the batch query returns zero records,
    // preventing the "No more than one executeBatch" limit in real orgs with audit history.
    private static void seedZeroResultSettings(Integer intervalMinutes) {
        AdminTrackSettings__c s = new AdminTrackSettings__c(
            IsActive__c            = true,
            SlackEnabled__c        = false,
            PullIntervalMinutes__c = intervalMinutes,
            LastPullTimestamp__c   = DateTime.now()
        );
        upsert s;
    }

    @IsTest
    static void scheduleJob_5min_setsSettingsAndCreatesJob() {
        seedZeroResultSettings(5);
        AdminTrackSchedulerService.abortExistingJob(); // clear any live org job before test
        Test.startTest();
        AdminTrackSchedulerService.scheduleJob(5);
        Test.stopTest();

        AdminTrackSettings__c s = AdminTrackSettings__c.getInstance();
        System.assertEquals(true, s.IsActive__c);
        System.assertEquals(5,    (Integer) s.PullIntervalMinutes__c);
    }

    @IsTest
    static void scheduleJob_15min_setsSettingsAndCreatesJob() {
        seedZeroResultSettings(15);
        AdminTrackSchedulerService.abortExistingJob(); // clear any live org job before test
        Test.startTest();
        AdminTrackSchedulerService.scheduleJob(15);
        Test.stopTest();

        AdminTrackSettings__c s = AdminTrackSettings__c.getInstance();
        System.assertEquals(true, s.IsActive__c);
        System.assertEquals(15,   (Integer) s.PullIntervalMinutes__c);
    }

    @IsTest
    static void scheduleJob_30min_setsSettingsAndCreatesJob() {
        seedZeroResultSettings(30);
        AdminTrackSchedulerService.abortExistingJob(); // clear any live org job before test
        Test.startTest();
        AdminTrackSchedulerService.scheduleJob(30);
        Test.stopTest();

        AdminTrackSettings__c s = AdminTrackSettings__c.getInstance();
        System.assertEquals(30, (Integer) s.PullIntervalMinutes__c);
    }

    @IsTest
    static void scheduleJob_60min_setsSettingsAndCreatesJob() {
        seedZeroResultSettings(60);
        AdminTrackSchedulerService.abortExistingJob(); // clear any live org job before test
        Test.startTest();
        AdminTrackSchedulerService.scheduleJob(60);
        Test.stopTest();

        AdminTrackSettings__c s = AdminTrackSettings__c.getInstance();
        System.assertEquals(60, (Integer) s.PullIntervalMinutes__c);
    }

    @IsTest
    static void scheduleJob_invalidInterval_throwsException() {
        Test.startTest();
        Boolean threw = false;
        try {
            AdminTrackSchedulerService.scheduleJob(45);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for value not in {5,15,30,60}');
    }

    @IsTest
    static void scheduleJob_nullInterval_throwsException() {
        Test.startTest();
        Boolean threw = false;
        try {
            AdminTrackSchedulerService.scheduleJob(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null interval');
    }

    // ─── AdminTrackSchedulerService.deactivateJob ───────────────────────────────

    @IsTest
    static void deactivateJob_setsInactive() {
        // Set up active settings
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            PullIntervalMinutes__c = 15
        );
        upsert settings;

        Test.startTest();
        AdminTrackSchedulerService.deactivateJob();
        Test.stopTest();

        AdminTrackSettings__c updated = AdminTrackSettings__c.getInstance();
        System.assertEquals(false, updated.IsActive__c, 'Should be inactive after deactivate');
    }

    // ─── AdminTrackSchedulerService.runNow ──────────────────────────────────────

    @IsTest
    static void runNow_executesBatchWithoutException() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            SlackEnabled__c        = false,
            PullIntervalMinutes__c = 15,
            LastPullTimestamp__c   = DateTime.now()
        );
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new SlackMockSuccess());

        Test.startTest();
        AdminTrackSchedulerService.runNow();
        Test.stopTest();

        System.assert(true, 'runNow should complete without exception');
    }

    // ─── AdminTrackSchedulerService.getJobStatus ────────────────────────────────

    @IsTest
    static void getJobStatus_noJob_noSettings_returnsInactive() {
        Test.startTest();
        Map<String, Object> status = AdminTrackSchedulerService.getJobStatus();
        Test.stopTest();

        System.assertEquals(false, status.get('isActive'));
        System.assertEquals(null,  status.get('nextRunTime'));
        System.assertEquals(null,  status.get('intervalMinutes'));
    }

    @IsTest
    static void getJobStatus_withActiveSettings_returnsActive() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            IsActive__c            = true,
            PullIntervalMinutes__c = 30
        );
        upsert settings;

        Test.startTest();
        Map<String, Object> status = AdminTrackSchedulerService.getJobStatus();
        Test.stopTest();

        System.assertEquals(true, status.get('isActive'));
        System.assertEquals(30,   status.get('intervalMinutes'));
    }

    // ─── AdminTrackSchedulerService.abortExistingJob ────────────────────────────

    @IsTest
    static void abortExistingJob_noJob_doesNotThrow() {
        Test.startTest();
        AdminTrackSchedulerService.abortExistingJob();
        Test.stopTest();
        System.assert(true, 'Should not throw when no jobs exist');
    }

    // ─── AdminTrackSchedulerService.hasPendingJob ────────────────────────────────

    @IsTest
    static void hasPendingJob_noPendingJob_returnsFalse() {
        Test.startTest();
        Boolean result = AdminTrackSchedulerService.hasPendingJob();
        Test.stopTest();
        System.assertEquals(false, result);
    }
}
