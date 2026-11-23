/**
 * Trigger deliberadamente delgado — toda la lógica vive en
 * seidor_MessagingSessionTriggerHandler para que sea testeable por llamada
 * directa (sin depender de poder insertar MessagingSession en test context,
 * limitación ya documentada en este proyecto).
 */
trigger MessagingSessionTrigger on MessagingSession (before insert, before update, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        seidor_MessagingSessionTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        seidor_MessagingSessionTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        seidor_MessagingSessionTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}