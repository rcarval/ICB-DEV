public with sharing class seidor_WhatsAppFiltro {

    private static final String API_VERSION = 'v62.0';
    private static final Integer PAGE_SIZE  = 100;
    private static final Integer MAX_PAGES  = 10;
    private static final Integer MAX_SESSION_ROWS = 500;

    public class SearchResult {
        @AuraEnabled public String sessionId { get; set; }
        @AuraEnabled public String sessionName { get; set; }
        @AuraEnabled public String conversationId { get; set; }
        @AuraEnabled public String endUserName { get; set; }
        @AuraEnabled public String matchingMessage { get; set; }
        @AuraEnabled public Integer matchCount { get; set; }
        @AuraEnabled public Datetime startTime { get; set; }
    }

    public class MessageWrapper implements Comparable {
        @AuraEnabled public String messageId { get; set; }
        @AuraEnabled public String senderRole { get; set; }
        @AuraEnabled public String senderName { get; set; }
        @AuraEnabled public String messageText { get; set; }
        @AuraEnabled public Datetime messageTimestamp { get; set; }

        public Integer compareTo(Object other) {
            MessageWrapper o = (MessageWrapper) other;
            if (this.messageTimestamp == null || o.messageTimestamp == null) return 0;
            if (this.messageTimestamp == o.messageTimestamp) return 0;
            return this.messageTimestamp < o.messageTimestamp ? -1 : 1;
        }
    }

    public class ConversationApiException extends Exception {}

    // ─── Métodos @AuraEnabled ───────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<SearchResult> searchKeywordInChats(String searchTerm, Integer limitSessions) {
        List<SearchResult> results = new List<SearchResult>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return results;
        }

        String searchLower = searchTerm.trim().toLowerCase();
        Integer safeLimit = limitSessions != null ? limitSessions : 30;

        Set<Id> mySessionIds = getMyAuthorizedSessionIds();
        if (mySessionIds.isEmpty()) {
            return results;
        }

        List<MessagingSession> sessions = [
            SELECT Id, Name, ConversationId, StartTime, MessagingEndUser.Name
            FROM MessagingSession
            WHERE ConversationId != null
            AND Id IN :mySessionIds
            WITH USER_MODE
            ORDER BY StartTime DESC
            LIMIT :safeLimit
        ];
        if (sessions.isEmpty()) return results;

        Set<Id> sfConvIds = new Set<Id>();
        for (MessagingSession ms : sessions) sfConvIds.add(ms.ConversationId);
        Map<Id, String> uuidBySfId = getConversationUUIDs(sfConvIds);

        for (MessagingSession ms : sessions) {
            String uuid = uuidBySfId.get(ms.ConversationId);
            if (String.isBlank(uuid)) continue;

            try {
                List<MessageWrapper> messages = fetchConversationEntries(uuid);
                String firstMatch = null;
                Integer matches = 0;

                for (MessageWrapper m : messages) {
                    if (String.isNotBlank(m.messageText) && m.messageText.toLowerCase().contains(searchLower)) {
                        matches++;
                        if (firstMatch == null) firstMatch = m.messageText;
                    }
                }

                if (matches > 0) {
                    SearchResult item = new SearchResult();
                    item.sessionId       = ms.Id;
                    item.sessionName     = ms.Name;
                    item.conversationId  = ms.ConversationId;
                    item.endUserName     = (ms.MessagingEndUser != null) ? ms.MessagingEndUser.Name : 'Desconocido';
                    item.matchingMessage = firstMatch;
                    item.matchCount      = matches;
                    item.startTime       = ms.StartTime;
                    results.add(item);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error buscando en sesión ' + ms.Id + ': ' + e.getMessage());
            }
        }

        return results;
    }

    @AuraEnabled(cacheable=false)
    public static List<MessageWrapper> getConversationMessages(String sessionId) {
        if (String.isBlank(sessionId)) {
            throw new AuraHandledException('sessionId es requerido');
        }

        List<MessagingSession> sessionList = [
            SELECT Id, ConversationId
            FROM MessagingSession
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (sessionList.isEmpty() || sessionList[0].ConversationId == null) {
            throw new AuraHandledException('La sesión no tiene una conversación asociada');
        }

        if (!isSessionAuthorizedForCurrentUser(sessionId)) {
            throw new AuraHandledException('No tiene autorización para ver esta conversación');
        }

        Map<Id, String> uuidMap = getConversationUUIDs(new Set<Id>{ sessionList[0].ConversationId });
        String uuid = uuidMap.get(sessionList[0].ConversationId);
        if (String.isBlank(uuid)) {
            throw new AuraHandledException('No se encontró el ConversationIdentifier (UUID)');
        }

        return fetchConversationEntries(uuid);
    }

    @TestVisible
    private static Set<Id> authorizedSessionIdsOverride = null;

    // ─── Autorización basada en MessagingSession.Agente__c ─────────

    @TestVisible
    private static Set<Id> getMyAuthorizedSessionIds() {
        if (Test.isRunningTest() && authorizedSessionIdsOverride != null) {
            return authorizedSessionIdsOverride;
        }
        Set<Id> sessionIds = new Set<Id>();
        for (MessagingSession ms : [
            SELECT Id
            FROM MessagingSession
            WHERE Agente__c = :UserInfo.getUserId()
            AND ConversationId != null
            WITH USER_MODE
            ORDER BY StartTime DESC
            LIMIT :MAX_SESSION_ROWS
        ]) {
            sessionIds.add(ms.Id);
        }
        return sessionIds;
    }

    @TestVisible
    private static Boolean isSessionAuthorizedForCurrentUser(Id sessionId) {
        if (Test.isRunningTest() && authorizedSessionIdsOverride != null) {
            return authorizedSessionIdsOverride.contains(sessionId);
        }
        Integer cnt = [
            SELECT COUNT()
            FROM MessagingSession
            WHERE Id = :sessionId
            AND Agente__c = :UserInfo.getUserId()
            WITH USER_MODE
        ];
        return cnt > 0;
    }

    // ─── Lógica de API call ─────────────────────────────────

    @TestVisible
    private static List<MessageWrapper> fetchConversationEntries(String uuid) {
        List<MessageWrapper> allMessages = new List<MessageWrapper>();
        String pageToken = null;
        Integer pageCount = 0;

        do {
            HttpResponse response = makeApiCall(buildEndpoint(uuid, pageToken));
            if (response.getStatusCode() != 200) {
                throw new ConversationApiException('API Error ' + response.getStatusCode() + ': ' + response.getBody());
            }

            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> entries = (List<Object>) parsed.get('conversationEntries');

            if (entries != null) {
                for (Object entryObj : entries) {
                    MessageWrapper w = toWrapper((Map<String, Object>) entryObj);
                    if (w != null && String.isNotBlank(w.messageText)) {
                        allMessages.add(w);
                    }
                }
            }

            Boolean hasNext = parsed.get('hasNextPage') == true;
            pageToken = hasNext ? (String) parsed.get('nextPageToken') : null;
            pageCount++;
        } while (pageToken != null && pageCount < MAX_PAGES);

        allMessages.sort();
        return allMessages;
    }

    @TestVisible
    private static MessageWrapper toWrapper(Map<String, Object> entry) {
        MessageWrapper w = new MessageWrapper();
        w.messageId = (String) entry.get('identifier');

        if (entry.containsKey('messageText')) {
            w.messageText = (String) entry.get('messageText');
        }
        else if (entry.get('entryPayload') != null) {
            Map<String, Object> payload = (Map<String, Object>) entry.get('entryPayload');
            if (payload.containsKey('text')) {
                w.messageText = (String) payload.get('text');
            }
        }

        Map<String, Object> senderInfo = (Map<String, Object>) entry.get('sender');
        if (senderInfo == null) {
            senderInfo = (Map<String, Object>) entry.get('actor');
        }
        if (senderInfo != null) {
            w.senderRole = (String) senderInfo.get('role');
            w.senderName = (String) senderInfo.get('subject');
        }

        Object ts = entry.get('serverReceivedTimestamp');
        if (ts != null) {
            w.messageTimestamp = parseTimestamp(String.valueOf(ts));
        }

        return w;
    }

    @TestVisible
    private static Datetime parseTimestamp(String rawTs) {
        try {
            if (rawTs.isNumeric()) {
                return Datetime.newInstance(Long.valueOf(rawTs));
            }
            return (Datetime) JSON.deserialize('"' + rawTs + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    private static HttpResponse makeApiCall(String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setTimeout(30000);
        req.setEndpoint('callout:SF_Internal_API' + endpoint);
        req.setHeader('Content-Type', 'application/json');
        return new Http().send(req);
    }

    @TestVisible
    private static String buildEndpoint(String uuid, String pageToken) {
        String base = '/services/data/' + API_VERSION +
                      '/connect/conversation/' + uuid +
                      '/entries?pageSize=' + PAGE_SIZE;
        if (String.isNotBlank(pageToken)) {
            base += '&pageParam=' + EncodingUtil.urlEncode(pageToken, 'UTF-8');
        }
        return base;
    }

    @TestVisible
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
}