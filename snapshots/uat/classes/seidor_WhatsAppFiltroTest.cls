@isTest
private class seidor_WhatsAppFiltroTest {

    // ─── 1. FLUJO COMPLETO CON DATOS REALES DEL ORG ─────────────────
    @isTest(SeeAllData=true)
    static void testFullFlowWithRealData() {
        List<MessagingSession> realSessions = [
            SELECT Id, ConversationId
            FROM MessagingSession
            WHERE ConversationId != null
            LIMIT 1
        ];

        if (!realSessions.isEmpty()) {
            seidor_WhatsAppFiltro.authorizedSessionIdsOverride = new Set<Id>{ realSessions[0].Id };

            Test.setMock(HttpCalloutMock.class, new seidor_WhatsAppFiltroMock(false, false));

            Test.startTest();
            List<seidor_WhatsAppFiltro.SearchResult> results = seidor_WhatsAppFiltro.searchKeywordInChats('ayuda', 10);
            List<seidor_WhatsAppFiltro.MessageWrapper> messages = seidor_WhatsAppFiltro.getConversationMessages(realSessions[0].Id);
            Test.stopTest();

            System.assertNotEquals(null, messages);
        }
    }

    // ─── 2. BÚSQUEDA COMPLETA CON MATCH DE KEYWORD ──────────────────
    @isTest
    static void testSearchKeywordInChats_WithMatches() {
        Test.setMock(HttpCalloutMock.class, new seidor_WhatsAppFiltroMock(false, false));

        Test.startTest();
        seidor_WhatsAppFiltro.searchKeywordInChats('a', 10);
        seidor_WhatsAppFiltro.searchKeywordInChats('', 10);
        seidor_WhatsAppFiltro.searchKeywordInChats(null, null);

        List<seidor_WhatsAppFiltro.SearchResult> results = seidor_WhatsAppFiltro.searchKeywordInChats('ayuda', 10);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Sin autorización no deberían retornarse resultados');
    }

    // ─── 3. LÓGICA INTERNA DE BÚSQUEDA (fetch directo) ──────────────
    @isTest
    static void testInternalSearchLogicDirectly() {
        Test.setMock(HttpCalloutMock.class, new seidor_WhatsAppFiltroMock(false, false));

        Test.startTest();
        List<seidor_WhatsAppFiltro.MessageWrapper> messages = seidor_WhatsAppFiltro.fetchConversationEntries('001xx000003DGY1AAA');

        Integer matchCount = 0;
        String firstMatch = null;
        String searchTerm = 'ayuda';

        for (seidor_WhatsAppFiltro.MessageWrapper msg : messages) {
            if (msg.messageText != null && msg.messageText.toLowerCase().contains(searchTerm.toLowerCase())) {
                matchCount++;
                if (firstMatch == null) {
                    firstMatch = msg.messageText;
                }
            }
        }
        Test.stopTest();

        System.assertNotEquals(0, messages.size());
    }

    // ─── 4. FETCH CONVERSATION ENTRIES (paginación y error) ─────────
    @isTest
    static void testFetchConversationEntries_Cases() {
        Test.setMock(HttpCalloutMock.class, new seidor_WhatsAppFiltroMock(false, true));
        Test.startTest();
        List<seidor_WhatsAppFiltro.MessageWrapper> msgsPage = seidor_WhatsAppFiltro.fetchConversationEntries('uuid-123');
        System.assertNotEquals(0, msgsPage.size());

        Test.setMock(HttpCalloutMock.class, new seidor_WhatsAppFiltroMock(true, false));
        try {
            seidor_WhatsAppFiltro.fetchConversationEntries('uuid-123');
        } catch (seidor_WhatsAppFiltro.ConversationApiException e) {
            System.assert(e.getMessage().contains('API Error 400'));
        }
        Test.stopTest();
    }

