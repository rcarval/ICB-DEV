public with sharing class GenerarPDFComodatoAction {
    @InvocableMethod(label='Generar PDF Comodato' description='Crea PDF, lo adjunta al Quote y crea partidas de servicios Comodato')
    public static List<Output> generar(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input i : inputs) {
            // Si hay multi-selección, delegar a la acción multi
            if (String.isNotBlank(i.machineSelectionsJson) && i.machineSelectionsJson != '[]') {
                GenerarPDFComodatoMultiAction.Input multiInput = new GenerarPDFComodatoMultiAction.Input();
                multiInput.machineSelectionsJson = i.machineSelectionsJson;
                multiInput.quoteId = i.quoteId;
                multiInput.ajustesJson = i.ajustesJson;
                List<GenerarPDFComodatoMultiAction.Output> multiResults =
                    GenerarPDFComodatoMultiAction.generar(new List<GenerarPDFComodatoMultiAction.Input>{ multiInput });
                results.add(new Output(multiResults[0].contentDocumentId));
            } else {
                // Lógica single original
                String machineName = obtenerNombreMaquina(i.machineId);
                Id conDocId = generarYAdjuntarPDF(i.machineId, i.quoteId, machineName, i.ajustesJson);
                crearPartidasServicios(i.machineId, i.quoteId);
                results.add(new Output(conDocId));
            }
        }
        return results;
    }

    private static String obtenerNombreMaquina(Id machineId) {
        List<Product2> prods = [SELECT Name FROM Product2 WHERE Id = :machineId LIMIT 1];
        return prods.isEmpty() ? 'Comodato' : prods[0].Name;
    }

    private static Id generarYAdjuntarPDF(Id machineId, Id quoteId, String machineName, String ajustesJson) {
        PageReference pdfPage = Page.ComodatoPropuesta;
        pdfPage.getParameters().put('machineId', String.valueOf(machineId));
        pdfPage.getParameters().put('renderPdf', 'true');
        // Sin este parametro el PDF se renderiza con los valores maestros, ignorando el ajuste.
        if (quoteId != null) {
            pdfPage.getParameters().put('quoteId', String.valueOf(quoteId));
        }
        if (String.isNotBlank(ajustesJson)) {
            pdfPage.getParameters().put('ajustesJson', ajustesJson);
        }

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
        // Servicios YA RESUELTOS: reflejan el ajuste excepcional de la Quote si existe.
        List<ComodatoOverrideResolver.LineaResuelta> servicios =
            new List<ComodatoOverrideResolver.LineaResuelta>();
        for (ComodatoOverrideResolver.LineaResuelta l :
                ComodatoOverrideResolver.resolver(new Set<Id>{ machineId }, quoteId)) {
            if (l.productoAsociadoId != null) {
                servicios.add(l);
            }
        }
        if (servicios.isEmpty()) return;

        if (quoteId == null) return;
        List<Quote> quotes = [SELECT Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
        if (quotes.isEmpty() || quotes[0].Pricebook2Id == null) return;
        Id pricebookId = quotes[0].Pricebook2Id;

        Set<Id> productoIds = new Set<Id>();
        for (ComodatoOverrideResolver.LineaResuelta s : servicios) productoIds.add(s.productoAsociadoId);

        Map<Id, Id> prod2ToPbe = new Map<Id, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productoIds AND IsActive = true
        ]) {
            prod2ToPbe.put(pbe.Product2Id, pbe.Id);
        }

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (ComodatoOverrideResolver.LineaResuelta s : servicios) {
            if (!prod2ToPbe.containsKey(s.productoAsociadoId)) continue;
            Decimal qty    = (s.cantidadMinimaMensual == null || s.cantidadMinimaMensual <= 0) ? 1 : s.cantidadMinimaMensual;
            Decimal precio = s.precioUnitarioNeto == null ? 0 : s.precioUnitarioNeto;
            QuoteLineItem qli   = new QuoteLineItem();
            qli.QuoteId          = quoteId;
            qli.Product2Id       = s.productoAsociadoId;
            qli.PricebookEntryId = prod2ToPbe.get(s.productoAsociadoId);
            qli.Quantity         = qty;
            qli.UnitPrice        = precio;
            qli.Estado__c        = 'Sin gestión';
            qlis.add(qli);
        }
        if (!qlis.isEmpty()) insert qlis;
    }

    public class Input {
        @InvocableVariable(label='ID de la Máquina (Product2)' required=false)
        public Id machineId;

        @InvocableVariable(label='ID de la Quote' required=true)
        public Id quoteId;

        @InvocableVariable(label='Selecciones Multi-Máquina JSON' required=false)
        public String machineSelectionsJson;

        @InvocableVariable(label='Ajustes excepcionales (JSON)' required=false)
        public String ajustesJson;
    }

    public class Output {
        @InvocableVariable public Id contentDocumentId;
        public Output(Id id) { this.contentDocumentId = id; }
    }
}