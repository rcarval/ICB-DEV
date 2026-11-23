@IsTest
private class ComodatoPropuestaControllerTest {

    @TestSetup
    static void setup() {
        Product2 machine = new Product2(
            Name               = 'MAQUINA TEST COMODATO',
            ProductCode        = 'TST-MAQ-001',
            Codigo__c          = 'TST-MAQ-001',
            IsActive           = true,
            Precio_de_Lista__c = 1000000
        );
        insert machine;

        Product2 insumo = new Product2(
            Name        = 'CAFE CAPSULAS TEST',
            ProductCode = 'TST-INS-001',
            Codigo__c   = 'TST-INS-001',
            IsActive    = true
        );
        insert insumo;

        Comodato__c insumoRec = new Comodato__c(
            Maquina__c                 = machine.Id,
            Producto_Asociado__c       = insumo.Id,
            Tipo_de_Asociacion__c      = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 50,
            Precio_Unitario_Neto__c    = 15000,
            Unidad_de_Medida__c        = 'Kg'
        );
        insert insumoRec;

        Comodato__c aporteRec = new Comodato__c(
            Maquina__c            = machine.Id,
            Producto_Asociado__c  = insumo.Id,
            Tipo_de_Asociacion__c = 'Aporte de Marca',
            Cantidad_Aporte__c    = 1
        );
        insert aporteRec;
    }

    @IsTest
    static void testGetPreviewHtml() {
        Product2 machine = [SELECT Id FROM Product2 WHERE Name = 'MAQUINA TEST COMODATO' LIMIT 1];

        Test.startTest();
        String html = ComodatoPropuestaController.getPreviewHtml(machine.Id);
        Test.stopTest();

        System.assertNotEquals(null, html, 'HTML no debe ser nulo');
        System.assert(html.contains('PROPUESTA'), 'Debe contener el encabezado');
        System.assert(html.contains('MAQUINA TEST COMODATO'), 'Debe contener el nombre de la maquina');
        System.assert(html.contains('CAFE CAPSULAS TEST'), 'Debe contener el producto asociado');
    }

    @IsTest
    static void testGetPreviewHtmlNoAportes() {
        // Crear maquina sin aportes
        Product2 machine2 = new Product2(
            Name = 'MAQUINA SIN APORTES',
            ProductCode = 'TST-002',
            Codigo__c = 'TST-002',
            IsActive = true
        );
        insert machine2;

        Test.startTest();
        String html = ComodatoPropuestaController.getPreviewHtml(machine2.Id);
        Test.stopTest();

        System.assert(!html.contains('Aporte por Marca'), 'No debe contener seccion de aportes');
    }

    @IsTest
    static void testGetPreviewHtmlNullMachine() {
        Test.startTest();
        String html = ComodatoPropuestaController.getPreviewHtml(null);
        Test.stopTest();
        System.assert(html.contains('Error'), 'Debe retornar mensaje de error para machineId nulo');
    }

    @IsTest
    static void testVFController() {
        Product2 machine = [SELECT Id FROM Product2 WHERE Name = 'MAQUINA TEST COMODATO' LIMIT 1];

        PageReference page = Page.ComodatoPropuesta;
        page.getParameters().put('machineId', machine.Id);
        Test.setCurrentPage(page);

        Test.startTest();
        ComodatoPropuestaController ctrl = new ComodatoPropuestaController();
        Test.stopTest();

        System.assertEquals(machine.Id, ctrl.machineId);
        System.assertNotEquals(null, ctrl.machine);
        System.assertEquals(1, ctrl.serviceLines.size(), 'Debe haber 1 insumo mensual');
        System.assertEquals(1, ctrl.aporteLines.size(), 'Debe haber 1 aporte de marca');
        System.assert(ctrl.serviceLines[0].ServiceName.contains('CAFE'), 'Nombre del insumo debe estar presente');
        System.assertNotEquals('', ctrl.serviceLines[0].FormattedPrice, 'Precio formateado no debe ser vacio');
    }
}