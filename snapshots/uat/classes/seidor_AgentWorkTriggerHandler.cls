public with sharing class seidor_AgentWorkTriggerHandler {

    @TestVisible
    private static Boolean suppressDml = false;

    @TestVisible
    private static Map<Id, MessagingSession> mockSessionsCache;

    public static void handleAfterInsert(List<AgentWork> newList) {
        handleAssignment(newList);
    }

    public static void handleAfterUpdate(List<AgentWork> newList, Map<Id, AgentWork> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;

        List<AgentWork> changed = new List<AgentWork>();
        for (AgentWork aw : newList) {
            AgentWork old = oldMap.get(aw.Id);
            if (old == null) continue;
            if (aw.UserId != old.UserId && aw.UserId != null) {
                changed.add(aw);
            }
        }
        if (changed.isEmpty()) return;
        handleAssignment(changed);
    }

    private static void handleAssignment(List<AgentWork> agentWorks) {
        if (agentWorks == null || agentWorks.isEmpty()) return;

        Set<Id> botIds = seidor_MessagingSessionTriggerHandler.getBotUserIds();
        Set<Id> workItemIds = new Set<Id>();
        Map<Id, Id> agentByWorkItem = new Map<Id, Id>();

        for (AgentWork aw : agentWorks) {
            if (aw.UserId == null) continue;
            if (aw.WorkItemId == null) continue;
            if (aw.WorkItemId.getSObjectType() != MessagingSession.SObjectType) continue;
            if (botIds.contains(aw.UserId)) continue;

            workItemIds.add(aw.WorkItemId);
            agentByWorkItem.put(aw.WorkItemId, aw.UserId);
        }

        if (workItemIds.isEmpty()) return;

        Map<Id, MessagingSession> sessions;
        if (mockSessionsCache != null) {
            sessions = mockSessionsCache;
        } else {
            sessions = new Map<Id, MessagingSession>(
                [SELECT Id, Ejecutivo_asignado__c FROM MessagingSession WHERE Id IN :workItemIds]
            );
        }

        List<MessagingSession> updates = new List<MessagingSession>();
        for (Id sessionId : agentByWorkItem.keySet()) {
            MessagingSession ms = sessions.get(sessionId);
            if (ms == null) continue;
            if (ms.Ejecutivo_asignado__c) continue;

            updates.add(new MessagingSession(
                Id = sessionId,
                Agente__c = agentByWorkItem.get(sessionId),
                Ejecutivo_asignado__c = true
            ));
        }

        if (updates.isEmpty()) return;

        if (suppressDml) {
            for (MessagingSession ms : updates) {
                if (mockSessionsCache != null && mockSessionsCache.containsKey(ms.Id)) {
                    mockSessionsCache.get(ms.Id).Agente__c = ms.Agente__c;
                    mockSessionsCache.get(ms.Id).Ejecutivo_asignado__c = ms.Ejecutivo_asignado__c;
                }
            }
        } else {
            update updates;
        }
    }
}