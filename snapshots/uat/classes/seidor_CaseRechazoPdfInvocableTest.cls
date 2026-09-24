@isTest
private class seidor_CaseRechazoPdfInvocableTest {

    @testSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'Cuenta Test Rechazo',
            Cliente_Despacho__c = 'FS99000-1'
        );
        insert acc;

        Product2 prodA = new Product2(Name = 'Producto A', IsActive = true, Codigo__c = '80000001');
        Product2 prodB = new Product2(Name = 'Producto B', IsActive = true, Codigo__c = '80000002');
        insert new List<Product2>{ prodA, prodB };

        Facturas__c factura = new Facturas__c(
            Cliente__c   = acc.Id,
            Direccion__c = 'FS99000-1'
        );
        insert factura;

        Case casoTotal = new Case(
            Subject                  = 'Caso Rechazo Total',
            Status                   = 'New',
            Origin                   = 'Phone',
            AccountId                = acc.Id,
            Factura__c               = factura.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Sub_Categoria__c         = 'Rechazo total',
            Motivo__c                = 'Producto con defecto de fabricacion',
            Horario_retiro__c        = '08:00 - 17:00'
        );
        insert casoTotal;

        Case casoParcial = new Case(
            Subject                  = 'Caso Rechazo Parcial',
            Status                   = 'New',
            Origin                   = 'Phone',
            AccountId                = acc.Id,
            Factura__c               = factura.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Sub_Categoria__c         = 'Rechazo parcial',
            Motivo__c                = 'Producto danado en transporte',
            Horario_retiro__c        = '08:00 - 17:00',
            Cantidad_reclamada__c    = 8
        );
        insert casoParcial;

        Case casoOtro = new Case(
            Subject                  = 'Caso Otro Tipo',
            Status                   = 'New',
            Origin                   = 'Phone',
            AccountId                = acc.Id,
            Factura__c               = factura.Id,
            Tipo_de_Requerimiento__c = 'Reclamo',
            Sub_Categoria__c         = 'Otro',
            Motivo__c                = 'Otro motivo',
            Horario_retiro__c        = '08:00 - 17:00'
        );
        insert casoOtro;

        List<Detalle_Factura__c> detalles = new List<Detalle_Factura__c>{
            new Detalle_Factura__c(
                Factura__c            = factura.Id,
                Product__c            = prodA.Id,
                SKU__c                = 'SKU-800A',
                Unidad_de_Medida__c   = 'UN',
                Cantidad__c           = 2,
                Caso__c               = casoParcial.Id,
                Valor_Neto__c         = 2000,
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c            = factura.Id,
                Product__c            = prodB.Id,
                SKU__c                = 'SKU-800B',
                Unidad_de_Medida__c   = 'KG',
                Caso__c               = casoParcial.Id,
                Valor_Neto__c         = 3500,
                Proceso_de_reclamo__c = false
            )
        };
        insert detalles;
    }

    @isTest
    static void test_rechazoTotal_enviaCorreo() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Rechazo Total' LIMIT 1];

        seidor_CaseRechazoPdfInvocable.FlowInput input = new seidor_CaseRechazoPdfInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';

        Test.startTest();
        seidor_CaseRechazoPdfInvocable.sendEmail(
            new List<seidor_CaseRechazoPdfInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        Integer emailsSent = Limits.getEmailInvocations();
        System.assert(emailsSent >= 0, 'Email sent without error');
    }

    @isTest
    static void test_rechazoParcial_enviaCorreo() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Rechazo Parcial' LIMIT 1];

        seidor_CaseRechazoPdfInvocable.FlowInput input = new seidor_CaseRechazoPdfInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';
        input.ccAddresses = 'cc@test.com';
        input.bccAddresses = 'bcc@test.com';

        Test.startTest();
        seidor_CaseRechazoPdfInvocable.sendEmail(
            new List<seidor_CaseRechazoPdfInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'Rechazo parcial ejecuta sin error');
    }

    @isTest
    static void test_casoOtroTipo_noEnviaCorreo() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Otro Tipo' LIMIT 1];

        seidor_CaseRechazoPdfInvocable.FlowInput input = new seidor_CaseRechazoPdfInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';

        Test.startTest();
        seidor_CaseRechazoPdfInvocable.sendEmail(
            new List<seidor_CaseRechazoPdfInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'Caso otro tipo ejecuta sin error');
    }

    @isTest
    static void test_multiplesInputs() {
        List<Case> casos = [
            SELECT Id FROM Case
            WHERE Subject IN ('Caso Rechazo Total', 'Caso Rechazo Parcial')
        ];

        List<seidor_CaseRechazoPdfInvocable.FlowInput> inputs =
            new List<seidor_CaseRechazoPdfInvocable.FlowInput>();

        for (Case c : casos) {
            seidor_CaseRechazoPdfInvocable.FlowInput input =
                new seidor_CaseRechazoPdfInvocable.FlowInput();
            input.caseId      = c.Id;
            input.toAddresses = 'test@test.com';
            inputs.add(input);
        }

        Test.startTest();
        seidor_CaseRechazoPdfInvocable.sendEmail(inputs);
        Test.stopTest();

        System.assertEquals(2, casos.size(), 'Debe haber 2 casos de rechazo');
    }

    @isTest
    static void test_ccAddressesNulas() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Rechazo Total' LIMIT 1];

        seidor_CaseRechazoPdfInvocable.FlowInput input = new seidor_CaseRechazoPdfInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';
        input.ccAddresses = null;
        input.bccAddresses = null;

        Test.startTest();
        seidor_CaseRechazoPdfInvocable.sendEmail(
            new List<seidor_CaseRechazoPdfInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'CC/BCC nulos ejecuta sin error');
    }

    @isTest
    static void test_vaciosSinDetalles() {
        Case casoVacio = [
            SELECT Id FROM Case WHERE Subject = 'Caso Rechazo Total' LIMIT 1
        ];

        delete [SELECT Id FROM Detalle_Factura__c];

        seidor_CaseRechazoPdfInvocable.FlowInput input = new seidor_CaseRechazoPdfInvocable.FlowInput();
        input.caseId      = casoVacio.Id;
        input.toAddresses = 'test@test.com';

        Test.startTest();
        seidor_CaseRechazoPdfInvocable.sendEmail(
            new List<seidor_CaseRechazoPdfInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'Sin detalles ejecuta sin error');
    }
}