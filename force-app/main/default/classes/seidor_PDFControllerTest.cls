@isTest
private class seidor_PDFControllerTest {

    // ─────────────────────────────────────────────
    // HELPER: crea datos de prueba completos
    // ─────────────────────────────────────────────
    @TestSetup
    static void setupTestData() {

        // 1 y 2. Crear UserRole y User dentro de runAs para evitar MIXED_DML
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'Administrador del sistema' LIMIT 1];

        // Usuario temporal para runAs
        User tempUser = new User(
            LastName = 'Temp',
            Alias = 'temp',
            Email = 'tempuser@test.com',
            Username = 'tempuser' + System.currentTimeMillis() + '@test.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'es',
            LocaleSidKey = 'es_CL',
            TimeZoneSidKey = 'America/Santiago',
            ProfileId = sysAdminProfile.Id
        );
        insert tempUser;

        System.runAs(tempUser) {

            UserRole parentRole = new UserRole(Name = 'Parent Role Test PDF');
            insert parentRole;

            UserRole childRole = new UserRole(
                Name         = 'Child Role Test PDF',
                ParentRoleId = parentRole.Id
            );
            insert childRole;

            User supervisor = new User(
                LastName           = 'SupervisorPDF',
                FirstName          = 'Test',
                Alias              = 'supPDF',
                Email              = 'supervisor.pdf.test@seidor.test.com',
                Username           = 'supervisor.pdf.test' + System.currentTimeMillis() + '@test.com',
                EmailEncodingKey   = 'UTF-8',
                LanguageLocaleKey  = 'es',
                LocaleSidKey       = 'es_CL',
                TimeZoneSidKey     = 'America/Santiago',
                ProfileId          = sysAdminProfile.Id,
                UserRoleId         = parentRole.Id,
                IsActive           = true
            );
            insert supervisor;
        }


        // 4. Cuenta
        Account acc = new Account(
            Name                  = 'Cuenta Test PDF',
            Nombre_de_Fantasia__c = 'Fantasia PDF',

            C_digo_de_cliente__c  = 'CLI001',
            OwnerId               = UserInfo.getUserId()
        );
        insert acc;

        // 5. Contacto
        Contact con = new Contact(
            LastName  = 'Contacto PDF',
            AccountId = acc.Id
        );
        insert con;

        // 6. Producto
        Product2 prod = new Product2(
            Name      = 'Producto PDF Test',
            IsActive  = true,
            Codigo__c = '104532850'
        );
        insert prod;

        // 7. Factura y Caso (vinculados por Numero_Factura__c = Name de Facturas__c)
        String facturaName = 'F-' + System.currentTimeMillis();
        Facturas__c factura = new Facturas__c(
            C_digo_de_Cliente__c = 'CODE-001',
            Cliente__c = acc.Id,
            Comuna__c = 'Comuna Test',
            Direccion__c = 'Direccion Test',
            Fecha_de_Documento__c = Date.today(),
            Folio_Documento__c = 'FOL-001',
            Numero_de_Factura__c = 'NUM-001',
            numero_pedido__c = 'PED-001',
            Propietario__c = '441',
            Region__c = 'Region Test',
            Sociedad__c = 'Sociedad Test',
            Tipo_de_Documento__c = 'Tipo Test',
            Total_Venta__c = 5000,
            Valor_Rappel__c = 500,
            Ya_procesada__c = false
        );
        insert factura;

        String resolvedFacturaName = [SELECT Name FROM Facturas__c WHERE Id = :factura.Id].Name;

        // 8. Caso principal
        Case c = new Case(
            Subject = 'Caso Test',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            ProductId = prod.Id,
            N_Factura__c = facturaName,
            Numero_Factura__c = resolvedFacturaName,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Lunes;Martes'
        );
        insert c;

