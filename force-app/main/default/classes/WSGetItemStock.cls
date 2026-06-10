/**
 * @description       :
 * @author            : JM
 * @group             :
 * @last modified on  : 24-09-2021
 * @last modified by  : JM
 **/
global inherited sharing class WSGetItemStock {
    public list<stock__c> stockToReturn = new List<Stock__c>();
    public list<almacen> stockTotalDeProductos = new list<almacen>();
    private static final String DB_EXCLUIDA = 'CORRECION_MONETARIA_SOLUEX_';
    /**
    * @description This constant holds the values from the custom setting list.
    * @author JM | 13-09-2021
    * @return Web_Service_Config__c
    **/
    private static final Web_Service_Config__c WS_CONF = Web_Service_Config__c.getValues(
        'Configuration'
    );

    /**
     * @description Entry point for call to SAP BLI web service to get items in stock.
     * @author Federico Rovere
     * @last modified on 13-09-2020 - JM
     * @param itemCode
     * @return Boolean
     **/
    public Boolean callForStock(string productCode){
        system.debug('productCode: ' + productCode);
        Product2 Producto = [SELECT id,ProductCode FROM Product2 WHERE id = :productCode];
        list<stock__c> ActualStock = [SELECT id,Name, CCP__c, PUG__c, KNA__c, PMC__c, SCL__c, TLX__c, ZCO__c,ACHC__c,AEXT__c, Stock_pedido__c, SCL_Stock_Pedido__c, LIM_Stock_Pedido__c, ING__c,COY__c,YAI__c,MHC__c,TSCV_VM1__C,LSC__c
                                        FROM stock__c 
                                        WHERE Producto__c = :productCode];
        list<Stock__c> stockToUpsert =  new list<Stock__c>();
        system.debug('Producto: ' + Producto);
        try {
            // Setting request
            system.debug('wsConfig: ' + WS_CONF );
            String url =
                WS_CONF.URL__c +
                '?wsaction=MULTISTOCK' +
                '&Test=' +
                String.valueOf(WS_CONF.Test__c) +
                '&ItemCode=' +
                Producto.ProductCode;
            String auth = 'Basic ' + WS_CONF.Token__c;
            
            system.debug('url: ' + url);
            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('GET');
            req.setHeader('Authorization', auth); // We're not using named credentials because the url does not use HTTPS and HTTP Basic Auth is not supported by Salesforce.
            req.setHeader('Content-Type', 'application/json');
            
            system.debug('req: ' + req);
            
            HttpResponse res = new Http().send(req);
            system.debug('RES Status: ' + res.getStatusCode());
            if(res.getStatusCode() == 200){
                system.debug('res.getBody: ' + res.getBody());
                WsStockResponse ParsedResponse = (WsStockResponse) JSON.deserializeStrict(res.getBody(), WsStockResponse.class);
                system.debug('ParsedResponse: ' + ParsedResponse);
                for(Databases dbs : ParsedResponse.Databases){
                    boolean Exist = false;
                    almacen nuevoAlmacen = new almacen();
                    nuevoAlmacen.nombreAlmacen = dbs.Database.Company;
                    for(stock__c stock : ActualStock)
                    {
                        if(stock.Name == dbs.Database.Company){
                            Exist = true;
                            for (Stock ST : dbs.Database.Stock) {
                                string Forecast = ST.Forecast;
                            	nuevoAlmacen.FORECAST = Forecast.substringBefore('.');
                                system.debug('ST.WhsCode: '+ST.WhsCode);
                                
                                switch on ST.WhsCode {
                                    when  'CCP'{
                                        stock.CCP__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.CCP = stOnHand.substringBefore('.');
                                    }
                                    when  'KNA'{
                                        stock.KNA__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.KNA = stOnHand.substringBefore('.');
                                    }
                                    when  'PMC'{
                                        stock.PMC__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.PMC = stOnHand.substringBefore('.');
                                    }
                                    when  'MHC'{
                                        stock.MHC__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.MHC = stOnHand.substringBefore('.');
                                    }
                                    when  'SCL'{
                                        stock.SCL__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.SCL = stOnHand.substringBefore('.');
                                        //stock.SCL_Stock_Pedido__c = integer.valueOf(ST.OnOrder);
                                    }
                                    when  'TLX'{
                                        stock.TLX__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.TLX = stOnHand.substringBefore('.');
                                    }
                                    when  'ZCO'{
                                        stock.ZCO__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.ZCO = stOnHand.substringBefore('.');
                                    }
                                    when  'ACHC'{
                                        stock.ACHC__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.ACHC = stOnHand.substringBefore('.');
                                    }
                                    when  'AEXT'{
                                        stock.AEXT__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.AEXT = stOnHand.substringBefore('.');
                                    }
                                    when  'ING'{
                                        stock.ING__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.ING = stOnHand.substringBefore('.');
                                    }
                                    when  'COY'{
                                        stock.COY__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.COY = stOnHand.substringBefore('.');
                                    }
                                    when  'YAI'{
                                        stock.YAI__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.YAI = stOnHand.substringBefore('.');
                                    }
                                    when  'SCVI'{
                                        //stock.MHC__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.SCVI = stOnHand.substringBefore('.');
                                    }
                                    when 'IMPT'{
                                        stock.IMPT__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.IMPT = stOnHand.substringBefore('.');
                                    }
                                    
                                    when 'TSCV-VM1'{
                                        stock.TSCV_VM1__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.IMPT = stOnHand.substringBefore('.');
                                    }
                                    when  'LSC'{
                                        stock.LSC__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.CCP = stOnHand.substringBefore('.');
                                    }
                                    when  'PUQ'{
                                        stock.PUG__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.PUQ = stOnHand.substringBefore('.');
                                    }
                                }
                            }
                            stockToUpsert.add(stock);
                        }
                    }
                    
                    if(Exist == false){
                        system.debug('Exist False');
                        stock__c newStock = new stock__c();
                        newStock.name = dbs.Database.Company;
                        newStock.Producto__c = Producto.Id;
                        for (Stock ST : dbs.Database.Stock) {
                            string Forecast = ST.Forecast;
                            system.debug('ST.WhsCode: '+ST.WhsCode);
                            nuevoAlmacen.FORECAST = Forecast.substringBefore('.');
                            switch on ST.WhsCode {
                                when  'CCP'{
                                    newStock.CCP__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.CCP = stOnHand.substringBefore('.');
                                }
                                when  'KNA'{
                                    newStock.KNA__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.KNA = stOnHand.substringBefore('.');
                                }
                                when  'PMC'{
                                    newStock.PMC__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.PMC = stOnHand.substringBefore('.');
                                }
                                when  'MHC'{
                                    newStock.MHC__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.MHC = stOnHand.substringBefore('.');
                                }
                                when  'SCL'{
                                    newStock.SCL__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.SCL = stOnHand.substringBefore('.');
                                    //newStock.SCL_Stock_Pedido__c = decimal.valueOf(ST.OnOrder);
                                }
                                when  'TLX'{
                                    newStock.TLX__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.TLX = stOnHand.substringBefore('.');
                                }
                                when  'ZCO'{
                                    newStock.ZCO__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.ZCO = stOnHand.substringBefore('.');
                                }
                                when  'ACHC'{
                                    newStock.ACHC__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.ACHC = stOnHand.substringBefore('.');
                                }
                                when  'AEXT'{
                                    newStock.AEXT__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.AEXT = stOnHand.substringBefore('.');
                                }
                                when  'ING'{
                                    newStock.ING__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.ING = stOnHand.substringBefore('.');
                                }
                                when  'COY'{
                                    newStock.COY__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.COY = stOnHand.substringBefore('.');
                                }
                                when  'YAI'{
                                    newStock.YAI__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.YAI = stOnHand.substringBefore('.');
                                }
                                when  'SCVI'{
                                        //stock.MHC__c = decimal.valueOf(ST.OnHand);
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.SCVI = stOnHand.substringBefore('.');
                                    }
                                when 'IMPT'{
                                    newStock.IMPT__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.IMPT = stOnHand.substringBefore('.');
                                }
                                when 'PUQ'{
                                    newStock.PUG__c = decimal.valueOf(ST.OnHand);
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.PUQ = stOnHand.substringBefore('.');
                                
                                }
                                when 'TSCV-VM1'{
                                    string stOnHand = ST.OnHand;
                                    nuevoAlmacen.IMPT = stOnHand.substringBefore('.');
                                }
                                when  'LSC'{
                                        string stOnHand = ST.OnHand;
                                        nuevoAlmacen.LSC = stOnHand.substringBefore('.');
                                    }
                                
                            }
                        }
                        stockToUpsert.add(newStock);
                    }
                    stockTotalDeProductos.add(nuevoAlmacen);
                }
            }
            System.debug('stockToUpsert: ' + stockToUpsert);
            //UPSERT stockToUpsert;
            stockToReturn.clear();
            stockToReturn = stockToUpsert;
            stockToUpsert.clear();
            return true;
        }
            catch (Exception e){
                system.debug(e.getMessage());
                system.debug(e.getTypeName());
                return false;
            }
    }
    private static Boolean isVisibleDatabaseName(String databaseName) {
        if (String.isBlank(databaseName)) {
            return false;
        }

        String normalizedName = databaseName.trim().toUpperCase();
        if (normalizedName.startsWith('Z')) {
            return false;
        }

        if (
            normalizedName == DB_EXCLUIDA ||
            normalizedName.startsWith('CORRECION_MONETARIA_SOLUEX')
        ) {
            return false;
        }

        return true;
    }

    public List<almacen> getActualStock(){
        List<almacen> filteredStock = new List<almacen>();
        for (almacen warehouse : stockTotalDeProductos) {
            if (warehouse != null && isVisibleDatabaseName(warehouse.nombreAlmacen)) {
                filteredStock.add(warehouse);
            }
        }
        return filteredStock;
    }
    
    webService static Boolean getItemStock(String itemCode) {
        Product2 itemQry = [
            SELECT
                Id,
                (
                    SELECT
                        Name,
                        Producto__c,
                        Stock__c,
                        Stock_comprometido__c,
                        SAP_Database__c
                    FROM Stocks__r
                )
            FROM Product2
            WHERE ProductCode = :itemCode // This field is indexed, so this query always return 1 row.
            WITH SECURITY_ENFORCED
        ];
        
        if (itemQry == null) {
            return false;
        }

        // Call the WebService
        List<Stock__c> updatedStock = getItemStockData(itemQry, itemCode);
        if (updatedStock.isEmpty()) {
            return false;
        }
        System.debug('Updated stock: ' + updatedStock);
        upsert Security.stripInaccessible(AccessType.UPSERTABLE, updatedStock)
            .getRecords();
        return true;
    }

    /**
     * @description
     * @author Federico Rovere
     * @last modified on 13-09-2021 - by JM
     * @param item ->  context Product2
     * @param itemCode ->  ProductCode for list of stock in databases
     * @return List<Stock__c> -> Currently available stock
     **/
    
    @SuppressWarnings('PMD.ApexSuggestUsingNamedCred')

    public static List<Stock__c> getItemStockData(Product2 item,String itemCode) {
        try {
            // Setting request
            String url =
                WS_CONF.URL__c +
                '?wsaction=MULTISTOCK' +
                '&Test=' +
                String.valueOf(WS_CONF.Test__c) +
                '&ItemCode=' +
                itemCode;
            String auth = 'Basic ' + WS_CONF.Token__c;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('GET');
            req.setHeader('Authorization', auth); // We're not using named credentials because the url does not use HTTPS and HTTP Basic Auth is not supported by Salesforce.
            req.setHeader('Content-Type', 'application/json');
            HttpResponse res = new Http().send(req);
            
            if (res.getStatusCode() == 200) {
                
                MultiStockResponse stockInSAP = MultiStockResponse.parse(res.getBody());

                if (stockInSAP == null) {
                    return null;
                }
                // Get all the stock list from server together in a single list.
                List<MultiStockResponse.Stock> currentStock = WSGetItemStockHelper.getFlatCurrentStock(stockInSAP);

                Map<String, Stock__c> allItemStock = new Map<String, Stock__c>();
                for (Stock__c stockItem : item.Stocks__r) {
                    allItemStock.put(stockItem.Name, stockItem);
                }

                List<Stock__c> updatedStock = WSGetItemStockHelper.matchStock(
                    item.Id,
                    allItemStock,
                    currentStock
                );
                if (!updatedStock.isEmpty()) {
                    return updatedStock;
                }
            } else {
                System.debug(LoggingLevel.WARN, res.getStatusCode());
                System.debug(LoggingLevel.WARN, res.getBody());
            }
        } catch (Exception exc) {
            System.debug(LoggingLevel.ERROR, exc.getCause());
            System.debug(LoggingLevel.ERROR, exc.getMessage());
        }
        return null;
    }
    
    public class WsStockResponse{
        public list<Databases> Databases;
    }
    public class Databases{
        public Database Database;
    }
    public class Database{
        public string Company;
        public list<Stock> Stock;
    }
    public class Stock{
        public string WhsCode;
        public string OnHand;
        public string IsCommited;
        public string OnOrder; 
        public string Forecast;
    }

    public class almacen{
        almacen(){}
        public string nombreAlmacen {get;set;}
        public string CCP {get;set;}
        public string KNA {get;set;}
        public string PMC {get;set;}
        public string SCL {get;set;}
        public string TLX {get;set;}
        public string ZCO {get;set;}
        public string ACHC {get;set;}
        public string AEXT {get;set;}
        public string ING {get;set;}
        public string COY {get;set;}
        public string YAI {get;set;}
        public string MHC {get;set;}
        public string IMPT {get;set;}
        public string SCVI {get;set;}
        public string PUQ {get; set;}
        public string FORECAST {get;set;}
        public string TSCV_VM1 {get;set;}
        public string LSC {get;set;}
        
    }
}