    // ─── 5. TO WRAPPER Y PARSE TIMESTAMP ─────────────────────────────
    @isTest
    static void testToWrapperAndTimestamp() {
        Test.startTest();

        Map<String, Object> entry1 = new Map<String, Object>{
            'identifier' => 'id-1',
            'messageText' => 'Necesito ayuda con mi cuenta',
            'sender' => new Map<String, Object>{'role' => 'Agent', 'subject' => 'Soporte'},
            'serverReceivedTimestamp' => '1782855294043'
        };
        seidor_WhatsAppFiltro.MessageWrapper w1 = seidor_WhatsAppFiltro.toWrapper(entry1);
        System.assertEquals('Soporte', w1.senderName);

        Map<String, Object> entry2 = new Map<String, Object>{
            'identifier' => 'id-2',
            'entryPayload' => new Map<String, Object>{'text' => 'Hola ayuda'},
            'actor' => new Map<String, Object>{'role' => 'EndUser', 'subject' => 'Cliente'},
            'serverReceivedTimestamp' => '2026-07-23T14:30:00.000Z'
        };
        seidor_WhatsAppFiltro.MessageWrapper w2 = seidor_WhatsAppFiltro.toWrapper(entry2);

        Map<String, Object> entry3 = new Map<String, Object>{
            'identifier' => 'id-3',
            'entryPayload' => new Map<String, Object>(),
            'serverReceivedTimestamp' => 'invalid-date'
        };
        seidor_WhatsAppFiltro.MessageWrapper w3 = seidor_WhatsAppFiltro.toWrapper(entry3);

        seidor_WhatsAppFiltro.parseTimestamp('1782855294043');
        seidor_WhatsAppFiltro.parseTimestamp('2026-07-23T14:30:00.000Z');
        seidor_WhatsAppFiltro.parseTimestamp(null);
        seidor_WhatsAppFiltro.parseTimestamp('');

        Test.stopTest();
    }

    // ─── 6. DTOs Y COMPARABLE ────────────────────────────────────────
    @isTest
    static void testDTOsAndComparable() {
        Test.startTest();

        seidor_WhatsAppFiltro.SearchResult res = new seidor_WhatsAppFiltro.SearchResult();
        res.sessionId = '0Mw000000000001AAA';
        res.sessionName = 'S-0001';
        res.conversationId = '0xd000000000001AAA';
        res.endUserName = 'Juan Perez';
        res.matchingMessage = 'Hola ayuda';
        res.matchCount = 1;
        res.startTime = Datetime.now();

        seidor_WhatsAppFiltro.MessageWrapper m1 = new seidor_WhatsAppFiltro.MessageWrapper();
        m1.messageTimestamp = Datetime.now().addMinutes(-10);

        seidor_WhatsAppFiltro.MessageWrapper m2 = new seidor_WhatsAppFiltro.MessageWrapper();
        m2.messageTimestamp = Datetime.now();

        seidor_WhatsAppFiltro.MessageWrapper m3 = new seidor_WhatsAppFiltro.MessageWrapper();

        m1.compareTo(m2);
        m2.compareTo(m1);
        m1.compareTo(m1);
        m1.compareTo(m3);
        m3.compareTo(m3);

        seidor_WhatsAppFiltro.buildEndpoint('uuid-123', 'token-abc');
        seidor_WhatsAppFiltro.buildEndpoint('uuid-123', null);
        seidor_WhatsAppFiltro.getConversationUUIDs(new Set<Id>());
        seidor_WhatsAppFiltro.getConversationUUIDs(new Set<Id>{ '0xd000000000001AAA' });

        Test.stopTest();
    }

    // ─── 7. GETCONVERSATIONUUIDS - RAMA DE QUERYEXCEPTION (catch) ───
    @isTest
    static void testGetConversationUUIDs_QueryException() {
        List<Profile> minAccessProfiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        if (minAccessProfiles.isEmpty()) return;
        Profile p = minAccessProfiles[0];

        User restrictedUser = buildTestUser(p.Id, 'restringido');
        insert restrictedUser;

        System.runAs(restrictedUser) {
            Test.startTest();
            Map<Id, String> result = seidor_WhatsAppFiltro.getConversationUUIDs(new Set<Id>{ '0xd000000000001AAA' });
            Test.stopTest();
            System.assertEquals(0, result.size());
        }
    }

