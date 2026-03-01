/**
 * AdminTrackExclusionService
 * @AuraEnabled CRUD methods for AdminTrackExclusionRule__c records.
 * Called by the adminTrackSetup LWC exclusion management panel.
 */
public with sharing class AdminTrackExclusionService {

    /**
     * Returns all exclusion rules, ordered by type then value.
     */
    @AuraEnabled
    public static List<AdminTrackExclusionRule__c> getExclusions() {
        return [
            SELECT Id, Name, ExclusionType__c, ExclusionValue__c, IsActive__c
            FROM AdminTrackExclusionRule__c
            ORDER BY ExclusionType__c, ExclusionValue__c
        ];
    }

    /**
     * Inserts a new active exclusion rule.
     */
    @AuraEnabled
    public static void addExclusion(String exclusionType, String exclusionValue) {
        if (String.isBlank(exclusionType) || String.isBlank(exclusionValue)) {
            throw new AuraHandledException('Type and Value are required.');
        }
        insert new AdminTrackExclusionRule__c(
            ExclusionType__c  = exclusionType,
            ExclusionValue__c = exclusionValue.trim(),
            IsActive__c       = true
        );
    }

    /**
     * Flips the IsActive__c flag on an existing exclusion rule.
     */
    @AuraEnabled
    public static void toggleExclusion(Id exclusionId, Boolean isActive) {
        update new AdminTrackExclusionRule__c(
            Id          = exclusionId,
            IsActive__c = isActive
        );
    }

    /**
     * Deletes an exclusion rule by Id.
     */
    @AuraEnabled
    public static void deleteExclusion(Id exclusionId) {
        delete new AdminTrackExclusionRule__c(Id = exclusionId);
    }
}
