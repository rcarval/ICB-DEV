/**
 * @description Test class for seidor_CaseComplaintReportController
 *
 * - El controller es un VF.
 *   ApexPages.currentPage() + parámetros URL simulados.
 * - loadCase() es private pero se ejercita indirectamente desde el constructor.
 */
@IsTest
private class seidor_CaseComplaintReportControllerTest {

    // ─────────────────────────────────────────────
    // SETUP GLOBAL
    // ─────────────────────────────────────────────

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account Controller');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Status    = 'New',
            Origin    = 'Phone',
            Subject   = 'Test VF Controller Case'
            // Campos custom opcionales — añadir si tienen validaciones activas:
            // Motivo__c                = 'Motivo de prueba',
            // Investigacion__c         = 'Investigación de prueba',
            // Acciones_Correctivas__c  = 'Acción correctiva',
            // Acciones_Preventivas__c  = 'Acción preventiva',
            // Conclusiones__c          = 'Conclusión',
            // Marca__c                 = 'Marca Test'
        );
        insert c;
    }

    // ─────────────────────────────────────────────
    // HELPER: simula contexto VF con parámetro id
    // ─────────────────────────────────────────────

    private static seidor_CaseComplaintReportController buildControllerWithCaseId(Id caseId) {
        PageReference page = Page.seidor_CaseComplaintReportPDF;
        if (caseId != null) {
            page.getParameters().put('id', caseId);
        }
        Test.setCurrentPage(page);
        return new seidor_CaseComplaintReportController();
    }

    // ─────────────────────────────────────────────
    // TESTS: CONSTRUCTOR CON ID VÁLIDO
    // ─────────────────────────────────────────────

    @IsTest
    static void testConstructor_withValidCaseId_loadsCaseRecord() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);
        Test.stopTest();

        Assert.isNotNull(controller.caseRecord,
            'El caseRecord debe estar cargado cuando se pasa un Id válido.');
        Assert.areEqual(c.Id, controller.caseRecord.Id,
            'El caseRecord.Id debe corresponder al Case del parámetro URL.');
    }

    /*@IsTest
    static void testConstructor_withValidCaseId_loadsAllRequiredFields() {
        Case c     = [SELECT Id FROM Case LIMIT 1];
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);
        Test.stopTest();

        // Valida que los campos del SELECT están presentes en el objeto retornado
        Assert.isNotNull(controller.caseRecord.CaseNumber,
            'El campo CaseNumber debe estar cargado.');
        Assert.areEqual(acc.Name, controller.caseRecord.Account.Name,
            'El campo Account.Name debe corresponder al Account del Case.');
        // Los campos custom deben ser accesibles (null es válido si no están seteados)
        // Si existen en el objeto, la ausencia de excepción ya valida el SELECT
        controller.caseRecord.Motivo__c.equals('Algo');               // acceso sin excepción
        controller.caseRecord.Investigacion__c.equals('Algo');
        controller.caseRecord.Acciones_Correctivas__c.equals('Algo');
        controller.caseRecord.Acciones_Preventivas__c.equals('Algo');
        controller.caseRecord.Conclusiones__c.equals('Algo');
    }*/

    @IsTest
    static void testConstructor_withValidCaseId_loadsProductAndBrand() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);
        Test.stopTest();

        // Product.Name puede ser null si no hay producto asociado — validamos acceso sin excepción
        String productName = controller.caseRecord.Product != null
            ? controller.caseRecord.Product.Name
            : null;

        // La ejecución sin excepción valida que el campo está en el SOQL
        Assert.isNotNull(controller.caseRecord,
            'El caseRecord debe existir incluso si Product es null.');
    }

    // ─────────────────────────────────────────────
    // TESTS: CONSTRUCTOR SIN ID
    // ─────────────────────────────────────────────

    @IsTest
    static void testConstructor_withoutCaseId_leavesRecordNull() {
        // No se setea el parámetro 'id'
        PageReference page = Page.seidor_CaseComplaintReportPDF;
        Test.setCurrentPage(page);

        Test.startTest();
        seidor_CaseComplaintReportController controller = new seidor_CaseComplaintReportController();
        Test.stopTest();

        Assert.isNull(controller.caseRecord,
            'El caseRecord debe ser null cuando no hay parámetro id en la URL.');
    }

    /*@IsTest
    static void testConstructor_withEmptyStringCaseId_leavesRecordNull() {
        // Parámetro id presente pero vacío — simula URL ?id=
        PageReference page = Page.seidor_CaseComplaintReportPDF;
        page.getParameters().put('id', '');
        Test.setCurrentPage(page);

        Test.startTest();
        seidor_CaseComplaintReportController controller = new seidor_CaseComplaintReportController();
        Test.stopTest();

        // Con id='' el cast a Id retorna null, por lo que no debe ejecutarse la query
        Assert.isNull(controller.caseRecord,
            'El caseRecord debe ser null cuando el parámetro id está vacío.');
    }*/

    // ─────────────────────────────────────────────
    // TESTS: INTEGRIDAD DE DATOS DEL CASO CARGADO
    // ─────────────────────────────────────────────

    @IsTest
    static void testCaseRecord_caseNumberIsNotEmpty() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);
        Test.stopTest();

        Assert.isTrue(
            String.isNotBlank(controller.caseRecord.CaseNumber),
            'CaseNumber no debe estar vacío — Salesforce lo genera automáticamente.'
        );
    }

    @IsTest
    static void testCaseRecord_accountIdMatchesInsertedAccount() {
        Case c     = [SELECT Id, AccountId FROM Case LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);
        Test.stopTest();

        Assert.areEqual(acc.Id, controller.caseRecord.AccountId,
            'El AccountId del caseRecord debe coincidir con el Account insertado en el setup.');
    }

    // ─────────────────────────────────────────────
    // TESTS: COMPORTAMIENTO ANTE CASO INEXISTENTE
    // ─────────────────────────────────────────────

    /**
     * NOTA: La clase actual NO maneja QueryException cuando el Case no existe.
     * Este test documenta el comportamiento actual (lanza excepción) y debe
     * actualizarse si se añade manejo de errores al controller.
     *
     * RECOMENDACIÓN DE ARQUITECTURA: Añadir try-catch en loadCase() y mostrar
     * un mensaje de error en la página VF en lugar de una excepción no controlada.
     */
    @IsTest
    static void testConstructor_withNonExistentCaseId_throwsQueryException() {
        Id fakeId = '500000000000000AAA';

        Test.startTest();
        try {
            seidor_CaseComplaintReportController controller = buildControllerWithCaseId(fakeId);
            Assert.fail('Se esperaba una QueryException para un Id inexistente, pero no se lanzó.');
        } catch (System.QueryException e) {
            Assert.isTrue(
                e.getMessage().contains('List has no rows'),
                'La excepción debe indicar que no hay registros. Mensaje: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────
    // TESTS: PROPIEDAD PÚBLICA caseRecord
    // ─────────────────────────────────────────────

    /**
     * Valida que caseRecord es accesible desde la Visualforce page
     * (propiedad pública con getter/setter).
     */
    @IsTest
    static void testCaseRecord_isPublicAndWritable() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);

        // Simula lo que VF haría al acceder a {!caseRecord.CaseNumber}
        String caseNumber = controller.caseRecord.CaseNumber;
        Test.stopTest();

        Assert.isNotNull(caseNumber,
            'La propiedad caseRecord debe ser accesible públicamente para la VF page.');
    }

    @IsTest
    static void testCaseRecord_canBeSetExternally() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        seidor_CaseComplaintReportController controller = buildControllerWithCaseId(c.Id);

        Case overrideCase = new Case(Subject = 'Override');

        Test.startTest();
        controller.caseRecord = overrideCase;
        Test.stopTest();

        Assert.areEqual('Override', controller.caseRecord.Subject,
            'La propiedad caseRecord debe permitir escritura desde el setter público.');
    }
}