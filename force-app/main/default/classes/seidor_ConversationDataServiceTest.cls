@IsTest
private class seidor_ConversationDataServiceTest {

    // =========================================================================
    // Validaciones de entrada (sin SeeAllData)
    // =========================================================================

    @IsTest
    static void getMessagesByConversationId_conIdVacio_debeArrojarExcepcion() {
        Test.startTest();
        try {
            seidor_ConversationDataService.getMessagesByConversationId('', 'sess-001');
            System.assert(false, 'Debió lanzar excepción');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void getMessagesByConversationId_conSfIdSinConversation_debeArrojarExcepcion() {
        // ID con formato válido de Salesforce, pero sin registro Conversation real
        String sfId = '0dw000000000001AAA';

        Test.startTest();
        try {
            seidor_ConversationDataService.getMessagesByConversationId(sfId, 'sess-001');
            System.assert(false, 'Debió lanzar excepción por UUID no encontrado');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void getMessagesByUUID_conUuidVacio_debeArrojarExcepcion() {
        Test.startTest();
        try {
            seidor_ConversationDataService.getMessagesByUUID('', 'conv-001', 'sess-001');
            System.assert(false, 'Debió lanzar excepción');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // =========================================================================
    // getSessionsWithMessages — resultado vacío (sin SeeAllData)
    // =========================================================================

    @IsTest
    static void getSessionsWithMessages_conStatusFilter_retornaVacio() {
        Test.startTest();
        List<seidor_ConversationEntryDTO.SessionWithMessages> result =
            seidor_ConversationDataService.getSessionsWithMessages(10, 'Ended');
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Sin datos debe retornar lista vacía');
    }

    @IsTest
    static void getSessionsWithMessages_sinStatusFilter_retornaVacio() {
        Test.startTest();
        List<seidor_ConversationEntryDTO.SessionWithMessages> result =
            seidor_ConversationDataService.getSessionsWithMessages(5, null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Sin datos debe retornar lista vacía');
    }

    // =========================================================================
    // API callout exitoso — via getMessagesByUUID
    // =========================================================================

    @IsTest
    static void getMessagesByUUID_conDatos_parseaMensajesCorrectamente() {
        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(200,
            '{"conversationEntries":[' +
            '{"identifier":"msg-001","messageText":"Hola necesito ayuda",' +
            '"sender":{"role":"EndUser","appType":"live_message","subject":"56912345678"},' +
            '"clientTimestamp":1780537198801,"serverReceivedTimestamp":1780537199330,' +
            '"clientDuration":0,"relatedRecords":[]},' +
            '{"identifier":"msg-002","messageText":"Con gusto le ayudo",' +
            '"sender":{"role":"Chatbot","appType":"chatbot","subject":"0XxOx0000005gmb"},' +
            '"clientTimestamp":1780537204290,"serverReceivedTimestamp":1780537204367,' +
            '"clientDuration":0,"relatedRecords":[]}' +
            '],"hasNextPage":false}'
        ));

        Test.startTest();
        List<seidor_ConversationEntryDTO.MessageWrapper> messages =
            seidor_ConversationDataService.getMessagesByUUID(
                '1c7ede13-06f7-4d52-9217-215823fd22b5', '0dwOx00000DQT5JIAX', 'sess-001'
            );
        Test.stopTest();

        System.assertEquals(2, messages.size());
        System.assertEquals('EndUser', messages[0].senderRole);
        System.assertEquals('Chatbot', messages[1].senderRole);
        System.assertEquals('Hola necesito ayuda', messages[0].messageText);
        System.assertNotEquals(null, messages[0].messageTimestamp,
            'messageTimestamp debe calcularse desde serverReceivedTimestamp');
        System.assertEquals('56912345678', messages[0].senderName);
        System.assertEquals('0dwOx00000DQT5JIAX', messages[0].conversationId);
        System.assertEquals('sess-001', messages[0].sessionId);
    }

    // =========================================================================
    // API error (404)
    // =========================================================================

    @IsTest
    static void getMessagesByUUID_conErrorApi_lanzaConversationApiException() {
        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(404,
            '[{"errorCode":"NOT_FOUND","message":"The requested resource does not exist"}]'
        ));

        Test.startTest();
        try {
            seidor_ConversationDataService.getMessagesByUUID(
                'uuid-invalido', 'conv-001', 'sess-001'
            );
            System.assert(false, 'Debió lanzar excepción');
        } catch (seidor_ConversationDataService.ConversationApiException e) {
            System.assert(e.getMessage().contains('404'),
                'El mensaje debe contener el código de error 404');
        }
        Test.stopTest();
    }

    // =========================================================================
    // Paginación — hasNextPage=true
    // =========================================================================

    @IsTest
    static void getMessagesByUUID_conPaginacion_consolidaMultiplesPaginas() {
        Test.setMock(HttpCalloutMock.class, new ConversationApiMockPaginated());

        Test.startTest();
        List<seidor_ConversationEntryDTO.MessageWrapper> messages =
            seidor_ConversationDataService.getMessagesByUUID(
                'uuid-paginado', 'conv-pag-001', 'sess-pag-001'
            );
        Test.stopTest();

        // 2 mensajes en la primera página + 1 en la segunda = 3 total
        System.assertEquals(3, messages.size(),
            'Debe consolidar mensajes de todas las páginas');
        System.assertEquals('msg-pagina1-1', messages[0].messageId);
        System.assertEquals('msg-pagina2-1', messages[2].messageId);
    }

    // =========================================================================
    // Actor fallback — entry.sender null, usa entry.actor
    // =========================================================================

    @IsTest
    static void getMessagesByUUID_conSenderNulo_usaActor() {
        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(200,
            '{"conversationEntries":[' +
            '{"identifier":"msg-system","messageText":"Conversación iniciada",' +
            '"actor":{"role":"System","appType":"conversation","subject":"System"},' +
            '"serverReceivedTimestamp":1780537199330}' +
            '],"hasNextPage":false}'
        ));

        Test.startTest();
        List<seidor_ConversationEntryDTO.MessageWrapper> messages =
            seidor_ConversationDataService.getMessagesByUUID(
                'uuid-actor-test', 'conv-002', 'sess-002'
            );
        Test.stopTest();

        System.assertEquals(1, messages.size());
        System.assertEquals('System', messages[0].senderRole,
            'Debe usar el role del actor cuando sender es null');
        System.assertEquals('System', messages[0].senderName,
            'Debe usar el subject del actor');
    }

    // =========================================================================
    // Mensajes con texto vacío se omiten
    // =========================================================================

    @IsTest
    static void getMessagesByUUID_conMensajeSinTexto_omiteEntrada() {
        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(200,
            '{"conversationEntries":[' +
            '{"identifier":"msg-001","messageText":"Texto visible",' +
            '"sender":{"role":"EndUser","appType":"live_message","subject":"user1"},' +
            '"serverReceivedTimestamp":1780537199330},' +
            '{"identifier":"msg-002","messageText":"",' +
            '"sender":{"role":"Chatbot","appType":"chatbot","subject":"bot1"},' +
            '"serverReceivedTimestamp":1780537199331},' +
            '{"identifier":"msg-003","messageText":null,' +
            '"sender":{"role":"System","appType":"conversation","subject":"sys"},' +
            '"serverReceivedTimestamp":1780537199332},' +
            '{"identifier":"msg-004","messageText":"  ",' +
            '"sender":{"role":"Agent","appType":"live_agent","subject":"agent1"},' +
            '"serverReceivedTimestamp":1780537199333}' +
            '],"hasNextPage":false}'
        ));

        Test.startTest();
        List<seidor_ConversationEntryDTO.MessageWrapper> messages =
            seidor_ConversationDataService.getMessagesByUUID(
                'uuid-blank-test', 'conv-003', 'sess-003'
            );
        Test.stopTest();

        // Solo msg-001 tiene texto visible; msg-002 (""), msg-003 (null), msg-004 ("  ") se omiten
        System.assertEquals(1, messages.size(),
            'Solo los mensajes con texto no-blank deben incluirse');
        System.assertEquals('Texto visible', messages[0].messageText);
    }

    // =========================================================================
    // DTO wrappers
    // =========================================================================

    @IsTest
    static void dtoWrappers_setAndGet() {
        seidor_ConversationEntryDTO.MessageWrapper w = new seidor_ConversationEntryDTO.MessageWrapper();
        w.messageId        = 'test-id';
        w.messageText      = 'Quiero café';
        w.senderRole       = 'EndUser';
        w.senderName       = '56975521803';
        w.conversationId   = 'conv-001';
        w.sessionId        = 'sess-001';
        w.messageTimestamp = DateTime.now();
        w.rawTimestamp     = '1780537199330';

        System.assertEquals('EndUser', w.senderRole);
        System.assertEquals('Quiero café', w.messageText);
        System.assertEquals('56975521803', w.senderName);

        seidor_ConversationEntryDTO.SessionWithMessages sw =
            new seidor_ConversationEntryDTO.SessionWithMessages();
        sw.sessionId     = 'sess-001';
        sw.status        = 'Ended';
        sw.totalMessages = 3;
        sw.agentMessages = 1;
        sw.userMessages  = 1;
        sw.botMessages   = 1;
        sw.messages      = new List<seidor_ConversationEntryDTO.MessageWrapper>{ w };

        System.assertEquals(1, sw.messages.size());
        System.assertEquals(3, sw.totalMessages);
    }

    // =========================================================================
    // ConversationApiException
    // =========================================================================

    @IsTest
    static void conversationApiException_setAndGetMessage() {
        seidor_ConversationDataService.ConversationApiException ex =
            new seidor_ConversationDataService.ConversationApiException('Error de prueba');
        System.assert(ex.getMessage().contains('Error de prueba'));
    }

    // =========================================================================
    // Tests con SeeAllData — requieren datos reales en el org
    // =========================================================================

    @IsTest(SeeAllData=true)
    static void getSessionsWithMessages_conDatosYApiMock() {
        List<MessagingSession> sessions = [
            SELECT Id, ConversationId FROM MessagingSession
            WHERE ConversationId != null
            LIMIT 2
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con ConversationId en el org.');
            return;
        }

        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(200,
            '{"conversationEntries":[' +
            '{"identifier":"msg-r1","messageText":"Mensaje real 1",' +
            '"sender":{"role":"EndUser","appType":"live_message","subject":"56912345678"},' +
            '"serverReceivedTimestamp":1780537199330},' +
            '{"identifier":"msg-r2","messageText":"Mensaje real 2",' +
            '"sender":{"role":"Agent","appType":"live_agent","subject":"agent"},' +
            '"serverReceivedTimestamp":1780537199331}' +
            '],"hasNextPage":false}'
        ));

        Test.startTest();
        List<seidor_ConversationEntryDTO.SessionWithMessages> result =
            seidor_ConversationDataService.getSessionsWithMessages(10, null);
        Test.stopTest();

        System.assert(!result.isEmpty(), 'Debe retornar al menos 1 sesión');
        for (seidor_ConversationEntryDTO.SessionWithMessages sw : result) {
            System.assertNotEquals(null, sw.sessionId);
            System.assertNotEquals(null, sw.conversationId);
            System.assertNotEquals(null, sw.conversationUUID);
            System.assertNotEquals(null, sw.status);
            System.assertNotEquals(null, sw.messages, 'messages no debe ser null');
            // Debe haber al menos un mensaje y conteos
            System.assert(sw.totalMessages >= 0);
            System.assert(sw.agentMessages + sw.userMessages + sw.botMessages == sw.totalMessages
                || sw.totalMessages == 0,
                'La suma de roles debe coincidir con totalMessages');
        }
    }

    @IsTest(SeeAllData=true)
    static void getSessionsWithMessages_apiError_enCatch() {
        List<MessagingSession> sessions = [
            SELECT Id, ConversationId FROM MessagingSession
            WHERE ConversationId != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con ConversationId en el org.');
            return;
        }

        // Mock que retorna 500 para forzar el catch
        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(500,
            '{"error":"Internal Server Error"}'
        ));

        Test.startTest();
        List<seidor_ConversationEntryDTO.SessionWithMessages> result =
            seidor_ConversationDataService.getSessionsWithMessages(10, null);
        Test.stopTest();

        // Las sesiones deben existir pero con mensajes vacíos (catch block)
        System.assert(!result.isEmpty(),
            'Debe retornar sesiones incluso con error de API');
        for (seidor_ConversationEntryDTO.SessionWithMessages sw : result) {
            System.assertEquals(0, sw.totalMessages,
                'Con error de API, totalMessages debe ser 0');
            System.assertEquals(0, sw.messages.size(),
                'Con error de API, lista de mensajes debe estar vacía');
        }
    }

    @IsTest(SeeAllData=true)
    static void getMessagesByConversationId_conDatosYApiMock() {
        List<Conversation> conversations = [
            SELECT Id, ConversationIdentifier FROM Conversation
            WHERE ConversationIdentifier != null
            LIMIT 1
        ];
        if (conversations.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay Conversation en el org.');
            return;
        }

        Test.setMock(HttpCalloutMock.class, new ConversationApiMock(200,
            '{"conversationEntries":[' +
            '{"identifier":"msg-cid-1","messageText":"Mensaje por ConversationId",' +
            '"sender":{"role":"EndUser","appType":"live_message","subject":"user"},' +
            '"serverReceivedTimestamp":1780537199330}' +
            '],"hasNextPage":false}'
        ));

        Test.startTest();
        List<seidor_ConversationEntryDTO.MessageWrapper> messages =
            seidor_ConversationDataService.getMessagesByConversationId(
                conversations[0].Id, 'sess-cid-test'
            );
        Test.stopTest();

        System.assert(!messages.isEmpty(),
            'Debe retornar mensajes para una Conversation válida con mock');
        System.assertEquals('Mensaje por ConversationId', messages[0].messageText);
    }

    // =========================================================================
    // Mocks HTTP
    // =========================================================================

    private class ConversationApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        ConversationApiMock(Integer code, String body) {
            this.statusCode = code;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    private class ConversationApiMockPaginated implements HttpCalloutMock {
        private Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (callCount == 1) {
                // Primera página con nextPageToken
                res.setBody(
                    '{"conversationEntries":[' +
                    '{"identifier":"msg-pagina1-1","messageText":"Mensaje página 1",' +
                    '"sender":{"role":"EndUser","appType":"live_message","subject":"user1"},' +
                    '"serverReceivedTimestamp":1780537199330},' +
                    '{"identifier":"msg-pagina1-2","messageText":"Otro mensaje p1",' +
                    '"sender":{"role":"Agent","appType":"live_agent","subject":"agent1"},' +
                    '"serverReceivedTimestamp":1780537199331}' +
                    '],"hasNextPage":true,"nextPageToken":"token-pagina-2"}'
                );
            } else {
                // Segunda página sin más páginas
                res.setBody(
                    '{"conversationEntries":[' +
                    '{"identifier":"msg-pagina2-1","messageText":"Mensaje página 2",' +
                    '"sender":{"role":"Chatbot","appType":"chatbot","subject":"bot1"},' +
                    '"serverReceivedTimestamp":1780537199332}' +
                    '],"hasNextPage":false}'
                );
            }

            return res;
        }
    }
}