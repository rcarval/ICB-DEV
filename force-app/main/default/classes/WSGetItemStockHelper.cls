/**
 * @description       :
 * @author            : JM
 * @group             :
 * @last modified on  : 24-09-2021
 * @last modified by  : JM
 **/
public inherited sharing class WSGetItemStockHelper {
    
    
    public static List<Stock__c> matchStock(
        String idItem,
        Map<String, Stock__c> allItemStock,
        List<MultiStockResponse.Stock> currentStock
    ) {
        Set<Stock__c> stockList = new Set<Stock__c>();
        Stock__c stock;
        for (MultiStockResponse.Stock wsStock : currentStock) {
            if (allItemStock.containsKey(wsStock.WhsCode)) {
                stock = allItemStock.get(wsStock.WhsCode);
                stock.SAP_Database__c = wsStock.sapDatabase;
            } else {
                stock = new Stock__c();
                stock.Name = wsStock.WhsCode;
                stock.Producto__c = idItem;
                stock.SAP_Database__c = wsStock.sapDatabase;
            }
            if (String.isNotBlank(wsStock.OnHand)) {
                stock.Stock__c = Decimal.valueOf(wsStock.OnHand).intValue();
            } else {
                stock.Stock__c = 0;
            }
            if (String.isNotBlank(wsStock.IsCommited)) {
                stock.Stock_comprometido__c = Decimal.valueOf(
                        wsStock.IsCommited
                    )
                    .intValue();
            } else {
                stock.Stock_comprometido__c = 0;
            }

            if (String.isNotBlank(wsStock.OnOrder)) {
                stock.Stock_pedido__c = Decimal.valueOf(wsStock.OnOrder)
                    .intValue();
            } else {
                stock.Stock_pedido__c = 0;
            }
            //system.debug('stock in match: '+stock);
            stockList.add(stock);
        }

        return new List<Stock__c>(stockList);
    }

    /**
     * @description
     * @author JM | 09-09-2021
     * @last modified on 13-09-2021 - by JM
     * @param stockList -> Parsed Response from server
     * @return Map<String, List<StockDetail>> -> Map of database by list of products for later data handling.
     **/
    
    public static Map<String, List<MultiStockResponse.Stock>> mapStocksByDatabase(
        MultiStockResponse stockList
    ) {
        Map<String, List<MultiStockResponse.Stock>> stockByDatabaseName = new Map<String, List<MultiStockResponse.Stock>>();
        for (MultiStockResponse.Databases db : stocklist.Databases) {
            stockByDatabaseName.put(
                db.Database.Company,
                db.Database.Stock
            );
        }
        return stockByDatabaseName;
    }

    /**
     * @description Flat the map of stock by database to a single list
     * @author JM | 13-09-2021
     * @param stockInSAP response from server
     * @return List<MultiStockResponse.Stock> -> single List of stock in SAP
     **/
    
    public static List<MultiStockResponse.Stock> getFlatCurrentStock(
        MultiStockResponse stockInSAP
    ) {
        List<MultiStockResponse.Stock> currentStock = new List<MultiStockResponse.Stock>();

        Map<String, List<MultiStockResponse.Stock>> stockByDB = mapStocksByDatabase(
            stockInSAP
        );
        List<String> databaseNames = new List<String>(stockByDB.keySet());
        for (Integer i = 0; i < stockByDB.values().size(); i++) {
            if (stockByDB.containsKey(databaseNames[i])) {
                List<MultiStockResponse.Stock> currentListInIteration = stockByDB.get(databaseNames[i]);
                for (Integer j = 0; j < currentListInIteration.size(); j++) {
                    currentListInIteration[j].sapDatabase = databaseNames[i];
                    currentStock.add(currentListInIteration[j]);
                }
            }
        }

        return currentStock;
    }
    
    @AuraEnabled
    public static Boolean CallAPImethod(string recordId){
        system.debug('llego APEX');
        WSGetItemStock tempvar = new WSGetItemStock();
        return tempvar.callForStock(recordId);
          
    }
}