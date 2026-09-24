trigger ICBFS_CampaignMemberTrigger on CampaignMember (before insert, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        ICBFS_CampaignMemberCanalHandler.beforeInsert(Trigger.new);
    }

    ICBFS_QR_CampaignMemberEmailHandler.afterSave(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}