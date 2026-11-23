public with sharing class seidor_SetAgenteFromOwnerAction {

    // Usuario/bot que posee la sesión mientras está en cola o al cerrarse.
    // TODO: si este Id cambia entre sandboxes (UAT vs prod), mover a
    // Custom Metadata Type (ej. Messaging_Bot_Owner__mdt) en vez de constante
    // hardcodeada — mismo criterio que ya aplican en otras clases del proyecto
    // para no hardcodear IDs sensibles al entorno.
    @TestVisible
    private static final Id BOT_OWNER_ID = '005Hn00000IcqeJIAR';

    @InvocableMethod(
        label='Setear Agente__c desde OwnerId (before-save)'
        description='Actualiza Agente__c con el nuevo OwnerId cuando cambia a un usuario real (no el bot de cola), para no perder trazabilidad de quién atendió la sesión.'
        category='MessagingSession'
    )
    public static void setAgenteFromOwner(List<MessagingSession> sessions) {
        if (sessions == null || sessions.isEmpty()) {
            return;
        }

        for (MessagingSession ms : sessions) {
            Id newOwnerId = ms.OwnerId;

            // Sin OwnerId, o el nuevo dueño es el bot/cola: no tocar Agente__c.
            if (newOwnerId == null || newOwnerId == BOT_OWNER_ID) {
                continue;
            }

            // Idempotente: si ya quedó igual (ej. entry criteria mal configurado
            // y este método se invoca sin que OwnerId realmente haya cambiado),
            // no genera un write innecesario.
            if (ms.Agente__c != newOwnerId) {
                ms.Agente__c = newOwnerId;
            }
        }
    }
}