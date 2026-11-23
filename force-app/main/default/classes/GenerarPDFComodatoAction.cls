public with sharing class GenerarPDFComodatoAction {
    @InvocableMethod(label='Generar PDF Comodato' description='Crea PDF, lo adjunta al Quote y crea partidas de servicios Comodato')
    public static List<Output> generar(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input i : inputs) {
            String machineName = obtenerNombreMaquina(i.machineId);
            Id conDocId = generarYAdjuntarPDF(i.machineId, i.quoteId, machineName);
            crearPartidasServicios(i.machineId, i.quoteId);
            results.add(new Output(conDocId));
        }
        return results;
    }

    private static String obtenerNombreMaquina(Id machineId) {
        List<Product2> prods = [SELECT Name FROM Product2 WHERE Id = :machineId LIMIT 1];
        return prods.isEmpty() ? 'Comodato' : prods[0].Name;
    }

    private static Id generarYAdjuntarPDF(Id machineId, Id quoteId, String machineName) {
        PageReference pdfPage = Page.ComodatoPropuesta;
        pdfPage.getParameters().put('machineId', String.valueOf(machineId));
        pdfPage.getParameters().put('renderPdf', 'true');

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('Test PDF Content')
            : pdfPage.getContentAsPDF();

        ContentVersion cv = new ContentVersion();
        cv.Title          = 'Propuesta Comodato - ' + machineName;
        cv.PathOnClient   = 'Propuesta_Comodato.pdf';
        cv.VersionData    = pdfBlob;
        cv.IsMajorVersion = true;
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        if (quoteId != null) {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = conDocId;
            cdl.LinkedEntityId    = quoteId;
            cdl.ShareType         = 'V';
            cdl.Visibility        = 'AllUsers';
            insert cdl;
        }

        return conDocId;
    }

    private static void crearPartidasServicios(Id machineId, Id quoteId) {
        List<Comodato__c> servicios = [
            SELECT Producto_Asociado__c, Precio_Unitario_Neto__c, Cantidad_Minima_Mensual__c
            FROM Comodato__c
            WHERE Maquina__c = :machineId AND Producto_Asociado__c != null
        ];
        if (servicios.isEmpty()) return;

        if (quoteId == null) return;
        List<Quote> quotes = [SELECT Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
        if (quotes.isEmpty() || quotes[0].Pricebook2Id == null) return;
        Id pricebookId = quotes[0].Pricebook2Id;

        Set<Id> productoIds = new Set<Id>();
        for (Comodato__c s : servicios) productoIds.add(s.Producto_Asociado__c);

        Map<Id, Id> prod2ToPbe = new Map<Id, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productoIds AND IsActive = true
        ]) {
            prod2ToPbe.put(pbe.Product2Id, pbe.Id);
        }

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Comodato__c s : servicios) {
            if (!prod2ToPbe.containsKey(s.Producto_Asociado__c)) continue;
            Decimal qty    = (s.Cantidad_Minima_Mensual__c == null || s.Cantidad_Minima_Mensual__c <= 0) ? 1 : s.Cantidad_Minima_Mensual__c;
            Decimal precio = s.Precio_Unitario_Neto__c == null ? 0 : s.Precio_Unitario_Neto__c;
            QuoteLineItem qli   = new QuoteLineItem();
            qli.QuoteId          = quoteId;
            qli.Product2Id       = s.Producto_Asociado__c;
            qli.PricebookEntryId = prod2ToPbe.get(s.Producto_Asociado__c);
            qli.Quantity         = qty;
            qli.UnitPrice        = precio;
            qli.Estado__c        = 'Sin gestión';
            qlis.add(qli);
        }
        if (!qlis.isEmpty()) insert qlis;
    }

    public class Input {
        @InvocableVariable(label='ID de la Máquina (Product2)' required=true)
        public Id machineId;

        @InvocableVariable(label='ID de la Quote' required=true)
        public Id quoteId;
    }

    public class Output {
        @InvocableVariable public Id contentDocumentId;
        public Output(Id id) { this.contentDocumentId = id; }
    }
}