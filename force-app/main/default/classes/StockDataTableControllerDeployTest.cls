@isTest
private class StockDataTableControllerDeployTest {
    private class ItemStockMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(getMockResponse());
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        Product2 product = new Product2(
            Name = 'Test Product',
            ProductCode = 'P-001',
            IsActive = true
        );
        product.put('Codigo__c', 'P-001');
        insert product;

        Web_Service_Config__c conf = new Web_Service_Config__c();
        conf.Name = 'Configuration';
        conf.URL__c = 'https://example.com';
        conf.Token__c = 'dGVzdDp0b2tlbg==';
        conf.Test__c = true;
        if (
            Web_Service_Config__c.SObjectType
                .getDescribe()
                .fields
                .getMap()
                .containsKey('Codigo__c')
        ) {
            conf.put('Codigo__c', 'CFG-001');
        }
        insert conf;
    }

    @isTest
    static void testControllerInitAndFilter() {
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new ItemStockMock());

        Test.startTest();
        ApexPages.currentPage().getParameters().put('id', product.Id);
        ApexPages.StandardController std = new ApexPages.StandardController(product);
        StockDataTableController controller = new StockDataTableController(std);
        Test.stopTest();

        System.assertNotEquals(null, controller.actualStock);
        System.assertEquals(1, controller.actualStock.size());
        System.assertEquals('TEST_MAQUITEC', controller.actualStock[0].nombreAlmacen);
    }

    @isTest
    static void testGetItemStockDataAndHelper() {
        Product2 product = [
            SELECT Id, ProductCode, (SELECT Id, Name, Producto__c FROM Stocks__r)
            FROM Product2
            LIMIT 1
        ];

        Stock__c existingStock = new Stock__c();
        existingStock.Name = 'TEST_MAQUITEC';
        existingStock.Producto__c = product.Id;
        existingStock.CCP__c = 0;
        insert existingStock;

        product = [
            SELECT Id, ProductCode, (SELECT Id, Name, Producto__c FROM Stocks__r)
            FROM Product2
            LIMIT 1
        ];

        Test.setMock(HttpCalloutMock.class, new ItemStockMock());

        Test.startTest();
        WSGetItemStock service = new WSGetItemStock();
        Boolean ok = service.callForStock(product.Id);
        List<Stock__c> updatedStock = WSGetItemStock.getItemStockData(product, product.ProductCode);
        Test.stopTest();

        System.assertEquals(true, ok);
        System.assertNotEquals(null, updatedStock);
        System.assert(updatedStock.size() > 0);

        MultiStockResponse parsed = MultiStockResponse.parse(getMockResponse());
        List<MultiStockResponse.Stock> flatStock = WSGetItemStockHelper.getFlatCurrentStock(parsed);
        System.assert(flatStock.size() > 0);

        Map<String, Stock__c> stockMap = new Map<String, Stock__c>();
        stockMap.put('CCP', existingStock);
        List<Stock__c> matched = WSGetItemStockHelper.matchStock(product.Id, stockMap, flatStock);
        System.assert(matched.size() > 0);
    }

    private static String getMockResponse() {
        return '{' +
            '"Databases":[' +
                '{"Database":{' +
                    '"Company":"TEST_MAQUITEC",' +
                    '"Stock":[' +
                        '{"WhsCode":"CCP","OnHand":"10.000000","IsCommited":"2.000000","OnOrder":"1.000000","Forecast":"3.000000"},' +
                        '{"WhsCode":"KNA","OnHand":"1.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"PMC","OnHand":"2.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"MHC","OnHand":"3.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"SCL","OnHand":"4.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"TLX","OnHand":"5.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"ZCO","OnHand":"6.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"ACHC","OnHand":"7.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"AEXT","OnHand":"8.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"ING","OnHand":"9.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"COY","OnHand":"10.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"YAI","OnHand":"11.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"SCVI","OnHand":"12.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"IMPT","OnHand":"13.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"TSCV-VM1","OnHand":"14.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"LSC","OnHand":"15.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"},' +
                        '{"WhsCode":"PUQ","OnHand":"16.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"}' +
                    ']' +
                '}},' +
                '{"Database":{' +
                    '"Company":"Z_TEST",' +
                    '"Stock":[' +
                        '{"WhsCode":"CCP","OnHand":"1.000000","IsCommited":"0.000000","OnOrder":"0.000000","Forecast":"1.000000"}' +
                    ']' +
                '}}' +
            ']' +
        '}';
    }
}