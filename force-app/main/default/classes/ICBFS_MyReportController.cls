public with sharing class ICBFS_MyReportController {
    @AuraEnabled(cacheable=true)
    public static List<FacturaWrapper> getUserFacturasLast3Months(Id userId) {
        if (userId == null) {
            throw new AuraHandledException('Usuario inválido');
        }
        List<Facturas__c> facturas = [
            SELECT Id,
                   Name,
                   Cliente__r.Name,
                   Cliente__r.Cliente_Despacho__c,
                   Fecha_de_Documento__c,
                   Cliente__r.C_digo_de_cliente__c,
                   Cliente__r.Nombre_de_Fantasia__c,
                   numero_pedido__c,
                   Cliente__r.Ventas_3_meses__c,
                   Total_Venta__c,
                   OwnerId
            FROM Facturas__c
            WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
              AND OwnerId = '005Hn00000Iy7s3IAB'
            ORDER BY Cliente__r.Name, Fecha_de_Documento__c DESC
        ];
        System.debug('Facturas encontradas: ' + facturas.size());

        List<FacturaWrapper> result = new List<FacturaWrapper>();
        for (Facturas__c f : facturas) {
            FacturaWrapper w = new FacturaWrapper();
            w.facturaId = f.Id;
            w.clienteName = f.Cliente__r.Name;
            w.clienteCodigo = f.Cliente__r.C_digo_de_cliente__c;
            w.clienteFantasia = f.Cliente__r.Nombre_de_Fantasia__c;
            w.numeroPedido = f.numero_pedido__c;
            w.fechaDocumento = f.Fecha_de_Documento__c;
            w.totalVenta = f.Total_Venta__c;
            // w.ventas3MesesCliente = f.Cliente__r.Ventas_3_meses__c;
            result.add(w);
        }
        return result;
    }

    public class FacturaWrapper {
        @AuraEnabled public Id facturaId { get; set; }
        @AuraEnabled public String clienteName { get; set; }
        @AuraEnabled public String clienteCodigo { get; set; }
        @AuraEnabled public String clienteFantasia { get; set; }
        @AuraEnabled public String numeroPedido { get; set; }
        @AuraEnabled public Date fechaDocumento { get; set; }
        @AuraEnabled public Decimal totalVenta { get; set; }
        // @AuraEnabled public Boolean ventas3MesesCliente { get; set; }
    }
}