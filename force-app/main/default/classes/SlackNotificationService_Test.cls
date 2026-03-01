/**
 * SlackNotificationService_Test
 * Unit tests for SlackNotificationService using a mock HTTP callout.
 */
@IsTest
private class SlackNotificationService_Test {

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

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private static List<Map<String, String>> makeSamples(Integer count) {
        List<Map<String, String>> samples = new List<Map<String, String>>();
        for (Integer i = 0; i < count; i++) {
            samples.add(new Map<String, String>{
                'section' => 'TestSection',
                'action'  => 'TestAction' + i,
                'display' => 'Test display text ' + i,
                'date'    => String.valueOf(DateTime.now())
            });
        }
        return samples;
    }

    // ─── isValidWebhookUrl Tests ────────────────────────────────────────────────

    @IsTest
    static void isValidWebhookUrl_validUrl_returnsTrue() {
        System.assertEquals(true,
            SlackNotificationService.isValidWebhookUrl('https://hooks.slack.com/services/T00/B00/abc'));
    }

    @IsTest
    static void isValidWebhookUrl_invalidUrl_returnsFalse() {
        System.assertEquals(false,
            SlackNotificationService.isValidWebhookUrl('https://evil.com/webhook'));
    }

    @IsTest
    static void isValidWebhookUrl_blank_returnsFalse() {
        System.assertEquals(false, SlackNotificationService.isValidWebhookUrl(''));
        System.assertEquals(false, SlackNotificationService.isValidWebhookUrl(null));
    }

    // ─── buildSlackMessage Tests ────────────────────────────────────────────────

    @IsTest
    static void buildSlackMessage_defaultTemplate_containsRecordCount() {
        List<Map<String, String>> samples = makeSamples(3);
        AdminTrackSettings__c settings = new AdminTrackSettings__c();
        DateTime now = DateTime.now();

        Test.startTest();
        String payload = SlackNotificationService.buildSlackMessage(3, 0, now.addMinutes(-15), now, samples, settings);
        Test.stopTest();

        System.assert(payload.contains('3'), 'Message should contain the record count');
        System.assert(payload.contains('text'), 'Payload should be valid JSON with text key');
    }

    @IsTest
    static void buildSlackMessage_customTemplate_tokensReplaced() {
        List<Map<String, String>> samples = makeSamples(5);
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            SlackMessageTemplate__c = '{count} changes in {orgName} at {timestamp}'
        );
        DateTime now = DateTime.now();

        Test.startTest();
        String payload = SlackNotificationService.buildSlackMessage(5, 0, now.addMinutes(-15), now, samples, settings);
        Test.stopTest();

        System.assert(payload.contains('5'), 'Count token should be replaced');
        System.assert(!payload.contains('{count}'), 'Unreplaced token should not appear');
    }

    @IsTest
    static void buildSlackMessage_moreThan10Changes_showsEllipsis() {
        List<Map<String, String>> samples = makeSamples(10);
        AdminTrackSettings__c settings = new AdminTrackSettings__c();
        DateTime now = DateTime.now();

        Test.startTest();
        String payload = SlackNotificationService.buildSlackMessage(15, 2, now.addMinutes(-15), now, samples, settings);
        Test.stopTest();

        System.assert(payload.contains('more'), 'Should mention remaining records');
    }

    @IsTest
    static void buildSlackMessage_withExcluded_mentionsExcluded() {
        List<Map<String, String>> samples = makeSamples(2);
        AdminTrackSettings__c settings = new AdminTrackSettings__c();
        DateTime now = DateTime.now();

        Test.startTest();
        String payload = SlackNotificationService.buildSlackMessage(2, 5, now.addMinutes(-15), now, samples, settings);
        Test.stopTest();

        System.assert(payload.contains('excluded'), 'Should mention excluded count');
    }

    // ─── sendSummary Tests ──────────────────────────────────────────────────────

    @IsTest
    static void sendSummary_slackDisabled_returnsFalse() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            SlackEnabled__c    = false,
            SlackWebhookUrl__c = 'https://hooks.slack.com/services/T00/B00/abc'
        );
        upsert settings;

        Test.startTest();
        Boolean result = SlackNotificationService.sendSummary(
            5, 0, DateTime.now().addMinutes(-15), DateTime.now(), makeSamples(5)
        );
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false when Slack disabled');
    }

    @IsTest
    static void sendSummary_invalidUrl_returnsFalse() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            SlackEnabled__c    = true,
            SlackWebhookUrl__c = 'https://evil.com/webhook'
        );
        upsert settings;

        Test.startTest();
        Boolean result = SlackNotificationService.sendSummary(
            3, 0, DateTime.now().addMinutes(-15), DateTime.now(), makeSamples(3)
        );
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false with invalid URL');
    }

    @IsTest
    static void sendSummary_successfulPost_returnsTrue() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            SlackEnabled__c    = true,
            SlackWebhookUrl__c = 'https://hooks.slack.com/services/T00/B00/abc'
        );
        upsert settings;
        Test.setMock(HttpCalloutMock.class, new SlackMockSuccess());

        Test.startTest();
        Boolean result = SlackNotificationService.sendSummary(
            4, 1, DateTime.now().addMinutes(-15), DateTime.now(), makeSamples(4)
        );
        Test.stopTest();

        System.assertEquals(true, result, 'Should return true on HTTP 200');
    }

    // ─── sendConfirmationAsync Tests ────────────────────────────────────────────

    @IsTest
    static void sendConfirmationAsync_validUrl_postsSuccessfully() {
        Test.setMock(HttpCalloutMock.class, new SlackMockSuccess());
        Test.startTest();
        SlackNotificationService.sendConfirmationAsync(
            'https://hooks.slack.com/services/T00/B00/abc'
        );
        Test.stopTest();
        // No exception thrown = confirmation posted without error
    }

    @IsTest
    static void sendConfirmationAsync_invalidUrl_doesNotPost() {
        // No mock registered — would throw CalloutException if a callout were attempted
        Test.startTest();
        SlackNotificationService.sendConfirmationAsync('https://evil.com/bad');
        Test.stopTest();
        // Should exit early without making any callout
    }

    @IsTest
    static void sendSummary_failedPost_returnsFalse() {
        AdminTrackSettings__c settings = new AdminTrackSettings__c(
            SlackEnabled__c    = true,
            SlackWebhookUrl__c = 'https://hooks.slack.com/services/T00/B00/abc'
        );
        upsert settings;
        Test.setMock(HttpCalloutMock.class, new SlackMockFailure());

        Test.startTest();
        Boolean result = SlackNotificationService.sendSummary(
            2, 0, DateTime.now().addMinutes(-15), DateTime.now(), makeSamples(2)
        );
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false on HTTP 400');
    }
}
