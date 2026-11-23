trigger OpportunityProactivaAE on Opportunity (before update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        OpportunityProactivaAEHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}