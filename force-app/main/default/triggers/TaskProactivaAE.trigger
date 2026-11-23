trigger TaskProactivaAE on Task (after update) {
    TaskProactivaAEHandler.afterUpdate(Trigger.new, Trigger.oldMap);
}