/**
 * AdminTrackLogService_Test
 * Unit tests for AdminTrackLogService — SetupAuditTrail query methods.
 * All queries run against real SetupAuditTrail data since the object cannot
 * be mocked; results are validated for type and shape, not exact content.
 */
@IsTest
private class AdminTrackLogService_Test {

    // ─── getSections ─────────────────────────────────────────────────────────────

    @IsTest
    static void getSections_returnsNonNullList() {
        Test.startTest();
        List<String> sections = AdminTrackLogService.getSections();
        Test.stopTest();

        System.assertNotEquals(null, sections, 'getSections should never return null');
    }

    @IsTest
    static void getSections_resultIsSorted() {
        Test.startTest();
        List<String> sections = AdminTrackLogService.getSections();
        Test.stopTest();

        for (Integer i = 1; i < sections.size(); i++) {
            System.assert(
                sections[i - 1].compareTo(sections[i]) <= 0,
                'getSections result should be sorted alphabetically'
            );
        }
    }

    // ─── getLogs ─────────────────────────────────────────────────────────────────

    @IsTest
    static void getLogs_noFilters_returnsNonNullList() {
        Test.startTest();
        List<SetupAuditTrail> results = AdminTrackLogService.getLogs(null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'getLogs should never return null');
    }

    @IsTest
    static void getLogs_withSinceDate_filtersFromDate() {
        String since = String.valueOf(Date.today().addDays(-30));
        Test.startTest();
        List<SetupAuditTrail> results = AdminTrackLogService.getLogs(since, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, results);
        // All returned records should be within the date window
        DateTime sinceDate = DateTime.newInstance(Date.today().addDays(-30), Time.newInstance(0, 0, 0, 0));
        for (SetupAuditTrail t : results) {
            System.assert(t.CreatedDate >= sinceDate,
                'All records should be on or after the since date');
        }
    }

    @IsTest
    static void getLogs_withUntilDate_appliesUpperBound() {
        String since = String.valueOf(Date.today().addDays(-60));
        String until = String.valueOf(Date.today().addDays(-30));
        Test.startTest();
        List<SetupAuditTrail> results = AdminTrackLogService.getLogs(since, until, null, null);
        Test.stopTest();

        System.assertNotEquals(null, results);
        DateTime untilDate = DateTime.newInstance(
            Date.today().addDays(-30), Time.newInstance(23, 59, 59, 0)
        );
        for (SetupAuditTrail t : results) {
            System.assert(t.CreatedDate <= untilDate,
                'All records should be on or before the until date');
        }
    }

    @IsTest
    static void getLogs_withUserId_filtersToUser() {
        Id currentUserId = UserInfo.getUserId();
        String since = String.valueOf(Date.today().addDays(-180));
        Test.startTest();
        List<SetupAuditTrail> results = AdminTrackLogService.getLogs(
            since, null, null, currentUserId
        );
        Test.stopTest();

        System.assertNotEquals(null, results);
        for (SetupAuditTrail t : results) {
            System.assertEquals(currentUserId, t.CreatedById,
                'All records should belong to the filtered user');
        }
    }

    @IsTest
    static void getLogs_withSectionFilter_returnsResults() {
        // Section filtering is documented as client-side — server query ignores it.
        // Passing a value should not throw; results are unfiltered by section.
        Test.startTest();
        List<SetupAuditTrail> results = AdminTrackLogService.getLogs(
            null, null, 'Manage Users', null
        );
        Test.stopTest();

        System.assertNotEquals(null, results,
            'Passing a section filter should not throw — filtering is client-side');
    }

    @IsTest
    static void getLogs_blankSinceDate_usesDefaultLookback() {
        // Blank sinceStr should default to 7-day lookback without throwing
        Test.startTest();
        List<SetupAuditTrail> results = AdminTrackLogService.getLogs('', null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Blank since date should use default lookback');
    }
}
