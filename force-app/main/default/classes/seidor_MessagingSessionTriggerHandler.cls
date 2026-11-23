public with sharing class seidor_MessagingSessionTriggerHandler {

    @TestVisible
    private static Set<Id> botUserIdsCache;

    @TestVisible
    private static Boolean afterUpdateExecuted = false;

    @TestVisible
    public static Set<Id> getBotUserIds() {
        if (botUserIdsCache == null) {
            botUserIdsCache = new Set<Id>();
            Map<String, Bot_Messaging__mdt> bots = Bot_Messaging__mdt.getAll();
            System.debug(LoggingLevel.INFO,
                '[seidor_MessagingSessionTriggerHandler] Bot_Messaging__mdt records found: ' + bots.size());
            for (Bot_Messaging__mdt bot : bots.values()) {
                if (String.isBlank(bot.Id_Usuario_Bot__c)) {
                    System.debug(LoggingLevel.WARN,
                        '[seidor_MessagingSessionTriggerHandler] Bot_Messaging__mdt ' + bot.DeveloperName
                        + ' has empty Id_Usuario_Bot__c — skipping');
                    continue;
                }
                try {
                    botUserIdsCache.add((Id) bot.Id_Usuario_Bot__c);
                    System.debug(LoggingLevel.INFO,
                        '[seidor_MessagingSessionTriggerHandler] Registered bot: '
                        + bot.DeveloperName + ' -> ' + bot.Id_Usuario_Bot__c);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN,
                        '[seidor_MessagingSessionTriggerHandler] Bot_Messaging__mdt ' + bot.DeveloperName
                        + ' has invalid Id_Usuario_Bot__c: ' + bot.Id_Usuario_Bot__c
                        + ' — ' + e.getMessage());
                }
            }
        }
        return botUserIdsCache;
    }

    /**
     * Handle before insert: si la sesión se crea directamente con un OwnerId
     * que es un usuario real (no bot, no queue), setear Agente__c de una vez.
     */
    public static void handleBeforeInsert(List<MessagingSession> newList) {
        if (newList == null || newList.isEmpty()) return;

        Set<Id> botIds = getBotUserIds();

        for (MessagingSession ms : newList) {
            Id ownerId = ms.OwnerId;

            if (ownerId == null) continue;
            if (ownerId.getSObjectType() != User.SObjectType) continue;
            if (botIds.contains(ownerId)) continue;
            if (ms.Ejecutivo_asignado__c) continue;

            ms.Agente__c = ownerId;
            ms.Ejecutivo_asignado__c = true;

            System.debug(LoggingLevel.INFO,
                '[seidor_MessagingSessionTriggerHandler] INSERT: Set Agente__c=' + ownerId
                + ' for session ' + ms.Id);
        }
    }

    /**
     * Handle before update: cuando OwnerId cambia, si el nuevo dueño es un
     * usuario real (no bot, no queue) o se puede resolver desde una queue,
     * actualiza Agente__c y marca Ejecutivo_asignado__c = true.
     * Si Ejecutivo_asignado__c ya es true, preserva el valor (no overwrite).
     */
    public static void handleBeforeUpdate(
        List<MessagingSession> newList,
        Map<Id, MessagingSession> oldMap
    ) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;

        Set<Id> botIds = getBotUserIds();

        // ── 1a pasada: detectar qué sesiones cambiaron OwnerId y
        //     recolectar Queue IDs para resolver miembros en bulk ──
        Set<Id> queueIds = new Set<Id>();

        for (MessagingSession ms : newList) {
            MessagingSession old = oldMap.get(ms.Id);
            if (old == null) continue;

            Id newOwnerId = ms.OwnerId;
            Id oldOwnerId = old.OwnerId;

            if (newOwnerId == oldOwnerId) continue;
            if (ms.Ejecutivo_asignado__c) continue;

            // Si el nuevo owner es una Queue, la agendamos para resolver
            if (newOwnerId != null && newOwnerId.getSObjectType() == Group.SObjectType) {
                queueIds.add(newOwnerId);
            }
        }

        // ── Resolver Queue → humano en bulk ──
        Map<Id, List<Id>> queueMembersMap = new Map<Id, List<Id>>();
        if (!queueIds.isEmpty()) {
            for (GroupMember gm : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :queueIds
            ]) {
                if (gm.UserOrGroupId.getSObjectType() == User.SObjectType
                    && !botIds.contains(gm.UserOrGroupId)) {
                    if (!queueMembersMap.containsKey(gm.GroupId)) {
                        queueMembersMap.put(gm.GroupId, new List<Id>());
                    }
                    queueMembersMap.get(gm.GroupId).add(gm.UserOrGroupId);
                }
            }
        }

        // ── 2a pasada: aplicar cambios ──
        for (MessagingSession ms : newList) {
            MessagingSession old = oldMap.get(ms.Id);
            if (old == null) continue;

            Id newOwnerId = ms.OwnerId;
            Id oldOwnerId = old.OwnerId;

            if (newOwnerId == oldOwnerId) continue;

            // ═══ GUARD: si Ejecutivo_asignado__c ya es true, no tocar ═══
            if (ms.Ejecutivo_asignado__c) {
                System.debug(LoggingLevel.INFO,
                    '[seidor_MessagingSessionTriggerHandler] UPDATE: Ejecutivo_asignado__c=true — '
                    + 'preserving Agente__c=' + ms.Agente__c
                    + ' (OwnerId change ' + oldOwnerId + ' → ' + newOwnerId + ')');
                continue;
            }

            // ── Caso A: nuevo owner es un User real (no bot) ──
            if (newOwnerId != null
                && newOwnerId.getSObjectType() == User.SObjectType
                && !botIds.contains(newOwnerId)) {

                ms.Agente__c = newOwnerId;
                ms.Ejecutivo_asignado__c = true;

                System.debug(LoggingLevel.INFO,
                    '[seidor_MessagingSessionTriggerHandler] UPDATE: Agente__c=' + newOwnerId
                    + ' (OwnerId changed ' + oldOwnerId + ' → ' + newOwnerId + ')');
                continue;
            }

            // ── Caso B: nuevo owner es una Queue — resolver a humano ──
            if (newOwnerId != null
                && newOwnerId.getSObjectType() == Group.SObjectType) {

                List<Id> members = queueMembersMap.get(newOwnerId);

                if (members != null && members.size() == 1) {
                    ms.Agente__c = members[0];
                    ms.Ejecutivo_asignado__c = true;

                    System.debug(LoggingLevel.INFO,
                        '[seidor_MessagingSessionTriggerHandler] UPDATE: Agente__c=' + members[0]
                        + ' (resolved from Queue ' + newOwnerId
                        + ', OwnerId changed ' + oldOwnerId + ' → ' + newOwnerId + ')');

                } else if (members != null && members.size() > 1) {
                    System.debug(LoggingLevel.WARN,
                        '[seidor_MessagingSessionTriggerHandler] UPDATE: Queue ' + newOwnerId
                        + ' has ' + members.size()
                        + ' human members — cannot determine which agent (OwnerId change '
                        + oldOwnerId + ' → ' + newOwnerId + ')');
                } else {
                    System.debug(LoggingLevel.INFO,
                        '[seidor_MessagingSessionTriggerHandler] UPDATE: Queue ' + newOwnerId
                        + ' has no resolvable human member (OwnerId change '
                        + oldOwnerId + ' → ' + newOwnerId + ')');
                }
                continue;
            }

            // ── Caso C: nuevo owner es bot o no se pudo resolver ──
            System.debug(LoggingLevel.INFO,
                '[seidor_MessagingSessionTriggerHandler] UPDATE: OwnerId changed '
                + oldOwnerId + ' → ' + newOwnerId
                + ' — NOT setting Agente__c (newOwner type='
                + (newOwnerId?.getSObjectType()?.getDescribe()?.getName() ?? 'null')
                + ')');
        }
    }

    /**
     * Handle after update: cuando OwnerId cambió a una Queue y no se pudo
     * resolver el agente en before update, consulta AgentWork para encontrar
     * el humano asignado por Omni-Channel y actualiza la sesión.
     * Se ejecuta solo una vez por transacción (guard afterUpdateExecuted).
     */
    public static void handleAfterUpdate(
        List<MessagingSession> newList,
        Map<Id, MessagingSession> oldMap
    ) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;
        if (afterUpdateExecuted) return;

        Set<Id> botIds = getBotUserIds();
        Set<Id> sessionIds = new Set<Id>();

        for (MessagingSession ms : newList) {
            MessagingSession old = oldMap.get(ms.Id);
            if (old == null) continue;
            if (ms.OwnerId == old.OwnerId) continue;
            if (ms.Ejecutivo_asignado__c) continue;
            // Solo procesamos si el OwnerId NO es un User directo
            if (ms.OwnerId != null && ms.OwnerId.getSObjectType() == User.SObjectType) continue;
            sessionIds.add(ms.Id);
        }

        if (sessionIds.isEmpty()) return;

        afterUpdateExecuted = true;
        Map<Id, Id> agentBySession = new Map<Id, Id>();

        // Intentar resolver vía AgentWork (estándar Omni-Channel)
        try {
            for (AgentWork aw : [
                SELECT WorkItemId, UserId
                FROM AgentWork
                WHERE WorkItemId IN :sessionIds
                AND UserId != null
                AND Status IN ('Assigned', 'InProgress', 'Completed')
            ]) {
                if (!botIds.contains(aw.UserId)) {
                    agentBySession.put(aw.WorkItemId, aw.UserId);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                '[seidor_MessagingSessionTriggerHandler] AgentWork query failed: ' + e.getMessage());
        }

        if (agentBySession.isEmpty()) {
            System.debug(LoggingLevel.INFO,
                '[seidor_MessagingSessionTriggerHandler] AFTER UPDATE: no se encontró agente via AgentWork para ' + sessionIds);
            return;
        }

        List<MessagingSession> updates = new List<MessagingSession>();
        for (Id sessionId : agentBySession.keySet()) {
            updates.add(new MessagingSession(
                Id = sessionId,
                Agente__c = agentBySession.get(sessionId),
                Ejecutivo_asignado__c = true
            ));
            System.debug(LoggingLevel.INFO,
                '[seidor_MessagingSessionTriggerHandler] AFTER UPDATE: Agente__c=' + agentBySession.get(sessionId)
                + ' for session ' + sessionId);
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
}