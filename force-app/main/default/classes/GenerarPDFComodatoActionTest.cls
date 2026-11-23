@IsTest
private class GenerarPDFComodatoActionTest {

    @IsTest
    static void testGeneratePDF_SinQuote() {
        Product2 machine = new Product2(Name='MAQUINA PDF TEST', ProductCode='TST-PDF-001', Codigo__c='TST-PDF-001', IsActive=true, Precio_de_Lista__c=500000);
        insert machine;

        Product2 servicio = new Product2(Name='SERVICIO PDF TEST', ProductCode='TST-SRV-001', Codigo__c='TST-SRV-001', IsActive=true, Precio_de_Lista__c=10000);
        insert servicio;

        Comodato__c comodato = new Comodato__c(
            Maquina__c              = machine.Id,
            Producto_Asociado__c    = servicio.Id,
            Tipo_de_Asociacion__c   = 'Servicio',
            Precio_Unitario_Neto__c = 50000,
            Cantidad_Minima_Mensual__c = 2
        );
        insert comodato;

        GenerarPDFComodatoAction.Input inp = new GenerarPDFComodatoAction.Input();
        inp.machineId = machine.Id;
        inp.quoteId   = null;

        Test.startTest();
        List<GenerarPDFComodatoAction.Output> results =
            GenerarPDFComodatoAction.generar(new List<GenerarPDFComodatoAction.Input>{ inp });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].contentDocumentId, 'Debe retornar el ContentDocumentId');
    }

    @IsTest
    static void testGeneratePDF_ConQuoteYServicios() {
        // Machine
        Product2 machine = new Product2(Name='MAQUINA FULL TEST', ProductCode='TST-FUL-001', Codigo__c='TST-FUL-001', IsActive=true, Precio_de_Lista__c=500000);
        insert machine;

        // Servicio
        Product2 servicio = new Product2(Name='SERVICIO FULL TEST', ProductCode='TST-FUL-002', Codigo__c='TST-FUL-002', IsActive=true, Precio_de_Lista__c=10000);
        insert servicio;

        // Comodato
        Comodato__c comodato = new Comodato__c(
            Maquina__c              = machine.Id,
            Producto_Asociado__c    = servicio.Id,
            Tipo_de_Asociacion__c   = 'Servicio',
            Precio_Unitario_Neto__c = 50000,
            Cantidad_Minima_Mensual__c = 3
        );
        insert comodato;

        // Pricebook
        Pricebook2 pb = new Pricebook2(Name='COMODATO TEST PB', IsActive=true);
        insert pb;

        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry stdPbe = new PricebookEntry(Pricebook2Id=stdPbId, Product2Id=servicio.Id, UnitPrice=10000, IsActive=true);
        insert stdPbe;

        PricebookEntry custPbe = new PricebookEntry(Pricebook2Id=pb.Id, Product2Id=servicio.Id, UnitPrice=10000, IsActive=true);
        insert custPbe;

        // Std PBE for machine too (needed by Quote)
        PricebookEntry stdPbeMachine = new PricebookEntry(Pricebook2Id=stdPbId, Product2Id=machine.Id, UnitPrice=0, IsActive=true);
        insert stdPbeMachine;

        // Account, Opportunity, Quote
        Account acc = new Account(Name='Test Comodato Account', RUT__c='11111111-1');
        insert acc;

        Opportunity opp = new Opportunity(Name='Test Opp Comodato', AccountId=acc.Id, StageName='Prospecting', CloseDate=Date.today(), Pricebook2Id=pb.Id);
        insert opp;

        Quote q = new Quote(Name='Test Quote Comodato', OpportunityId=opp.Id, Pricebook2Id=pb.Id, Status='Draft', QuoteAccountId=acc.Id);
        insert q;

        GenerarPDFComodatoAction.Input inp = new GenerarPDFComodatoAction.Input();
        inp.machineId = machine.Id;
        inp.quoteId   = q.Id;

        Test.startTest();
        List<GenerarPDFComodatoAction.Output> results =
            GenerarPDFComodatoAction.generar(new List<GenerarPDFComodatoAction.Input>{ inp });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].contentDocumentId);

        // Verificar ContentDocumentLink adjunto al Quote
        List<ContentDocumentLink> cdls = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id];
        System.assertEquals(1, cdls.size(), 'Debe haber un PDF adjunto al Quote');

        // Verificar QuoteLineItems de servicios
        List<QuoteLineItem> qlis = [SELECT Id, UnitPrice FROM QuoteLineItem WHERE QuoteId = :q.Id];
        System.assertEquals(1, qlis.size(), 'Debe crear 1 QLI de servicio');
        System.assertEquals(50000, qlis[0].UnitPrice, 'El precio debe venir de Comodato');
    }
}