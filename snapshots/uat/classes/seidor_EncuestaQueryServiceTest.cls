@isTest
private class seidor_EncuestaQueryServiceTest {

    @TestSetup
    static void makeData() {
        // Encuesta completa (todas las respuestas)
        Encuesta_cliente__c e1 = new Encuesta_cliente__c(
            Numero_Sesion__c             = 'SES-001',
            Telefono__c                  = '+56912345678',
            Tu_solicitud_fue_resuelta__c = 'Si',
            Calificacion_de_atenci_n__c  = 'Muy buena',
            CSAT_Puntaje__c              = 5,
            Qu_podr_amos_mejorar__c      = 'Nada, excelente',
            Estado_encuesta__c           = 'Completada',
            Fecha_y_hora_encuesta__c     = DateTime.now().addDays(-5)
        );
        // Encuesta solo con CSAT
        Encuesta_cliente__c e2 = new Encuesta_cliente__c(
            Numero_Sesion__c             = 'SES-002',
            Telefono__c                  = '+56998765432',
            Tu_solicitud_fue_resuelta__c = 'No',
            Calificacion_de_atenci_n__c  = 'Mala',
            CSAT_Puntaje__c              = 2,
            Estado_encuesta__c           = 'Completada',
            Fecha_y_hora_encuesta__c     = DateTime.now().addDays(-3)
        );
        // Encuesta sin respuestas (sin FCR ni CSAT)
        Encuesta_cliente__c e3 = new Encuesta_cliente__c(
            Numero_Sesion__c             = 'SES-003',
            Estado_encuesta__c           = 'Incompleta',
            Fecha_y_hora_encuesta__c     = DateTime.now().addDays(-1)
        );
        insert new List<Encuesta_cliente__c>{ e1, e2, e3 };
    }

    // ── getSurveyData ─────────────────────────────────────────────────────────

    @isTest
    static void testGetSurveyData_allRecords() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(dateFrom, dateTo, null, false);
        Test.stopTest();

