@IsTest
private with sharing class EnviarSAPGateControllerTest {
    @IsTest
    static void testInitWithoutIdShowsError() {
        Test.setCurrentPage(new PageReference('/apex/EnviarSAPGate'));

        EnviarSAPGateController controller = new EnviarSAPGateController();
        PageReference nextPage = controller.init();

        System.assertEquals(null, nextPage);
        System.assertEquals(true, controller.getHasError());
        System.assertEquals(false, controller.getHasMissingFields());
    }

    @IsTest
    static void testInitWithInvalidIdShowsError() {
        Test.setCurrentPage(new PageReference('/apex/EnviarSAPGate'));
        ApexPages.currentPage().getParameters().put('id', 'invalido');

        EnviarSAPGateController controller = new EnviarSAPGateController();
        PageReference nextPage = controller.init();

        System.assertEquals(null, nextPage);
        System.assertEquals(true, controller.getHasError());
    }

    @IsTest
    static void testInitWithIncompleteAccountShowsMissingFields() {
        Account testAccount = new Account(Name = 'Cuenta incompleta');
        insert testAccount;

        Test.setCurrentPage(new PageReference('/apex/EnviarSAPGate'));
        ApexPages.currentPage().getParameters().put('id', testAccount.Id);

        EnviarSAPGateController controller = new EnviarSAPGateController();
        PageReference nextPage = controller.init();

        System.assertEquals(null, nextPage);
        System.assertEquals(false, controller.getHasError());
        System.assertEquals(true, controller.getHasMissingFields());
        System.assert(controller.missingFields.contains('RUT'));
        System.assert(controller.missingFields.contains('Direccion de despacho'));
    }

    @IsTest
    static void testCollectMissingFieldsHandlesNullAccount() {
        List<String> issues = EnviarSAPGateController.collectMissingFields(null);

        System.assertEquals(1, issues.size());
        System.assertEquals('No se pudo cargar la cuenta.', issues[0]);
    }

    @IsTest
    static void testMaybeRedirectWhenAccountIsComplete() {
        Account persistedAccount = new Account(Name = 'Cuenta base');
        insert persistedAccount;

        Account completeAccount = buildCompleteAccount();
        EnviarSAPGateController controller = EnviarSAPGateController.forTest(persistedAccount.Id, completeAccount);

        PageReference nextPage = controller.maybeRedirect();

        System.assertNotEquals(null, nextPage);
        System.assertEquals('/flow/Auto_crear_cliente_full_v1?varAccountId=' + persistedAccount.Id, nextPage.getUrl());
        System.assertEquals(false, controller.getHasMissingFields());
    }

    @IsTest
    static void testHardcodedFlowFieldsAreNotRequired() {
        Account accountWithoutHardcodedFields = buildCompleteAccount();
        accountWithoutHardcodedFields.Status_Jur_dico__c = null;
        accountWithoutHardcodedFields.putSObject('Codigo_Ramo__r', null);

        Comuna__c dispatchComuna = (Comuna__c) accountWithoutHardcodedFields.getSObject('Comuna_Despacho__r');
        dispatchComuna.Incoterms__c = null;
        accountWithoutHardcodedFields.putSObject('Comuna_Despacho__r', dispatchComuna);

        List<String> issues = EnviarSAPGateController.collectMissingFields(accountWithoutHardcodedFields);

        System.assertEquals(false, issues.contains('Status juridico'));
        System.assertEquals(false, issues.contains('Incoterms de la comuna de despacho'));
        System.assertEquals(false, issues.contains('Codigo de ramo'));
    }

    private static Account buildCompleteAccount() {
        Account testAccount = new Account();
        testAccount.Name = 'Cuenta completa';
        testAccount.Nombre_de_Fantasia__c = 'Fantasia';
        testAccount.RUT__c = '12345678-9';
        testAccount.ShippingStreet = 'Despacho 123';
        testAccount.ShippingCity = 'Santiago';
        testAccount.BillingStreet = 'Facturacion 456';
        testAccount.Phone = '+56912345678';
        testAccount.Email__c = 'qa@example.com';
        testAccount.Centro_de_Abastecimiento__c = firstPicklistValue(Account.Centro_de_Abastecimiento__c, 'FS00');
        testAccount.Sucursal__c = firstPicklistValue(Account.Sucursal__c, 'S001');
        testAccount.Region_Despacho__c = firstPicklistValue(Account.Region_Despacho__c, '13');
        testAccount.Region__c = firstPicklistValue(Account.Region__c, '13');
        testAccount.Gerencia__c = firstPicklistValue(Account.Gerencia__c, '115');

        User ownerRecord = new User(Id = UserInfo.getUserId());
        ownerRecord.put('Id_SAP_Ref_Cr_ditos__c', 1234);
        testAccount.putSObject('Owner', ownerRecord);

        Comuna__c dispatchComuna = new Comuna__c(Name = 'Santiago');
        dispatchComuna.Condici_n_de_expedici_n__c = '01';
        testAccount.putSObject('Comuna_Despacho__r', dispatchComuna);

        Comuna__c billingComuna = new Comuna__c(Name = 'Maipu');
        testAccount.putSObject('Comuna_Facturaci_n__r', billingComuna);

        SObject ramoRecord = Account.Codigo_Ramo__c.getDescribe().getReferenceTo()[0].newSObject();
        ramoRecord.put('Name', '01 - Test');
        testAccount.putSObject('Codigo_Ramo__r', ramoRecord);

        return testAccount;
    }

    private static String firstPicklistValue(Schema.SObjectField fieldRef, String fallbackValue) {
        List<Schema.PicklistEntry> values = fieldRef.getDescribe().getPicklistValues();
        return values.isEmpty() ? fallbackValue : values[0].getValue();
    }
}