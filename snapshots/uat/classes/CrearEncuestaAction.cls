public with sharing class CrearEncuestaAction {

    public class Input {
        @InvocableVariable(required=true)
        public Id messagingSessionId;

        @InvocableVariable
        public String calificacion;

        @InvocableVariable
        public String solicitudResuelta;

        @InvocableVariable
        public String comentarioMejora;
    }

    @InvocableMethod(
        label='Crear Encuesta Cliente'
        description='Crea un registro Encuesta_cliente__c con las respuestas de la encuesta'
        category='Messaging'
    )
    public static void crearEncuesta(List<Input> inputs) {

        Set<Id> sessionIds = new Set<Id>();
        for (Input inp : inputs) {
            if (inp.messagingSessionId != null) sessionIds.add(inp.messagingSessionId);
        }
        if (sessionIds.isEmpty()) return;

        // Deduplicar por SessionId
        Set<Id> existentes = new Set<Id>();
        for (Encuesta_cliente__c e : [
            SELECT Sesi_n_de_Mensajer_a__c
            FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__c IN :sessionIds
        ]) {
            existentes.add(e.Sesi_n_de_Mensajer_a__c);
        }

        // Datos de la sesión
        Map<Id, MessagingSession> sessionMap = new Map<Id, MessagingSession>([
            SELECT Id, Name, EndTime, MessagingEndUserId, Agente__c, Cliente__c, Contacto__c
            FROM MessagingSession
            WHERE Id IN :sessionIds
        ]);

        // Teléfono del cliente desde MessagingEndUser
        Set<Id> euIds = new Set<Id>();
        for (MessagingSession s : sessionMap.values()) {
            if (s.MessagingEndUserId != null) euIds.add(s.MessagingEndUserId);
        }
        Map<Id, String> phoneByEu = new Map<Id, String>();
        if (!euIds.isEmpty()) {
            for (MessagingEndUser u : [
                SELECT Id, MessagingPlatformKey
                FROM MessagingEndUser WHERE Id IN :euIds
            ]) {
                phoneByEu.put(u.Id, u.MessagingPlatformKey);
            }
        }

        List<Encuesta_cliente__c> encuestas = new List<Encuesta_cliente__c>();

        for (Input inp : inputs) {
            if (inp.messagingSessionId == null) continue;
            if (existentes.contains(inp.messagingSessionId)) continue;

            MessagingSession s  = sessionMap.get(inp.messagingSessionId);
            Id euId             = s != null ? s.MessagingEndUserId : null;

            encuestas.add(new Encuesta_cliente__c(
                Sesi_n_de_Mensajer_a__c      = inp.messagingSessionId,
                Numero_Sesion__c              = s != null ? s.Name     : null,
                Nombre_del_agente__c          = s != null ? s.Agente__c : null,
                Fecha_y_hora_encuesta__c      = s != null ? s.EndTime  : null,
                Cliente__c                    = s.Cliente__c,
                Contacto_cliente__c           = s.Contacto__c,
                Telefono__c                   = euId != null ? phoneByEu.get(euId)   : null,
                Calificacion_de_atenci_n__c   = inp.calificacion,
                Tu_solicitud_fue_resuelta__c  = inp.solicitudResuelta,
                Qu_podr_amos_mejorar__c       = inp.comentarioMejora
            ));
        }

        if (!encuestas.isEmpty()) insert encuestas;
    }
}