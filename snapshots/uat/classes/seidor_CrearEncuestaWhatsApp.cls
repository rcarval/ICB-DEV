/**
 * @description Invocable de Bot/Flow: crea Encuesta_cliente__c a partir de los
 * mensajes reales de la conversación de WhatsApp.
 *
 * Migrado desde seidor_WhatsAppConversationEntries (roto: usaba
 * UserInfo.getSessionId() como Bearer, lo cual falla en Lightning Experience
 * con INVALID_SESSION_ID, y parseaba la clave JSON equivocada) hacia
 * seidor_ConversationDataService (Named Credential, parseo correcto).
 *
 * También se reemplazó el parsing posicional de respuestas (frágil: asumía
 * que la 1ª respuesta del cliente era CSAT, la 2ª FCR, etc.) por el matching
 * por texto de pregunta de seidor_EncuestaQAMatcher — la misma lógica que
 * usa seidor_EncuestaSyncBatch, para que ambas rutas de creación coincidan.
 */
public with sharing class seidor_CrearEncuestaWhatsApp {

    public class Input {
        @InvocableVariable(required=true)
        public Id messagingSessionId;
    }

    @InvocableMethod(
        label='Crear encuesta desde conversación WhatsApp'
        description='Obtiene los mensajes de la sesión vía Conversation API y crea un registro Encuesta_cliente__c.'
    )
    public static void crearEncuesta(List<Input> inputs) {

        Set<Id> sessionIds = new Set<Id>();
        for (Input inp : inputs) {
            if (inp.messagingSessionId != null) sessionIds.add(inp.messagingSessionId);
        }
        if (sessionIds.isEmpty()) return;

        // Deduplicar: ignorar sesiones que ya tienen encuesta
        Map<Id, Encuesta_cliente__c> existentes = new Map<Id, Encuesta_cliente__c>();
        for (Encuesta_cliente__c e : [
            SELECT Id, Sesi_n_de_Mensajer_a__c
            FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__c IN :sessionIds
        ]) {
            existentes.put(e.Sesi_n_de_Mensajer_a__c, e);
        }

        // Datos de la sesión (Conversation, EndUser, Agente, nombre, fecha)
        Map<Id, MessagingSession> sessionMap = new Map<Id, MessagingSession>([
            SELECT Id, Name, EndTime, ConversationId, MessagingEndUserId,
                   Agente__c, Cliente__c, Contacto__c
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

        List<Encuesta_cliente__c> nuevasEncuestas = new List<Encuesta_cliente__c>();

        for (Input inp : inputs) {
            if (inp.messagingSessionId == null) continue;
            if (existentes.containsKey(inp.messagingSessionId)) continue;

            MessagingSession s = sessionMap.get(inp.messagingSessionId);
            if (s == null || s.ConversationId == null) continue;

            List<seidor_ConversationEntryDTO.MessageWrapper> messages;
            try {
                messages = seidor_ConversationDataService.getMessagesByConversationId(
                    s.ConversationId, inp.messagingSessionId
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'seidor_CrearEncuestaWhatsApp – error API sesión ' + inp.messagingSessionId
                    + ': ' + e.getMessage());
                continue;
            }

            if (messages == null || messages.size() < 2) continue;

            seidor_EncuestaQAMatcher.MatchResult match =
                seidor_EncuestaQAMatcher.extractFromMessages(messages);

            if (match.isEmpty()) continue;

            Id euId = s.MessagingEndUserId;
            String status = (match.fcrAnswer != null && match.csatAnswer != null)
                            ? 'Completada' : 'Incompleta';

            Encuesta_cliente__c encuesta = new Encuesta_cliente__c(
                Sesi_n_de_Mensajer_a__c      = inp.messagingSessionId,
                Numero_Sesion__c             = s.Name,
                Nombre_del_agente__c         = s.Agente__c,
                Fecha_y_hora_encuesta__c     = s.EndTime,
                Cliente__c                   = s.Cliente__c,
                Contacto_cliente__c          = s.Contacto__c,
                Telefono__c                  = euId != null ? phoneByEu.get(euId) : null,
                Tu_solicitud_fue_resuelta__c = match.fcrAnswer,
                Calificacion_de_atenci_n__c  = match.csatAnswer,
                CSAT_Puntaje__c              = match.csatScore,
                Qu_podr_amos_mejorar__c      = match.mejorAnswer,
                Estado_encuesta__c           = status
            );

            nuevasEncuestas.add(encuesta);
        }

        if (!nuevasEncuestas.isEmpty()) insert nuevasEncuestas;
    }
}