/**
 * AdminTrackExclusionService_Test
 * Unit tests for AdminTrackExclusionService CRUD methods.
 */
@IsTest
private class AdminTrackExclusionService_Test {

    @IsTest
    static void getExclusions_empty_returnsEmptyList() {
        Test.startTest();
        List<AdminTrackExclusionRule__c> result = AdminTrackExclusionService.getExclusions();
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Expected empty list when no records exist');
    }

    @IsTest
    static void getExclusions_afterInsert_returnsRecord() {
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'Section',
            ExclusionValue__c = 'Manage Users',
            IsActive__c       = true
        );

        Test.startTest();
        List<AdminTrackExclusionRule__c> result = AdminTrackExclusionService.getExclusions();
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('Section',      result[0].ExclusionType__c);
        System.assertEquals('Manage Users', result[0].ExclusionValue__c);
        System.assertEquals(true,           result[0].IsActive__c);
    }

    @IsTest
    static void addExclusion_valid_createsRecord() {
        Test.startTest();
        AdminTrackExclusionService.addExclusion('Action', 'PasswordReset');
        Test.stopTest();

        List<AdminTrackExclusionRule__c> records = [SELECT ExclusionType__c, ExclusionValue__c, IsActive__c FROM AdminTrackExclusionRule__c];
        System.assertEquals(1, records.size());
        System.assertEquals('Action',        records[0].ExclusionType__c);
        System.assertEquals('PasswordReset', records[0].ExclusionValue__c);
        System.assertEquals(true,            records[0].IsActive__c);
    }

    @IsTest
    static void addExclusion_trimsWhitespace() {
        Test.startTest();
        AdminTrackExclusionService.addExclusion('Section', '  Manage Users  ');
        Test.stopTest();

        List<AdminTrackExclusionRule__c> records = [SELECT ExclusionValue__c FROM AdminTrackExclusionRule__c];
        System.assertEquals('Manage Users', records[0].ExclusionValue__c, 'Value should be trimmed');
    }

    @IsTest
    static void addExclusion_blankType_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AdminTrackExclusionService.addExclusion('', 'SomeValue');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for blank type');
    }

    @IsTest
    static void addExclusion_blankValue_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AdminTrackExclusionService.addExclusion('Section', '');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for blank value');
    }

    @IsTest
    static void toggleExclusion_deactivates() {
        AdminTrackExclusionRule__c exc = new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'Action',
            ExclusionValue__c = 'PasswordReset',
            IsActive__c       = true
        );
        insert exc;

        Test.startTest();
        AdminTrackExclusionService.toggleExclusion(exc.Id, false);
        Test.stopTest();

        AdminTrackExclusionRule__c updated = [SELECT IsActive__c FROM AdminTrackExclusionRule__c WHERE Id = :exc.Id];
        System.assertEquals(false, updated.IsActive__c, 'Should be deactivated');
    }

    @IsTest
    static void toggleExclusion_activates() {
        AdminTrackExclusionRule__c exc = new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'Section',
            ExclusionValue__c = 'Manage Users',
            IsActive__c       = false
        );
        insert exc;

        Test.startTest();
        AdminTrackExclusionService.toggleExclusion(exc.Id, true);
        Test.stopTest();

        AdminTrackExclusionRule__c updated = [SELECT IsActive__c FROM AdminTrackExclusionRule__c WHERE Id = :exc.Id];
        System.assertEquals(true, updated.IsActive__c, 'Should be activated');
    }

    @IsTest
    static void deleteExclusion_deletesRecord() {
        AdminTrackExclusionRule__c exc = new AdminTrackExclusionRule__c(
            ExclusionType__c  = 'User',
            ExclusionValue__c = '005000000000001AAA',
            IsActive__c       = true
        );
        insert exc;

        Test.startTest();
        AdminTrackExclusionService.deleteExclusion(exc.Id);
        Test.stopTest();

        List<AdminTrackExclusionRule__c> remaining = [SELECT Id FROM AdminTrackExclusionRule__c WHERE Id = :exc.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }
}
