@isTest
private class seidor_EncuestaQAMatcherTest {

    // ── Tests de normalización (migrados desde seidor_EncuestaSyncBatchTest) ──
    // Ahora viven acá porque la lógica se movió a seidor_EncuestaQAMatcher,
    // compartida también por seidor_CrearEncuestaWhatsApp.

    @isTest
    static void testNormalizeFcr() {
        System.assertEquals('Si',   seidor_EncuestaQAMatcher.normalizeFcr('Si'));
        System.assertEquals('Si',   seidor_EncuestaQAMatcher.normalizeFcr('sí'));
        System.assertEquals('Si',   seidor_EncuestaQAMatcher.normalizeFcr('SÍ'));
        System.assertEquals('Si',   seidor_EncuestaQAMatcher.normalizeFcr('Yes'));
        System.assertEquals('No',   seidor_EncuestaQAMatcher.normalizeFcr('no'));
        System.assertEquals('No',   seidor_EncuestaQAMatcher.normalizeFcr('NO'));
        System.assertEquals(null,   seidor_EncuestaQAMatcher.normalizeFcr(''));
        System.assertEquals(null,   seidor_EncuestaQAMatcher.normalizeFcr(null));
        // Texto libre largo no debe mapearse
        System.assertEquals(null,   seidor_EncuestaQAMatcher.normalizeFcr(
            'La verdad no quedé conforme con la atención'));
    }

    @isTest
    static void testNormalizeCsat() {
        System.assertEquals('Muy buena', seidor_EncuestaQAMatcher.normalizeCsat('5'));
        System.assertEquals('Muy buena', seidor_EncuestaQAMatcher.normalizeCsat('Muy buena'));
        System.assertEquals('Muy buena', seidor_EncuestaQAMatcher.normalizeCsat('5 Muy buena😍'));
        System.assertEquals('Buena',     seidor_EncuestaQAMatcher.normalizeCsat('4'));
        System.assertEquals('Buena',     seidor_EncuestaQAMatcher.normalizeCsat('Buena'));
        System.assertEquals('Buena',     seidor_EncuestaQAMatcher.normalizeCsat('4 Buena'));
        System.assertEquals('Regular',   seidor_EncuestaQAMatcher.normalizeCsat('3'));
        System.assertEquals('Regular',   seidor_EncuestaQAMatcher.normalizeCsat('Regular'));
        System.assertEquals('Mala',      seidor_EncuestaQAMatcher.normalizeCsat('2'));
        System.assertEquals('Mala',      seidor_EncuestaQAMatcher.normalizeCsat('Mala'));
        System.assertEquals('Muy mala',  seidor_EncuestaQAMatcher.normalizeCsat('1'));
        System.assertEquals('Muy mala',  seidor_EncuestaQAMatcher.normalizeCsat('Muy mala'));
        System.assertEquals(null,        seidor_EncuestaQAMatcher.normalizeCsat(null));
        System.assertEquals(null,        seidor_EncuestaQAMatcher.normalizeCsat(''));
        System.assertEquals(null,        seidor_EncuestaQAMatcher.normalizeCsat('no sé'));
    }

    @isTest
    static void testExtractCsatScore() {
        System.assertEquals(5, seidor_EncuestaQAMatcher.extractCsatScore('5'));
        System.assertEquals(5, seidor_EncuestaQAMatcher.extractCsatScore('Muy buena'));
        System.assertEquals(5, seidor_EncuestaQAMatcher.extractCsatScore('5 Muy buena😍'));
        System.assertEquals(4, seidor_EncuestaQAMatcher.extractCsatScore('4'));
        System.assertEquals(4, seidor_EncuestaQAMatcher.extractCsatScore('Buena'));
        System.assertEquals(3, seidor_EncuestaQAMatcher.extractCsatScore('3'));
        System.assertEquals(3, seidor_EncuestaQAMatcher.extractCsatScore('Regular'));
        System.assertEquals(2, seidor_EncuestaQAMatcher.extractCsatScore('2'));
        System.assertEquals(2, seidor_EncuestaQAMatcher.extractCsatScore('Mala'));
        System.assertEquals(1, seidor_EncuestaQAMatcher.extractCsatScore('1'));
        System.assertEquals(1, seidor_EncuestaQAMatcher.extractCsatScore('Muy mala'));
        System.assertEquals(null, seidor_EncuestaQAMatcher.extractCsatScore(null));
        System.assertEquals(null, seidor_EncuestaQAMatcher.extractCsatScore(''));
        System.assertEquals(null, seidor_EncuestaQAMatcher.extractCsatScore('texto libre'));
    }

    // ── Test del matching completo pregunta→respuesta ─────────────────────────

    @isTest
    static void testExtractFromMessages_completo() {
        List<seidor_ConversationEntryDTO.MessageWrapper> messages = new List<seidor_ConversationEntryDTO.MessageWrapper>();

        // Texto real de las preguntas del bot en producción (2026-07-02)
        messages.add(buildMsg('Chatbot', 'Gracias por contactar a ICB Food Service!😊\n¿Resolvimos tu solicitud? 💬 Responde con Sí o No.', DateTime.newInstance(2026, 6, 1, 10, 0, 0)));
        messages.add(buildMsg('EndUser', 'Si',                          DateTime.newInstance(2026, 6, 1, 10, 0, 5)));
        messages.add(buildMsg('Chatbot', 'Califica nuestra atención [Ingrese entre 1 y 5] 1 Muy mala 😡 2 Mala 😠 3 Regular🙄 4 Buena 😊 5 Muy buena 😍', DateTime.newInstance(2026, 6, 1, 10, 0, 10)));
        messages.add(buildMsg('EndUser', '5',                           DateTime.newInstance(2026, 6, 1, 10, 0, 15)));
        messages.add(buildMsg('Chatbot', 'Una última pregunta… ¿Qué comentario o sugerencia nos dejarías? 👇🏻', DateTime.newInstance(2026, 6, 1, 10, 0, 20)));
        messages.add(buildMsg('EndUser', 'Todo excelente',               DateTime.newInstance(2026, 6, 1, 10, 0, 25)));

        Test.startTest();
        seidor_EncuestaQAMatcher.MatchResult result = seidor_EncuestaQAMatcher.extractFromMessages(messages);
        Test.stopTest();

        System.assertEquals('Si',         result.fcrAnswer);
        System.assertEquals('Muy buena',  result.csatAnswer);
        System.assertEquals(5,            result.csatScore);
        System.assertEquals('Todo excelente', result.mejorAnswer);
        System.assertEquals(false,        result.isEmpty());
    }

    @isTest
    static void testExtractFromMessages_vacioOInsuficiente() {
        Test.startTest();
        seidor_EncuestaQAMatcher.MatchResult r1 = seidor_EncuestaQAMatcher.extractFromMessages(null);
        seidor_EncuestaQAMatcher.MatchResult r2 = seidor_EncuestaQAMatcher.extractFromMessages(
            new List<seidor_ConversationEntryDTO.MessageWrapper>{ buildMsg('EndUser', 'Hola', DateTime.now()) }
        );
		seidor_EncuestaQAMatcher.getInt();
        Test.stopTest();

        System.assertEquals(true, r1.isEmpty());
        System.assertEquals(true, r2.isEmpty());
    }

    private static seidor_ConversationEntryDTO.MessageWrapper buildMsg(String role, String text, DateTime ts) {
        seidor_ConversationEntryDTO.MessageWrapper w = new seidor_ConversationEntryDTO.MessageWrapper();
        w.senderRole       = role;
        w.messageText      = text;
        w.messageTimestamp = ts;
        return w;
       
    }
}