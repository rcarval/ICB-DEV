/**
 * @description Tests para seidor_CrearEncuestaWhatsApp.
 * Antes de este fix la clase no tenía ningún test — dependía de
 * UserInfo.getSessionId() como Bearer token, imposible de mockear
 * de forma confiable. Tras migrar a seidor_ConversationDataService
 * (Named Credential) sí se puede mockear el callout con HttpCalloutMock.
 */
@isTest
private class seidor_CrearEncuestaWhatsAppTest {

    private class MockConversationApi implements HttpCalloutMock {
        private String body;
        MockConversationApi(String body) { this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    @isTest
    static void crearEncuesta_sinInputs_noHaceNada() {
        Test.startTest();
        seidor_CrearEncuestaWhatsApp.crearEncuesta(new List<seidor_CrearEncuestaWhatsApp.Input>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Encuesta_cliente__c]);
    }

    @isTest
    static void crearEncuesta_inputConSessionIdNull_noHaceNada() {
        seidor_CrearEncuestaWhatsApp.Input inp = new seidor_CrearEncuestaWhatsApp.Input();
        inp.messagingSessionId = null;

        Test.startTest();
        seidor_CrearEncuestaWhatsApp.crearEncuesta(
            new List<seidor_CrearEncuestaWhatsApp.Input>{ inp }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Encuesta_cliente__c]);
    }

    // Requiere una MessagingSession real con ConversationId en el org
    // (Digital Engagement configurado) — se omite con gracia si no existe,
    // mismo patrón que el resto de los tests de este proyecto.
    @isTest(SeeAllData=true)
    static void crearEncuesta_conSesionRealYMockDeApi_creaRegistro() {
        List<MessagingSession> sessions = [
            SELECT Id, ConversationId
            FROM MessagingSession
            WHERE ConversationId != null
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con ConversationId en el org.');
            return;
        }

        Id sessionId = sessions[0].Id;

        Integer existentesAntes = [
            SELECT COUNT() FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__c = :sessionId
        ];
        if (existentesAntes > 0) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: la sesión encontrada ya tiene una encuesta (dedupe la bloquearía).');
            return;
        }

        Test.setMock(HttpCalloutMock.class, new MockConversationApi(
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
        ));

        seidor_CrearEncuestaWhatsApp.Input inp = new seidor_CrearEncuestaWhatsApp.Input();
        inp.messagingSessionId = sessionId;

        Test.startTest();
        seidor_CrearEncuestaWhatsApp.crearEncuesta(
            new List<seidor_CrearEncuestaWhatsApp.Input>{ inp }
        );
        Test.stopTest();

        List<Encuesta_cliente__c> creadas = [
            SELECT Tu_solicitud_fue_resuelta__c, Calificacion_de_atenci_n__c,
                   CSAT_Puntaje__c, Estado_encuesta__c
            FROM Encuesta_cliente__c
            WHERE Sesi_n_de_Mensajer_a__c = :sessionId
        ];

        System.assertEquals(1, creadas.size(), 'Debe crear exactamente 1 encuesta para la sesión.');
        System.assertEquals('Si',        creadas[0].Tu_solicitud_fue_resuelta__c);
        System.assertEquals('Muy buena', creadas[0].Calificacion_de_atenci_n__c);
        System.assertEquals(5,           creadas[0].CSAT_Puntaje__c);
        System.assertEquals('Completada', creadas[0].Estado_encuesta__c);
    }
}