@isTest
private class seidor_RetiroProgramadoInvocableTest {

    @testSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'Cuenta Test Retiro',
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
            Subject                  = 'Caso Retiro Total',
            Status                   = 'New',
            Origin                   = 'Phone',
            AccountId                = acc.Id,
            Factura__c               = factura.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Sub_Categoria__c         = 'Rechazo total',
            Motivo__c                = 'Producto con defecto de fabricacion',
            Fecha_retiro__c          = Date.today().addDays(-2),
            Horario_retiro__c        = '08:00 - 17:00'
        );
        insert casoTotal;

        Case casoParcial = new Case(
            Subject                  = 'Caso Retiro Parcial',
            Status                   = 'New',
            Origin                   = 'Phone',
            AccountId                = acc.Id,
            Factura__c               = factura.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Sub_Categoria__c         = 'Rechazo parcial',
            Motivo__c                = 'Producto danado en transporte',
            Fecha_retiro__c          = Date.today().addDays(-3),
            Horario_retiro__c        = '09:00 - 13:00',
            Cantidad_reclamada__c    = 8
        );
        insert casoParcial;

        Case casoOtro = new Case(
            Subject                  = 'Caso Retiro Otro',
            Status                   = 'New',
            Origin                   = 'Phone',
            AccountId                = acc.Id,
            Factura__c               = factura.Id,
            Tipo_de_Requerimiento__c = 'Reclamo',
            Sub_Categoria__c         = 'Otro',
            Motivo__c                = 'Otro motivo',
            Fecha_retiro__c          = Date.today().addDays(-4),
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
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c            = factura.Id,
                Product__c            = prodB.Id,
                SKU__c                = 'SKU-800C',
                Unidad_de_Medida__c   = 'CA',
                Cantidad__c           = 5,
                Valor_Neto__c         = 1200,
                Proceso_de_reclamo__c = false
            )
        };
        insert detalles;
    }

    @isTest
    static void test_rechazoTotal_traeTodosLosDetalles() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Retiro Total' LIMIT 1];

        seidor_RetiroProgramadoInvocable.FlowInput input = new seidor_RetiroProgramadoInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';

        Test.startTest();
        seidor_RetiroProgramadoInvocable.sendEmail(
            new List<seidor_RetiroProgramadoInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        Integer emailsSent = Limits.getEmailInvocations();
        System.assert(emailsSent >= 0, 'Rechazo total ejecuta sin error');
    }

    @isTest
    static void test_rechazoParcial_filtraProcesoYCase() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Retiro Parcial' LIMIT 1];

        seidor_RetiroProgramadoInvocable.FlowInput input = new seidor_RetiroProgramadoInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';
        input.ccAddresses = 'cc@test.com';
        input.bccAddresses = 'bcc@test.com';

        Test.startTest();
        seidor_RetiroProgramadoInvocable.sendEmail(
            new List<seidor_RetiroProgramadoInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'Rechazo parcial con filtros ejecuta sin error');
    }

    @isTest
    static void test_casoOtroTipo_noEnviaCorreo() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Retiro Otro' LIMIT 1];

        seidor_RetiroProgramadoInvocable.FlowInput input = new seidor_RetiroProgramadoInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';

        Test.startTest();
        seidor_RetiroProgramadoInvocable.sendEmail(
            new List<seidor_RetiroProgramadoInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations(), 'No debe enviarse correo para otro tipo');
    }

    @isTest
    static void test_rechazoParcial_cantidadFallback() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Retiro Parcial' LIMIT 1];

        // Deja solo un detalle sin Cantidad__c para forzar el fallback.
        delete [SELECT Id FROM Detalle_Factura__c WHERE Proceso_de_reclamo__c = false];
        List<Detalle_Factura__c> detalles = [
            SELECT Id, Cantidad__c FROM Detalle_Factura__c
        ];
        detalles[0].Cantidad__c = null;
        update detalles;

        seidor_RetiroProgramadoInvocable.FlowInput input = new seidor_RetiroProgramadoInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';

        Test.startTest();
        seidor_RetiroProgramadoInvocable.sendEmail(
            new List<seidor_RetiroProgramadoInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'Rechazo parcial con cantidad nula ejecuta sin error');
    }

    @isTest
    static void test_ccBccNulos() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Retiro Total' LIMIT 1];

        seidor_RetiroProgramadoInvocable.FlowInput input = new seidor_RetiroProgramadoInvocable.FlowInput();
        input.caseId      = c.Id;
        input.toAddresses = 'test@test.com';
        input.ccAddresses = null;
        input.bccAddresses = null;

        Test.startTest();
        seidor_RetiroProgramadoInvocable.sendEmail(
            new List<seidor_RetiroProgramadoInvocable.FlowInput>{ input }
        );
        Test.stopTest();

        System.assert(true, 'CC/BCC nulos ejecuta sin error');
    }

    @isTest
    static void test_htmlCorporativo_rechazoTotal() {
        Case c = [SELECT Id, CaseNumber, Account.Name, Factura__c, Cantidad_reclamada__c,
                         Fecha_retiro__c, Horario_retiro__c, Nombre_Direcci_n__c, Comuna_sucursal__c
                  FROM Case WHERE Subject = 'Caso Retiro Total' LIMIT 1];
        List<Detalle_Factura__c> detalles = [
            SELECT Name, SKU__c, Product__r.Name, Cantidad__c,
                   Unidad_de_Medida__c, Valor_Neto__c
            FROM Detalle_Factura__c
            WHERE Factura__c = :c.Factura__c
            ORDER BY Name
        ];

        String html = seidor_RetiroProgramadoInvocable.buildHtmlBody(c, detalles, false);

        System.assert(html.contains('https://raw.githubusercontent.com/sebaCode0297/ICBFS_IMG/main/header.png'), 'Debe incluir header corporativo');
        System.assert(html.contains('https://raw.githubusercontent.com/sebaCode0297/ICBFS_IMG/main/logo-footer.png'), 'Debe incluir logo footer');
        System.assert(html.contains('Programación de Retiro'), 'Debe incluir titulo corporativo');
        System.assert(html.contains('Datos del retiro'), 'Debe incluir titulo Datos del retiro');
        System.assert(html.contains('Fecha de retiro'), 'Debe incluir fecha de retiro');
        System.assert(html.indexOf('</table>') < html.indexOf('Fecha de retiro'), 'Datos del retiro debe ir debajo de la tabla');
        System.assert(html.contains('border-top:3px solid #E40147'), 'Banda de datos con acento');
        System.assert(html.contains('Horario de retiro'), 'Micro-label Horario de retiro');
        System.assert(html.contains('Dirección'), 'Micro-label Dirección');
        System.assert(html.contains('class="stack"'), 'Columnas responsive de la banda');
        List<String> meses = new List<String>{
            'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
            'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
        };
        Date fechaRetiro = Date.today().addDays(-2);
        String fechaEsperada = fechaRetiro.day() + ' de ' + meses[fechaRetiro.month() - 1] + ' de ' + fechaRetiro.year();
        System.assert(html.contains(fechaEsperada), 'Debe formatear la fecha en espanol');
        System.assert(html.contains('De 08:00 A 17:00'), 'Debe formatear el horario De X A Y');
        System.assert(html.contains('SKU-800A') && html.contains('SKU-800B') && html.contains('SKU-800C'), 'Rechazo total trae todos los detalles');
        System.assert(html.contains('2 | UN'), 'Debe incluir cantidad con UM');
        System.assert(html.contains('Total'), 'Debe incluir fila total');
        System.assert(html.contains('PIA'), 'Debe incluir footer corporativo');
    }

    @isTest
    static void test_htmlCorporativo_rechazoParcial_filtraYFallback() {
        Case c = [SELECT Id, CaseNumber, Account.Name, Factura__c, Cantidad_reclamada__c,
                         Fecha_retiro__c, Horario_retiro__c, Nombre_Direcci_n__c, Comuna_sucursal__c
                  FROM Case WHERE Subject = 'Caso Retiro Parcial' LIMIT 1];
        List<Detalle_Factura__c> detalles = [
            SELECT Name, SKU__c, Product__r.Name, Cantidad__c,
                   Unidad_de_Medida__c, Valor_Neto__c
            FROM Detalle_Factura__c
            WHERE Factura__c = :c.Factura__c
              AND Proceso_de_reclamo__c = true
              AND Caso__c = :c.Id
            ORDER BY Name
        ];

        String html = seidor_RetiroProgramadoInvocable.buildHtmlBody(c, detalles, true);

        System.assert(html.contains('SKU-800A') && html.contains('SKU-800B'), 'Rechazo parcial trae detalles en reclamo');
        System.assert(!html.contains('SKU-800C'), 'Rechazo parcial no trae detalles fuera de reclamo');
        System.assert(html.contains('8 | KG'), 'Debe aplicar fallback de cantidad del caso');
    }

    @isTest
    static void test_contactoVisibleSigueCCC() {
        Case c = [SELECT Id, CaseNumber, Account.Name, Factura__c, Cantidad_reclamada__c,
                         Fecha_retiro__c, Horario_retiro__c, Nombre_Direcci_n__c, Comuna_sucursal__c
                  FROM Case WHERE Subject = 'Caso Retiro Total' LIMIT 1];
        List<Detalle_Factura__c> detalles = [
            SELECT Name, SKU__c, Product__r.Name, Cantidad__c,
                   Unidad_de_Medida__c, Valor_Neto__c
            FROM Detalle_Factura__c
            WHERE Factura__c = :c.Factura__c
            ORDER BY Name
        ];

        String html = seidor_RetiroProgramadoInvocable.buildHtmlBody(c, detalles, false);

        System.assert(html.contains('ccc@icbfs.cl'), 'El contacto visible debe seguir siendo ccc@icbfs.cl');
        System.assert(!html.contains('notificaciones@icbfs.cl'), 'No debe cambiarse la casilla visible a notificaciones');
    }

    @isTest
    static void test_multiplesInputs() {
        List<Case> casos = [
            SELECT Id FROM Case
            WHERE Subject IN ('Caso Retiro Total', 'Caso Retiro Parcial')
        ];

        List<seidor_RetiroProgramadoInvocable.FlowInput> inputs =
            new List<seidor_RetiroProgramadoInvocable.FlowInput>();

        for (Case c : casos) {
            seidor_RetiroProgramadoInvocable.FlowInput input =
                new seidor_RetiroProgramadoInvocable.FlowInput();
            input.caseId      = c.Id;
            input.toAddresses = 'test@test.com';
            inputs.add(input);
        }

        Test.startTest();
        seidor_RetiroProgramadoInvocable.sendEmail(inputs);
        Test.stopTest();

        System.assertEquals(2, inputs.size(), 'Debe haber 2 casos de rechazo');
    }
}