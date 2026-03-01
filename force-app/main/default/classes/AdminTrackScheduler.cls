/**
 * AdminTrackScheduler
 * Schedulable wrapper that launches AdminTrackBatch on each tick.
 */
public with sharing class AdminTrackScheduler implements Schedulable {

    public void execute(SchedulableContext ctx) {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings == null || !settings.IsActive__c) {
            System.debug(LoggingLevel.INFO,
                'AdminTrackScheduler: IsActive__c is false — skipping batch execution.');
            return;
        }
        Database.executeBatch(new AdminTrackBatch(), 200);
    }
}
