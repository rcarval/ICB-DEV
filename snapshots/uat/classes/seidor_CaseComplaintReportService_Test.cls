/**
 * @description Test class para seidor_CaseComplaintReportService
 *
 * ESCENARIOS CUBIERTOS:
 *  - Constructor VF: con Id válido, sin Id
 *  - generarPDF: caso exitoso (ContentVersion + ContentDocumentLink)
 *  - generarPDF: caseId null → mensaje de error controlado
 *  - generarPDF: caseId inexistente → catch de excepción
 *  - generarPDF: lista vacía → retorna vacío
 *  - generarPDF: múltiples casos (bulkification)
 *  - generarPDF: lista mixta (válido + null)
 */
@IsTest
private class seidor_CaseComplaintReportService_Test {

    // ─────────────────────────────────────────────
    // SETUP
    // ─────────────────────────────────────────────

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Cuenta Test Reclamo');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Status    = 'New',
            Origin    = 'Phone',
            Subject   = 'Caso Reclamo Test'
        );
        insert c;
    }

    // ─────────────────────────────────────────────
    // HELPER
    // ─────────────────────────────────────────────

    private static void setCurrentPageWithCaseId(Id caseId) {
        PageReference page = Page.seidor_CaseComplaintReportPDF;
        if (caseId != null) {
            page.getParameters().put('id', caseId);
        }
        Test.setCurrentPage(page);
    }

    // ─────────────────────────────────────────────
    // TESTS: CONSTRUCTOR VF
    // ─────────────────────────────────────────────

    @IsTest
    static void testConstructor_conIdValido_cargaCaseRecord() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        setCurrentPageWithCaseId(c.Id);

        Test.startTest();
        seidor_CaseComplaintReportService svc = new seidor_CaseComplaintReportService();
        Test.stopTest();

        Assert.isNotNull(svc.caseRecord,
            'caseRecord debe cargarse cuando se provee un Id válido en el parámetro URL.');
        Assert.areEqual(c.Id, svc.caseRecord.Id,
            'caseRecord.Id debe coincidir con el Id del parámetro URL.');
    }

    @IsTest
    static void testConstructor_sinId_dejaCaseRecordNull() {
        PageReference page = Page.seidor_CaseComplaintReportPDF;
        Test.setCurrentPage(page);

        Test.startTest();
        seidor_CaseComplaintReportService svc = new seidor_CaseComplaintReportService();
        Test.stopTest();

        Assert.isNull(svc.caseRecord,
            'caseRecord debe ser null cuando no hay parámetro id en la URL.');
    }

    @IsTest
    static void testConstructor_conIdValido_cargaCamposSOQL() {
        Case c      = [SELECT Id FROM Case LIMIT 1];
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        setCurrentPageWithCaseId(c.Id);

        Test.startTest();
        seidor_CaseComplaintReportService svc = new seidor_CaseComplaintReportService();
        Test.stopTest();

        Assert.isNotNull(svc.caseRecord.CaseNumber,
            'CaseNumber debe estar en el SELECT.');
        Assert.areEqual(acc.Name, svc.caseRecord.Account.Name,
            'Account.Name debe estar disponible mediante relación.');
        Assert.areEqual(acc.Id, svc.caseRecord.AccountId,
            'AccountId debe estar en el SELECT.');
    }

    // ─────────────────────────────────────────────
    // TESTS: generarPDF — ESCENARIO EXITOSO
    // ─────────────────────────────────────────────

    @IsTest
    static void testGenerarPDF_casoValido_retornaOK() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<seidor_CaseComplaintReportService.ResultadoPDF> resultados = seidor_CaseComplaintReportService.generarPDF(
            new List<Id>{ c.Id }
        );
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Debe retornar exactamente 1 resultado para 1 caseId.');
        Assert.isTrue(resultados[0].mensaje.startsWith('OK'),
            'El resultado debe iniciar con OK para un caso válido. Obtenido: ' + resultados[0].mensaje);
    }

    @IsTest
    static void testGenerarPDF_casoValido_creaContentVersion() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Integer cvAntes = [SELECT COUNT() FROM ContentVersion];

        Test.startTest();
        seidor_CaseComplaintReportService.generarPDF(new List<Id>{ c.Id });
        Test.stopTest();

        Integer cvDespues = [SELECT COUNT() FROM ContentVersion];
        Assert.areEqual(cvAntes + 1, cvDespues,
            'Debe crearse exactamente 1 ContentVersion por cada PDF generado.');
    }

    @IsTest
    static void testGenerarPDF_casoValido_tituloPdfContieneCaseNumber() {
        Case c = [SELECT Id, CaseNumber FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportService.generarPDF(new List<Id>{ c.Id });
        Test.stopTest();

        ContentVersion cv = [
            SELECT Title, PathOnClient
            FROM ContentVersion
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Assert.isTrue(cv.Title.contains(c.CaseNumber),
            'El Title del CV debe contener el CaseNumber. Título: ' + cv.Title);
        Assert.isTrue(cv.PathOnClient.endsWith('.pdf'),
            'PathOnClient debe terminar en .pdf. Path: ' + cv.PathOnClient);
    }

    @IsTest
    static void testGenerarPDF_casoValido_creaContentDocumentLink() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportService.generarPDF(new List<Id>{ c.Id });
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id
        ];

        Assert.areEqual(1, links.size(),
            'Debe crearse 1 ContentDocumentLink vinculado al Case.');
        Assert.areEqual('V', links[0].ShareType,
            'ShareType debe ser "V".');
        Assert.areEqual('AllUsers', links[0].Visibility,
            'Visibility debe ser "AllUsers".');
    }

    @IsTest
    static void testGenerarPDF_casoValido_contentVersionDataNoEsVacia() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportService.generarPDF(new List<Id>{ c.Id });
        Test.stopTest();

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Assert.isNotNull(cv.VersionData,
            'VersionData no debe ser null — Test.isRunningTest() genera Blob.valueOf("TEST PDF").');
        Assert.isTrue(cv.VersionData.size() > 0,
            'VersionData debe tener contenido.');
    }

    // ─────────────────────────────────────────────
    // TESTS: generarPDF — MANEJO DE ERRORES
    // ─────────────────────────────────────────────

    @IsTest
    static void testGenerarPDF_caseIdNull_retornaErrorControlado() {
        Test.startTest();
        List<seidor_CaseComplaintReportService.ResultadoPDF> resultados = seidor_CaseComplaintReportService.generarPDF(
            new List<Id>{ null }
        );
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Debe retornar 1 resultado aunque el Id sea null.');
        Assert.isTrue(resultados[0].mensaje.startsWith('ERROR'),
            'Debe retornar ERROR para Id null. Obtenido: ' + resultados[0].mensaje);
        Assert.isTrue(resultados[0].mensaje.contains('obligatorio'),
            'El mensaje debe indicar que el Id es obligatorio.');
    }

    @IsTest
    static void testGenerarPDF_caseIdInexistente_retornaErrorCatch() {
        Id fakeId = '500000000000000AAA';

        Test.startTest();
        List<seidor_CaseComplaintReportService.ResultadoPDF> resultados = seidor_CaseComplaintReportService.generarPDF(
            new List<Id>{ fakeId }
        );
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Debe retornar 1 resultado para un Id inexistente.');
        Assert.isTrue(resultados[0].mensaje.startsWith('ERROR'),
            'El catch debe producir un ERROR. Obtenido: ' + resultados[0].mensaje);
    }

    @IsTest
    static void testGenerarPDF_listaVacia_retornaListaVacia() {
        Test.startTest();
        List<seidor_CaseComplaintReportService.ResultadoPDF> resultados = seidor_CaseComplaintReportService.generarPDF(
            new List<Id>()
        );
        Test.stopTest();

        Assert.isTrue(resultados.isEmpty(),
            'Una lista vacía de Ids debe retornar una lista vacía de resultados sin errores.');
    }

    // ─────────────────────────────────────────────
    // TESTS: generarPDF — BULKIFICATION
    // ─────────────────────────────────────────────

    @IsTest
    static void testGenerarPDF_multiplesCasos_retornaUnResultadoPorCaso() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<Case> casos = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            casos.add(new Case(
                AccountId = acc.Id,
                Status    = 'New',
                Origin    = 'Phone',
                Subject   = 'Caso Bulk ' + i
            ));
        }
        insert casos;

        List<Id> caseIds = new List<Id>(new Map<Id, Case>(casos).keySet());

        Test.startTest();
        List<seidor_CaseComplaintReportService.ResultadoPDF> resultados = seidor_CaseComplaintReportService.generarPDF(caseIds);
        Test.stopTest();

        Assert.areEqual(5, resultados.size(),
            'Debe retornar 1 resultado por cada caseId enviado.');
        for (seidor_CaseComplaintReportService.ResultadoPDF r : resultados) {
            Assert.isTrue(r.mensaje.startsWith('OK'),
                'Todos los resultados deben ser OK para casos válidos. Obtenido: ' + r.mensaje);
        }
    }

    @IsTest
    static void testGenerarPDF_multiplesCasos_creaUnLinkPorCaso() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<Case> casos = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            casos.add(new Case(
                AccountId = acc.Id,
                Status    = 'New',
                Origin    = 'Phone',
                Subject   = 'Caso Link Bulk ' + i
            ));
        }
        insert casos;

        List<Id> caseIds = new List<Id>(new Map<Id, Case>(casos).keySet());

        Test.startTest();
        seidor_CaseComplaintReportService.generarPDF(caseIds);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :caseIds
        ];

        Assert.areEqual(3, links.size(),
            'Debe crearse exactamente 1 ContentDocumentLink por cada caso procesado.');
    }

    // ─────────────────────────────────────────────
    // TESTS: generarPDF — LISTA MIXTA
    // ─────────────────────────────────────────────

    @IsTest
    static void testGenerarPDF_listaMixta_procesaCadaEntradaIndependientemente() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        // Lista con un Id válido y uno null
        List<Id> caseIds = new List<Id>{ c.Id, null };

        Test.startTest();
        List<seidor_CaseComplaintReportService.ResultadoPDF> resultados = seidor_CaseComplaintReportService.generarPDF(caseIds);
        Test.stopTest();

        Assert.areEqual(2, resultados.size(),
            'Debe retornar exactamente 2 resultados para 2 entradas.');
        Assert.isTrue(resultados[0].mensaje.startsWith('OK'),
            'La entrada válida debe retornar OK. Obtenido: ' + resultados[0].mensaje);
        Assert.isTrue(resultados[1].mensaje.startsWith('ERROR'),
            'La entrada null debe retornar ERROR. Obtenido: ' + resultados[1].mensaje);
    }
}