/**
 * AdminTrackLogService
 * Returns SetupAuditTrail records for the LWC Audit Log tab.
 * Reads directly from the standard object — no custom object storage required.
 * Supports server-side filtering by date range, section, and user name.
 */
public with sharing class AdminTrackLogService {

    /**
     * Returns all distinct Section values from the last 180 days of SetupAuditTrail,
     * sorted alphabetically. Used to populate the Section picklist in the LWC.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getSections() {
        Set<String> sections = new Set<String>();
        for (SetupAuditTrail trail : [
            SELECT Section
            FROM SetupAuditTrail
            WHERE CreatedDate >= :DateTime.now().addDays(-180)
            LIMIT 5000
        ]) {
            if (!String.isBlank(trail.Section)) {
                sections.add(trail.Section);
            }
        }
        List<String> sorted = new List<String>(sections);
        sorted.sort();
        return sorted;
    }

    @AuraEnabled
    public static List<SetupAuditTrail> getLogs(
        String sinceStr,
        String untilStr,
        String sectionFilter,
        String userId
    ) {
        DateTime sinceDate = String.isBlank(sinceStr)
            ? DateTime.now().addDays(-7)
            : DateTime.newInstance(Date.valueOf(sinceStr), Time.newInstance(0, 0, 0, 0));

        String query =
            'SELECT Id, Action, Section, Display, CreatedDate, CreatedBy.Name ' +
            'FROM SetupAuditTrail ' +
            'WHERE CreatedDate >= :sinceDate';

        DateTime untilDate = null;
        if (!String.isBlank(untilStr)) {
            untilDate = DateTime.newInstance(
                Date.valueOf(untilStr), Time.newInstance(23, 59, 59, 0)
            );
            query += ' AND CreatedDate <= :untilDate';
        }

        // Note: SetupAuditTrail.Section is not filterable in SOQL.
        // Section filtering is applied client-side in the LWC.

        // Filter by selected user ID from the LWC lookup field
        if (!String.isBlank(userId)) {
            query += ' AND CreatedById = :userId';
        }

        query += ' ORDER BY CreatedDate DESC LIMIT 500';

        return Database.query(query);
    }
}
