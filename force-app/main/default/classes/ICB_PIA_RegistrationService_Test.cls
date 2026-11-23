@IsTest
private class ICB_PIA_RegistrationService_Test {

    private class PIARegistrationMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        PIARegistrationMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setStatus(statusCode >= 200 && statusCode < 300 ? 'OK' : 'Error');
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        Comuna__c comuna = new Comuna__c(
            Name = 'PROVIDENCIA',
            Condici_n_de_expedici_n__c = 'SN',
            Incoterms__c = 'SN',
            Region__c = '13',
            RegionCompleta__c = '13 - Región Metropolitana'
        );
        insert comuna;

        Account acc = new Account(
            Name = 'Restaurante PIA Test',
            Email__c = 'pia.test@example.com',
            RUT__c = '11111111-1',
            BillingStreet = 'Av Providencia 1234',
            BillingCity = 'Santiago',
            ShippingStreet = 'Calle Despacho 987',
            ShippingCity = 'Quilpué',
            Region__c = '13 - Región Metropolitana',
            Comuna_Facturaci_n__c = comuna.Id,
            Nombre_de_contacto__c = 'Juan Perez',
            C_digo_de_cliente__c = 'FS34880',
            ShippingLatitude = -33.4489,
            ShippingLongitude = -70.6693,
            ICBFS_Numero__c = '1234'
        );
        insert acc;

