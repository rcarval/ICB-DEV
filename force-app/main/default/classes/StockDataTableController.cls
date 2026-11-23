public class StockDataTableController {
    public ApexPages.StandardController standardController;

    public WSGetItemStock itemStock = new WSGetItemStock();
    public List<WSGetItemStock.almacen> actualStock {get; set;}
    private static final String DB_EXCLUIDA = 'CORRECION_MONETARIA_SOLUEX_';

    public StockDataTableController(ApexPages.StandardController standardController) {
        this.standardController = standardController;
        init();
    }

    public void init() {
        id recordId = apexpages.currentpage().getparameters().get('id');
        boolean resultado = this.itemStock.callForStock(recordId);
        List<WSGetItemStock.almacen> actualStockTemp = this.itemStock.getActualStock();
        
        if (actualStockTemp != null) {
            actualStock = new List<WSGetItemStock.almacen>();
            for (WSGetItemStock.almacen almacen : actualStockTemp) {
                String nombreAlmacen = almacen != null && String.isNotBlank(almacen.nombreAlmacen)
                    ? almacen.nombreAlmacen.trim()
                    : null;
                if (almacen != null
                    && String.isNotBlank(nombreAlmacen)
                    && !nombreAlmacen.toUpperCase().startsWith('Z')
                    && nombreAlmacen.toUpperCase() != DB_EXCLUIDA) {
                    actualStock.add(almacen);
                }
            }

            this.itemStock.stockTotalDeProductos = actualStock;
        }
    }
}