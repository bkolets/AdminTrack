/**
 * AdminTrackExclusionService
 * @AuraEnabled CRUD methods for AdminTrackExclusionRule__c records.
 * Called by the adminTrackSetup LWC exclusion management panel.
 *
 * All DML operations enforce object-level CRUD permissions before executing.
 * SOQL results are stripped of inaccessible fields via Security.stripInaccessible.
 */
public with sharing class AdminTrackExclusionService {

    /**
     * Returns all exclusion rules, ordered by type then value.
     * Inaccessible fields are stripped per FLS rules.
     */
    @AuraEnabled
    public static List<AdminTrackExclusionRule__c> getExclusions() {
        List<AdminTrackExclusionRule__c> results = [
            SELECT Id, Name, ExclusionType__c, ExclusionValue__c, IsActive__c
            FROM AdminTrackExclusionRule__c
            ORDER BY ExclusionType__c, ExclusionValue__c
        ];
        return (List<AdminTrackExclusionRule__c>) Security.stripInaccessible(
            AccessType.READABLE, results
        ).getRecords();
    }

    /**
     * Inserts a new active exclusion rule.
     * Throws AuraHandledException if the running user lacks create access.
     */
    @AuraEnabled
    public static void addExclusion(String exclusionType, String exclusionValue) {
        if (String.isBlank(exclusionType) || String.isBlank(exclusionValue)) {
            throw new AuraHandledException('Type and Value are required.');
        }
        if (!Schema.sObjectType.AdminTrackExclusionRule__c.isCreateable()) {
            throw new AuraHandledException(
                'Insufficient permissions: create access required on AdminTrackExclusionRule__c.');
        }
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = exclusionType,
            ExclusionValue__c = exclusionValue.trim(),
            IsActive__c       = true
        );
    }

    /**
     * Flips the IsActive__c flag on an existing exclusion rule.
     * Throws AuraHandledException if the running user lacks update access.
     */
    @AuraEnabled
    public static void toggleExclusion(Id exclusionId, Boolean isActive) {
        if (!Schema.sObjectType.AdminTrackExclusionRule__c.isUpdateable()) {
            throw new AuraHandledException(
                'Insufficient permissions: update access required on AdminTrackExclusionRule__c.');
        }
        update new AdminTrackExclusionRule__c(
            Id          = exclusionId,
            IsActive__c = isActive
        );
    }

    /**
     * Deletes an exclusion rule by Id.
     * Throws AuraHandledException if the running user lacks delete access.
     */
    @AuraEnabled
    public static void deleteExclusion(Id exclusionId) {
        if (!Schema.sObjectType.AdminTrackExclusionRule__c.isDeletable()) {
            throw new AuraHandledException(
                'Insufficient permissions: delete access required on AdminTrackExclusionRule__c.');
        }
        delete new AdminTrackExclusionRule__c(Id = exclusionId);
    }
}
