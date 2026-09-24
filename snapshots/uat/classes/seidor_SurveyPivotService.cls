public with sharing class seidor_SurveyPivotService {

    @AuraEnabled(cacheable=false)
    public static SurveyPivotResult getSurveyQAData(
        String dateFrom, String dateTo, String agentId, String questionText, String statusFilter, Integer limitSessions
    ) {
        SurveyPivotResult result = new SurveyPivotResult();
        result.rows = new List<SurveyQARow>();
        result.uniqueQuestions = new List<String>();

        Set<String> questionSet = new Set<String>();
        List<MessagingSession> sessions = queryEndedSessions(dateFrom, dateTo, statusFilter, limitSessions);
        if (sessions.isEmpty()) return result;

        Map<Id, AgentInfo>    agentInfoMap = getAgentInfo(sessions);
        Map<Id, EndUserInfo>  endUserMap   = getEndUserInfo(sessions);
        Map<Id, String>       uuidBySfId   = getConversationUUIDs(sessions);

        // Deduplicar por ConversationId — múltiples MessagingSession pueden apuntar
        // a la misma Conversation (ej. transferencias entre agentes). Sin esto, los
        // mismos mensajes se fetean N veces y aparecen como filas idénticas en el pivot.
        Map<Id, MessagingSession> sessionByConvId = new Map<Id, MessagingSession>();
        for (MessagingSession s : sessions) {
            if (s.ConversationId != null && !sessionByConvId.containsKey(s.ConversationId)) {
                sessionByConvId.put(s.ConversationId, s);
            }
        }

        // Mapa ConversationId → AgentInfo construido ANTES de deduplicar.
        // Prioridad: campo Agente__c (escrito por el agente al tipificar) > AgentWork cross-lookup.
        // Session A (agente humano) tiene AgentWork; Session B (bot) no lo tiene.
        // Al recorrer todos los sessions, Session A popula el mapa con su ConvId
        // y Session B lo hereda en el lookup, resolviendo el agente correctamente.
        Map<Id, AgentInfo> agentByConvId = new Map<Id, AgentInfo>();
        for (MessagingSession s : sessions) {
            if (s.ConversationId == null) continue;
            // Preferir Agente__c cuando esté poblado (más confiable que AgentWork)
            if (s.Agente__c != null && !agentByConvId.containsKey(s.ConversationId)) {
                AgentInfo ai = new AgentInfo();
                ai.userId = s.Agente__c;
                ai.name   = s.Agente__r != null ? s.Agente__r.Name : null;
                agentByConvId.put(s.ConversationId, ai);
            }
        }
        // Fallback: AgentWork para conversaciones sin Agente__c
        for (MessagingSession s : sessions) {
            if (s.ConversationId == null) continue;
            if (!agentByConvId.containsKey(s.ConversationId)) {
                AgentInfo ai = agentInfoMap.get(s.Id);
                if (ai != null) {
                    agentByConvId.put(s.ConversationId, ai);
                }
            }
        }

        String normalizedQuestionFilter = String.isNotBlank(questionText) ? normalizeQuestion(questionText) : null;
        Integer apiErrorCount = 0;
        String  firstApiError = null;

        for (MessagingSession s : sessionByConvId.values()) {
            AgentInfo ai = agentByConvId.get(s.ConversationId);

            // Filtrar por ejecutivo a nivel servidor
            if (String.isNotBlank(agentId)) {
                Id agentIdFilter = (Id)agentId;
                if (ai == null || agentIdFilter != (Id)ai.userId) continue;
            }

            String uuid = uuidBySfId.get(s.ConversationId);
            if (String.isBlank(uuid)) continue;

            List<seidor_ConversationEntryDTO.MessageWrapper> messages;
            try {
                messages = seidor_ConversationDataService.getMessagesByUUID(uuid, s.ConversationId, s.Id);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'API Error session ' + s.Id + ': ' + e.getMessage());
                apiErrorCount++;
                if (firstApiError == null) firstApiError = e.getMessage();
                continue;
            }

            if (messages == null || messages.size() < 2) continue;

            messages = sortMessagesByTimestamp(messages);

            for (Integer i = 0; i < messages.size() - 1; i++) {
                seidor_ConversationEntryDTO.MessageWrapper current = messages[i];
                seidor_ConversationEntryDTO.MessageWrapper next = messages[i + 1];

                String role = current.senderRole;
                if (role != 'Chatbot' && role != 'System') continue;
                if (next.senderRole != 'EndUser') continue;
                if (String.isBlank(current.messageText)) continue;
                if (String.isBlank(next.messageText)) continue;

                String normalizedQuestion = normalizeQuestion(current.messageText);

                // Filtrar por pregunta a nivel servidor
                if (normalizedQuestionFilter != null && !normalizedQuestion.equals(normalizedQuestionFilter)) {
                    continue;
                }

                SurveyQARow row = new SurveyQARow();
                row.sessionId    = s.Id;
                row.sessionName  = s.Name;
                row.conversationUUID = uuid;
                row.agentId = ai != null ? ai.userId : null;
                row.agentName = ai != null ? ai.name : 'Sin asignar';
                EndUserInfo eu   = endUserMap.get(s.MessagingEndUserId);
                row.endUserPhone = eu != null ? eu.phone       : null;
                row.endUserName  = eu != null ? eu.name        : null;
                row.accountName  = eu != null ? eu.accountName : null;
                row.questionText = normalizedQuestion;
                row.answerText = next.messageText;
                row.sessionStartTime = s.StartTime;
                row.sessionEndTime   = s.EndTime;
                row.questionTimestamp = current.messageTimestamp;

                result.rows.add(row);

                if (String.isNotBlank(normalizedQuestion)) {
                    questionSet.add(normalizedQuestion);
                }
            }
        }

        result.uniqueQuestions = new List<String>(questionSet);
        result.uniqueQuestions.sort();

        if (apiErrorCount > 0 && result.rows.isEmpty()) {
            String detail = String.isNotBlank(firstApiError) ? ' | Detalle: ' + firstApiError : '';
            throw new AuraHandledException(
                'No se obtuvieron mensajes del API (' + apiErrorCount + ' sesión(es) con error).' +
                detail
            );
        }

        return result;
    }

    private static String normalizeQuestion(String q) {
        if (String.isBlank(q)) return '';
        String normalized = q.trim();
        if (normalized.length() > 200) normalized = normalized.substring(0, 200);
        return normalized;
    }

    private static List<MessagingSession> queryEndedSessions(
        String dateFrom, String dateTo, String statusFilter, Integer lim
    ) {
        Integer safeLimit = lim != null && lim > 0 ? lim : 100;
        DateTime dtFrom = parseDate(dateFrom, false);
        DateTime dtTo = parseDate(dateTo, true);

        String status = String.isNotBlank(statusFilter) ? statusFilter : 'Ended';

        return [
            SELECT Id, Name, ConversationId, Status, StartTime, EndTime, MessagingEndUserId,
                   Agente__c, Agente__r.Name
            FROM MessagingSession
            WHERE StartTime >= :dtFrom
              AND StartTime <= :dtTo
              AND Status = :status
              AND ConversationId != null
            ORDER BY StartTime DESC
            LIMIT :safeLimit
        ];
    }

    private static Map<Id, AgentInfo> getAgentInfo(List<MessagingSession> sessions) {
        Map<Id, AgentInfo> result = new Map<Id, AgentInfo>();
        Set<Id> sessionIds = new Set<Id>();
        for (MessagingSession s : sessions) sessionIds.add(s.Id);

        for (AgentWork aw : [
            SELECT WorkItemId, UserId, User.Name
            FROM AgentWork
            WHERE WorkItemId IN :sessionIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!result.containsKey(aw.WorkItemId)) {
                AgentInfo ai = new AgentInfo();
                ai.userId = aw.UserId;
                ai.name = aw.User.Name;
                result.put(aw.WorkItemId, ai);
            }
        }
        return result;
    }

    private class AgentInfo {
        public String userId;
        public String name;
    }

    private class EndUserInfo {
        public String phone;
        public String name;
        public String accountName;
    }

    private static Map<Id, EndUserInfo> getEndUserInfo(List<MessagingSession> sessions) {
        Map<Id, EndUserInfo> result = new Map<Id, EndUserInfo>();
        Set<Id> userIds = new Set<Id>();
        for (MessagingSession s : sessions) {
            if (s.MessagingEndUserId != null) userIds.add(s.MessagingEndUserId);
        }
        if (userIds.isEmpty()) return result;
        for (MessagingEndUser u : [
            SELECT Id, Name, MessagingPlatformKey,
                   ContactId, Contact.Name, Contact.Account.Name
            FROM MessagingEndUser WHERE Id IN :userIds
        ]) {
            EndUserInfo info = new EndUserInfo();
            info.phone       = u.MessagingPlatformKey;
            info.name        = u.ContactId != null ? u.Contact.Name : u.Name;
            info.accountName = (u.ContactId != null && u.Contact.AccountId != null)
                               ? u.Contact.Account.Name : null;
            result.put(u.Id, info);
        }
        return result;
    }

    private static Map<Id, String> getConversationUUIDs(List<MessagingSession> sessions) {
        Map<Id, String> result = new Map<Id, String>();
        Set<Id> convIds = new Set<Id>();
        for (MessagingSession s : sessions) {
            if (s.ConversationId != null) convIds.add(s.ConversationId);
        }
        if (convIds.isEmpty()) return result;
        for (Conversation c : [
            SELECT Id, ConversationIdentifier FROM Conversation WHERE Id IN :convIds
        ]) {
            result.put(c.Id, c.ConversationIdentifier);
        }
        return result;
    }

    private static List<seidor_ConversationEntryDTO.MessageWrapper> sortMessagesByTimestamp(
        List<seidor_ConversationEntryDTO.MessageWrapper> msgs
    ) {
        List<seidor_ConversationEntryDTO.MessageWrapper> sorted = new List<seidor_ConversationEntryDTO.MessageWrapper>();
        Map<DateTime, List<seidor_ConversationEntryDTO.MessageWrapper>> byTime =
            new Map<DateTime, List<seidor_ConversationEntryDTO.MessageWrapper>>();
        List<DateTime> timestamps = new List<DateTime>();

        for (seidor_ConversationEntryDTO.MessageWrapper m : msgs) {
            DateTime ts = m.messageTimestamp;
            if (ts == null) ts = DateTime.newInstance(2000, 1, 1);
            if (!byTime.containsKey(ts)) {
                byTime.put(ts, new List<seidor_ConversationEntryDTO.MessageWrapper>());
                timestamps.add(ts);
            }
            byTime.get(ts).add(m);
        }

        timestamps.sort();
        for (DateTime ts : timestamps) {
            sorted.addAll(byTime.get(ts));
        }
        return sorted;
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
        } catch (Exception e) {
            return endOfDay ? DateTime.now()
                : DateTime.newInstance(Date.today().addDays(-30), Time.newInstance(0,0,0,0));
        }
    }

    public class SurveyPivotResult {
        @AuraEnabled public List<SurveyQARow> rows;
        @AuraEnabled public List<String> uniqueQuestions;
    }

    public class SurveyQARow {
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   sessionName;
        @AuraEnabled public String   conversationUUID;
        @AuraEnabled public String   agentId;
        @AuraEnabled public String   agentName;
        @AuraEnabled public String   endUserPhone;
        @AuraEnabled public String   endUserName;
        @AuraEnabled public String   accountName;
        @AuraEnabled public String   questionText;
        @AuraEnabled public String   answerText;
        @AuraEnabled public DateTime sessionStartTime;
        @AuraEnabled public DateTime sessionEndTime;
        @AuraEnabled public DateTime questionTimestamp;
    }
}