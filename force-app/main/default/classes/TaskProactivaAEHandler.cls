public with sharing class TaskProactivaAEHandler {

    private static final String RT_AUTO_ENROLAMIENTO = 'Auto_Enrolamiento';
    private static final String TASK_SUBJECT = 'Enviar propuesta al cliente';
    private static final String STAGE_VISITA_CONCERTADA = 'Visita Concertada';
    private static final String STAGE_PROPUESTA_ENVIADA = 'Propuesta Enviada';

    public static void afterUpdate(List<Task> newList, Map<Id, Task> oldMap) {
        Set<Id> oppIds = new Set<Id>();

        for (Task t : newList) {
            Task oldTask = oldMap.get(t.Id);
            if (oldTask == null) {
                continue;
            }

            if (t.WhatId == null || String.valueOf(t.WhatId).startsWith('006') == false) {
                continue;
            }

            if (t.Subject == TASK_SUBJECT && oldTask.IsClosed == false && t.IsClosed == true) {
                oppIds.add(t.WhatId);
            }
        }

        if (oppIds.isEmpty()) {
            return;
        }

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Opportunity opp : [
            SELECT Id, StageName, RecordType.DeveloperName
            FROM Opportunity
            WHERE Id IN :oppIds
        ]) {
            if (opp.RecordType != null &&
                opp.RecordType.DeveloperName == RT_AUTO_ENROLAMIENTO &&
                opp.StageName == STAGE_VISITA_CONCERTADA) {
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    StageName = STAGE_PROPUESTA_ENVIADA
                ));
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}