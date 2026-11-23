/**
 * @description Servicio para obtener mensajes de sesiones de mensajería
 * via Connect REST API — Enhanced WhatsApp channel
 *
 * ENDPOINT CORRECTO (validado en sandbox UAT):
 *   GET /services/data/v62.0/connect/conversation/{ConversationIdentifier}/entries
 *
 * PUNTOS CRÍTICOS:
 *   - "conversation" en SINGULAR (no "conversations")
 *   - Usar ConversationIdentifier (UUID) del objeto Conversation, NO el Salesforce ID (0dw...)
 *   - Obtener el UUID via SOQL: SELECT ConversationIdentifier FROM Conversation WHERE Id = '0dw...'
 *
 * ROLES de sender:
 *   - EndUser  → cliente (appType: live_message)
 *   - Chatbot  → bot automatizado (appType: chatbot)
 *   - System   → mensajes de sistema (appType: conversation)
 *   - Agent    → agente humano (appType: live_agent)
 */
public with sharing class seidor_ConversationDataService {

    private static final String API_VERSION = 'v62.0';
    private static final Integer PAGE_SIZE  = 100;
    private static final Integer MAX_PAGES  = 10;

    // ─── Métodos @AuraEnabled ──────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<seidor_ConversationEntryDTO.SessionWithMessages> getSessionsWithMessages(
        Integer limitSessions,
        String statusFilter
    ) {
        List<MessagingSession> sessions = querySessions(limitSessions, statusFilter);
        if (sessions.isEmpty()) return new List<seidor_ConversationEntryDTO.SessionWithMessages>();

        Set<Id> sfConvIds = new Set<Id>();
        for (MessagingSession s : sessions) {
            if (String.isNotBlank(s.ConversationId)) sfConvIds.add(s.ConversationId);
        }

        Map<Id, String> uuidBySfId = getConversationUUIDs(sfConvIds);

        Map<Id, MessagingSession> sessionByConvId = new Map<Id, MessagingSession>();
        for (MessagingSession s : sessions) {
            if (String.isNotBlank(s.ConversationId) && !sessionByConvId.containsKey(s.ConversationId)) {
                sessionByConvId.put(s.ConversationId, s);
            }
        }

        List<seidor_ConversationEntryDTO.SessionWithMessages> result =
            new List<seidor_ConversationEntryDTO.SessionWithMessages>();

        for (Id sfConvId : sfConvIds) {
            MessagingSession session = sessionByConvId.get(sfConvId);
            String uuid = uuidBySfId.get(sfConvId);
            if (String.isBlank(uuid)) continue;

            seidor_ConversationEntryDTO.SessionWithMessages sw =
                new seidor_ConversationEntryDTO.SessionWithMessages();
            sw.sessionId        = session.Id;
            sw.conversationId   = sfConvId;
            sw.conversationUUID = uuid;
            sw.status           = session.Status;
            sw.endUserId        = session.MessagingEndUserId;
            sw.channelId        = session.MessagingChannelId;
            sw.startTime        = session.StartTime;
            sw.endTime          = session.EndTime;

            try {
                sw.messages      = getMessagesForConversation(uuid, sfConvId, session.Id);
                sw.totalMessages = sw.messages.size();
                sw.agentMessages = countByRole(sw.messages, 'Agent');
                sw.userMessages  = countByRole(sw.messages, 'EndUser');
                sw.botMessages   = countByRole(sw.messages, 'Chatbot');
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error en conversación ' + sfConvId + ': ' + e.getMessage());
                sw.messages      = new List<seidor_ConversationEntryDTO.MessageWrapper>();
                sw.totalMessages = 0;
            }

            result.add(sw);
        }

        return result;
    }

    @AuraEnabled(cacheable=false)
    public static List<seidor_ConversationEntryDTO.MessageWrapper> getMessagesByConversationId(
        String conversationSfId,
        String sessionId
    ) {
        if (String.isBlank(conversationSfId)) {
            throw new AuraHandledException('ConversationId es requerido');
        }

        Map<Id, String> uuidMap = getConversationUUIDs(new Set<Id>{ conversationSfId });
        String uuid = uuidMap.get(conversationSfId);

        if (String.isBlank(uuid)) {
            throw new AuraHandledException('ConversationIdentifier (UUID) no encontrado para: ' + conversationSfId);
        }

        return getMessagesForConversation(uuid, conversationSfId, sessionId);
    }

    @AuraEnabled(cacheable=false)
    public static List<seidor_ConversationEntryDTO.MessageWrapper> getMessagesByUUID(
        String conversationUUID,
        String conversationSfId,
        String sessionId
    ) {
        if (String.isBlank(conversationUUID)) {
            throw new AuraHandledException('ConversationIdentifier UUID es requerido');
        }
        return getMessagesForConversation(conversationUUID, conversationSfId, sessionId);
    }

    // ─── Lógica de API Call ────────────────────────────────────────────────────

    private static List<seidor_ConversationEntryDTO.MessageWrapper> getMessagesForConversation(
        String uuid,
        String sfConvId,
        String sessionId
    ) {
        List<seidor_ConversationEntryDTO.MessageWrapper> allMessages =
            new List<seidor_ConversationEntryDTO.MessageWrapper>();
        String pageToken = null;
        Integer pageCount = 0;

        do {
            HttpResponse response = makeApiCall(buildEndpoint(uuid, pageToken));

            if (response.getStatusCode() != 200) {
                throw new seidor_ConversationDataService.ConversationApiException(
                    'API Error ' + response.getStatusCode() + ': ' + response.getBody()
                );
            }

            seidor_ConversationEntryDTO.ConversationEntriesResponse parsed =
                (seidor_ConversationEntryDTO.ConversationEntriesResponse) JSON.deserialize(
                    response.getBody(),
                    seidor_ConversationEntryDTO.ConversationEntriesResponse.class
                );

            if (parsed.conversationEntries != null) {
                for (seidor_ConversationEntryDTO.ConversationEntry entry : parsed.conversationEntries) {
                    if (String.isNotBlank(entry.messageText)) {
                        allMessages.add(toWrapper(entry, sfConvId, sessionId));
                    }
                }
            }

            pageToken = parsed.hasNextPage == true ? parsed.nextPageToken : null;
            pageCount++;

        } while (pageToken != null && pageCount < MAX_PAGES);

        return allMessages;
    }

    private static HttpResponse makeApiCall(String endpoint) {
        // Named Credential maneja la autenticación automáticamente.
        // UserInfo.getSessionId() NO funciona en Lightning Experience (INVALID_SESSION_ID).
        // Prerequisito: crear Named Credential "SF_Internal_API" en Setup.
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setTimeout(30000);
        req.setEndpoint('callout:SF_Internal_API' + endpoint);
        req.setHeader('Content-Type', 'application/json');
        return new Http().send(req);
    }

    private static String buildEndpoint(String uuid, String pageToken) {
        String base = '/services/data/' + API_VERSION +
                      '/connect/conversation/' + uuid +
                      '/entries?pageSize=' + PAGE_SIZE;
        if (String.isNotBlank(pageToken)) {
            base += '&pageParam=' + EncodingUtil.urlEncode(pageToken, 'UTF-8');
        }
        return base;
    }

    // ─── Helpers SOQL ─────────────────────────────────────────────────────────

    private static Map<Id, String> getConversationUUIDs(Set<Id> sfConvIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (sfConvIds.isEmpty()) return result;
        try {
            for (Conversation c : [
                SELECT Id, ConversationIdentifier
                FROM Conversation
                WHERE Id IN :sfConvIds
                WITH USER_MODE
            ]) {
                result.put(c.Id, c.ConversationIdentifier);
            }
        } catch (System.QueryException qe) {
            System.debug(LoggingLevel.WARN, 'Conversation query error: ' + qe.getMessage());
        }
        return result;
    }

    private static List<MessagingSession> querySessions(Integer lim, String statusFilter) {
        Integer safeLimit = lim != null ? lim : 20;
        try {
            if (String.isNotBlank(statusFilter)) {
                return [
                    SELECT Id, ConversationId, Status, StartTime, EndTime,
                           MessagingEndUserId, MessagingChannelId
                    FROM MessagingSession
                    WHERE Status = :statusFilter AND ConversationId != null
                    WITH USER_MODE
                    ORDER BY StartTime DESC LIMIT :safeLimit
                ];
            }
            return [
                SELECT Id, ConversationId, Status, StartTime, EndTime,
                       MessagingEndUserId, MessagingChannelId
                FROM MessagingSession
                WHERE ConversationId != null
                WITH USER_MODE
                ORDER BY StartTime DESC LIMIT :safeLimit
            ];
        } catch (System.QueryException qe) {
            throw new AuraHandledException(
                'No tienes permisos para consultar sesiones de mensajería: ' + qe.getMessage()
            );
        }
    }

    private static seidor_ConversationEntryDTO.MessageWrapper toWrapper(
        seidor_ConversationEntryDTO.ConversationEntry entry,
        String conversationId,
        String sessionId
    ) {
        seidor_ConversationEntryDTO.MessageWrapper w = new seidor_ConversationEntryDTO.MessageWrapper();
        w.messageId        = entry.identifier;
        w.conversationId   = conversationId;
        w.sessionId        = sessionId;
        w.messageText      = entry.messageText;
        w.rawTimestamp     = String.valueOf(entry.serverReceivedTimestamp);

        seidor_ConversationEntryDTO.SenderInfo senderInfo = entry.sender != null ? entry.sender : entry.actor;
        if (senderInfo != null) {
            w.senderRole = senderInfo.role;
            w.senderName = senderInfo.subject;
        }

        if (entry.serverReceivedTimestamp != null) {
            w.messageTimestamp = DateTime.newInstance(entry.serverReceivedTimestamp);
        }

        return w;
    }

    private static Integer countByRole(
        List<seidor_ConversationEntryDTO.MessageWrapper> msgs, String role
    ) {
        Integer count = 0;
        for (seidor_ConversationEntryDTO.MessageWrapper m : msgs) {
            if (m.senderRole == role) count++;
        }
        return count;
    }

    public class ConversationApiException extends Exception {}
}