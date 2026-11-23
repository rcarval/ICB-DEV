trigger EventVisitSyncAutoEnrolamiento on Event (after insert, after update, after delete, after undelete) {
    EventVisitSyncAEHandler.syncFromEvents(
        Trigger.new,
        Trigger.oldMap,
        Trigger.isDelete
    );
}