        insert new Contact(
            LastName = 'Perez',
            FirstName = 'Juan',
            Email = 'pia.test@example.com',
            MobilePhone = '+56912345678',
            AccountId = acc.Id
        );
    }

    @IsTest
    static void registerAccount_success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String body = '{"id":"USR123","status":"email_verified","createdAt":"2026-06-10T12:00:00Z",' +
            '"requestFieldValues":{"business":{"id":"BC331","city":{"distributionCenter":"FS00","salesOffice":"S001"}}}}';
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(201, body));

        Test.startTest();
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(acc.Id, false);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Debe ser exitoso');
        System.assertEquals(ICB_PIA_RegistrationService.ESTADO_CREADO, result.estadoSolicitud);

        Account updated = [
            SELECT PIA_ID_Externo__c, PIA_Estado_Solicitud__c, PIA_Business_ID__c,
                   Centro_Distribucion__c, Oficina_Ventas__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals('USR123', updated.PIA_ID_Externo__c);
        System.assertEquals('BC331', updated.PIA_Business_ID__c);
        System.assertEquals('FS00', updated.Centro_Distribucion__c);
        System.assertEquals('S001', updated.Oficina_Ventas__c);
    }

    @IsTest
    static void registerAccount_duplicate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String body = '{"id":"USR999","status":"duplicate","message":"email already exists"}';
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(409, body));

        Test.startTest();
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(acc.Id, false);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(ICB_PIA_RegistrationService.ESTADO_DUPLICADO, result.estadoSolicitud);

        Account updated = [SELECT PIA_ID_Externo__c, PIA_Estado_Solicitud__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('USR999', updated.PIA_ID_Externo__c);
    }

    @IsTest
    static void registerAccount_duplicateWithoutId_requiresReconciliation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String body = '{"code":"BUSINESS_ALREADY_EXISTS","message":"The business already exists in the system."}';
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(400, body));

        Test.startTest();
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(acc.Id, false);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Un duplicado sin ID no puede marcarse exitoso');
        System.assertEquals(ICB_PIA_RegistrationService.ESTADO_DUPLICADO, result.estadoSolicitud);
        System.assert(result.mensaje.contains('no contiene ID'));

        Account updated = [
            SELECT PIA_ID_Externo__c, PIA_Estado_Solicitud__c, PIA_Error_Log__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(null, updated.PIA_ID_Externo__c);
        System.assertEquals(ICB_PIA_RegistrationService.ESTADO_DUPLICADO, updated.PIA_Estado_Solicitud__c);
        System.assert(updated.PIA_Error_Log__c.contains('conciliación manual'));
    }

    @IsTest
    static void registerAccount_httpError() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(500, '{"error":"internal"}'));

        Test.startTest();
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(acc.Id, false);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ICB_PIA_RegistrationService.ESTADO_ERROR, result.estadoSolicitud);

        Account updated = [SELECT PIA_Error_Log__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals(null, updated.PIA_Error_Log__c);
    }

    @IsTest
    static void registerAccount_idempotentWhenPiaIdExists() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        acc.PIA_ID_Externo__c = 'EXISTING123';
        acc.PIA_Estado_Solicitud__c = ICB_PIA_RegistrationService.ESTADO_CREADO;
        update acc;

        Test.startTest();
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(acc.Id, false);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assert(result.mensaje.contains('omite'), 'Debe omitir callout');
    }

    @IsTest
    static void registerAccount_withoutSapCode() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        acc.C_digo_de_cliente__c = null;
        update acc;

        Test.startTest();
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(acc.Id, false);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(ICB_PIA_RegistrationService.ESTADO_ERROR, result.estadoSolicitud);
    }

    @IsTest
    static void enqueueAction_queuesJob() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        ICB_PIA_RegistrationEnqueueAction.InvocableInput input =
            new ICB_PIA_RegistrationEnqueueAction.InvocableInput();
        input.accountId = acc.Id;

        Test.startTest();
        List<ICB_PIA_RegistrationEnqueueAction.InvocableOutput> outputs =
            ICB_PIA_RegistrationEnqueueAction.encolarRegistroPia(
                new List<ICB_PIA_RegistrationEnqueueAction.InvocableInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].queued);
    }

    @IsTest
    static void enqueueAction_invalidInput() {
        Test.startTest();
        List<ICB_PIA_RegistrationEnqueueAction.InvocableOutput> outputs =
            ICB_PIA_RegistrationEnqueueAction.encolarRegistroPia(
                new List<ICB_PIA_RegistrationEnqueueAction.InvocableInput>{
                    new ICB_PIA_RegistrationEnqueueAction.InvocableInput()
                }
            );
        Test.stopTest();

        System.assertEquals(false, outputs[0].queued);
    }

    @IsTest
    static void enqueueAction_blocksRequestAlreadyInProgress() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        update new Account(
            Id = acc.Id,
            PIA_Estado_Solicitud__c = ICB_PIA_RegistrationService.ESTADO_EN_PROCESO
        );

        ICB_PIA_RegistrationEnqueueAction.InvocableInput input =
            new ICB_PIA_RegistrationEnqueueAction.InvocableInput();
        input.accountId = acc.Id;

        Test.startTest();
        List<ICB_PIA_RegistrationEnqueueAction.InvocableOutput> outputs =
            ICB_PIA_RegistrationEnqueueAction.encolarRegistroPia(
                new List<ICB_PIA_RegistrationEnqueueAction.InvocableInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(false, outputs[0].queued);
        System.assert(outputs[0].mensaje.contains('en proceso'));
    }

    @IsTest
    static void enqueueAction_deduplicatesRepeatedAccountIds() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String body = '{"id":"USR888","status":"email_verified","createdAt":"2026-06-10T12:00:00Z"}';
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(200, body));

        ICB_PIA_RegistrationEnqueueAction.InvocableInput firstInput =
            new ICB_PIA_RegistrationEnqueueAction.InvocableInput();
        firstInput.accountId = acc.Id;
        ICB_PIA_RegistrationEnqueueAction.InvocableInput repeatedInput =
            new ICB_PIA_RegistrationEnqueueAction.InvocableInput();
        repeatedInput.accountId = acc.Id;

        Test.startTest();
        List<ICB_PIA_RegistrationEnqueueAction.InvocableOutput> outputs =
            ICB_PIA_RegistrationEnqueueAction.encolarRegistroPia(
                new List<ICB_PIA_RegistrationEnqueueAction.InvocableInput>{ firstInput, repeatedInput }
            );
        Test.stopTest();

        System.assertEquals(true, outputs[0].queued);
        System.assertEquals(false, outputs[1].queued);
        System.assert(outputs[1].mensaje.contains('ya fue considerada'));
    }

    @IsTest
    static void queueable_success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String body = '{"id":"USR777","status":"email_verified","createdAt":"2026-06-10T12:00:00Z"}';
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(200, body));

        Test.startTest();
        System.enqueueJob(new ICB_PIA_RegistrationQueueable(acc.Id, false));
        Test.stopTest();

        Account updated = [SELECT PIA_ID_Externo__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('USR777', updated.PIA_ID_Externo__c);
    }

    @IsTest
    static void flowAction_success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String body = '{"id":"USR777","status":"email_verified","createdAt":"2026-06-10T12:00:00Z"}';
        Test.setMock(HttpCalloutMock.class, new PIARegistrationMock(200, body));

        ICB_PIA_RegistrationFlowAction.InvocableInput input = new ICB_PIA_RegistrationFlowAction.InvocableInput();
        input.accountId = acc.Id;
        input.forceRetry = false;

        Test.startTest();
        List<ICB_PIA_RegistrationFlowAction.InvocableOutput> outputs =
            ICB_PIA_RegistrationFlowAction.registrarCuentaEnPia(new List<ICB_PIA_RegistrationFlowAction.InvocableInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].success);
    }

    @IsTest
    static void resolveCellphone_usesAccountPhoneWhenNoContact() {
        Account acc = [
            SELECT Id, Phone,
                   (SELECT Id, MobilePhone, Phone FROM Contacts LIMIT 1)
            FROM Account
            LIMIT 1
        ];
        Contact con = acc.Contacts[0];
        con.MobilePhone = null;
        con.Phone = null;
        update con;

        acc.Phone = '994908047';
        update new Account(Id = acc.Id, Phone = '994908047');

        acc = [
            SELECT Id, Phone,
                   (SELECT MobilePhone, Phone FROM Contacts LIMIT 1)
            FROM Account
            WHERE Id = :acc.Id
        ];

        String cellphone = ICB_PIA_RegistrationService.resolveCellphone(acc);
        System.assertEquals('+56994908047', cellphone);
    }

    @IsTest
    static void extractRegionId_normalizesLeadingZero() {
        Account region04 = new Account(Region__c = '04 - La Serena');
        Account region13 = new Account(Region__c = '13 - Región Metropolitana');

        System.assertEquals('4', ICB_PIA_RegistrationService.extractRegionId(region04));
        System.assertEquals('13', ICB_PIA_RegistrationService.extractRegionId(region13));
        System.assertEquals('04', ICB_PIA_RegistrationService.formatRegionIdForPia('4'));
        System.assertEquals('13', ICB_PIA_RegistrationService.formatRegionIdForPia('13'));
    }

    @IsTest
    static void buildRequestBody_containsB2bType() {
        Account acc = [
            SELECT Id, Name, Email__c, RUT__c, BillingStreet, ShippingStreet, ICBFS_Numero__c, Region__c,
                   ShippingLatitude, ShippingLongitude, BillingLatitude, BillingLongitude,
                   ICBFS_Latitud_Longitud__c, Latitud_y_Longitud_Facturacion__c,
                   Comuna_Facturaci_n__r.Name, Comuna_Facturaci_n__r.Region__c,
                   Nombre_de_contacto__c,
                   (SELECT FirstName, LastName, Email, MobilePhone, Phone FROM Contacts LIMIT 1)
            FROM Account
            LIMIT 1
        ];

        String body = ICB_PIA_RegistrationService.buildRequestBody(acc);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);

        System.assertEquals('b2b', parsed.get('type'));
        System.assertEquals('pia.test@example.com', parsed.get('email'));

        Map<String, Object> address = (Map<String, Object>) parsed.get('address');
        Map<String, Object> business = (Map<String, Object>) parsed.get('business');
        System.assertNotEquals(null, address.get('address'));
        System.assertNotEquals(null, address.get('coordinates'));
        System.assertNotEquals(null, business.get('address'));
        System.assertNotEquals(null, business.get('coordinates'));
        System.assertNotEquals(null, business.get('rut'));
        System.assertNotEquals(address.get('address'), business.get('address'),
            'address y business deben usar direcciones distintas cuando Billing y Shipping difieren');
    }
}