public without sharing class MachineSelectorController {
    @AuraEnabled(cacheable=true)
    public static List<Product2> getMachines(String pricebookId) {
        System.debug('Searching machines for Pricebook: ' + pricebookId);
        
        // Si no hay lista de precios, devolvemos todas las máquinas activas por defecto
        if (String.isBlank(pricebookId)) {
            return [
                SELECT Id, Name, Description,
                       Categoria__r.Name,
                       Tipo_de_Negocio_Recomendado__c,
                       Tipo_de_Leche__c,
                       Capacidad_Sugerida__c,
                       Metodologia__c
                FROM Product2
                WHERE Categoria__r.Name = '593 MAQUINAS Y REPUESTOS'
                  AND IsActive = true
                ORDER BY Name ASC
            ];
        }

        // Buscamos productos que tengan una entrada activa en la lista de precios especificada
        List<PricebookEntry> entries = [
            SELECT Product2Id, 
                   Product2.Name, 
                   Product2.Description,
                   Product2.Categoria__r.Name,
                   Product2.Tipo_de_Negocio_Recomendado__c,
                   Product2.Tipo_de_Leche__c,
                   Product2.Capacidad_Sugerida__c,
                   Product2.Metodologia__c
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
              AND IsActive = true
              AND Product2.IsActive = true
              AND Product2.Categoria__r.Name = '593 MAQUINAS Y REPUESTOS'
            ORDER BY Product2.Name ASC
        ];

        List<Product2> products = new List<Product2>();
        for (PricebookEntry pbe : entries) {
            // Mapeamos los campos del producto para que el LWC los reciba correctamente
            products.add(pbe.Product2);
        }
        return products;
    }
}