        // 9. Detalle de factura
        Detalle_Factura__c detalle = new Detalle_Factura__c(
            Factura__c          = factura.Id,
            Product__c          = prod.Id,
            Cantidad__c         = 2,
            Descripcion__c      = 'Descripción test',
            SKU__c              = 'SKU-001',
            Unidad_de_Medida__c = 'UN',
            Valor_Neto__c       = 1000,
            Peso_neto__c        = 5
        );
        insert detalle;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4: Constructor sin caseId → retorno temprano
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testConstructorNoCaseId() {
        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        // NO se agrega caseId

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(null, ctrl.caso,                   'caso debe ser null sin caseId');
        System.assertEquals(null, ctrl.detalleProductoFactura, 'detalleProductoFactura debe ser null');
        System.assertEquals(null, ctrl.supervisorName,         'supervisorName debe ser null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 5: isPreview con distintos valores de parámetro
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testIsPreviewFalseVariants() {
        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);

        // Valor diferente a 'true'
        ApexPages.currentPage().getParameters().put('preview', 'false');
        seidor_PDFController ctrl = new seidor_PDFController();
        System.assertEquals(false, ctrl.isPreview, 'isPreview debe ser false para valor "false"');

        // Valor null (sin parámetro)
        ApexPages.currentPage().getParameters().remove('preview');
        System.assertEquals(false, ctrl.isPreview, 'isPreview debe ser false cuando no hay parámetro');

        seidor_PDFController.getInt();
        Test.stopTest();

    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Constructor con caseId vÃ¡lido
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testConstructorWithCaseId() {
        Case testCase = [
            SELECT Id, Numero_Factura__c, AccountId, ProductId
            FROM Case
            LIMIT 1
        ];

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.caso, 'caso should be populated');
        System.assertEquals(testCase.Id, ctrl.caso.Id, 'caso.Id should match');
        System.assertNotEquals(null, ctrl.tipoRequerimiento, 'tipoRequerimiento should be set');
        System.assertNotEquals(null, ctrl.pdfFileName, 'pdfFileName should be set');
        System.assertNotEquals(null, ctrl.isDevolucion, 'isDevolucion should be set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: isPreview con valor true
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testIsPreviewTrue() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);
        ApexPages.currentPage().getParameters().put('preview', 'true');

        Test.startTest();
        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isPreview, 'isPreview debe ser true');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: DÃ­as cerrados
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testDiasCerrados() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        Test.startTest();
        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.getIsLunesCerrado(), 'Lunes deberÃ­a estar cerrado');
        System.assertEquals(true, ctrl.getIsMartesCerrado(), 'Martes deberÃ­a estar cerrado');
        System.assertEquals(false, ctrl.getIsMiercolesCerrado(), 'MiÃ©rcoles no deberÃ­a estar cerrado');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Constructor con download=true
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testConstructorWithDownload() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);
        ApexPages.currentPage().getParameters().put('download', 'true');

        Test.startTest();
        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.caso, 'caso should be populated');
        System.assertEquals(true, ctrl.isPreview == false, 'preview debe ser false por defecto');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Devoluciones con ProductId asignado → producto directo del Case
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testDevolucionesConProductId() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Product2 prod = [SELECT Id, Name FROM Product2 LIMIT 1];

        Case testCase = new Case(
            Subject = 'Devoluciones con producto',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            ProductId = prod.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Cantidad_reclamada__c = 5,
            UM_Unidad_de_Medida__c = 'KG',
            Valor_Neto__c = 25000,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Lunes'
        );
        insert testCase;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assertEquals(1, ctrl.detallesWrapper.size(), 'Debe haber 1 detalle (producto del Case)');
        System.assertEquals(5, ctrl.detallesWrapper[0].det.Cantidad__c, 'Cantidad debe ser la del Case');
        System.assertEquals(25000, ctrl.detallesWrapper[0].det.Valor_Neto__c, 'Valor Neto debe ser el del Case');
        System.assertEquals(25000, ctrl.totalValorNeto, 'Total debe ser el valor neto del Case');
        System.assertEquals('DEVOLUCIÓN', ctrl.tipoRequerimiento, 'tipoRequerimiento debe ser DEVOLUCIÓN');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Devoluciones con Factura (normal, no rechazo parcial)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testDevolucionesConFactura() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Facturas__c factura = [SELECT Id FROM Facturas__c LIMIT 1];
        Detalle_Factura__c detalle = [SELECT Id, Valor_Neto__c FROM Detalle_Factura__c LIMIT 1];

        Case testCase = new Case(
            Subject = 'Devoluciones con factura',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Factura__c = factura.Id,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Viernes'
        );
        insert testCase;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assert(ctrl.detallesWrapper.size() >= 1, 'Debe haber al menos 1 detalle de la factura');
        System.assertEquals(detalle.Valor_Neto__c, ctrl.detallesWrapper[0].det.Valor_Neto__c, 'Valor Neto debe ser el del detalle de factura');
        System.assertEquals(detalle.Valor_Neto__c, ctrl.totalValorNeto, 'Total debe coincidir con el valor del detalle');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Rechazo parcial (Categoria = Rechazo de pedido, Sub_Categoria = Rechazo parcial)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testRechazoParcial() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Facturas__c factura = [SELECT Id FROM Facturas__c LIMIT 1];

        Case testCase = new Case(
            Subject = 'Rechazo parcial',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Factura__c = factura.Id,
            Categoria__c = 'Rechazo de pedido',
            Sub_Categoria__c = 'Rechazo parcial',
            Cantidad_reclamada__c = 3,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Jueves'
        );
        insert testCase;

        Detalle_Factura__c detConReclamo = new Detalle_Factura__c(
            Factura__c          = factura.Id,
            Caso__c             = testCase.Id,
            Cantidad__c         = 3,
            Descripcion__c      = 'Detalle con reclamo',
            SKU__c              = 'SKU-RP-001',
            Unidad_de_Medida__c = 'UN',
            Valor_Neto__c       = 7500,
            Peso_neto__c        = 10,
            Proceso_de_reclamo__c = true
        );
        insert detConReclamo;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assert(ctrl.detallesWrapper.size() >= 1, 'Debe haber al menos 1 detalle con Proceso_de_reclamo__c = true y Caso__c del caso');
        System.assertEquals(detConReclamo.Valor_Neto__c, ctrl.detallesWrapper[0].det.Valor_Neto__c, 'Valor Neto debe ser el del detalle de la factura');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Rechazo parcial con Cantidad__c vacío en el detalle → fallback a Cantidad_reclamada__c del Case
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testRechazoParcialCantidadFallback() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Facturas__c factura = [SELECT Id FROM Facturas__c LIMIT 1];

        Case testCase = new Case(
            Subject = 'Rechazo parcial sin cantidad',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Factura__c = factura.Id,
            Categoria__c = 'Rechazo de pedido',
            Sub_Categoria__c = 'Rechazo parcial',
            Cantidad_reclamada__c = 7,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Jueves'
        );
        insert testCase;

        Detalle_Factura__c detConReclamo = new Detalle_Factura__c(
            Factura__c          = factura.Id,
            Caso__c             = testCase.Id,
            Cantidad__c         = null,
            Descripcion__c      = 'Detalle sin cantidad',
            SKU__c              = 'SKU-RP-002',
            Unidad_de_Medida__c = 'UN',
            Valor_Neto__c       = 9000,
            Peso_neto__c        = 10,
            Proceso_de_reclamo__c = true
        );
        insert detConReclamo;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assert(ctrl.detallesWrapper.size() >= 1, 'Debe haber al menos 1 detalle');
        System.assertEquals(7, ctrl.detallesWrapper[0].det.Cantidad__c, 'Cantidad vacía debe tomar Cantidad_reclamada__c del Case');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Rechazo parcial lee Cantidad__c del Detalle_Factura__c (no del Case)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testRechazoParcialCantidadDesdeDetalle() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Facturas__c factura = [SELECT Id FROM Facturas__c LIMIT 1];

        Case testCase = new Case(
            Subject = 'Rechazo parcial',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Factura__c = factura.Id,
            Categoria__c = 'Rechazo de pedido',
            Sub_Categoria__c = 'Rechazo parcial',
            Cantidad_reclamada__c = 99,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Jueves'
        );
        insert testCase;

        // Detalle de factura vinculado al Case: el rechazo parcial debe leer
        // su Cantidad__c directo desde el Detalle_Factura__c.
        Detalle_Factura__c detConReclamo = new Detalle_Factura__c(
            Factura__c          = factura.Id,
            Caso__c             = testCase.Id,
            Cantidad__c         = 11,
            Descripcion__c      = 'Detalle con reclamo',
            SKU__c              = 'SKU-RP-003',
            Unidad_de_Medida__c = 'UN',
            Valor_Neto__c       = 5000,
            Peso_neto__c        = 10,
            Proceso_de_reclamo__c = true
        );
        insert detConReclamo;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assert(ctrl.detallesWrapper.size() >= 1, 'Debe traer el detalle de la factura con Proceso_de_reclamo__c = true');
        System.assertEquals(11, ctrl.detallesWrapper[0].det.Cantidad__c, 'Cantidad debe venir del Cantidad__c del Detalle_Factura__c, no del Case');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Rechazo parcial con UN SOLO ProductId asignado al Case → pese a tener
    // producto directo, la Cantidad debe salir del Detalle_Factura__c (no del Case)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testRechazoParcialUnSoloProducto() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Facturas__c factura = [SELECT Id FROM Facturas__c LIMIT 1];
        Product2 prod = [SELECT Id, Name FROM Product2 LIMIT 1];

        Case testCase = new Case(
            Subject = 'Rechazo parcial un solo producto',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            ProductId = prod.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Factura__c = factura.Id,
            Categoria__c = 'Rechazo de pedido',
            Sub_Categoria__c = 'Rechazo parcial',
            Cantidad_reclamada__c = 55,
            UM_Unidad_de_Medida__c = 'XX',
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Jueves'
        );
        insert testCase;

        // Detalle de factura del MISMO producto con Cantidad__c real.
        Detalle_Factura__c detConReclamo = new Detalle_Factura__c(
            Factura__c          = factura.Id,
            Caso__c             = testCase.Id,
            Product__c          = prod.Id,
            Cantidad__c         = 18,
            Descripcion__c      = 'Detalle con reclamo',
            SKU__c              = 'SKU-RP-UNO',
            Unidad_de_Medida__c = 'UN',
            Valor_Neto__c       = 6000,
            Peso_neto__c        = 10,
            Proceso_de_reclamo__c = true
        );
        insert detConReclamo;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assert(ctrl.detallesWrapper.size() >= 1, 'Debe traer el detalle de la factura con Proceso_de_reclamo__c = true');
        System.assertEquals(18, ctrl.detallesWrapper[0].det.Cantidad__c, 'Cantidad debe venir del Cantidad__c del Detalle_Factura__c a pesar de que el Case tenga ProductId');
        System.assertEquals(6000, ctrl.detallesWrapper[0].det.Valor_Neto__c, 'Valor Neto debe venir del Detalle_Factura__c');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST: Devoluciones sin Factura__c → fallback por Numero_Factura__c + ProductId
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testDevolucionesSinFactura() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        Case testCase = new Case(
            Subject = 'Devoluciones sin factura',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            ProductId = prod.Id,
            Tipo_de_Requerimiento__c = 'Devoluciones',
            Numero_Factura__c = 'NUM-001',
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2',
            Dias_cerrados__c = 'Sábado'
        );
        insert testCase;

        Test.startTest();
        PageReference pageRef = Page.ReclamoCalidadPDFController;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('caseId', testCase.Id);

        seidor_PDFController ctrl = new seidor_PDFController();
        Test.stopTest();

        System.assertEquals(true, ctrl.isDevolucion, 'isDevolucion debe ser true');
        System.assert(ctrl.detallesWrapper.size() >= 1, 'Debe encontrar detalles por Numero_Factura__c + ProductId');
        System.assertNotEquals(null, ctrl.totalValorNeto, 'totalValorNeto debe estar calculado');
    }
}