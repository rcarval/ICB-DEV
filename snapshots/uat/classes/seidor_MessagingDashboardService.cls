/**
 * @description Servicio de datos para el dashboard de mensajería
 * Provee: sesiones con filtros, presencia de ejecutivos, bitácora
 *
 * FUERA DE HORARIO: se lee directamente de MessagingSession.Fuera_de_horario__c
 *   (fuente única de verdad, calculada por seidor_getWhatsAppFueraHorario vía
 *   BusinessHours.isWithin() al momento de crear la sesión). No se recalcula
 *   aquí con una ventana fija para evitar que el dashboard y la tipificación
 *   puedan mostrar valores distintos para la misma sesión.
 * CSAT: Muy buena=5, Buena=4, Regular=3, Mala=2, Muy mala=1
 * FCR:  % de respuestas "Si" a "¿Tu solicitud fue resuelta?"
 */
public with sharing class seidor_MessagingDashboardService {

    // Techo de seguridad (no un límite de UX): protege el heap/gobernanza si alguien
    // pide un rango de fechas enorme. El alcance real de la búsqueda lo define
    // el filtro Desde/Hasta que el usuario elige en el LWC, no este número.
    private static final Integer MAX_SESSIONS_CEILING = 10000;

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    public class DashboardData {
        @AuraEnabled public List<SessionRow>  sessions;
        @AuraEnabled public List<AgentOption> agentOptions;
        @AuraEnabled public Integer totalSessions;
        @AuraEnabled public Integer outOfHoursSessions;
        @AuraEnabled public Integer activeSessions;
        @AuraEnabled public Integer endedSessions;
        @AuraEnabled public Integer newSessions;
    }

    public class SessionRow {
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   conversationId;
        @AuraEnabled public String   conversationUUID;
        @AuraEnabled public String   status;
        @AuraEnabled public DateTime startTime;
        @AuraEnabled public DateTime endTime;
        @AuraEnabled public Long     durationMinutes;
        @AuraEnabled public String   agentId;
        @AuraEnabled public String   agentName;
        @AuraEnabled public String   endUserId;
        @AuraEnabled public String   endUserPhone;
        @AuraEnabled public String   endUserName;
        @AuraEnabled public String   accountName;
        @AuraEnabled public Boolean  isOutOfHours;
        @AuraEnabled public String   channelId;
    }

    public class AgentPresenceRow {
        @AuraEnabled public String   userId;
        @AuraEnabled public String   userName;
        @AuraEnabled public String   presenceStatus;
        @AuraEnabled public String   statusCategory;  // Available | Busy | Offline
        @AuraEnabled public Boolean  isOnline;
        @AuraEnabled public Integer  activeSessions;
        @AuraEnabled public DateTime lastStatusChange;
    }

    public class PresenceHistoryRow {
        @AuraEnabled public String   recordId;
        @AuraEnabled public String   userId;
        @AuraEnabled public String   userName;
        @AuraEnabled public String   statusName;
        @AuraEnabled public Boolean  isAvailable;
        @AuraEnabled public DateTime desde;
        @AuraEnabled public DateTime hasta;
        @AuraEnabled public Long     durationMinutes;
    }

    public class BitacoraRow {
        @AuraEnabled public String   workId;
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   agentId;
        @AuraEnabled public String   agentName;
        @AuraEnabled public String   workStatus;      // Opened | Closed | Declined
        @AuraEnabled public DateTime assignedTime;
        @AuraEnabled public DateTime closedTime;
        @AuraEnabled public Long     handlingMinutes;
        @AuraEnabled public String   sessionStatus;
        @AuraEnabled public DateTime sessionStartTime;
        @AuraEnabled public String   endUserPhone;
        @AuraEnabled public String   endUserName;
        @AuraEnabled public String   accountName;
    }

    public class AgentOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class HourlyCount {
        @AuraEnabled public Integer hour;
        @AuraEnabled public Integer count;
    }

    public class HourlyDateCount {
        @AuraEnabled public String  dateStr;
        @AuraEnabled public Integer hour;
        @AuraEnabled public Integer count;
    }

    // ─── Métodos @AuraEnabled ──────────────────────────────────────────────────

    /**
     * Datos principales del dashboard de atención.
     * Incluye info de agente, fuera de horario y duración.
     *
     * @param dateFrom   YYYY-MM-DD o null
     * @param dateTo     YYYY-MM-DD o null
     * @param agentId    UserId del agente o null para todos
     * @param statusFilter 'Ended' | 'Active' | 'New' | null
     * @param limitSessions máximo de sesiones (default 100)
     */
    @AuraEnabled(cacheable=false)
    public static DashboardData getSessionsDashboard(
        String dateFrom, String dateTo, String agentId,
        String statusFilter, Integer limitSessions
    ) {
        Integer safeLimit = (limitSessions != null && limitSessions > 0)
            ? Math.min(limitSessions, MAX_SESSIONS_CEILING)
            : MAX_SESSIONS_CEILING;

        // 1. Obtener sesiones con filtros de fecha y estado
        List<MessagingSession> sessions = querySessions(dateFrom, dateTo, statusFilter, safeLimit);
        if (sessions.isEmpty()) {
            DashboardData empty = new DashboardData();
            empty.sessions        = new List<SessionRow>();
            empty.agentOptions    = new List<AgentOption>();
            empty.totalSessions   = 0;
            empty.outOfHoursSessions = 0;
            empty.activeSessions  = 0;
            empty.endedSessions   = 0;
            empty.newSessions     = 0;
            return empty;
        }

        // 2. Recopilar IDs necesarios
        Set<Id> sessionIds = new Set<Id>();
        Set<Id> convIds    = new Set<Id>();
        Set<Id> endUserIds = new Set<Id>();
        for (MessagingSession s : sessions) {
            sessionIds.add(s.Id);
            if (s.ConversationId != null) convIds.add(s.ConversationId);
            if (s.MessagingEndUserId != null) endUserIds.add(s.MessagingEndUserId);
        }

        // 3. Queries complementarias en paralelo
        Map<Id, AgentWork>       agentWorkMap = getAgentWorkBySession(sessionIds);
        Map<Id, String>          uuidMap      = getConversationUUIDs(convIds);
        Map<Id, EndUserInfo>     endUserMap   = getEndUserInfo(endUserIds);

        // 4. Construir resultado aplicando filtro de agente
        DashboardData result = new DashboardData();
        result.sessions        = new List<SessionRow>();
        result.totalSessions   = 0;
        result.outOfHoursSessions = 0;
        result.activeSessions  = 0;
        result.endedSessions   = 0;
        result.newSessions     = 0;

        Map<String, AgentOption> agentOptionsMap = new Map<String, AgentOption>();

        for (MessagingSession s : sessions) {
            AgentWork aw          = agentWorkMap.get(s.Id);
            String    sessionAgent = aw != null ? aw.UserId   : null;
            String    agentName    = aw != null ? aw.User.Name : 'Sin asignar';

            // Filtro por agente
            if (String.isNotBlank(agentId) && agentId != sessionAgent) continue;

            SessionRow row      = new SessionRow();
            row.sessionId       = s.Id;
            row.conversationId  = s.ConversationId;
            row.conversationUUID = uuidMap.get(s.ConversationId);
            row.status          = s.Status;
            row.startTime       = s.StartTime;
            row.endTime         = s.EndTime;
            row.agentId         = sessionAgent;
            row.agentName       = agentName;
            row.endUserId       = s.MessagingEndUserId;
            EndUserInfo eu      = endUserMap.get(s.MessagingEndUserId);
            row.endUserPhone    = eu != null ? eu.phone       : null;
            row.endUserName     = eu != null ? eu.name        : null;
            row.accountName     = eu != null ? eu.accountName : null;
            row.channelId       = s.MessagingChannelId;

            // Fuente única de verdad: el flag ya persistido por el Bot
            // (seidor_getWhatsAppFueraHorario, vía BusinessHours.isWithin()).
            row.isOutOfHours    = s.Fuera_de_horario__c == true;

            // Duración en minutos
            if (s.StartTime != null && s.EndTime != null) {
                row.durationMinutes = (s.EndTime.getTime() - s.StartTime.getTime()) / 60000;
            }

            result.sessions.add(row);
            result.totalSessions++;
            if (row.isOutOfHours) result.outOfHoursSessions++;
            if      (s.Status == 'Ended')  result.endedSessions++;
            else if (s.Status == 'New')    result.newSessions++;
            else if (s.Status == 'Active') result.activeSessions++;

            // Acumular opciones de agente para el filtro
            if (String.isNotBlank(sessionAgent) && !agentOptionsMap.containsKey(sessionAgent)) {
                AgentOption opt = new AgentOption();
                opt.value = sessionAgent;
                opt.label = agentName;
                agentOptionsMap.put(sessionAgent, opt);
            }
        }

        result.agentOptions = agentOptionsMap.values();
        return result;
    }

    /**
     * Cantidad de sesiones creadas agrupadas por hora (horario Santiago/Chile).
     * Reutiliza querySessions y filtra por agente vía AgentWork.
     *
     * @param dateFrom     YYYY-MM-DD o null
     * @param dateTo       YYYY-MM-DD o null
     * @param agentId      UserId del agente o null para todos
     * @param statusFilter 'Ended' | 'Active' | null para todos
     */
    @AuraEnabled(cacheable=false)
    public static List<HourlyCount> getHourlySessionCount(
        String dateFrom, String dateTo, String agentId, String statusFilter
    ) {
        Integer safeLimit = MAX_SESSIONS_CEILING;
        List<MessagingSession> sessions = querySessions(dateFrom, dateTo, statusFilter, safeLimit);

        // Inicializar mapa 0-23
        Map<Integer, Integer> hourMap = new Map<Integer, Integer>();
        for (Integer h = 0; h < 24; h++) {
            hourMap.put(h, 0);
        }

        if (sessions.isEmpty()) {
            List<HourlyCount> empty = new List<HourlyCount>();
            for (Integer h = 0; h < 24; h++) {
                HourlyCount hc = new HourlyCount();
                hc.hour = h;
                hc.count = 0;
                empty.add(hc);
            }
            return empty;
        }

        // Filtro por agente: obtener AgentWork si se especifica
        Map<Id, AgentWork> agentWorkMap = new Map<Id, AgentWork>();
        if (String.isNotBlank(agentId)) {
            Set<Id> sessionIds = new Set<Id>();
            for (MessagingSession s : sessions) {
                sessionIds.add(s.Id);
            }
            agentWorkMap = getAgentWorkBySession(sessionIds);
        }

        for (MessagingSession s : sessions) {
            if (String.isNotBlank(agentId)) {
                AgentWork aw = agentWorkMap.get(s.Id);
                String sessionAgent = aw != null ? aw.UserId : null;
                if (agentId != sessionAgent) continue;
            }

            if (s.StartTime == null) continue;

            // Convertir a hora de Santiago usando formato en locale es_CL
            // 'HH' = hora 24h en la timezone del servidor.
            // Como el servidor puede no estar en Chile, usamos el offset
            // estándar de Chile (-3/-4 hrs vs UTC) para calcular la hora local.
            Integer santiagoHour = getSantiagoHour(s.StartTime);
            hourMap.put(santiagoHour, hourMap.get(santiagoHour) + 1);
        }

        List<HourlyCount> result = new List<HourlyCount>();
        for (Integer h = 0; h < 24; h++) {
            HourlyCount hc = new HourlyCount();
            hc.hour = h;
            hc.count = hourMap.get(h);
            result.add(hc);
        }
        return result;
    }

    /**
     * Convierte un DateTime UTC a la hora equivalente en horario Santiago/Chile.
     * Chile usa UTC-4 (invierno) / UTC-3 (verano, ~primer sábado de septiembre
     * al primer sábado de abril). Para simplificar, usa UTC-4 como hora estándar
     * y UTC-3 cuando la hora UTC está entre 00:00-03:59 (overlap de DST).
     */
    private static Integer getSantiagoHour(DateTime dt) {
        Integer utcHour = dt.hourGmt();
        // Aproximación para Chile: UTC-4 (CLT) / UTC-3 (CLST)
        // CLST (verano): primer sábado de septiembre → primer sábado de abril
        Integer santiagoHour = utcHour - 4;
        if (santiagoHour < 0) santiagoHour += 24;

        // Ajuste aproximado para horario de verano (CLST = UTC-3)
        // Si el mes está entre Oct-Abr (aprox verano chileno) → restar 3 en vez de 4
        Integer month = dt.monthGmt();
        Boolean isSummerApprox = (month >= 10 || month <= 3);
        if (isSummerApprox) {
            santiagoHour = utcHour - 3;
            if (santiagoHour < 0) santiagoHour += 24;
        }

        return santiagoHour;
    }

    private static Date getSantiagoDate(DateTime dt) {
        Integer utcHour = dt.hourGmt();
        Integer offset = -4;
        Integer month  = dt.monthGmt();
        if (month >= 10 || month <= 3) {
            offset = -3;
        }
        Integer localHour = utcHour + offset;
        Date baseDate = dt.dateGmt();
        if (localHour < 0) {
            return baseDate.addDays(-1);
        } else if (localHour >= 24) {
            return baseDate.addDays(1);
        }
        return baseDate;
    }

    private static final List<String> DAY_NAMES =
        new List<String>{'Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'};

    @AuraEnabled(cacheable=false)
    public static List<HourlyDateCount> getHourlyDateSessionCount(
        String dateFrom, String dateTo, String agentId
    ) {
        Integer safeLimit = MAX_SESSIONS_CEILING;
        List<MessagingSession> sessions = querySessions(dateFrom, dateTo, null, safeLimit);

        Map<Id, AgentWork> agentWorkMap = new Map<Id, AgentWork>();
        if (String.isNotBlank(agentId)) {
            Set<Id> sessionIds = new Set<Id>();
            for (MessagingSession s : sessions) {
                sessionIds.add(s.Id);
            }
            agentWorkMap = getAgentWorkBySession(sessionIds);
        }

        // Key = 'YYYY-MM-DD|HH'
        Map<String, Integer> cellMap = new Map<String, Integer>();

        for (MessagingSession s : sessions) {
            if (String.isNotBlank(agentId)) {
                AgentWork aw = agentWorkMap.get(s.Id);
                String sessionAgent = aw != null ? aw.UserId : null;
                if (agentId != sessionAgent) continue;
            }
            if (s.StartTime == null) continue;

            Date santiagoDate = getSantiagoDate(s.StartTime);
            Integer santiagoHour = getSantiagoHour(s.StartTime);

            String key = String.valueOf(santiagoDate) + '|' + santiagoHour;
            cellMap.put(key, (cellMap.containsKey(key) ? cellMap.get(key) : 0) + 1);
        }

        // Fechas únicas ordenadas
        Set<Date> dateSet = new Set<Date>();
        for (MessagingSession s : sessions) {
            if (s.StartTime != null) {
                dateSet.add(getSantiagoDate(s.StartTime));
            }
        }
        List<Date> sortedDates = new List<Date>(dateSet);
        sortedDates.sort();

        List<HourlyDateCount> result = new List<HourlyDateCount>();
        for (Date d : sortedDates) {
            for (Integer h = 0; h < 24; h++) {
                String key = String.valueOf(d) + '|' + h;
                Integer cnt = cellMap.containsKey(key) ? cellMap.get(key) : 0;
                if (cnt > 0) {
                    DateTime dtVal = DateTime.newInstanceGMT(d, Time.newInstance(h, 0, 0, 0));
                    Integer isoDow = Integer.valueOf(dtVal.format('u'));
                    Integer dayIdx = isoDow == 7 ? 0 : isoDow;
                    HourlyDateCount hdc = new HourlyDateCount();
                    hdc.dateStr = DAY_NAMES[dayIdx] + ' ' +
                        String.valueOf(d.day()).leftPad(2, '0') + '/' +
                        String.valueOf(d.month()).leftPad(2, '0') + '/' +
                        String.valueOf(d.year());
                    hdc.hour  = h;
                    hdc.count = cnt;
                    result.add(hdc);
                }
            }
        }
        return result;
    }

    /**
     * Estado de presencia en tiempo real de los ejecutivos.
     * Requiere Omni-Channel habilitado.
     */
    @AuraEnabled(cacheable=false)
    public static List<AgentPresenceRow> getAgentPresenceStatus() {
        List<AgentPresenceRow> result = new List<AgentPresenceRow>();
        try {
            // Agentes actualmente conectados en Omni-Channel
            List<UserServicePresence> presences = [
                SELECT UserId, User.Name,
                       ServicePresenceStatus.MasterLabel,
                       CreatedDate
                FROM UserServicePresence
                WHERE IsCurrentState = true
                WITH USER_MODE
                ORDER BY User.Name ASC
                LIMIT 200
            ];

            Map<Id, Integer> activeSessionsMap = countActiveSessionsByAgent();
            Set<Id> onlineUserIds = new Set<Id>();

            for (UserServicePresence usp : presences) {
                AgentPresenceRow row = new AgentPresenceRow();
                row.userId           = usp.UserId;
                row.userName         = usp.User.Name;
                row.presenceStatus   = usp.ServicePresenceStatus.MasterLabel;
                row.statusCategory   = isAvailableStatus(usp.ServicePresenceStatus.MasterLabel)
                                       ? 'Available' : 'Busy';
                row.isOnline         = true;
                row.activeSessions   = activeSessionsMap.containsKey(usp.UserId)
                                       ? activeSessionsMap.get(usp.UserId) : 0;
                row.lastStatusChange = usp.CreatedDate;
                result.add(row);
                onlineUserIds.add(usp.UserId);
            }

            // Pool de agentes conocidos (últimos 30 días via AgentWork)
            // Agentes del pool que NO están conectados ahora → Offline
            Map<Id, String> knownAgents = new Map<Id, String>();
            for (AgentWork aw : [
                SELECT UserId, User.Name
                FROM AgentWork
                WHERE CreatedDate = LAST_N_DAYS:30
                WITH USER_MODE
                LIMIT 1000
            ]) {
                if (!knownAgents.containsKey(aw.UserId)) {
                    knownAgents.put(aw.UserId, aw.User.Name);
                }
            }

            for (Id uid : knownAgents.keySet()) {
                if (!onlineUserIds.contains(uid)) {
                    AgentPresenceRow row = new AgentPresenceRow();
                    row.userId         = uid;
                    row.userName       = knownAgents.get(uid);
                    row.presenceStatus = 'Offline';
                    row.statusCategory = 'Offline';
                    row.isOnline       = false;
                    row.activeSessions = 0;
                    result.add(row);
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Presence error: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Bitácora de asignaciones y cambios de estado via AgentWork.
     */
    @AuraEnabled(cacheable=false)
    public static List<BitacoraRow> getBitacoraEntries(
        String dateFrom, String dateTo, String agentId, Integer limitEntries
    ) {
        Integer safeLimit = limitEntries != null ? limitEntries : 200;
        DateTime dtFrom   = parseDate(dateFrom, false);
        DateTime dtTo     = parseDate(dateTo, true);

        List<AgentWork> works;
        try {
            if (String.isNotBlank(agentId)) {
                works = [
                    SELECT Id, WorkItemId, UserId, User.Name, Status,
                           CreatedDate, CloseDateTime
                    FROM AgentWork
                    WHERE CreatedDate >= :dtFrom
                      AND CreatedDate <= :dtTo
                      AND UserId = :agentId
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT :safeLimit
                ];
            } else {
                works = [
                    SELECT Id, WorkItemId, UserId, User.Name, Status,
                           CreatedDate, CloseDateTime
                    FROM AgentWork
                    WHERE CreatedDate >= :dtFrom
                      AND CreatedDate <= :dtTo
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT :safeLimit
                ];
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AgentWork error: ' + e.getMessage());
            return new List<BitacoraRow>();
        }

        if (works.isEmpty()) return new List<BitacoraRow>();

        Set<Id> sessionIds = new Set<Id>();
        for (AgentWork aw : works) sessionIds.add(aw.WorkItemId);

        Map<Id, MessagingSession> sessionMap;
        try {
            sessionMap = new Map<Id, MessagingSession>([
                SELECT Id, Status, StartTime, EndTime, MessagingEndUserId
                FROM MessagingSession
                WHERE Id IN :sessionIds
                WITH USER_MODE
            ]);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'MessagingSession error: ' + e.getMessage());
            return new List<BitacoraRow>();
        }

        Set<Id> endUserIds = new Set<Id>();
        for (MessagingSession s : sessionMap.values()) {
            if (s.MessagingEndUserId != null) endUserIds.add(s.MessagingEndUserId);
        }
        Map<Id, EndUserInfo> endUserMap = getEndUserInfo(endUserIds);

        List<BitacoraRow> result = new List<BitacoraRow>();
        for (AgentWork aw : works) {
            MessagingSession s = sessionMap.get(aw.WorkItemId);
            if (s == null) continue;

            BitacoraRow row      = new BitacoraRow();
            row.workId           = aw.Id;
            row.sessionId        = aw.WorkItemId;
            row.agentId          = aw.UserId;
            row.agentName        = aw.User.Name;
            row.workStatus       = aw.Status;
            row.assignedTime     = aw.CreatedDate;
            row.closedTime       = aw.CloseDateTime;
            row.sessionStatus    = s.Status;
            row.sessionStartTime = s.StartTime;
            EndUserInfo bitEu    = endUserMap.get(s.MessagingEndUserId);
            row.endUserPhone     = bitEu != null ? bitEu.phone       : null;
            row.endUserName      = bitEu != null ? bitEu.name        : null;
            row.accountName      = bitEu != null ? bitEu.accountName : null;

            if (aw.CreatedDate != null && aw.CloseDateTime != null) {
                row.handlingMinutes = (aw.CloseDateTime.getTime() - aw.CreatedDate.getTime()) / 60000;
            }

            result.add(row);
        }
        return result;
    }

    /**
     * Historial de estados de presencia de los ejecutivos.
     * Devuelve un registro por cada cambio de estado en el rango de fechas.
     * El campo "hasta" se calcula como el CreatedDate del siguiente registro del mismo usuario.
     */
    @AuraEnabled(cacheable=false)
    public static List<PresenceHistoryRow> getPresenceHistory(
        String dateFrom, String dateTo, Integer limitEntries
    ) {
        Integer safeLimit = limitEntries != null ? limitEntries : 1000;
        DateTime dtFrom   = parseDate(dateFrom, false);
        DateTime dtTo     = parseDate(dateTo, true);

        List<UserServicePresence> records;
        try {
            records = [
                SELECT Id, UserId, User.Name,
                       ServicePresenceStatus.MasterLabel, IsCurrentState,
                       CreatedDate
                FROM UserServicePresence
                WHERE CreatedDate >= :dtFrom
                  AND CreatedDate <= :dtTo
                WITH USER_MODE
                ORDER BY UserId, CreatedDate ASC
                LIMIT :safeLimit
            ];
        } catch (System.QueryException qe) {
            throw new AuraHandledException(
                'No tienes permisos para consultar el historial de presencia: ' + qe.getMessage()
            );
        }

        if (records.isEmpty()) return new List<PresenceHistoryRow>();

        // Agrupar por usuario (ya vienen ordenados por UserId, CreatedDate ASC)
        Map<Id, List<UserServicePresence>> byUser = new Map<Id, List<UserServicePresence>>();
        for (UserServicePresence usp : records) {
            if (!byUser.containsKey(usp.UserId)) {
                byUser.put(usp.UserId, new List<UserServicePresence>());
            }
            byUser.get(usp.UserId).add(usp);
        }

        List<PresenceHistoryRow> result = new List<PresenceHistoryRow>();
        for (Id uid : byUser.keySet()) {
            List<UserServicePresence> userRecs = byUser.get(uid);
            for (Integer i = 0; i < userRecs.size(); i++) {
                UserServicePresence usp = userRecs[i];
                PresenceHistoryRow row  = new PresenceHistoryRow();
                row.recordId       = usp.Id;
                row.userId         = usp.UserId;
                row.userName       = usp.User.Name;
                row.statusName     = usp.ServicePresenceStatus.MasterLabel;
                row.isAvailable    = isAvailableStatus(usp.ServicePresenceStatus.MasterLabel);
                row.desde          = usp.CreatedDate;
                if (i + 1 < userRecs.size()) {
                    row.hasta           = userRecs[i + 1].CreatedDate;
                    row.durationMinutes = (row.hasta.getTime() - row.desde.getTime()) / 60000;
                }
                // Último registro sin siguiente → hasta = null (activo o fuera del rango)
                result.add(row);
            }
        }
        return result;
    }

    // ─── Helpers privados ─────────────────────────────────────────────────────

    private static List<MessagingSession> querySessions(
        String dateFrom, String dateTo, String statusFilter, Integer lim
    ) {
        DateTime dtFrom = parseDate(dateFrom, false);
        DateTime dtTo   = parseDate(dateTo, true);

        try {
            if (String.isNotBlank(statusFilter)) {
                return [
                    SELECT Id, ConversationId, Status, StartTime, EndTime,
                           MessagingEndUserId, MessagingChannelId, Fuera_de_horario__c
                    FROM MessagingSession
                    WHERE StartTime >= :dtFrom
                      AND StartTime <= :dtTo
                      AND Status = :statusFilter
                      AND ConversationId != null
                    WITH USER_MODE
                    ORDER BY StartTime DESC
                    LIMIT :lim
                ];
            }
            return [
                SELECT Id, ConversationId, Status, StartTime, EndTime,
                       MessagingEndUserId, MessagingChannelId, Fuera_de_horario__c
                FROM MessagingSession
                WHERE StartTime >= :dtFrom
                  AND StartTime <= :dtTo
                  AND ConversationId != null
                WITH USER_MODE
                ORDER BY StartTime DESC
                LIMIT :lim
            ];
        } catch (System.QueryException qe) {
            throw new AuraHandledException(
                'No tienes permisos para consultar sesiones de mensajería: ' + qe.getMessage()
            );
        }
    }

    // Determina si un estado de presencia es "Disponible" basándose en su MasterLabel.
    // ServicePresenceStatus no expone IsAvailable como campo SOQL; se infiere del nombre.
    private static Boolean isAvailableStatus(String masterLabel) {
        if (String.isBlank(masterLabel)) return false;
        String lbl = masterLabel.toLowerCase();
        return lbl.contains('disponible') || lbl.contains('available');
    }

    private static Map<Id, AgentWork> getAgentWorkBySession(Set<Id> sessionIds) {
        Map<Id, AgentWork> result = new Map<Id, AgentWork>();
        try {
            List<AgentWork> works = [
                SELECT Id, WorkItemId, UserId, User.Name, Status, CreatedDate
                FROM AgentWork
                WHERE WorkItemId IN :sessionIds
                WITH USER_MODE
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
        try {
            for (Conversation c : [
                SELECT Id, ConversationIdentifier
                FROM Conversation
                WHERE Id IN :sfConvIds
                WITH USER_MODE
            ]) {
                result.put(c.Id, c.ConversationIdentifier);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Conversation query error: ' + e.getMessage());
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
        try {
            for (MessagingEndUser u : [
                SELECT Id, Name, MessagingPlatformKey,
                       ContactId, Contact.Name, Contact.Account.Name
                FROM MessagingEndUser
                WHERE Id IN :endUserIds
                WITH USER_MODE
            ]) {
                EndUserInfo info = new EndUserInfo();
                info.phone       = u.MessagingPlatformKey;
                info.name        = u.ContactId != null ? u.Contact.Name : u.Name;
                info.accountName = (u.ContactId != null && u.Contact.AccountId != null)
                                   ? u.Contact.Account.Name : null;
                result.put(u.Id, info);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'MessagingEndUser query error: ' + e.getMessage());
        }
        return result;
    }

    private static Map<Id, Integer> countActiveSessionsByAgent() {
        Map<Id, Integer> result = new Map<Id, Integer>();
        try {
            List<AggregateResult> agg = [
                SELECT UserId, COUNT(Id) cnt
                FROM AgentWork
                WHERE Status = 'Opened'
                WITH USER_MODE
                GROUP BY UserId
            ];
            for (AggregateResult ar : agg) {
                result.put((Id)ar.get('UserId'), (Integer)ar.get('cnt'));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'countActiveSessions error: ' + e.getMessage());
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
        } catch (Exception e) {
            return endOfDay ? DateTime.now()
                : DateTime.newInstance(Date.today().addDays(-30), Time.newInstance(0,0,0,0));
        }
    }
}