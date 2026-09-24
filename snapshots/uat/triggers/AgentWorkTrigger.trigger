trigger AgentWorkTrigger on AgentWork (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        seidor_AgentWorkTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        seidor_AgentWorkTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}