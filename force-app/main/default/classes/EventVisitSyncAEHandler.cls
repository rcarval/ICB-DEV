public with sharing class EventVisitSyncAEHandler {

    private static final String VISIT_STATUS_PROGRAMADA = 'Programada';
    private static final String VISIT_STATUS_CONCRETADA = 'Concretada';
    private static final String OPP_RT_AUTO_ENROLAMIENTO = 'Auto_Enrolamiento';

    public static void syncFromEvents(
        List<Event> newList,
        Map<Id, Event> oldMap,
        Boolean isDelete
    ) {
        Set<Id> opportunityIds = collectOpportunityIds(newList, oldMap, isDelete);
        if (opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> autoEnrolamientoOpps = new Map<Id, Opportunity>([
            SELECT Id, StageName, Tiene_Visita_Agendada__c, Visita_Concretada__c, Detalles__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND RecordType.DeveloperName = :OPP_RT_AUTO_ENROLAMIENTO
        ]);

        if (autoEnrolamientoOpps.isEmpty()) {
            return;
        }

        Set<Id> autoOppIds = autoEnrolamientoOpps.keySet();
        Set<Id> oppsWithProgrammedVisit = new Set<Id>();
        Map<Id, String> oppConcretadaDetailByOppId = collectConcretadaDetails(newList, oldMap, isDelete, autoOppIds);

        for (Event ev : [
            SELECT Id, WhatId
            FROM Event
            WHERE WhatId IN :autoOppIds
              AND Estado_de_la_visita__c = :VISIT_STATUS_PROGRAMADA
        ]) {
            if (ev.WhatId != null) {
                oppsWithProgrammedVisit.add(ev.WhatId);
            }
        }

        List<Opportunity> updates = new List<Opportunity>();
        for (Opportunity opp : autoEnrolamientoOpps.values()) {
            Boolean expectedValue = oppsWithProgrammedVisit.contains(opp.Id);
            Boolean shouldRollbackStage = isDelete
                && !expectedValue
                && opp.StageName == 'Visita Agendada';

            Boolean shouldAdvanceStage = !isDelete
                && expectedValue
                && opp.StageName == 'Cliente Contactado';

            Boolean shouldMarkConcretada = oppConcretadaDetailByOppId.containsKey(opp.Id) && !opp.Visita_Concretada__c;
            Boolean shouldFillDetalle = oppConcretadaDetailByOppId.containsKey(opp.Id) && String.isBlank(opp.Detalles__c);

            if (opp.Tiene_Visita_Agendada__c != expectedValue || shouldRollbackStage || shouldAdvanceStage || shouldMarkConcretada || shouldFillDetalle) {
                Opportunity oppUpdate = new Opportunity(
                    Id = opp.Id,
                    Tiene_Visita_Agendada__c = expectedValue
                );

                if (shouldRollbackStage) {
                    oppUpdate.StageName = 'Cliente Contactado';
                } else if (shouldAdvanceStage) {
                    oppUpdate.StageName = 'Visita Agendada';
                }

                if (shouldMarkConcretada) {
                    oppUpdate.Visita_Concretada__c = true;
                }

                if (shouldFillDetalle) {
                    oppUpdate.Detalles__c = oppConcretadaDetailByOppId.get(opp.Id);
                }

                updates.add(oppUpdate);
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Map<Id, String> collectConcretadaDetails(
        List<Event> newList,
        Map<Id, Event> oldMap,
        Boolean isDelete,
        Set<Id> autoOppIds
    ) {
        Map<Id, String> result = new Map<Id, String>();
        if (isDelete || newList == null || autoOppIds.isEmpty()) {
            return result;
        }

        for (Event ev : newList) {
            if (ev.WhatId == null || !autoOppIds.contains(ev.WhatId)) {
                continue;
            }

            if (ev.Estado_de_la_visita__c != VISIT_STATUS_CONCRETADA) {
                continue;
            }

            String detail = String.isNotBlank(ev.Description) ? ev.Description : ev.Subject;
            if (String.isNotBlank(detail) && !result.containsKey(ev.WhatId)) {
                result.put(ev.WhatId, detail);
            }
        }

        return result;
    }

    private static Set<Id> collectOpportunityIds(
        List<Event> newList,
        Map<Id, Event> oldMap,
        Boolean isDelete
    ) {
        Set<Id> oppIds = new Set<Id>();

        if (newList != null) {
            for (Event ev : newList) {
                addIfOpportunityId(oppIds, ev.WhatId);
                if (oldMap != null && oldMap.containsKey(ev.Id)) {
                    addIfOpportunityId(oppIds, oldMap.get(ev.Id).WhatId);
                }
            }
        }

        if (isDelete && oldMap != null) {
            for (Event oldEv : oldMap.values()) {
                addIfOpportunityId(oppIds, oldEv.WhatId);
            }
        }

        return oppIds;
    }

    private static void addIfOpportunityId(Set<Id> oppIds, Id whatId) {
        if (whatId == null) {
            return;
        }

        String idValue = String.valueOf(whatId);
        if (idValue.startsWith('006')) {
            oppIds.add(whatId);
        }
    }
}