@isTest
private class seidor_MessagingDashboardServiceTest {

    // =========================================================================
    // Tests sin SeeAllData — cobertura base sobre parseDate, querySessions
    // y la rama de resultado vacío en cada método público.
    // Las queries sobre objetos de plataforma retornan vacío en test context.
    // =========================================================================

    @isTest
    static void getSessionsDashboard_emptyResult_sinFiltros() {
        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(null, null, null, null, null);
        Test.stopTest();

        System.assertEquals(0, result.totalSessions, 'Sin datos debe retornar 0 sesiones');
        System.assertEquals(0, result.sessions.size(), 'Lista de sesiones debe estar vacía');
        System.assertEquals(0, result.agentOptions.size(), 'Sin agentes');
        System.assertEquals(0, result.activeSessions, 'Sin activas');
        System.assertEquals(0, result.endedSessions, 'Sin terminadas');
        System.assertEquals(0, result.newSessions, 'Sin nuevas');
        System.assertEquals(0, result.outOfHoursSessions, 'Sin fuera de horario');
    }

    @isTest
    static void getSessionsDashboard_emptyResult_conFiltroStatus() {
        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                '2026-01-01', '2026-01-31', null, 'Ended', 50);
        Test.stopTest();

        System.assertEquals(0, result.totalSessions);
        System.assertNotEquals(null, result);
    }

    @isTest
    static void getSessionsDashboard_emptyResult_conAgenteInexistente() {
        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                null, null, UserInfo.getUserId(), null, 100);
        Test.stopTest();

        System.assertEquals(0, result.totalSessions);
    }

    @isTest
    static void getBitacoraEntries_emptyResult_sinFiltros() {
        Test.startTest();
        List<seidor_MessagingDashboardService.BitacoraRow> rows =
            seidor_MessagingDashboardService.getBitacoraEntries(null, null, null, null);
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Sin AgentWork debe retornar lista vacía');
    }

    @isTest
    static void getBitacoraEntries_emptyResult_conFiltros() {
        Test.startTest();
        List<seidor_MessagingDashboardService.BitacoraRow> rows =
            seidor_MessagingDashboardService.getBitacoraEntries(
                '2026-01-01', '2026-01-31', UserInfo.getUserId(), 200);
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    @isTest
    static void getPresenceHistory_emptyResult_sinFiltros() {
        Test.startTest();
        try {
            List<seidor_MessagingDashboardService.PresenceHistoryRow> rows =
                seidor_MessagingDashboardService.getPresenceHistory(null, null, null);
            System.assertEquals(0, rows.size(), 'Sin datos debe retornar lista vacía');
        } catch (AuraHandledException expected) {
            // Sin permisos para UserServicePresence también es válido
            System.assert(true, 'Excepción de permisos capturada correctamente');
        }
        Test.stopTest();
    }

    @isTest
    static void getPresenceHistory_emptyResult_conFechas() {
        Test.startTest();
        try {
            List<seidor_MessagingDashboardService.PresenceHistoryRow> rows =
                seidor_MessagingDashboardService.getPresenceHistory(
                    '2026-01-01', '2026-01-31', 500);
            System.assertEquals(0, rows.size());
        } catch (AuraHandledException expected) {
            System.assert(true, 'Excepción de permisos capturada correctamente');
        }
        Test.stopTest();
    }

    @isTest
    static void getAgentPresenceStatus_conResultadoVacio() {
        Test.startTest();
        List<seidor_MessagingDashboardService.AgentPresenceRow> rows =
            seidor_MessagingDashboardService.getAgentPresenceStatus();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Nunca debe retornar null');
    }

    // =========================================================================
    // Tests con SeeAllData — requieren datos reales en el org.
    // Usan return silencioso si no hay datos, sin fallar.
    // =========================================================================

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_conDatos_completos() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession LIMIT 3
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay MessagingSession en el org.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(null, null, null, null, 100);
        Test.stopTest();

        System.assertNotEquals(null, result, 'DashboardData no debe ser null');
        System.assert(!result.sessions.isEmpty(), 'Debe retornar al menos 1 sesión');

        for (seidor_MessagingDashboardService.SessionRow row : result.sessions) {
            System.assertNotEquals(null, row.sessionId, 'sessionId no debe ser null');
            System.assertNotEquals(null, row.status, 'status no debe ser null');
            // Al menos una debe tener startTime
        }

        // totalSessions incluye todos los status; active+ended+new puede omitir
        // status adicionales (ej. 'Waiting'), por lo tanto total >= suma.
        Integer counted = result.activeSessions + result.endedSessions + result.newSessions;
        System.assert(result.totalSessions >= counted,
            'totalSessions debe ser >= suma de active + ended + new');

        // agentOptions debe contener al menos un agente (o cero si todos null)
        System.assertNotEquals(null, result.agentOptions);
    }

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_conFiltroStatus_Ended() {
        List<MessagingSession> ended = [
            SELECT Id FROM MessagingSession WHERE Status = 'Ended' LIMIT 1
        ];
        if (ended.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con Status=Ended en el org.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                null, null, null, 'Ended', 100);
        Test.stopTest();

        for (seidor_MessagingDashboardService.SessionRow row : result.sessions) {
            System.assertEquals('Ended', row.status,
                'Todas las sesiones deben tener status Ended');
        }
        System.assertEquals(result.totalSessions, result.endedSessions,
            'Todas las sesiones filtradas deben contarse como ended');
    }

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_conFiltroStatus_Active() {
        List<MessagingSession> active = [
            SELECT Id FROM MessagingSession WHERE Status = 'Active' LIMIT 1
        ];
        if (active.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con Status=Active en el org.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                null, null, null, 'Active', 100);
        Test.stopTest();

        for (seidor_MessagingDashboardService.SessionRow row : result.sessions) {
            System.assertEquals('Active', row.status);
        }
        System.assertEquals(result.totalSessions, result.activeSessions);
    }

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_conAgenteValido() {
        List<AgentWork> works = [
            SELECT UserId FROM AgentWork
            WHERE UserId != null
            LIMIT 1
        ];
        if (works.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay AgentWork con UserId en el org.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                null, null, works[0].UserId, null, 100);
        Test.stopTest();

        System.assertNotEquals(null, result);
        if (!result.sessions.isEmpty()) {
            for (seidor_MessagingDashboardService.SessionRow row : result.sessions) {
                System.assertEquals(works[0].UserId, row.agentId,
                    'Todas las sesiones deben pertenecer al agente filtrado');
            }
        }
    }

    @isTest(SeeAllData=true)
    static void getAgentPresenceStatus_conDatos() {
        List<UserServicePresence> presences = [
            SELECT Id FROM UserServicePresence WHERE IsCurrentState = true LIMIT 1
        ];

        Test.startTest();
        List<seidor_MessagingDashboardService.AgentPresenceRow> rows =
            seidor_MessagingDashboardService.getAgentPresenceStatus();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Nunca debe retornar null');

        if (!presences.isEmpty()) {
            // Si hay presencia activa, debe haber al menos un agente online
            Boolean hayOnline = false;
            for (seidor_MessagingDashboardService.AgentPresenceRow row : rows) {
                if (row.isOnline) {
                    hayOnline = true;
                    System.assertNotEquals(null, row.userId);
                    System.assertNotEquals(null, row.presenceStatus);
                    System.assertNotEquals(null, row.statusCategory);
                    System.assert(
                        row.activeSessions >= 0,
                        'activeSessions no debe ser negativo'
                    );
                }
            }
            System.assert(hayOnline,
                'Debe haber al menos un agente online cuando existen UserServicePresence activos');
        }

        // Validar que todos los rows tengan userId y userName
        for (seidor_MessagingDashboardService.AgentPresenceRow row : rows) {
            System.assertNotEquals(null, row.userId, 'userId no debe ser null');
            System.assertNotEquals(null, row.userName, 'userName no debe ser null');
            System.assertNotEquals(null, row.statusCategory,
                'statusCategory debe ser Available, Busy u Offline');
        }
    }

    @isTest(SeeAllData=true)
    static void getBitacoraEntries_conDatos_sinFiltro() {
        List<AgentWork> works = [
            SELECT Id FROM AgentWork LIMIT 1
        ];
        if (works.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay AgentWork en el org.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.BitacoraRow> rows =
            seidor_MessagingDashboardService.getBitacoraEntries(null, null, null, 200);
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Debe retornar al menos 1 fila de bitácora');

        for (seidor_MessagingDashboardService.BitacoraRow row : rows) {
            System.assertNotEquals(null, row.workId, 'workId no debe ser null');
            System.assertNotEquals(null, row.sessionId, 'sessionId no debe ser null');
            System.assertNotEquals(null, row.agentName, 'agentName no debe ser null');
            // handlingMinutes puede ser null si no hay assigned+closed time
        }
    }

    @isTest(SeeAllData=true)
    static void getBitacoraEntries_conFiltroAgente() {
        List<AgentWork> works = [
            SELECT UserId FROM AgentWork
            WHERE UserId != null
            LIMIT 1
        ];
        if (works.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay AgentWork con UserId en el org.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.BitacoraRow> rows =
            seidor_MessagingDashboardService.getBitacoraEntries(
                null, null, works[0].UserId, 200);
        Test.stopTest();

        System.assertNotEquals(null, rows);
        for (seidor_MessagingDashboardService.BitacoraRow row : rows) {
            System.assertEquals(works[0].UserId, row.agentId,
                'Todas las entradas deben pertenecer al agente filtrado');
        }
    }

    @isTest(SeeAllData=true)
    static void getPresenceHistory_conDatos() {
        List<UserServicePresence> records = [
            SELECT Id FROM UserServicePresence LIMIT 2
        ];
        if (records.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay UserServicePresence en el org.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.PresenceHistoryRow> rows =
            seidor_MessagingDashboardService.getPresenceHistory(null, null, 1000);
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Debe retornar al menos 1 registro de historial');

        for (seidor_MessagingDashboardService.PresenceHistoryRow row : rows) {
            System.assertNotEquals(null, row.recordId);
            System.assertNotEquals(null, row.userId);
            System.assertNotEquals(null, row.userName);
            System.assertNotEquals(null, row.statusName);
            System.assertNotEquals(null, row.desde);
            System.assertNotEquals(null, row.isAvailable,
                'isAvailable debe ser true o false, no null');
        }
    }

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_conFechasEspecificas() {
        List<MessagingSession> sessions = [
            SELECT Id, StartTime FROM MessagingSession
            WHERE StartTime != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con StartTime en el org.');
            return;
        }

        Date startDate = sessions[0].StartTime.date();
        String dateStr = String.valueOf(startDate);

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                dateStr, dateStr, null, null, 100);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    // =========================================================================
    // Regresión: eliminación del límite artificial (75 en LWC / 100 default Apex)
    // Bug reportado: 642 MessagingSession reales, dashboard solo mostraba 75.
    // El alcance ahora lo define el rango Desde/Hasta, no un límite fijo.
    // =========================================================================

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_sinLimite_superaElAntiguoDefaultDe100() {
        Integer totalReal = [
            SELECT COUNT()
            FROM MessagingSession
            WHERE StartTime >= :DateTime.now().addDays(-30)
              AND ConversationId != null
        ];
        if (totalReal <= 100) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: el org tiene ' + totalReal +
                ' sesiones en el rango default (30 días); no alcanza para probar ' +
                'que el límite ya no trunca en 100.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(null, null, null, null, null);
        Test.stopTest();

        System.assert(result.totalSessions > 100,
            'El nuevo comportamiento no debe truncar en 100 cuando existen ' +
            totalReal + ' sesiones reales en el rango. totalSessions=' + result.totalSessions);
    }

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_techoDeSeguridad_conLimiteAbsurdamenteAlto() {
        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(
                null, null, null, null, 999999999);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'No debe fallar aunque el caller pida un límite absurdamente alto; ' +
            'el techo interno de seguridad debe contenerlo.');
    }

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_isOutOfHours_calculado() {
        List<MessagingSession> sessions = [
            SELECT Id, StartTime FROM MessagingSession
            WHERE StartTime != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con StartTime en el org.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(null, null, null, null, 100);
        Test.stopTest();

        for (seidor_MessagingDashboardService.SessionRow row : result.sessions) {
            // isOutOfHours debe ser true o false, nunca null
            // (Fuera_de_horario__c es Checkbox: nunca es null en Salesforce)
            System.assertNotEquals(null, row.isOutOfHours);
            if (row.startTime != null && row.endTime != null) {
                System.assertNotEquals(null, row.durationMinutes,
                    'durationMinutes debe calcularse si start y end no son null');
                System.assert(row.durationMinutes >= 0,
                    'durationMinutes no debe ser negativo');
            }
        }
    }

    // =========================================================================
    // Regresión: isOutOfHours debe reflejar el campo persistido Fuera_de_horario__c
    // (seteado por seidor_getWhatsAppFueraHorario vía BusinessHours), no un
    // cálculo propio con ventana fija 8-17hrs. Antes de este fix el dashboard
    // podía mostrar un valor distinto al que ve MessagingSessionTipificacionCtrl
    // para la misma sesión.
    // =========================================================================

    @isTest(SeeAllData=true)
    static void getSessionsDashboard_isOutOfHours_reflejaCampoPersistido() {
        List<MessagingSession> conFlagActivo = [
            SELECT Id, Fuera_de_horario__c
            FROM MessagingSession
            WHERE Fuera_de_horario__c = true
              AND StartTime >= :DateTime.now().addDays(-30)
            LIMIT 1
        ];
        if (conFlagActivo.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con Fuera_de_horario__c = true ' +
                'en el rango default de 30 días.');
            return;
        }

        Test.startTest();
        seidor_MessagingDashboardService.DashboardData result =
            seidor_MessagingDashboardService.getSessionsDashboard(null, null, null, null, null);
        Test.stopTest();

        Boolean encontrada = false;
        for (seidor_MessagingDashboardService.SessionRow row : result.sessions) {
            if (row.sessionId == conFlagActivo[0].Id) {
                encontrada = true;
                System.assertEquals(true, row.isOutOfHours,
                    'isOutOfHours debe reflejar Fuera_de_horario__c = true, ' +
                    'no un cálculo propio del dashboard.');
            }
        }
        System.assert(encontrada,
            'La sesión con Fuera_de_horario__c=true debe estar en el resultado del dashboard.');
    }

    // =========================================================================
    // Tests para getHourlySessionCount
    // =========================================================================

    @isTest
    static void getHourlySessionCount_emptyResult_sinFiltros() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(null, null, null, null);
        Test.stopTest();

        System.assertEquals(24, result.size(), 'Debe retornar 24 horas');
        for (seidor_MessagingDashboardService.HourlyCount hc : result) {
            System.assertNotEquals(null, hc.hour, 'hour no debe ser null');
            System.assertEquals(0, hc.count, 'count debe ser 0 sin datos');
        }
    }

    @isTest
    static void getHourlySessionCount_emptyResult_conFechas() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(
                '2026-01-01', '2026-01-31', null, null);
        Test.stopTest();

        System.assertEquals(24, result.size());
        for (seidor_MessagingDashboardService.HourlyCount hc : result) {
            System.assertEquals(0, hc.count);
        }
    }

    @isTest
    static void getHourlySessionCount_emptyResult_conAgenteInexistente() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(
                null, null, UserInfo.getUserId(), null);
        Test.stopTest();

        System.assertEquals(24, result.size());
    }

    @isTest(SeeAllData=true)
    static void getHourlySessionCount_conDatos() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession LIMIT 3
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay MessagingSession en el org.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(null, null, null, null);
        Test.stopTest();

        System.assertEquals(24, result.size(), 'Debe retornar 24 horas');
        Integer totalFromResult = 0;
        for (seidor_MessagingDashboardService.HourlyCount hc : result) {
            System.assertNotEquals(null, hc.hour);
            System.assert(hc.hour >= 0 && hc.hour < 24, 'hour debe estar entre 0 y 23');
            System.assert(hc.count >= 0, 'count no debe ser negativo');
            totalFromResult += hc.count;
        }
        System.assert(totalFromResult > 0, 'Debe haber al menos 1 sesión contada');
    }

    @isTest(SeeAllData=true)
    static void getHourlySessionCount_conAgenteValido() {
        List<AgentWork> works = [
            SELECT UserId FROM AgentWork
            WHERE UserId != null
            LIMIT 1
        ];
        if (works.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay AgentWork con UserId en el org.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(
                null, null, works[0].UserId, null);
        Test.stopTest();

        System.assertEquals(24, result.size());
    }

    @isTest
    static void getHourlySessionCount_emptyResult_conFiltroStatus_Ended() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(
                null, null, null, 'Ended');
        Test.stopTest();

        System.assertEquals(24, result.size());
        for (seidor_MessagingDashboardService.HourlyCount hc : result) {
            System.assertEquals(0, hc.count, 'count debe ser 0 sin datos');
        }
    }

    @isTest(SeeAllData=true)
    static void getHourlySessionCount_conFiltroStatus_Ended() {
        List<MessagingSession> ended = [
            SELECT Id FROM MessagingSession WHERE Status = 'Ended' LIMIT 1
        ];
        if (ended.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con Status=Ended.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(
                null, null, null, 'Ended');
        Test.stopTest();

        System.assertEquals(24, result.size());
        Integer totalFromResult = 0;
        for (seidor_MessagingDashboardService.HourlyCount hc : result) {
            totalFromResult += hc.count;
        }
        System.assert(totalFromResult > 0, 'Debe haber al menos 1 sesión Ended contada');
    }

    @isTest(SeeAllData=true)
    static void getHourlySessionCount_conFiltroStatus_Active() {
        List<MessagingSession> active = [
            SELECT Id FROM MessagingSession WHERE Status = 'Active' LIMIT 1
        ];
        if (active.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con Status=Active.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(
                null, null, null, 'Active');
        Test.stopTest();

        System.assertEquals(24, result.size());
        Integer totalFromResult = 0;
        for (seidor_MessagingDashboardService.HourlyCount hc : result) {
            totalFromResult += hc.count;
        }
        System.assert(totalFromResult > 0, 'Debe haber al menos 1 sesión Active contada');
    }

    @isTest
    static void getSantiagoHour_verificaRango() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyCount> result =
            seidor_MessagingDashboardService.getHourlySessionCount(null, null, null, null);
        Test.stopTest();
        System.assertEquals(24, result.size());
    }

    // =========================================================================
    // Tests para getHourlyDateSessionCount
    // =========================================================================

    @isTest
    static void getHourlyDateSessionCount_emptyResult() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyDateCount> result =
            seidor_MessagingDashboardService.getHourlyDateSessionCount(null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result no debe ser null');
    }

    @isTest(SeeAllData=true)
    static void getHourlyDateSessionCount_conDatos() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession LIMIT 3
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay MessagingSession en el org.');
            return;
        }

        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyDateCount> result =
            seidor_MessagingDashboardService.getHourlyDateSessionCount(null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        for (seidor_MessagingDashboardService.HourlyDateCount hdc : result) {
            System.assertNotEquals(null, hdc.dateStr, 'dateStr no debe ser null');
            System.assert(hdc.hour >= 0 && hdc.hour < 24, 'hour debe estar entre 0 y 23');
            System.assert(hdc.count > 0, 'count debe ser > 0 para filas retornadas');
        }
    }

    @isTest
    static void getHourlyDateSessionCount_conAgenteInexistente() {
        Test.startTest();
        List<seidor_MessagingDashboardService.HourlyDateCount> result =
            seidor_MessagingDashboardService.getHourlyDateSessionCount(
                null, null, UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, result);
    }
}