/**
 * AdminTrackService
 * Manages exclusion rule filtering for SetupAuditTrail entries.
 */
public with sharing class AdminTrackService {

    // Cached exclusions for the lifetime of this transaction
    private static List<AdminTrackExclusionRule__c> cachedExclusions;

    /**
     * Checks whether a given trail entry matches any active exclusion rule.
     */
    public static Boolean shouldExclude(String action, String section, Id userId) {
        for (AdminTrackExclusionRule__c rule : getActiveExclusions()) {
            String val = rule.ExclusionValue__c;
            if (String.isBlank(val)) {
                continue;
            }
            String ruleType = rule.ExclusionType__c;
            if (ruleType == 'Section' && section != null && section.equalsIgnoreCase(val)) {
                return true;
            }
            if (ruleType == 'Action' && action != null && action.equalsIgnoreCase(val)) {
                return true;
            }
            if (ruleType == 'User' && userId != null) {
                String userIdStr = String.valueOf(userId);
                if (userIdStr.equals(val) || userIdStr.left(15).equals(val.left(15))) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Returns all active AdminTrackExclusionRule__c records, cached per transaction.
     */
    public static List<AdminTrackExclusionRule__c> getActiveExclusions() {
        if (cachedExclusions == null) {
            cachedExclusions = [
                SELECT ExclusionType__c, ExclusionValue__c, IsActive__c
                FROM AdminTrackExclusionRule__c
                WHERE IsActive__c = true
            ];
        }
        return cachedExclusions;
    }

    @TestVisible
    private static void clearExclusionCache() {
        cachedExclusions = null;
    }
}
