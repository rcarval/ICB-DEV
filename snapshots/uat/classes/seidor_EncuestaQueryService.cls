public with sharing class seidor_EncuestaQueryService {

    public class SurveyRow {
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   sessionName;
        @AuraEnabled public String   agentId;
        @AuraEnabled public String   agentName;
        @AuraEnabled public String   accountName;
        @AuraEnabled public String   clientName;
        @AuraEnabled public String   phone;
        @AuraEnabled public String   fcrAnswer;
        @AuraEnabled public String   csatAnswer;
        @AuraEnabled public Integer  csatScore;
        @AuraEnabled public String   mejorAnswer;
        @AuraEnabled public String   status;
        @AuraEnabled public DateTime sessionEndTime;
        @AuraEnabled public String   categoria; // 'sin_respuesta' | 'fuera_de_horario'
    }

    @AuraEnabled(cacheable=false)
    public static List<SurveyRow> getSurveyData(
        String dateFrom, String dateTo, String agentId, Boolean csatOnly
    ) {
        DateTime dtFrom     = parseDate(dateFrom, false);
        DateTime dtTo       = parseDate(dateTo,   true);
        Boolean  hasAgent   = String.isNotBlank(agentId);
        Boolean  hasCsatFilter = csatOnly == true;

        List<Encuesta_cliente__c> records;

        try {
            if (hasAgent && hasCsatFilter) {
                Id agId = (Id) agentId;
                records = [
                    SELECT Sesi_n_de_Mensajer_a__c, Numero_Sesion__c,
                           Nombre_del_agente__c, Nombre_del_agente__r.Name,
                           Cliente__c, Cliente__r.Name,
                           Contacto_cliente__c, Contacto_cliente__r.Name,
                           Telefono__c,
                           Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c,
                           CSAT_Puntaje__c, Qu_podr_amos_mejorar__c,
                           Estado_encuesta__c, Fecha_y_hora_encuesta__c
                    FROM Encuesta_cliente__c
                    WHERE Fecha_y_hora_encuesta__c >= :dtFrom
                      AND Fecha_y_hora_encuesta__c <= :dtTo
                      AND Nombre_del_agente__c = :agId
                      AND CSAT_Puntaje__c != null
                      AND Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c != true
                    WITH SYSTEM_MODE
                    ORDER BY Fecha_y_hora_encuesta__c DESC
                    LIMIT 5000
                ];
            } else if (hasAgent) {
                Id agId = (Id) agentId;
                records = [
                    SELECT Sesi_n_de_Mensajer_a__c, Numero_Sesion__c,
                           Nombre_del_agente__c, Nombre_del_agente__r.Name,
                           Cliente__c, Cliente__r.Name,
                           Contacto_cliente__c, Contacto_cliente__r.Name,
                           Telefono__c,
                           Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c,
                           CSAT_Puntaje__c, Qu_podr_amos_mejorar__c,
                           Estado_encuesta__c, Fecha_y_hora_encuesta__c
                    FROM Encuesta_cliente__c
                    WHERE Fecha_y_hora_encuesta__c >= :dtFrom
                      AND Fecha_y_hora_encuesta__c <= :dtTo
                      AND Nombre_del_agente__c = :agId
                      AND Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c != true
                    WITH SYSTEM_MODE
                    ORDER BY Fecha_y_hora_encuesta__c DESC
                    LIMIT 5000
                ];
            } else if (hasCsatFilter) {
                records = [
                    SELECT Sesi_n_de_Mensajer_a__c, Numero_Sesion__c,
                           Nombre_del_agente__c, Nombre_del_agente__r.Name,
                           Cliente__c, Cliente__r.Name,
                           Contacto_cliente__c, Contacto_cliente__r.Name,
                           Telefono__c,
                           Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c,
                           CSAT_Puntaje__c, Qu_podr_amos_mejorar__c,
                           Estado_encuesta__c, Fecha_y_hora_encuesta__c
                    FROM Encuesta_cliente__c
                    WHERE Fecha_y_hora_encuesta__c >= :dtFrom
                      AND Fecha_y_hora_encuesta__c <= :dtTo
                      AND CSAT_Puntaje__c != null
                      AND Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c != true
                    WITH SYSTEM_MODE
                    ORDER BY Fecha_y_hora_encuesta__c DESC
                    LIMIT 5000
                ];
            } else {
                records = [
                    SELECT Sesi_n_de_Mensajer_a__c, Numero_Sesion__c,
                           Nombre_del_agente__c, Nombre_del_agente__r.Name,
                           Cliente__c, Cliente__r.Name,
                           Contacto_cliente__c, Contacto_cliente__r.Name,
                           Telefono__c,
                           Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c,
                           CSAT_Puntaje__c, Qu_podr_amos_mejorar__c,
                           Estado_encuesta__c, Fecha_y_hora_encuesta__c
                    FROM Encuesta_cliente__c
                    WHERE Fecha_y_hora_encuesta__c >= :dtFrom
                      AND Fecha_y_hora_encuesta__c <= :dtTo
                      AND Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c != true
                    WITH SYSTEM_MODE
                    ORDER BY Fecha_y_hora_encuesta__c DESC
                    LIMIT 5000
                ];
            }
        } catch (System.QueryException qe) {
            throw new AuraHandledException(
                'No tienes permisos para consultar encuestas: ' + qe.getMessage()
            );
        }

        List<SurveyRow> result = new List<SurveyRow>();
        for (Encuesta_cliente__c e : records) {
            SurveyRow r = new SurveyRow();
            r.sessionId      = e.Sesi_n_de_Mensajer_a__c;
            r.sessionName    = e.Numero_Sesion__c;
            r.agentId        = e.Nombre_del_agente__c;
            r.agentName      = e.Nombre_del_agente__r != null
                               ? e.Nombre_del_agente__r.Name : 'Sin asignar';
            r.accountName    = e.Cliente__r           != null ? e.Cliente__r.Name           : null;
            r.clientName     = e.Contacto_cliente__r  != null ? e.Contacto_cliente__r.Name  : null;
            r.phone          = e.Telefono__c;
            r.fcrAnswer      = e.Tu_solicitud_fue_resuelta__c;
            r.csatAnswer     = e.Calificacion_de_atenci_n__c;
            r.csatScore      = e.CSAT_Puntaje__c != null ? Integer.valueOf(e.CSAT_Puntaje__c) : null;
            r.mejorAnswer    = e.Qu_podr_amos_mejorar__c;
            r.status         = e.Estado_encuesta__c;
            r.sessionEndTime = e.Fecha_y_hora_encuesta__c;
            result.add(r);
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static List<SurveyRow> getEmptySurveyData(String dateFrom, String dateTo) {
        DateTime dtFrom = parseDate(dateFrom, false);
        DateTime dtTo   = parseDate(dateTo,   true);

        List<Encuesta_cliente__c> records;
        try {
            records = [
                SELECT Sesi_n_de_Mensajer_a__c, Numero_Sesion__c,
                       Nombre_del_agente__c, Nombre_del_agente__r.Name,
                       Cliente__c, Cliente__r.Name,
                       Contacto_cliente__c, Contacto_cliente__r.Name,
                       Telefono__c,
                       Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c,
                       CSAT_Puntaje__c, Qu_podr_amos_mejorar__c,
                       Estado_encuesta__c, Fecha_y_hora_encuesta__c,
                       Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c
                FROM Encuesta_cliente__c
                WHERE Fecha_y_hora_encuesta__c >= :dtFrom
                  AND Fecha_y_hora_encuesta__c <= :dtTo
                  AND (
                    (Tu_solicitud_fue_resuelta__c = null AND CSAT_Puntaje__c = null)
                    OR Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c = true
                  )
                WITH SYSTEM_MODE
                ORDER BY Fecha_y_hora_encuesta__c DESC
                LIMIT 5000
            ];
        } catch (System.QueryException qe) {
            throw new AuraHandledException(
                'No tienes permisos para consultar encuestas: ' + qe.getMessage()
            );
        }

        List<SurveyRow> result = new List<SurveyRow>();
        for (Encuesta_cliente__c e : records) {
            SurveyRow r = new SurveyRow();
            r.sessionId      = e.Sesi_n_de_Mensajer_a__c;
            r.sessionName    = e.Numero_Sesion__c;
            r.agentId        = e.Nombre_del_agente__c;
            r.agentName      = e.Nombre_del_agente__r != null
                               ? e.Nombre_del_agente__r.Name : 'Sin asignar';
            r.accountName    = e.Cliente__r           != null ? e.Cliente__r.Name           : null;
            r.clientName     = e.Contacto_cliente__r  != null ? e.Contacto_cliente__r.Name  : null;
            r.phone          = e.Telefono__c;
            r.fcrAnswer      = e.Tu_solicitud_fue_resuelta__c;
            r.csatAnswer     = e.Calificacion_de_atenci_n__c;
            r.csatScore      = e.CSAT_Puntaje__c != null ? Integer.valueOf(e.CSAT_Puntaje__c) : null;
            r.mejorAnswer    = e.Qu_podr_amos_mejorar__c;
            r.status         = e.Estado_encuesta__c;
            r.sessionEndTime = e.Fecha_y_hora_encuesta__c;
            r.categoria      = e.Sesi_n_de_Mensajer_a__r != null
                               && e.Sesi_n_de_Mensajer_a__r.Fuera_de_horario__c == true
                               ? 'fuera_de_horario' : 'sin_respuesta';
            result.add(r);
        }
        return result;
    }

    private static DateTime parseDate(String dateStr, Boolean endOfDay) {
        if (String.isBlank(dateStr)) {
            return endOfDay
                ? DateTime.now()
                : DateTime.newInstance(Date.today().addDays(-30), Time.newInstance(0,0,0,0));
        }
        try {
            Date d = Date.valueOf(dateStr);
            return endOfDay
                ? DateTime.newInstance(d, Time.newInstance(23,59,59,0))
                : DateTime.newInstance(d, Time.newInstance(0,0,0,0));
        } catch (Exception ex) {
            return endOfDay
                ? DateTime.now()
                : DateTime.newInstance(Date.today().addDays(-30), Time.newInstance(0,0,0,0));
        }
    }
}