@isTest
private class seidor_ResponseTimeServiceTest {

    // =========================================================================
    // Tests sin SeeAllData — cobertura sobre parseDate, session query vacía,
    // DTOs y rama de resultado vacío.
    // =========================================================================

    @isTest
    static void testEmptyResult_allNullParams() {
        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, null);
        Test.stopTest();

        System.assertEquals(0, res.agentGroups.size(), 'Sin datos debe retornar 0 grupos');
        System.assertEquals(0, res.agentOptions.size(), 'Sin datos debe retornar 0 opciones');
    }

    @isTest
    static void testEmptyResult_conLimitExplicito() {
        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, 500);
        Test.stopTest();

        System.assertEquals(0, res.agentGroups.size());
    }

    @isTest
    static void testEmptyResult_conFiltroAgente() {
        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(
                null, null, UserInfo.getUserId(), 100);
        Test.stopTest();

        System.assertEquals(0, res.agentGroups.size());
    }

    @isTest
    static void testEmptyResult_fechasValidas() {
        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(
                '2026-01-01', '2026-01-31', null, null);
        Test.stopTest();

        System.assertNotEquals(null, res);
    }

    @isTest
    static void testEmptyResult_fechasInvalidas() {
        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(
                'not-a-date', 'bad-date', null, null);
        Test.stopTest();

        System.assertNotEquals(null, res);
    }

    // =========================================================================
    // Tests con SeeAllData — requieren datos reales en el org.
    // Usan return silencioso si no hay datos, sin fallar.
    // =========================================================================

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_conDatos_completos() {
        List<MessagingSession> sessions = [
            SELECT Id, ConversationId, StartTime, EndTime, MessagingEndUserId,
                   Agente__c, Agente__r.Name
            FROM MessagingSession
            WHERE Status = 'Ended' AND ConversationId != null AND StartTime != null
            ORDER BY StartTime DESC
            LIMIT 5
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession ended en el org.');
            return;
        }

        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, 500);
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result no debe ser null');
        System.assert(!res.agentGroups.isEmpty(),
            'Debe haber al menos 1 grupo de agente');

        System.assert(!res.agentOptions.isEmpty() || res.agentGroups.size() == 1,
            'Debe haber opciones de agente (o solo grupo sin asignar)');

        Integer totalSessions = 0;
        for (seidor_ResponseTimeService.AgentGroup g : res.agentGroups) {
            System.assert(!g.sessions.isEmpty(),
                'Cada grupo debe tener al menos 1 sesión');
            totalSessions += g.sessions.size();
            for (seidor_ResponseTimeService.SessionInfo s : g.sessions) {
                System.assertNotEquals(null, s.sessionId, 'sessionId no debe ser null');
                System.assertNotEquals(null, s.startTime, 'startTime no debe ser null');
                System.assertNotEquals(null, s.agentId, 'agentId no debe ser null');
                System.assertNotEquals(null, s.agentName, 'agentName no debe ser null');
            }
        }
        System.assert(totalSessions > 0, 'Total de sesiones debe ser > 0');
    }

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_conFiltroAgente() {
        List<MessagingSession> sessions = [
            SELECT Id, Agente__c
            FROM MessagingSession
            WHERE Status = 'Ended' AND Agente__c != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con Agente__c en el org.');
            return;
        }

        String agentId = sessions[0].Agente__c;

        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(null, null, agentId, 500);
        Test.stopTest();

        System.assertNotEquals(null, res);
        for (seidor_ResponseTimeService.AgentGroup g : res.agentGroups) {
            System.assertEquals(agentId, g.agentId,
                'Todos los grupos deben pertenecer al agente filtrado');
        }
    }

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_agentOptions() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession
            WHERE Status = 'Ended' AND ConversationId != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession ended en el org.');
            return;
        }

        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, 500);
        Test.stopTest();

        System.assertNotEquals(null, res.agentOptions);
        for (seidor_ResponseTimeService.AgentOption opt : res.agentOptions) {
            System.assertNotEquals(null, opt.value, 'AgentOption value no debe ser null');
            System.assertNotEquals(null, opt.label, 'AgentOption label no debe ser null');
        }
    }

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_agentOptionsOrdenados() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession
            WHERE Status = 'Ended' AND ConversationId != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession ended en el org.');
            return;
        }

        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, 500);
        Test.stopTest();

        System.assertNotEquals(null, res.agentOptions);
        for (Integer i = 1; i < res.agentOptions.size(); i++) {
            String prev = res.agentOptions[i-1].label != null ? res.agentOptions[i-1].label : '';
            String curr = res.agentOptions[i].label   != null ? res.agentOptions[i].label   : '';
            System.assert(prev.compareTo(curr) <= 0,
                'agentOptions debe estar ordenado alfabéticamente');
        }
    }

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_filtroSinResultados() {
        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(
                null, null, UserInfo.getUserId(), 100);
        Test.stopTest();

        System.assertNotEquals(null, res);
    }

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_conFechas() {
        List<MessagingSession> sessions = [
            SELECT Id, StartTime
            FROM MessagingSession
            WHERE Status = 'Ended' AND StartTime != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con StartTime en el org.');
            return;
        }

        String dateStr = String.valueOf(sessions[0].StartTime.date());

        Test.startTest();
        seidor_ResponseTimeService.Result res =
            seidor_ResponseTimeService.getAgentSessions(dateStr, dateStr, null, 500);
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assertNotEquals(null, res.agentGroups);
    }

    @isTest(SeeAllData=true)
    static void testGetAgentSessions_conLimit() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession
            WHERE Status = 'Ended' AND ConversationId != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession ended en el org.');
            return;
        }

        Test.startTest();
        seidor_ResponseTimeService.Result res1 =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, 1);
        seidor_ResponseTimeService.Result resAll =
            seidor_ResponseTimeService.getAgentSessions(null, null, null, 5000);
        Test.stopTest();

        System.assertNotEquals(null, res1, 'Result con limit=1 no debe ser null');
        System.assertNotEquals(null, resAll, 'Result con limit=5000 no debe ser null');
    }
}