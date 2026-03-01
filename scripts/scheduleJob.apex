// Schedule AdminTrack to run every hour via: sf apex run -f scripts/scheduleJob.apex
// Abort existing job first (if any)
List<CronTrigger> existing = [
    SELECT Id FROM CronTrigger
    WHERE CronJobDetail.Name = 'AdminTrack_Scheduler'
    AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
];
for (CronTrigger ct : existing) {
    System.abortJob(ct.Id);
}

// Schedule hourly
String cronExp = '0 0 * * * ?';
System.schedule('AdminTrack_Scheduler', cronExp, new AdminTrackScheduler());
System.debug('AdminTrack_Scheduler scheduled with CRON: ' + cronExp);
