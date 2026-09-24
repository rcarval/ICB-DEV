@isTest
private class seidor_EncuestaSyncBatchTest {

    // ── Mock HTTP para seidor_ConversationDataService ─────────────────────────

    private class MockConversationApi implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"conversationEntries":[],"hasNextPage":false}');
            return res;
        }
    }

    // Los tests de normalización (normalizeFcr/normalizeCsat/extractCsatScore)
    // se movieron a seidor_EncuestaQAMatcherTest — esa lógica ahora vive en
    // seidor_EncuestaQAMatcher, compartida con seidor_CrearEncuestaWhatsApp.

    // ── Test ejecución del batch ──────────────────────────────────────────────

    @isTest
    static void testBatchExecution() {
        Test.setMock(HttpCalloutMock.class, new MockConversationApi());
        Test.startTest();
        seidor_EncuestaSyncBatch batch = new seidor_EncuestaSyncBatch(30);
        Database.executeBatch(batch, 10);
        Test.stopTest();
        // Sin sesiones en el org de test — verifica que el batch termina sin error
        System.assertEquals(0, [SELECT COUNT() FROM Encuesta_cliente__c]);
    }

    // El test anterior corre con el org de test vacío (sin SeeAllData), por lo que
    // start() nunca retorna sesiones y el cuerpo real de execute(bc, scope) —resolución
    // de UUID, llamada a la API, matching Q&A e insert— nunca se ejecuta (de ahí la
    // cobertura baja de esta clase). Para cubrirlo se usa una MessagingSession real del
    // org (con su Conversation real, necesaria para resolver el ConversationIdentifier)
    // y se llama execute() directamente, sin pasar por start(), para no depender de si
    // ya existen encuestas para otras sesiones. Cualquier Encuesta_cliente__c
    // preexistente para la sesión elegida se borra dentro de la transacción del test
    // (se revierte al finalizar, como toda la data de test).
    @isTest(SeeAllData=true)
    static void testBatchExecution_conSesionRealYMockDeApi_procesaYCreaEncuesta() {
        List<MessagingSession> sessions = [
            SELECT Id, Name, ConversationId, StartTime, EndTime, MessagingEndUserId,
                   Agente__c, Cliente__c, Contacto__c, Fuera_de_horario__c
            FROM MessagingSession
            WHERE ConversationId != null
              AND Fuera_de_horario__c = false
            LIMIT 20
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con ConversationId en el org.');
            return;
        }

        MessagingSession target;
        for (MessagingSession s : sessions) {
            List<Conversation> conv = [
                SELECT Id, ConversationIdentifier
                FROM Conversation
                WHERE Id = :s.ConversationId AND ConversationIdentifier != null
                LIMIT 1
            ];
            if (!conv.isEmpty()) { target = s; break; }
        }
        if (target == null) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: ninguna sesión encontrada tiene Conversation con ConversationIdentifier.');
            return;
        }

        // El batch excluye por ConversationId completo, no solo por Sesi_n_de_Mensajer_a__c:
        // si OTRA MessagingSession que comparte el mismo ConversationId (p.ej. la sesión del
        // bot vs. la del agente humano) ya tiene encuesta, sessionByConvId descarta la
        // conversación entera y el batch retorna antes de llamar a la API. Por eso hay que
        // limpiar las encuestas de TODAS las sesiones hermanas de este ConversationId, no
        // solo la de target.Id.
        Set<Id> siblingSessionIds = new Set<Id>();
        for (MessagingSession sib : [
            SELECT Id FROM MessagingSession WHERE ConversationId = :target.ConversationId
        ]) {
            siblingSessionIds.add(sib.Id);
        }
        delete [
            SELECT Id FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__c IN :siblingSessionIds
        ];

        Test.setMock(HttpCalloutMock.class, new MockConversationApiConSurvey());

        Test.startTest();
        seidor_EncuestaSyncBatch batch = new seidor_EncuestaSyncBatch(365 * 5);
        batch.execute(null, new List<MessagingSession>{ target });
        Test.stopTest();

        List<Encuesta_cliente__c> creadas = [
            SELECT Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c, CSAT_Puntaje__c
            FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__c = :target.Id
        ];
        System.assertEquals(1, creadas.size(), 'Debe crear la encuesta para la sesión real.');
        System.assertEquals('Si', creadas[0].Tu_solicitud_fue_resuelta__c);
    }

    private class MockConversationApiConSurvey implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"conversationEntries":[' +
                '{"identifier":"m1","messageText":"¿Tu solicitud fue resuelta?",' +
                ' "sender":{"role":"Chatbot","appType":"chatbot","subject":"bot"},' +
                ' "serverReceivedTimestamp":1780537198000},' +
                '{"identifier":"m2","messageText":"Si",' +
                ' "sender":{"role":"EndUser","appType":"live_message","subject":"56912345678"},' +
                ' "serverReceivedTimestamp":1780537199000},' +
                '{"identifier":"m3","messageText":"Por favor califica nuestra atención",' +
                ' "sender":{"role":"Chatbot","appType":"chatbot","subject":"bot"},' +
                ' "serverReceivedTimestamp":1780537200000},' +
                '{"identifier":"m4","messageText":"5",' +
                ' "sender":{"role":"EndUser","appType":"live_message","subject":"56912345678"},' +
                ' "serverReceivedTimestamp":1780537201000}' +
                '],"hasNextPage":false}'
            );
            return res;
        }
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String cron = '0 0 2 * * ?';
        System.schedule('TestEncuestaSyncBatch', cron, new seidor_EncuestaSyncBatch());
        Test.stopTest();
    }

    @isTest
    static void testDefaultConstructor() {
        seidor_EncuestaSyncBatch b = new seidor_EncuestaSyncBatch();
        System.assertNotEquals(null, b);
    }
}