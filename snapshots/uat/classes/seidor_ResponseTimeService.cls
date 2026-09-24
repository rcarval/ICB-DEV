/**
 * @description Servicio de datos para el dashboard de tiempos de respuesta por ejecutivo.
 * Consulta sesiones de mensajería finalizadas, obtiene el AgentWork más reciente por sesión,
 * los UUIDs de conversación y los teléfonos de usuario final, y agrupa por agente.
 */
public with sharing class seidor_ResponseTimeService {

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    public class SessionInfo {
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   conversationId;
        @AuraEnabled public String   conversationUUID;
        @AuraEnabled public String   agentId;
        @AuraEnabled public String   agentName;
        @AuraEnabled public String   endUserPhone;
        @AuraEnabled public String   endUserName;
        @AuraEnabled public String   accountName;
        @AuraEnabled public DateTime startTime;
        @AuraEnabled public DateTime endTime;
        @AuraEnabled public Long     durationMinutes;
    }

    public class AgentGroup {
        @AuraEnabled public String          agentId;
        @AuraEnabled public String          agentName;
        @AuraEnabled public List<SessionInfo> sessions;
    }

    public class AgentOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class Result {
        @AuraEnabled public List<AgentGroup>  agentGroups;
        @AuraEnabled public List<AgentOption> agentOptions;
    }

    // ─── Método @AuraEnabled ───────────────────────────────────────────────────

    /**
     * Obtiene sesiones de mensajería finalizadas agrupadas por ejecutivo.
     *
     * @param dateFrom      YYYY-MM-DD o null (default: hoy - 7 días)
     * @param dateTo        YYYY-MM-DD o null (default: hoy)
     * @param agentId       UserId del agente o null para todos
     * @param limitSessions máximo de sesiones (default 200)
     */
    @AuraEnabled(cacheable=false)
    public static Result getAgentSessions(
        String dateFrom, String dateTo, String agentId, Integer limitSessions
    ) {
        Integer safeLimit = limitSessions != null ? limitSessions : 200;
        DateTime dtFrom   = parseDate(dateFrom, false);
        DateTime dtTo     = parseDate(dateTo,   true);

        // 1. Sesiones finalizadas en el rango de fechas
        List<MessagingSession> sessions = [
            SELECT Id, ConversationId, StartTime, EndTime, MessagingEndUserId,
                   Agente__c, Agente__r.Name
            FROM MessagingSession
            WHERE Status = 'Ended'
              AND ConversationId != null
              AND StartTime >= :dtFrom
              AND StartTime <= :dtTo
            ORDER BY StartTime DESC
            LIMIT :safeLimit
        ];

        Result emptyResult = new Result();
        emptyResult.agentGroups  = new List<AgentGroup>();
        emptyResult.agentOptions = new List<AgentOption>();
        if (sessions.isEmpty()) return emptyResult;

        // 2. Recopilar IDs necesarios
        Set<Id> sessionIds = new Set<Id>();
        Set<Id> convIds    = new Set<Id>();
        Set<Id> endUserIds = new Set<Id>();
        for (MessagingSession s : sessions) {
            sessionIds.add(s.Id);
            if (s.ConversationId    != null) convIds.add(s.ConversationId);
            if (s.MessagingEndUserId != null) endUserIds.add(s.MessagingEndUserId);
        }

        // 3. Queries complementarias
        Map<Id, AgentWork>   agentWorkMap = getAgentWorkBySession(sessionIds);
        Map<Id, String>      uuidMap      = getConversationUUIDs(convIds);
        Map<Id, EndUserInfo> endUserMap   = getEndUserInfo(endUserIds);

        // 4. Agrupar por agente
        Map<String, AgentGroup>  groupMap       = new Map<String, AgentGroup>();
        Map<String, AgentOption> agentOptionsMap = new Map<String, AgentOption>();

        for (MessagingSession s : sessions) {
            AgentWork aw = agentWorkMap.get(s.Id);
            // Preferir Agente__c (escrito al tipificar) sobre AgentWork
            String sessionAgent = s.Agente__c != null
                ? s.Agente__c
                : (aw != null ? aw.UserId : null);
            String agentNm = s.Agente__c != null
                ? (s.Agente__r != null ? s.Agente__r.Name : 'Sin asignar')
                : (aw != null ? aw.User.Name : 'Sin asignar');

            // Filtro por agente si se especificó
            if (String.isNotBlank(agentId) && agentId != sessionAgent) continue;

            SessionInfo info          = new SessionInfo();
            info.sessionId            = s.Id;
            info.conversationId       = s.ConversationId;
            info.conversationUUID     = uuidMap.get(s.ConversationId);
            info.agentId              = sessionAgent;
            info.agentName            = agentNm;
            EndUserInfo eu            = endUserMap.get(s.MessagingEndUserId);
            info.endUserPhone         = eu != null ? eu.phone       : null;
            info.endUserName          = eu != null ? eu.name        : null;
            info.accountName          = eu != null ? eu.accountName : null;
            info.startTime            = s.StartTime;
            info.endTime              = s.EndTime;
            if (s.StartTime != null && s.EndTime != null) {
                info.durationMinutes = (s.EndTime.getTime() - s.StartTime.getTime()) / 60000;
            }

            // Clave de agrupación: agentId o '__sin_asignar__' para sin asignar
            String groupKey = String.isNotBlank(sessionAgent) ? sessionAgent : '__sin_asignar__';

            if (!groupMap.containsKey(groupKey)) {
                AgentGroup grp = new AgentGroup();
                grp.agentId   = sessionAgent;
                grp.agentName = agentNm;
                grp.sessions  = new List<SessionInfo>();
                groupMap.put(groupKey, grp);
            }
            groupMap.get(groupKey).sessions.add(info);

            // Acumular opciones de agente
            if (String.isNotBlank(sessionAgent) && !agentOptionsMap.containsKey(sessionAgent)) {
                AgentOption opt = new AgentOption();
                opt.value = sessionAgent;
                opt.label = agentNm;
                agentOptionsMap.put(sessionAgent, opt);
            }
        }

        // 5. Ordenar grupos por nombre de agente
        List<AgentGroup> groups = groupMap.values();
        groups.sort(new AgentGroupComparator());

        Result res      = new Result();
        res.agentGroups  = groups;
        List<AgentOption> options = agentOptionsMap.values();
        options.sort(new AgentOptionComparator());
        res.agentOptions = options;
        return res;
    }

    // ─── Comparador para ordenar grupos ───────────────────────────────────────

    private class AgentGroupComparator implements Comparator<AgentGroup> {
        public Integer compare(AgentGroup a, AgentGroup b) {
            String na = a.agentName != null ? a.agentName : '';
            String nb = b.agentName != null ? b.agentName : '';
            return na.compareTo(nb);
        }
    }

    private class AgentOptionComparator implements Comparator<AgentOption> {
        public Integer compare(AgentOption a, AgentOption b) {
            String la = a.label != null ? a.label : '';
            String lb = b.label != null ? b.label : '';
            return la.compareTo(lb);
        }
    }

    // ─── Helpers privados ─────────────────────────────────────────────────────

    private static Map<Id, AgentWork> getAgentWorkBySession(Set<Id> sessionIds) {
        Map<Id, AgentWork> result = new Map<Id, AgentWork>();
        try {
            List<AgentWork> works = [
                SELECT Id, WorkItemId, UserId, User.Name, Status, CreatedDate
                FROM AgentWork
                WHERE WorkItemId IN :sessionIds
                ORDER BY CreatedDate DESC
            ];
            // Tomar el AgentWork más reciente por sesión
            for (AgentWork aw : works) {
                if (!result.containsKey(aw.WorkItemId)) {
                    result.put(aw.WorkItemId, aw);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AgentWork query error: ' + e.getMessage());
        }
        return result;
    }

    private static Map<Id, String> getConversationUUIDs(Set<Id> sfConvIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (sfConvIds.isEmpty()) return result;
        for (Conversation c : [
            SELECT Id, ConversationIdentifier
            FROM Conversation
            WHERE Id IN :sfConvIds
        ]) {
            result.put(c.Id, c.ConversationIdentifier);
        }
        return result;
    }

    private class EndUserInfo {
        public String phone;
        public String name;
        public String accountName;
    }

    private static Map<Id, EndUserInfo> getEndUserInfo(Set<Id> endUserIds) {
        Map<Id, EndUserInfo> result = new Map<Id, EndUserInfo>();
        if (endUserIds.isEmpty()) return result;
        for (MessagingEndUser u : [
            SELECT Id, Name, MessagingPlatformKey,
                   ContactId, Contact.Name, Contact.Account.Name
            FROM MessagingEndUser WHERE Id IN :endUserIds
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

    /**
     * Convierte una cadena YYYY-MM-DD a DateTime.
     * Si el valor es nulo o inválido usa el default:
     *   - dateFrom default → hoy - 7 días al inicio del día
     *   - dateTo   default → ahora
     */
    private static DateTime parseDate(String dateStr, Boolean endOfDay) {
        if (String.isBlank(dateStr)) {
            return endOfDay
                ? DateTime.now()
                : DateTime.newInstance(Date.today().addDays(-7), Time.newInstance(0, 0, 0, 0));
        }
        try {
            Date d = Date.valueOf(dateStr);
            return endOfDay
                ? DateTime.newInstance(d, Time.newInstance(23, 59, 59, 0))
                : DateTime.newInstance(d, Time.newInstance(0,  0,  0,  0));
        } catch (Exception e) {
            return endOfDay
                ? DateTime.now()
                : DateTime.newInstance(Date.today().addDays(-7), Time.newInstance(0, 0, 0, 0));
        }
    }
}