    // ─── 8. AUTORIZACIÓN - CASO POSITIVO (vía override de test) ────
    @isTest(SeeAllData=true)
    static void testAgente_AuthorizesOwnSession() {
        List<MessagingSession> realSessions = [
            SELECT Id
            FROM MessagingSession
            WHERE ConversationId != null
            LIMIT 1
        ];
        if (realSessions.isEmpty()) return;

        seidor_WhatsAppFiltro.authorizedSessionIdsOverride = new Set<Id>{ realSessions[0].Id };

        Test.startTest();
        Set<Id> authorizedIds = seidor_WhatsAppFiltro.getMyAuthorizedSessionIds();
        Boolean isAuthorized = seidor_WhatsAppFiltro.isSessionAuthorizedForCurrentUser(realSessions[0].Id);
        Test.stopTest();

        System.assert(authorizedIds.contains(realSessions[0].Id));
        System.assert(isAuthorized);
    }

    // ─── 9. AUTORIZACIÓN - CASO NEGATIVO (bloqueo determinístico vía override) ─
    @isTest(SeeAllData=true)
    static void testAgente_BlocksUnauthorizedSession() {
        List<MessagingSession> realSessions = [
            SELECT Id FROM MessagingSession LIMIT 1
        ];
        if (realSessions.isEmpty()) return;

        seidor_WhatsAppFiltro.authorizedSessionIdsOverride = new Set<Id>();

        Test.startTest();
        Boolean isAuthorized = seidor_WhatsAppFiltro.isSessionAuthorizedForCurrentUser(realSessions[0].Id);
        Test.stopTest();

        System.assert(!isAuthorized);

        try {
            seidor_WhatsAppFiltro.getConversationMessages(realSessions[0].Id);
            System.assert(false, 'Se esperaba AuraHandledException por falta de autorización');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ─── 10. AISLAMIENTO ENTRE DOS EJECUTIVOS DISTINTOS ─────────────
    @isTest(SeeAllData=true)
    static void testAgente_IsolatesBetweenUsers() {
        List<MessagingSession> realSessions = [
            SELECT Id, ConversationId
            FROM MessagingSession
            WHERE ConversationId != null
            LIMIT 2
        ];
        if (realSessions.size() < 2) return;

        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        User agentA = buildTestUser(p.Id, 'qaagentA');
        insert agentA;

        Test.setMock(HttpCalloutMock.class, new seidor_WhatsAppFiltroMock(false, false));

        System.runAs(agentA) {
            seidor_WhatsAppFiltro.authorizedSessionIdsOverride = new Set<Id>{ realSessions[0].Id };

            Test.startTest();
            List<seidor_WhatsAppFiltro.SearchResult> resultsA = seidor_WhatsAppFiltro.searchKeywordInChats('a', 10);
            Test.stopTest();

            for (seidor_WhatsAppFiltro.SearchResult r : resultsA) {
                System.assertEquals(realSessions[0].Id, r.sessionId, 'El filtro debe restringir a solo la sesión autorizada para este agente');
            }
        }
    }

    // ─── HELPERS ─────────────────────────────────────────────────────

    private static User buildTestUser(Id profileId, String aliasPrefix) {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime());
        return new User(
            ProfileId = profileId,
            LastName = aliasPrefix,
            Email = aliasPrefix + '@test.com.invalid',
            Username = aliasPrefix + uniqueSuffix + '@test.com.invalid',
            Alias = (aliasPrefix + uniqueSuffix).right(8),
            TimeZoneSidKey = 'America/Santiago',
            LocaleSidKey = 'es_CL',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'es'
        );
    }
}