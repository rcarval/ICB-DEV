@IsTest
private class ContratoComodatoController_Test {

    @IsTest
    static void testLoadDataConMaquinaYAccesorios() {
        Account acc = new Account(
            Name = 'Cliente Contrato Test',
            RUT__c = '76086428-5',
            C_digo_de_cliente__c = 'FS99999',
            Nombre_de_Fantasia__c = 'Fantasia Test'
        );
        insert acc;

        Contact con = new Contact(
            LastName = 'Representante Test',
            AccountId = acc.Id,
            Email = 'representante@test.com',
            MobilePhone = '+56911111111',
            RUT__c = '11111111-1'
        );
        insert con;

        Contact contactoComercial = new Contact(
            LastName = 'Contacto Comercial Test',
            AccountId = acc.Id,
            Email = 'comercial@test.com',
            MobilePhone = '+56922222222',
            RUT__c = '22222222-2'
        );
        insert contactoComercial;

        Opportunity opp = new Opportunity(
            Name = 'Opp Contrato Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert opp;

        insert new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = con.Id,
            Role = 'Representante Legal',
            IsPrimary = true
        );
        insert new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contactoComercial.Id,
            Role = 'Contacto Comercial',
            IsPrimary = false
        );

        Product2 maquina = new Product2(
            Name = 'MAQUINA TEST CONTRATO',
            IsActive = true,
            Codigo__c = 'MQTESTCONTRATO',
            Capacidad_Sugerida__c = 'Baja',
            Metodologia__c = 'CAPSULA',
            Tag__c = 'Equipamiento',
            Precio_de_Lista__c = 500000
        );
        insert maquina;

        Product2 accesorio = new Product2(
            Name = 'CAPSULA TEST CONTRATO',
            IsActive = true,
            Codigo__c = 'CAPTESTCONTRATO'
        );
        insert accesorio;

        insert new Comodato__c(
            Maquina__c = maquina.Id,
            Producto_Asociado__c = accesorio.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 5,
            Unidad_de_Medida__c = 'Unidades',
            Precio_Unitario_Neto__c = 64000
        );

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = maquina.Id,
            UnitPrice = 0,
            IsActive = true
        );

        Quote q = new Quote(
            Name = 'Quote Contrato Test',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId
        );
        insert q;

        List<PricebookEntry> pbes = [SELECT Id FROM PricebookEntry WHERE Product2Id = :maquina.Id AND Pricebook2Id = :pricebookId LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbes[0].Id,
            Product2Id = maquina.Id,
            Quantity = 1,
            UnitPrice = 0
        );

        Test.setCurrentPage(Page.ContratoComodatoFinal);
        ApexPages.currentPage().getParameters().put('opportunityId', opp.Id);

        Test.startTest();
        ContratoComodatoController ctrl = new ContratoComodatoController();
        Test.stopTest();

        System.assertEquals(opp.Id, ctrl.opp.Id, 'Debe cargar la Opportunity');
        System.assertEquals(maquina.Id, ctrl.maquina.Id, 'Debe identificar la maquina por Capacidad_Sugerida__c');
        System.assertEquals(con.Id, ctrl.representanteLegal.Id, 'Debe encontrar al Representante Legal');
        System.assertEquals(contactoComercial.Id, ctrl.contactoComercial.Id, 'Debe separar el contacto comercial del representante legal');
        System.assertEquals(1, ctrl.lineasMaquina.size(), 'Debe incluir la maquina en su propia tabla');
        System.assertEquals(1, ctrl.lineasAccesorios.size(), 'Debe incluir 1 accesorio en su propia tabla');
        System.assertEquals(2, ctrl.lineasUbicacion.size(), 'Ubicacion debe incluir maquina + accesorio');
        System.assertEquals(1, ctrl.lineasCondicionesComerciales.size(), 'Debe incluir 1 condicion comercial (Insumo Mensual)');
        System.assertEquals('Revisión anual', ctrl.lineasCondicionesComerciales[0].politicaDePrecios, 'Debe traer politica de precios por defecto');
        System.assertEquals('No informado', ctrl.tipoDeNegocio, 'Sin Negocio_Gastronomico__c debe caer en el fallback');
        System.assertEquals('No informado', ctrl.direccionDespacho, 'Sin Negocio_Gastronomico__c debe caer en el fallback');
        System.assert(String.isNotBlank(ctrl.fechaContratoLarga), 'Debe formatear la fecha larga');
        System.assertEquals('Santiago', ctrl.ciudadContrato, 'Ciudad del contrato fija');
        System.assertEquals('77.965.620-9', ctrl.rutICB, 'RUT de ICB fijo');
    }

    @IsTest
    static void testLoadDataSinOpportunity() {
        Test.setCurrentPage(Page.ContratoComodatoFinal);
        ApexPages.currentPage().getParameters().put('opportunityId', '006000000000000AAA');

        Test.startTest();
        ContratoComodatoController ctrl = new ContratoComodatoController();
        Test.stopTest();

        System.assertEquals(null, ctrl.opp, 'No debe cargar Opportunity inexistente');
        System.assertEquals(0, ctrl.lineasMaquina.size(), 'No debe haber lineas sin Opportunity valida');
        System.assertEquals(0, ctrl.lineasAccesorios.size(), 'No debe haber lineas sin Opportunity valida');
    }
}