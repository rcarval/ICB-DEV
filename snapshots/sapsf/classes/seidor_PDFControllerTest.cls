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

        // 7. Dirección de retiro (objeto personalizado — ajustar API Name si difiere)
        //    Si el objeto tiene otro API name en tu org, cámbialo aquí.
        //    Se asume que existe el objeto usado en el lookup Direccion_de_Retiro__c del Case.
        //    Si no existe ese objeto en sandbox, comenta este bloque y el campo en el Case.

        // 8. Caso principal (con N_FDR__c poblado → fdrNumber = '1')
        String facturaName = 'F-' + System.currentTimeMillis();
        Case c = new Case(
            Subject = 'Caso Test',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            ContactId = con.Id,
            ProductId = prod.Id,
            N_Factura__c = facturaName,
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2'
        );
        insert c;

        // 9. Factura (objeto padre de Detalle_Factura__c)
        //    Se asume que existe el objeto Factura__c con campo Name y lookup al Case.
        //    Ajustar API Names según tu org.
                // Crear Factura (simulada por Name)
        Facturas__c factura = new Facturas__c(
            // Name = facturaName,
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

        // 10. Detalle de factura
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
}