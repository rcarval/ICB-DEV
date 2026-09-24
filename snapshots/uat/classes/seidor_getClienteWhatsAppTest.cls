@isTest
private class seidor_getClienteWhatsAppTest {

    @testSetup
    static void setup() {
        List<Account> testAccounts = new List<Account>{
            new Account(
                Name = 'Cliente Test Uno',
                RUT__c = '12345678-5',
                C_digo_de_cliente__c = 'FS001',
                Nombre_de_Fantasia__c = 'Fantasia Uno'
            ),
            new Account(
                Name = 'Cliente Test Dos',
                RUT__c = '11111111-1',
                C_digo_de_cliente__c = 'FS002',
                Nombre_de_Fantasia__c = 'Fantasia Dos'
            ),
            new Account(
                Name = 'Otra Razon Social',
                RUT__c = '22222222-2',
                C_digo_de_cliente__c = 'OTRO01',
                Nombre_de_Fantasia__c = 'Otra Fantasia'
            )
        };
        insert testAccounts;
    }

    @isTest
    static void searchCliente_searchPorNombre_debeRetornarResultados() {
        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('Cliente Test');
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Debe encontrar 2 cuentas con "Cliente Test"');
    }

    @isTest
    static void searchCliente_searchPorRUT_debeRetornarResultado() {
        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('12345678-5');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe encontrar 1 cuenta por RUT');
        Assert.areEqual('Cliente Test Uno', results[0].Name);
    }

    @isTest
    static void searchCliente_searchPorCodigoCliente_debeRetornarResultado() {
        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('FS002');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe encontrar 1 cuenta por código');
        Assert.areEqual('Cliente Test Dos', results[0].Name);
    }

    @isTest
    static void searchCliente_searchPorNombreFantasia_debeRetornarResultado() {
        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('Fantasia');
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Debe encontrar 3 cuentas por nombre de fantasía');
    }

    @isTest
    static void searchCliente_sinResultados_debeRetornarListaVacia() {
        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('ZZZZNoExiste');
        Test.stopTest();

        Assert.isNotNull(results, 'No debe retornar null');
        Assert.areEqual(0, results.size(), 'Debe retornar lista vacía');
    }

    @isTest
    static void searchCliente_searchTermVacio_debeLanzarExcepcion() {
        AuraHandledException ex;
        try {
            Test.startTest();
            seidor_getClienteWhatsApp.searchCliente('');
            Test.stopTest();
        } catch (AuraHandledException e) {
            ex = e;
        }
        Assert.isNotNull(ex, 'Debe lanzar excepción con término vacío');
    }

    @isTest
    static void searchCliente_searchTermNull_debeLanzarExcepcion() {
        AuraHandledException ex;
        try {
            Test.startTest();
            seidor_getClienteWhatsApp.searchCliente(null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            ex = e;
        }
        Assert.isNotNull(ex, 'Debe lanzar excepción con término null');
    }

    @isTest
    static void searchCliente_searchTermMenor3Caracteres_debeLanzarExcepcion() {
        AuraHandledException ex;
        try {
            Test.startTest();
            seidor_getClienteWhatsApp.searchCliente('ab');
            Test.stopTest();
        } catch (AuraHandledException e) {
            ex = e;
        }
        Assert.isNotNull(ex, 'Debe lanzar excepción con término menor a 3 caracteres');
    }

    @isTest
    static void searchCliente_busquedaCaseInsensitive_debeRetornarResultados() {
        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('cliente test uno');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe encontrar cuenta ignorando mayúsculas/minúsculas');
    }

    @isTest
    static void searchCliente_limiteMaximo50Resultados() {
        List<Account> bulkAccounts = new List<Account>();
        for (Integer i = 0; i < 60; i++) {
            bulkAccounts.add(new Account(Name = 'Bulk Cliente ' + i));
        }
        insert bulkAccounts;

        Test.startTest();
        List<Account> results = seidor_getClienteWhatsApp.searchCliente('Bulk');
        Test.stopTest();

        Assert.areEqual(50, results.size(), 'Debe respetar el límite de 50 resultados');
    }
}