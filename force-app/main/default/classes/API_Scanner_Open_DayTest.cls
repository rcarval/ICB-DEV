@IsTest
private with sharing class API_Scanner_Open_DayTest {

    private static void habilitarCampaniaQR(Campaign camp) {
        Map<String, Schema.SObjectField> fields = Campaign.SObjectType.getDescribe().fields.getMap();
        if (fields.containsKey('QR_Activo__c') && fields.get('QR_Activo__c').getDescribe().isUpdateable()) {
            camp.put('QR_Activo__c', true);
            update camp;
        }
    }

    private static void autorizarStaffEnCampania(Id campaignId) {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey('QR_Evento_Usuario__c')) {
            return;
        }

        SObject staff = gd.get('QR_Evento_Usuario__c').newSObject();
        staff.put('Campaign__c', campaignId);
        staff.put('Usuario__c', UserInfo.getUserId());
        if (staff.getSObjectType().getDescribe().fields.getMap().containsKey('Activo__c')) {
            staff.put('Activo__c', true);
        }
        insert staff;
    }

    private static API_Scanner_Open_Day.ResponseBody runRequest(Map<String, Object> payload) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/scanner-open-day/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return API_Scanner_Open_Day.processRequest();
    }

    @IsTest
    static void tokenIsRequired() {
        Test.startTest();
        API_Scanner_Open_Day.ResponseBody resp = runRequest(new Map<String, Object>{
            'varToken' => null,
            'varAccion' => 'LOOKUP'
        });
        Test.stopTest();

        System.assertEquals('ERROR', resp.varResultado);
        System.assertEquals('Token es requerido', resp.varMensaje);
    }

    @IsTest
    static void tokenNotFoundReturnsError() {
        Test.startTest();
        API_Scanner_Open_Day.ResponseBody resp = runRequest(new Map<String, Object>{
            'varToken' => 'TOKEN_INEXISTENTE_123',
            'varAccion' => 'LOOKUP'
        });
        Test.stopTest();

        System.assertEquals('ERROR', resp.varResultado);
        System.assertNotEquals(null, resp.varMensaje);
    }

    @IsTest
    static void lookupAndScanWithContact() {
        Account acc = new Account(Name = 'Cuenta Test Scanner');
        insert acc;

        Contact c = new Contact(LastName = 'Contacto Scanner', Email = 'scanner@test.com', AccountId = acc.Id);
        insert c;

        Campaign camp = new Campaign(Name = 'Campaign Scanner Test', IsActive = true);
        insert camp;
        habilitarCampaniaQR(camp);
        autorizarStaffEnCampania(camp.Id);

        String token = 'TOKEN_SCANNER_TEST_001';
        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            ContactId = c.Id,
            Status = 'Sent',
            QR_Token__c = token
        );
        insert cm;

        Test.startTest();
        API_Scanner_Open_Day.ResponseBody lookupResp = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'LOOKUP'
        });
        API_Scanner_Open_Day.ResponseBody scanResp = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'SCAN'
        });
        Test.stopTest();

        System.assertEquals('OK', lookupResp.varResultado, 'LOOKUP mensaje: ' + lookupResp.varMensaje);
        System.assertEquals('Contacto Scanner', lookupResp.varNombre);
        System.assertEquals('scanner@test.com', lookupResp.varEmail);
        System.assertEquals('Cuenta Test Scanner', lookupResp.varEmpresa);
        System.assertEquals(camp.Name, lookupResp.varCampania);

        System.assertEquals('OK', scanResp.varResultado, 'SCAN mensaje: ' + scanResp.varMensaje);
        System.assertNotEquals(null, scanResp.varMensaje);

        List<QR_Scan__c> scans = [
            SELECT Id, Token__c, Resultado__c
            FROM QR_Scan__c
            WHERE CampaignMemberId__c = :cm.Id
        ];
        System.assert(!scans.isEmpty(), 'Debería crear un QR_Scan__c');
        System.assertEquals(token, scans[0].Token__c);
        System.assertEquals('OK', scans[0].Resultado__c);
    }

    @IsTest
    static void productoCreatesCatalogAndProduct() {
        Account acc = new Account(Name = 'Cuenta Producto Test');
        insert acc;

        Contact c = new Contact(LastName = 'Contacto Producto', Email = 'producto@test.com', AccountId = acc.Id);
        insert c;

        Campaign camp = new Campaign(Name = 'Campaign Producto Test', IsActive = true);
        insert camp;
        habilitarCampaniaQR(camp);
        autorizarStaffEnCampania(camp.Id);

        String token = 'TOKEN_PRODUCTO_TEST_001';
        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            ContactId = c.Id,
            Status = 'Sent',
            QR_Token__c = token
        );
        insert cm;

        Test.startTest();
        API_Scanner_Open_Day.ResponseBody resp = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'PRODUCTO',
            'varNombreOpp' => 'Test Producto',
            'varDetalle' => 'Detalle test',
            'varValor' => 1500
        });
        API_Scanner_Open_Day.ResponseBody resp2 = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'PRODUCTO',
            'varNombreOpp' => 'Test Producto 2',
            'varDetalle' => 'Detalle test 2',
            'varValor' => 2500
        });
        Test.stopTest();

        System.assertEquals('OK', resp.varResultado, 'PRODUCTO1 mensaje: ' + resp.varMensaje);
        System.assertEquals('OK', resp2.varResultado, 'PRODUCTO2 mensaje: ' + resp2.varMensaje);
        System.assertNotEquals(null, resp.varMensaje);
        System.assertNotEquals(null, resp.varOppId, 'Para contacto con cuenta debe crear oportunidad');

        Opportunity opp = [SELECT Id, Name, CampaignId FROM Opportunity WHERE Id = :resp.varOppId LIMIT 1];
        System.assertEquals(camp.Id, opp.CampaignId, 'La oportunidad debe quedar asociada a la campana');
        System.assertEquals('Test Producto - ' + camp.Name, opp.Name, 'El nombre debe ser nombre ingresado + campana');

        CampaignMember cmAfter = [SELECT QR_Catalogo_producto__c FROM CampaignMember WHERE Id = :cm.Id];
        System.assertNotEquals(null, cmAfter.QR_Catalogo_producto__c, 'Debe asociar catálogo al CampaignMember');

        Map<String, Schema.SObjectField> prodFields = ICBFS_QR_Producto__c.SObjectType.getDescribe().fields.getMap();
        List<String> prodSelectFields = new List<String>{ 'Id', 'Name', 'QR_Catalogo_producto__c' };
        if (prodFields.containsKey('Oportunidad__c')) {
            prodSelectFields.add('Oportunidad__c');
        } else if (prodFields.containsKey('Opportunity__c')) {
            prodSelectFields.add('Opportunity__c');
        }

        Id catalogoIdForProductos = cmAfter.QR_Catalogo_producto__c;
        List<SObject> productos = Database.query(
            'SELECT ' + String.join(prodSelectFields, ',') +
            ' FROM ICBFS_QR_Producto__c WHERE QR_Catalogo_producto__c = :catalogoIdForProductos'
        );
        System.assert(!productos.isEmpty(), 'Debe crear ICBFS_QR_Producto__c');

        Map<String, Schema.SObjectField> catFields = QR_Catalogo_productos__c.SObjectType.getDescribe().fields.getMap();
        List<String> selectFields = new List<String>{ 'Id' };
        if (catFields.containsKey('Campa_a__c')) selectFields.add('Campa_a__c');
        if (catFields.containsKey('Contacto__c')) selectFields.add('Contacto__c');
        if (catFields.containsKey('Cliente__c')) selectFields.add('Cliente__c');
        if (catFields.containsKey('Oportunidad__c')) selectFields.add('Oportunidad__c');
        if (catFields.containsKey('Valor_de_Catalogo__c')) {
            selectFields.add('Valor_de_Catalogo__c');
        } else if (catFields.containsKey('Valor_Catalogo__c')) {
            selectFields.add('Valor_Catalogo__c');
        }

        Id catalogoId = cmAfter.QR_Catalogo_producto__c;
        SObject catalogo = Database.query(
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM QR_Catalogo_productos__c WHERE Id = :catalogoId LIMIT 1'
        );

        if (catFields.containsKey('Campa_a__c')) {
            System.assertEquals(camp.Id, (Id) catalogo.get('Campa_a__c'));
        }
        if (catFields.containsKey('Contacto__c')) {
            System.assertEquals(c.Id, (Id) catalogo.get('Contacto__c'));
        }
        if (catFields.containsKey('Cliente__c')) {
            System.assertEquals(acc.Id, (Id) catalogo.get('Cliente__c'));
        }
        if (catFields.containsKey('Oportunidad__c')) {
            System.assertEquals(null, catalogo.get('Oportunidad__c'));
        }

        if (resp.varOppId != null) {
            if (prodFields.containsKey('Oportunidad__c')) {
                System.assertEquals((Id) resp.varOppId, (Id) productos[0].get('Oportunidad__c'));
            } else if (prodFields.containsKey('Opportunity__c')) {
                System.assertEquals((Id) resp.varOppId, (Id) productos[0].get('Opportunity__c'));
            }
        }

        String valorField = null;
        if (catFields.containsKey('Valor_de_Catalogo__c') && catFields.get('Valor_de_Catalogo__c').getDescribe().isUpdateable()) {
            valorField = 'Valor_de_Catalogo__c';
        } else if (catFields.containsKey('Valor_Catalogo__c') && catFields.get('Valor_Catalogo__c').getDescribe().isUpdateable()) {
            valorField = 'Valor_Catalogo__c';
        }
        if (valorField != null) {
            Decimal valorCatalogo = (Decimal) catalogo.get(valorField);
            System.assertEquals(4000, valorCatalogo, 'Debe acumular valor de catálogo');
        }
    }

    @IsTest
    static void productoWithLeadCreatesCatalogWithoutOpportunity() {
        Lead lead = new Lead(
            LastName = 'Lead Producto',
            Company = 'Empresa Lead Producto',
            Email = 'lead.producto@test.com'
        );
        insert lead;

        Campaign camp = new Campaign(Name = 'Campaign Producto Lead', IsActive = true);
        insert camp;
        habilitarCampaniaQR(camp);
        autorizarStaffEnCampania(camp.Id);

        String token = 'TOKEN_PRODUCTO_LEAD_001';
        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            LeadId = lead.Id,
            Status = 'Sent',
            QR_Token__c = token
        );
        insert cm;

        Test.startTest();
        API_Scanner_Open_Day.ResponseBody resp = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'PRODUCTO',
            'varNombreOpp' => 'Producto Lead',
            'varDetalle' => 'Detalle lead',
            'varValor' => 900
        });
        Test.stopTest();

        System.assertEquals('OK', resp.varResultado, 'PRODUCTO LEAD mensaje: ' + resp.varMensaje);
        System.assertEquals(null, resp.varOppId, 'Para lead/prospecto sin cuenta no debe crear oportunidad');

        CampaignMember cmAfter = [SELECT QR_Catalogo_producto__c FROM CampaignMember WHERE Id = :cm.Id];
        System.assertNotEquals(null, cmAfter.QR_Catalogo_producto__c);
    }

    @IsTest
    static void lookupAndScanWithAccountOnlyCampaignMember() {
        Account acc = new Account(Name = 'Cuenta Solo Account Scanner');
        insert acc;

        Campaign camp = new Campaign(Name = 'Campaign Account Only', IsActive = true);
        insert camp;
        habilitarCampaniaQR(camp);
        autorizarStaffEnCampania(camp.Id);

        String token = 'TOKEN_ACCOUNT_ONLY_001';
        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            AccountId = acc.Id,
            Status = 'Sent',
            QR_Token__c = token
        );
        insert cm;

        Test.startTest();
        API_Scanner_Open_Day.ResponseBody lookupResp = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'LOOKUP'
        });
        API_Scanner_Open_Day.ResponseBody scanResp = runRequest(new Map<String, Object>{
            'varToken' => token,
            'varAccion' => 'SCAN'
        });
        Test.stopTest();

        System.assertEquals('OK', lookupResp.varResultado, 'LOOKUP ACCOUNT mensaje: ' + lookupResp.varMensaje);
        System.assertEquals(acc.Name, lookupResp.varNombre);
        System.assertEquals(acc.Name, lookupResp.varEmpresa);

        System.assertEquals('OK', scanResp.varResultado, 'SCAN ACCOUNT mensaje: ' + scanResp.varMensaje);
    }
}