        System.assertEquals(3, rows.size(), 'e1, e2, e3 retornan (sin lookup, null != true → true)');
    }

    @isTest
    static void testGetSurveyData_csatOnly() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(dateFrom, dateTo, null, true);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'e1 y e2 tienen CSAT_Puntaje__c');
        for (seidor_EncuestaQueryService.SurveyRow r : rows) {
            System.assertNotEquals(null, r.csatScore);
        }
    }

    @isTest
    static void testGetSurveyData_fieldMapping() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(dateFrom, dateTo, null, false);
        Test.stopTest();

        seidor_EncuestaQueryService.SurveyRow r = null;
        for (seidor_EncuestaQueryService.SurveyRow row : rows) {
            if (row.sessionName == 'SES-001') { r = row; break; }
        }
        System.assertNotEquals(null, r, 'SES-001 debe estar en resultados');
        System.assertEquals('+56912345678', r.phone);
        System.assertEquals('Si',           r.fcrAnswer);
        System.assertEquals('Muy buena',    r.csatAnswer);
        System.assertEquals(5,              r.csatScore);
        System.assertEquals('Completada',   r.status);
        System.assertEquals('Sin asignar',  r.agentName);
        System.assertEquals(null,           r.sessionId, 'Sin lookup a MessagingSession');
        System.assertEquals(null,           r.accountName);
        System.assertEquals(null,           r.clientName);
        System.assertEquals(null,           r.categoria, 'getSurveyData no setea categoria');
    }

    @isTest
    static void testGetSurveyData_agentFilter_sinResultados() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();
        User agent = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(dateFrom, dateTo, agent.Id, false);
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Sin encuestas para ese agente');
    }

    @isTest
    static void testGetSurveyData_agentAndCsatFilter() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();
        User agent = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(dateFrom, dateTo, agent.Id, true);
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Sin encuestas CSAT para ese agente');
    }

    @isTest
    static void testGetSurveyData_agentConResultados() {
        // Crea un usuario como agente y una encuesta vinculada
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        User u = new User(
            Alias                  = 'tstagt',
            Email                  = 'testagent@example.com',
            EmailEncodingKey       = 'UTF-8',
            LastName               = 'TestAgent',
            LanguageLocaleKey      = 'en_US',
            LocaleSidKey           = 'en_US',
            ProfileId              = p.Id,
            TimeZoneSidKey         = 'America/Santiago',
            UserName               = 'testagent_' + DateTime.now().getTime() + '@example.com'
        );
        insert u;

        Encuesta_cliente__c e = new Encuesta_cliente__c(
            Numero_Sesion__c             = 'SES-AGENT',
            Nombre_del_agente__c         = u.Id,
            Tu_solicitud_fue_resuelta__c = 'Si',
            Calificacion_de_atenci_n__c  = 'Buena',
            CSAT_Puntaje__c              = 4,
            Estado_encuesta__c           = 'Completada',
            Fecha_y_hora_encuesta__c     = DateTime.now()
        );
        insert e;

        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(dateFrom, dateTo, u.Id, false);
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Debe encontrar la encuesta del agente');
        System.assertEquals('SES-AGENT', rows[0].sessionName);
        User actualUser = [SELECT Name FROM User WHERE Id = :u.Id];
        System.assertEquals(actualUser.Name, rows[0].agentName);
    }

    @isTest
    static void testGetSurveyData_blankDates() {
        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getSurveyData(null, null, null, false);
        Test.stopTest();
        System.assertNotEquals(null, rows);
    }

    // ── getEmptySurveyData ────────────────────────────────────────────────────

    @isTest
    static void testGetEmptySurveyData_sinRespuesta() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getEmptySurveyData(dateFrom, dateTo);
        Test.stopTest();

        // e3 (SES-003) es sin_respuesta: FCR y CSAT null, y no tiene lookup a sesión
        System.assert(rows.size() >= 1, 'Debe incluir al menos SES-003');
        for (seidor_EncuestaQueryService.SurveyRow r : rows) {
            if (r.sessionName == 'SES-003') {
                System.assertEquals('sin_respuesta', r.categoria);
                System.assertEquals(null, r.fcrAnswer);
                System.assertEquals(null, r.csatScore);
            }
        }
    }

    @isTest
    static void testGetEmptySurveyData_fieldMapping() {
        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getEmptySurveyData(dateFrom, dateTo);
        Test.stopTest();

        seidor_EncuestaQueryService.SurveyRow r = null;
        for (seidor_EncuestaQueryService.SurveyRow row : rows) {
            if (row.sessionName == 'SES-003') { r = row; break; }
        }
        System.assertNotEquals(null, r, 'SES-003 debe estar en resultados');
        System.assertEquals('Incompleta',    r.status);
        System.assertEquals('Sin asignar',   r.agentName);
        System.assertEquals(null,            r.phone, 'SES-003 no tiene teléfono');
        System.assertEquals(null,            r.csatAnswer);
        System.assertEquals('sin_respuesta', r.categoria);
    }

    @isTest
    static void testGetEmptySurveyData_blankDates() {
        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getEmptySurveyData(null, null);
        Test.stopTest();
        System.assertNotEquals(null, rows);
    }

    @isTest
    static void testGetEmptySurveyData_conFueraDeHorario() {
        // Intentar crear MessagingSession; si no es posible (entorno de test sin
        // setup), el test se omite sin fallar
        MessagingSession ms;
        try {
            ms = new MessagingSession(
                Fuera_de_horario__c = true
            );
            insert ms;
        } catch (Exception ex) {
            System.debug('TEST OMITIDO: no se pudo crear MessagingSession: ' + ex.getMessage());
            return;
        }

        Encuesta_cliente__c e = new Encuesta_cliente__c(
            Numero_Sesion__c             = 'SES-FH',
            Sesi_n_de_Mensajer_a__c      = ms.Id,
            Tu_solicitud_fue_resuelta__c = 'Si',
            Calificacion_de_atenci_n__c  = 'Regular',
            CSAT_Puntaje__c              = 3,
            Estado_encuesta__c           = 'Completada',
            Fecha_y_hora_encuesta__c     = DateTime.now()
        );
        insert e;

        String dateFrom = Date.today().addDays(-30).format();
        String dateTo   = Date.today().format();

        Test.startTest();
        List<seidor_EncuestaQueryService.SurveyRow> rows =
            seidor_EncuestaQueryService.getEmptySurveyData(dateFrom, dateTo);
        Test.stopTest();

        seidor_EncuestaQueryService.SurveyRow found = null;
        for (seidor_EncuestaQueryService.SurveyRow r : rows) {
            if (r.sessionName == 'SES-FH') { found = r; break; }
        }
        System.assertNotEquals(null, found, 'SES-FH debe aparecer en resultados');
        System.assertEquals('fuera_de_horario', found.categoria);
        System.assertEquals('Si',               found.fcrAnswer);
        System.assertEquals(3,                  found.csatScore);
    }
}