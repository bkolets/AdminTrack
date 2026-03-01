// Execute AdminTrackBatch manually via: sf apex run -f scripts/runBatch.apex
Database.executeBatch(new AdminTrackBatch(), 200);
System.debug('AdminTrackBatch submitted.');
