/**
 * AdminTrackService_Test
 * Unit tests for AdminTrackService. Targets ≥ 85% coverage.
 * AdminTrackExclusionRule__c is a regular Custom Object, so records can be
 * inserted directly in tests — no cache injection needed.
 */
@IsTest
private class AdminTrackService_Test {

    // ─── shouldExclude Tests ────────────────────────────────────────────────────

    @IsTest
    static void shouldExclude_noRules_returnsFalse() {
        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('PasswordReset', 'Manage Users', UserInfo.getUserId());
        Test.stopTest();
        System.assertEquals(false, result, 'Expected no exclusion when no rules exist');
    }

    @IsTest
    static void shouldExclude_sectionRule_matchReturnsTrue() {
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'Section',
            ExclusionValue__c = 'Manage Users',
            IsActive__c       = true
        );
        AdminTrackService.clearExclusionCache();

        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('PasswordReset', 'Manage Users', UserInfo.getUserId());
        Test.stopTest();
        System.assertEquals(true, result, 'Section match should exclude the record');
    }

    @IsTest
    static void shouldExclude_actionRule_matchReturnsTrue() {
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'Action',
            ExclusionValue__c = 'PasswordReset',
            IsActive__c       = true
        );
        AdminTrackService.clearExclusionCache();

        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('PasswordReset', 'Manage Users', UserInfo.getUserId());
        Test.stopTest();
        System.assertEquals(true, result, 'Action match should exclude the record');
    }

    @IsTest
    static void shouldExclude_userRule_matchReturnsTrue() {
        Id userId = UserInfo.getUserId();
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'User',
            ExclusionValue__c = String.valueOf(userId),
            IsActive__c       = true
        );
        AdminTrackService.clearExclusionCache();

        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('PasswordReset', 'Manage Users', userId);
        Test.stopTest();
        System.assertEquals(true, result, 'User ID match should exclude the record');
    }

    @IsTest
    static void shouldExclude_userRule_15charMatch() {
        Id userId = UserInfo.getUserId();
        String shortId = String.valueOf(userId).left(15);
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'User',
            ExclusionValue__c = shortId,
            IsActive__c       = true
        );
        AdminTrackService.clearExclusionCache();

        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('PasswordReset', 'Manage Users', userId);
        Test.stopTest();
        System.assertEquals(true, result, '15-char user ID match should exclude the record');
    }

    @IsTest
    static void shouldExclude_inactiveRule_doesNotExclude() {
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'Section',
            ExclusionValue__c = 'Manage Users',
            IsActive__c       = false
        );
        AdminTrackService.clearExclusionCache();

        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('PasswordReset', 'Manage Users', UserInfo.getUserId());
        Test.stopTest();
        System.assertEquals(false, result, 'Inactive rule should not exclude');
    }

    @IsTest
    static void shouldExclude_noUserIdOnUserRule_returnsFalse() {
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'User',
            ExclusionValue__c = '005000000000001AAA',
            IsActive__c       = true
        );
        AdminTrackService.clearExclusionCache();

        Test.startTest();
        Boolean result = AdminTrackService.shouldExclude('Action', 'Section', null);
        Test.stopTest();
        System.assertEquals(false, result, 'Null userId should not match user rule');
    }

    // ─── getActiveExclusions Tests ──────────────────────────────────────────────

    @IsTest
    static void getActiveExclusions_returnsList() {
        Test.startTest();
        List<AdminTrackExclusionRule__c> exclusions = AdminTrackService.getActiveExclusions();
        Test.stopTest();
        System.assertNotEquals(null, exclusions, 'Should return a list (possibly empty)');
    }

    @IsTest
    static void getActiveExclusions_cacheWorks() {
        Test.startTest();
        List<AdminTrackExclusionRule__c> first  = AdminTrackService.getActiveExclusions();
        List<AdminTrackExclusionRule__c> second = AdminTrackService.getActiveExclusions();
        Test.stopTest();
        System.assert(first === second, 'Second call should return cached result');
    }

    @IsTest
    static void clearExclusionCache_resetsCache() {
        AdminTrackService.getActiveExclusions();
        AdminTrackService.clearExclusionCache();
        Test.startTest();
        List<AdminTrackExclusionRule__c> result = AdminTrackService.getActiveExclusions();
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
}
