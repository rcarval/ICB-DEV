public class seidor_EncuestaSyncBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    // El matching de preguntas/respuestas vive en seidor_EncuestaQAMatcher,
    // compartido con seidor_CrearEncuestaWhatsApp — única fuente de verdad.

    // Scope conservador: worst-case 10 callouts/sesión × 10 = 100 (límite governor)
    private static final Integer BATCH_SCOPE = 10;

    private Integer daysBack;

    public seidor_EncuestaSyncBatch()                 { this.daysBack = 90; }
    public seidor_EncuestaSyncBatch(Integer daysBack) { this.daysBack = daysBack; }

    // ── Schedulable ───────────────────────────────────────────────────────────

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new seidor_EncuestaSyncBatch(90), BATCH_SCOPE);
    }

    // ── Batchable: start ──────────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date fromDate = Date.today().addDays(-daysBack);
        return Database.getQueryLocator([
            SELECT Id, Name, ConversationId, StartTime, EndTime, MessagingEndUserId,
                   Agente__c, Agente__r.Name, Cliente__c, Contacto__c
            FROM MessagingSession
            WHERE Status = 'Ended'
              AND StartTime >= :fromDate
              AND ConversationId != null
              AND Id NOT IN (
                  SELECT Sesi_n_de_Mensajer_a__c
                  FROM Encuesta_cliente__c
                  WHERE Sesi_n_de_Mensajer_a__c != null
              )
            ORDER BY StartTime DESC
        ]);
    }

    // ── Batchable: execute ────────────────────────────────────────────────────

    public void execute(Database.BatchableContext bc, List<MessagingSession> scope) {

        // 1. Construir mapas base
        Map<Id, MessagingSession> sessionByConvId = new Map<Id, MessagingSession>();
        Map<Id, Id>               convIdBySession  = new Map<Id, Id>();
        Set<Id>                   convIds          = new Set<Id>();

        for (MessagingSession s : scope) {
            convIdBySession.put(s.Id, s.ConversationId);
            convIds.add(s.ConversationId);
            // DESC: la primera vista por ConvId es la más reciente (Sesión B / bot)
            if (!sessionByConvId.containsKey(s.ConversationId)) {
                sessionByConvId.put(s.ConversationId, s);
            }
        }

        // 2. Excluir conversaciones ya procesadas (por ConvId, no solo por SessionId)
        Set<Id> alreadyDoneConvIds = new Set<Id>();
        for (Encuesta_cliente__c e : [
            SELECT Sesi_n_de_Mensajer_a__r.ConversationId
            FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__r.ConversationId IN :convIds
              AND Sesi_n_de_Mensajer_a__c != null
        ]) {
            if (e.Sesi_n_de_Mensajer_a__r != null
                    && e.Sesi_n_de_Mensajer_a__r.ConversationId != null) {
                alreadyDoneConvIds.add(e.Sesi_n_de_Mensajer_a__r.ConversationId);
            }
        }
        for (Id cid : alreadyDoneConvIds) sessionByConvId.remove(cid);
        if (sessionByConvId.isEmpty()) return;

        // 3. UUIDs de conversación
        Map<Id, String> uuidByConvId = new Map<Id, String>();
        for (Conversation c : [
            SELECT Id, ConversationIdentifier
            FROM Conversation
            WHERE Id IN :sessionByConvId.keySet()
        ]) {
            uuidByConvId.put(c.Id, c.ConversationIdentifier);
        }

        // 4. Teléfono del cliente (desde MessagingEndUser)
        Set<Id> euIds = new Set<Id>();
        for (MessagingSession s : sessionByConvId.values()) {
            if (s.MessagingEndUserId != null) euIds.add(s.MessagingEndUserId);
        }
        Map<Id, EndUserData> euMap = new Map<Id, EndUserData>();
        if (!euIds.isEmpty()) {
            for (MessagingEndUser u : [
                SELECT Id, MessagingPlatformKey
                FROM MessagingEndUser
                WHERE Id IN :euIds
            ]) {
                EndUserData eu = new EndUserData();
                eu.phone = u.MessagingPlatformKey;
                euMap.put(u.Id, eu);
            }
        }

        // 5. Resolución del agente: Agente__c > AgentWork (fallback)
        Set<Id> scopeIds = convIdBySession.keySet();
        Map<Id, Id> agentIdByConv = new Map<Id, Id>();

        for (MessagingSession s : scope) {
            if (s.Agente__c != null && !agentIdByConv.containsKey(s.ConversationId)) {
                agentIdByConv.put(s.ConversationId, s.Agente__c);
            }
        }
        for (AgentWork aw : [
            SELECT WorkItemId, UserId
            FROM AgentWork
            WHERE WorkItemId IN :scopeIds
            ORDER BY CreatedDate DESC
        ]) {
            Id convId = convIdBySession.get(aw.WorkItemId);
            if (convId != null && !agentIdByConv.containsKey(convId)) {
                agentIdByConv.put(convId, aw.UserId);
            }
        }

        // 6. Llamada a la API y parseo de Q&A por cada conversación única
        List<Encuesta_cliente__c> toInsert = new List<Encuesta_cliente__c>();

        for (MessagingSession s : sessionByConvId.values()) {
            String uuid = uuidByConvId.get(s.ConversationId);
            if (String.isBlank(uuid)) continue;

            List<seidor_ConversationEntryDTO.MessageWrapper> messages;
            try {
                messages = seidor_ConversationDataService.getMessagesByUUID(
                    uuid, s.ConversationId, s.Id
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'EncuestaSyncBatch – error API sesión ' + s.Id + ': ' + e.getMessage());
                continue;
            }

            if (messages == null || messages.size() < 2) continue;

            seidor_EncuestaQAMatcher.MatchResult match =
                seidor_EncuestaQAMatcher.extractFromMessages(messages);

            String status = (match.fcrAnswer != null && match.csatAnswer != null)
                            ? 'Completada' : 'Incompleta';
            EndUserData eu = euMap.get(s.MessagingEndUserId);

            toInsert.add(new Encuesta_cliente__c(
                Sesi_n_de_Mensajer_a__c     = s.Id,
                Numero_Sesion__c             = s.Name,
                Nombre_del_agente__c         = agentIdByConv.get(s.ConversationId),
                Cliente__c                   = s.Cliente__c,
                Contacto_cliente__c          = s.Contacto__c,
                Telefono__c                  = eu != null ? eu.phone      : null,
                Tu_solicitud_fue_resuelta__c = match.fcrAnswer,
                Calificacion_de_atenci_n__c  = match.csatAnswer,
                CSAT_Puntaje__c              = match.csatScore,
                Qu_podr_amos_mejorar__c      = match.mejorAnswer,
                Estado_encuesta__c           = status,
                Fecha_y_hora_encuesta__c     = s.EndTime
            ));
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('seidor_EncuestaSyncBatch finalizado.');
    }

    private class EndUserData {
        String phone;
    }
}