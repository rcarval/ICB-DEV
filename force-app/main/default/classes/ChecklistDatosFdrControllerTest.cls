@isTest
private class ChecklistDatosFdrControllerTest {

    private static Integer secuencia = 0;

    private static String rutUnico() {
        String base = String.valueOf(Datetime.now().getTime());
        Integer cuerpo = Math.mod(Integer.valueOf(base.right(6)) * 100 + (++secuencia), 99999999);
        return String.valueOf(cuerpo).leftPad(8, '0') + '-' + calcularDv(cuerpo);
    }

    private static String calcularDv(Integer n) {
        Integer sum = 0;
        Integer mul = 2;
        Integer value = n;
        while (value > 0) {
            sum += Math.mod(value, 10) * mul;
            mul = (mul == 7) ? 2 : mul + 1;
            value = value / 10;
        }
        Integer res = 11 - Math.mod(sum, 11);
        if (res == 11) {
            return '0';
        }
        if (res == 10) {
            return 'K';
        }
        return String.valueOf(res);
    }

    @testSetup
    static void setup() {
        String sufijo = String.valueOf(Datetime.now().getTime()).right(8);
        Id rtSucursal = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Sucursal')
            .getRecordTypeId();

        Account incompleta = new Account(
            Name = 'Suc Incompleta ' + sufijo,
            RecordTypeId = rtSucursal,
            RUT__c = rutUnico()
        );
        Account completa = new Account(
            Name = 'Suc Completa ' + sufijo,
            RecordTypeId = rtSucursal,
            RUT__c = rutUnico(),
            Nombre_de_Fantasia__c = 'Fantasia OK'
        );
        insert new List<Account>{ incompleta, completa };

        insert new Contact(
            LastName = 'Completo',
            AccountId = completa.Id,
            Email = 'completo' + sufijo + '@test.icb.cl',
            MobilePhone = '+56911112222'
        );
    }

    @isTest
    static void evaluate_incomplete_without_fantasia_and_contact() {
        Account acc = [SELECT Id FROM Account WHERE Name LIKE 'Suc Incompleta %' LIMIT 1];

        Test.startTest();
        ChecklistDatosFdrController.ChecklistResult result =
            ChecklistDatosFdrController.evaluate(acc.Id);
        Test.stopTest();

        System.assertEquals(false, result.isComplete);
        System.assertEquals(2, result.missingLabels.size());
    }

    @isTest
    static void evaluate_complete_account() {
        ChecklistDatosFdrController.testCanCreateCaseOverride = false;
        Account acc = [SELECT Id FROM Account WHERE Name LIKE 'Suc Completa %' LIMIT 1];

        Test.startTest();
        ChecklistDatosFdrController.ChecklistResult result =
            ChecklistDatosFdrController.evaluate(acc.Id);
        Test.stopTest();

        System.assertEquals(true, result.isComplete);
        System.assertEquals(0, result.missingLabels.size());
        System.assertEquals(
            false,
            result.canCreateCase,
            'Sin permiso Crear_Caso_FDR no debe mostrar CTA'
        );
    }

    @isTest
    static void evaluate_complete_with_create_case_permission() {
        ChecklistDatosFdrController.testCanCreateCaseOverride = true;
        Account acc = [SELECT Id FROM Account WHERE Name LIKE 'Suc Completa %' LIMIT 1];

        Test.startTest();
        ChecklistDatosFdrController.ChecklistResult result =
            ChecklistDatosFdrController.evaluate(acc.Id);
        Test.stopTest();

        System.assertEquals(true, result.isComplete);
        System.assertEquals(true, result.canCreateCase);
    }

    @isTest
    static void invocable_returns_flow_response() {
        Account acc = [SELECT Id FROM Account WHERE Name LIKE 'Suc Completa %' LIMIT 1];
        ChecklistDatosFdrController.FlowRequest req =
            new ChecklistDatosFdrController.FlowRequest();
        req.accountId = acc.Id;

        Test.startTest();
        List<ChecklistDatosFdrController.FlowResponse> responses =
            ChecklistDatosFdrController.validateForFlow(
                new List<ChecklistDatosFdrController.FlowRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].isComplete);
    }

    @isTest
    static void evaluate_null_throws() {
        Boolean threw = false;
        try {
            ChecklistDatosFdrController.evaluate(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
