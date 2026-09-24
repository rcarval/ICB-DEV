/**
 * Verifica el registro del resultado del envio a SAP.
 *
 * Lo que motiva estos tests: el campo Ultimo_Error_SAP__c no distinguia si el problema venia
 * de Salesforce --un dato faltante, el envio nunca salio-- o de SAP --el servicio rechazo el
 * mensaje--. Ahora cada mensaje se etiqueta en el origen.
 */
@IsTest
private class ICB_ComodatoSapQueueable_Test {

    /**
     * SAP simulado. Distingue las dos llamadas del protocolo real: primero un GET que devuelve
     * el token CSRF y despues el POST con el contrato. Si el GET no trae el header
     * x-csrf-token, el cliente aborta antes de enviar nada.
     */
    private class MockSap implements HttpCalloutMock {
        private Integer codigo;
        private String cuerpo;
        MockSap(Integer codigo, String cuerpo) { this.codigo = codigo; this.cuerpo = cuerpo; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setHeader('x-csrf-token', 'token-de-prueba');
                res.setBody('{}');
                return res;
            }
            res.setStatusCode(codigo);
            res.setBody(cuerpo);
            return res;
        }
    }

    /**
     * Escenario minimo que el builder acepta.
     *
     * @param completo false deja la Quote sin lineas, para forzar la validacion de Salesforce.
     */
    private static Contrato_Digital__c montar(Boolean completo) {
        Account cta = new Account(
            Name = 'CLIENTE SAP Q TEST',
            C_digo_de_cliente__c = '1000123',
            Cliente_Despacho__c = '1000123',
            // El flow FlowBeforeAPI_Insert deriva Sucursal__c de este campo; sin el, el insert
            // muere con INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST.
            SucursalAuxiliar__c = 'S001',
            Sucursal__c = 'S001 - Suc Santiago'
        );
        insert cta;

        Product2 maq = new Product2(Name = 'MAQUINA Q TEST', Codigo__c = '40002159',
                                    IsActive = true, Visible_For_Sales__c = true,
                                    Tipo_Equipo__c = 'Máquina Café');
        Product2 ins = new Product2(Name = 'CAPSULA Q TEST', Codigo__c = 'INS-Q-1',
                                    IsActive = true, Visible_For_Sales__c = true);
        insert new List<Product2>{ maq, ins };

        insert new Comodato__c(
            Maquina__c = maq.Id, Producto_Asociado__c = ins.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 5, Unidad_de_Medida__c = 'Unidades',
            Precio_Unitario_Neto__c = 8000
        );

        Id std = Test.getStandardPricebookId();
        List<PricebookEntry> enStd = new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = std, Product2Id = maq.Id,
                               UnitPrice = 1000, IsActive = true),
            new PricebookEntry(Pricebook2Id = std, Product2Id = ins.Id,
                               UnitPrice = 1000, IsActive = true)
        };
        insert enStd;

        Pricebook2 comodato = new Pricebook2(Name = 'COMODATO', IsActive = true);
        insert comodato;
        insert new PricebookEntry(Pricebook2Id = comodato.Id, Product2Id = maq.Id,
                                  UnitPrice = 210000, IsActive = true, UseStandardPrice = false);

        Opportunity opp = new Opportunity(
            Name = 'OPP Q TEST', AccountId = cta.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), Pricebook2Id = std
        );
        insert opp;

        Quote q = new Quote(Name = 'QUOTE Q TEST', OpportunityId = opp.Id, Pricebook2Id = std);
        insert q;
        if (completo) {
            insert new List<QuoteLineItem>{
                new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[0].Id,
                                  Quantity = 1, UnitPrice = 0),
                new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[1].Id,
                                  Quantity = 24, UnitPrice = 8000)
            };
        }

        Contrato_Digital__c cd = new Contrato_Digital__c(
            Presupuesto__c = q.Id, Oportunidad__c = opp.Id,
            Contrato_ID__c = 'FD-00000619', Fecha_Firma__c = System.now(),
            PDF_Firmado_URL__c = 's3://icbfs-documents/signed/FD-00000619/test.pdf'
        );
        insert cd;
        return cd;
    }

    private static Contrato_Digital__c leer(Id cdId) {
        return [SELECT Estado_Envio_SAP__c, Ultimo_Error_SAP__c, Codigo_HTTP_SAP__c,
                       Intentos_Envio_SAP__c
                FROM Contrato_Digital__c WHERE Id = :cdId];
    }

    @IsTest
    static void unEnvioAceptadoQuedaSinError() {
        Contrato_Digital__c cd = montar(true);

        Test.setMock(HttpCalloutMock.class, new MockSap(200, '{"ok":true}'));
        Test.startTest();
        System.enqueueJob(new ICB_ComodatoSapQueueable(cd.Id));
        Test.stopTest();

        Contrato_Digital__c r = leer(cd.Id);
        System.assertEquals('Enviado', r.Estado_Envio_SAP__c);
        System.assertEquals(null, r.Ultimo_Error_SAP__c, 'Un envio aceptado no deja error.');
        System.assertEquals(1, r.Intentos_Envio_SAP__c);
    }

    @IsTest
    static void unRechazoDeSapSeEtiquetaComoSAP() {
        Contrato_Digital__c cd = montar(true);

        Test.setMock(HttpCalloutMock.class, new MockSap(500, 'contrato duplicado'));
        Test.startTest();
        System.enqueueJob(new ICB_ComodatoSapQueueable(cd.Id));
        Test.stopTest();

        Contrato_Digital__c r = leer(cd.Id);
        System.assertEquals('Error', r.Estado_Envio_SAP__c);
        System.assert(r.Ultimo_Error_SAP__c.startsWith('[SAP]'),
            'Debe quedar claro que el rechazo es de SAP. Fue: ' + r.Ultimo_Error_SAP__c);
        System.assert(r.Ultimo_Error_SAP__c.contains('500'), 'Y traer el codigo HTTP.');
        System.assert(r.Ultimo_Error_SAP__c.contains('contrato duplicado'),
            'Y la respuesta del servicio, que es lo que permite entender el rechazo.');
        System.assertEquals(500, r.Codigo_HTTP_SAP__c);
    }

    @IsTest
    static void unDatoFaltanteSeEtiquetaComoSALESFORCE() {
        Contrato_Digital__c cd = montar(false);   // Quote sin lineas

        Test.setMock(HttpCalloutMock.class, new MockSap(200, '{"ok":true}'));
        Test.startTest();
        System.enqueueJob(new ICB_ComodatoSapQueueable(cd.Id));
        Test.stopTest();

        Contrato_Digital__c r = leer(cd.Id);
        System.assertEquals('Error', r.Estado_Envio_SAP__c);
        System.assert(r.Ultimo_Error_SAP__c.startsWith('[SALESFORCE]'),
            'El envio no salio del org: el problema es nuestro, no de SAP. Fue: '
            + r.Ultimo_Error_SAP__c);
        System.assertEquals(null, r.Codigo_HTTP_SAP__c,
            'Sin llamada no hay codigo HTTP que registrar.');
    }

    @IsTest
    static void noReenviaLoQueYaFueEnviado() {
        Contrato_Digital__c cd = montar(true);
        update new Contrato_Digital__c(Id = cd.Id, Estado_Envio_SAP__c = 'Enviado',
                                       Intentos_Envio_SAP__c = 1);

        Test.setMock(HttpCalloutMock.class, new MockSap(500, 'no deberia llamarse'));
        Test.startTest();
        System.enqueueJob(new ICB_ComodatoSapQueueable(cd.Id));
        Test.stopTest();

        Contrato_Digital__c r = leer(cd.Id);
        System.assertEquals('Enviado', r.Estado_Envio_SAP__c, 'No debe pisar un envio exitoso.');
        System.assertEquals(1, r.Intentos_Envio_SAP__c, 'Ni contar un intento nuevo.');
    }
}