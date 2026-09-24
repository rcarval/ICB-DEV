@IsTest
private class GenerarContratoComodatoAction_Test {

    private class UploadAndPutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'POST') {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{"success":true,"contratoId":"FD-CONTRATO-001","uploadUrl":"https://s3.mock.amazonaws.com/unsigned/FD-CONTRATO-001?X-Amz-...","expiresAt":"2025-01-28T15:45:00Z"}'
                );
            } else if (req.getMethod() == 'PUT') {
                res.setStatusCode(200);
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }

    private class UploadFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setStatus('503 Service Unavailable');
            res.setBody('{"success":false,"message":"Servicio de firma no disponible"}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Cliente Generar Contrato Test');
        insert acc;

        Contact con = new Contact(
            LastName = 'Representante Generar Test',
            AccountId = acc.Id,
            Email = 'generarcontrato@test.com',
            MobilePhone = '+56922222222',
            RUT__c = '22222222-2'
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Opp Generar Contrato Test',
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

        Product2 maquina = new Product2(
            Name = 'MAQUINA TEST GENERAR CONTRATO',
            IsActive = true,
            Codigo__c = 'MQGENCONTRATO',
            Capacidad_Sugerida__c = 'Baja',
            Metodologia__c = 'CAPSULA'
        );
        insert maquina;

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = maquina.Id,
            UnitPrice = 0,
            IsActive = true
        );

        Quote q = new Quote(
            Name = 'Quote Generar Contrato Test',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId
        );
        insert q;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :maquina.Id AND Pricebook2Id = :pricebookId LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maquina.Id,
            Quantity = 1,
            UnitPrice = 0
        );
    }

    @IsTest
    static void testGenerarYEnviar_Ok() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        GenerarContratoComodatoAction.Input input = new GenerarContratoComodatoAction.Input();
        input.opportunityId = opp.Id;

        Test.setMock(HttpCalloutMock.class, new UploadAndPutMock());

        Test.startTest();
        List<GenerarContratoComodatoAction.Output> outputs =
            GenerarContratoComodatoAction.generarYEnviar(new List<GenerarContratoComodatoAction.Input>{ input });
        Test.stopTest();

        System.assert(!outputs.isEmpty(), 'Debe devolver una salida');
        System.assertEquals(true, outputs[0].success, 'Debe generar y enviar correctamente');
        System.assertEquals(null, outputs[0].errorMessage, 'No debe traer error');
        System.assert(String.isNotBlank(outputs[0].pdfBase64), 'Debe exponer el PDF en memoria al Flow');
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion], 'No debe guardar el PDF en Archivos');
    }

    @IsTest
    static void testGenerarYEnviar_SinOpportunityId() {
        GenerarContratoComodatoAction.Input input = new GenerarContratoComodatoAction.Input();
        input.opportunityId = null;

        List<GenerarContratoComodatoAction.Output> outputs =
            GenerarContratoComodatoAction.generarYEnviar(new List<GenerarContratoComodatoAction.Input>{ input });

        System.assert(!outputs.isEmpty());
        System.assertEquals(false, outputs[0].success);
        System.assert(String.isNotBlank(outputs[0].errorMessage));
    }

    @IsTest
    static void testGenerarYEnviar_SinQuote() {
        Account acc = new Account(Name = 'Cliente Sin Quote');
        insert acc;
        Opportunity oppSinQuote = new Opportunity(
            Name = 'Opp Sin Quote',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert oppSinQuote;

        GenerarContratoComodatoAction.Input input = new GenerarContratoComodatoAction.Input();
        input.opportunityId = oppSinQuote.Id;

        List<GenerarContratoComodatoAction.Output> outputs =
            GenerarContratoComodatoAction.generarYEnviar(new List<GenerarContratoComodatoAction.Input>{ input });

        System.assert(!outputs.isEmpty());
        System.assertEquals(false, outputs[0].success);
        System.assert(outputs[0].errorMessage.contains('Presupuesto'));
    }

    @IsTest
    static void testGenerarYEnviar_FallaFirma_ConservaPdfParaDescarga() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        GenerarContratoComodatoAction.Input input = new GenerarContratoComodatoAction.Input();
        input.opportunityId = opp.Id;
        Test.setMock(HttpCalloutMock.class, new UploadFailureMock());

        Test.startTest();
        List<GenerarContratoComodatoAction.Output> outputs =
            GenerarContratoComodatoAction.generarYEnviar(new List<GenerarContratoComodatoAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success);
        System.assert(String.isNotBlank(outputs[0].errorMessage));
        System.assert(String.isNotBlank(outputs[0].pdfBase64), 'Debe exponer el PDF en memoria al Flow');
        System.assert(outputs[0].pdfFileName.endsWith('.pdf'), 'Debe conservar el nombre del PDF descargable');
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion], 'No debe guardar el PDF en Archivos');
    }
}