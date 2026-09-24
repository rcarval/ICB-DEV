/**
 * Invocable Action que genera un PDF de propuesta Comodato para múltiples máquinas.
 * - Agrupa máquinas: si hay 2+ de la misma, genera una sola sección.
 * - Si hay máquinas distintas, genera secciones separadas con sus configuraciones.
 * - Crea QuoteLineItems por cada máquina×cantidad + sus servicios asociados.
 */
public with sharing class GenerarPDFComodatoMultiAction {

    @InvocableMethod(label='Generar PDF Comodato Multi-Máquina' description='Genera PDF multi-sección y crea partidas para múltiples máquinas')
    public static List<Output> generar(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input i : inputs) {
            try {
                Id conDocId = procesarMultiMaquina(i);
                results.add(new Output(conDocId, true, ''));
            } catch (Exception e) {
                results.add(new Output(null, false, e.getMessage()));
            }
        }
        return results;
    }

    private static Id procesarMultiMaquina(Input input) {
        // Parsear las selecciones: formato JSON [{machineId, quantity}]
        List<MachineSelection> selections = parsearSelecciones(input.machineSelectionsJson);
        if (selections.isEmpty()) {
            throw new AuraHandledException('No se seleccionaron máquinas.');
        }

        // Agrupar por machineId (deduplicar sumando cantidades)
        Map<Id, Integer> machineQuantities = new Map<Id, Integer>();
        for (MachineSelection sel : selections) {
            Integer existing = machineQuantities.containsKey(sel.machineId)
                ? machineQuantities.get(sel.machineId) : 0;
            machineQuantities.put(sel.machineId, existing + sel.quantity);
        }

        // Obtener IDs únicos de máquinas
        Set<Id> uniqueMachineIds = machineQuantities.keySet();

        // Generar PDF multi-sección
        Id conDocId = generarPDFMultiSeccion(uniqueMachineIds, machineQuantities, input.quoteId, input.ajustesJson);

        // Crear partidas en el Quote + OLIs en la Opportunity
        crearPartidasMultiMaquina(uniqueMachineIds, machineQuantities, input.quoteId);

        return conDocId;
    }

    private static Id generarPDFMultiSeccion(Set<Id> machineIds, Map<Id, Integer> quantities, Id quoteId, String ajustesJson) {
        // Generar HTML del PDF usando el controller
        String html = ComodatoPropuestaMultiController.buildMultiMachinePdfHtml(machineIds, quantities, quoteId);

        // Convertir a PDF via VF
        PageReference pdfPage = Page.ComodatoPropuestaMulti;
        pdfPage.getParameters().put('machineIds', String.join(new List<Id>(machineIds), ','));
        pdfPage.getParameters().put('quantities', serializeQuantities(machineIds, quantities));
        pdfPage.getParameters().put('renderPdf', 'true');
        // Sin este parametro el PDF se renderiza con los valores maestros, ignorando el ajuste.
        if (quoteId != null) {
            pdfPage.getParameters().put('quoteId', String.valueOf(quoteId));
        }
        // getContentAsPDF() corre en un contexto aparte que no ve los Comodato_Override__c
        // creados en esta misma transaccion, asi que los ajustes viajan tambien por parametro.
        if (String.isNotBlank(ajustesJson)) {
            pdfPage.getParameters().put('ajustesJson', ajustesJson);
        }

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('Test PDF Multi Content')
            : pdfPage.getContentAsPDF();

        // Crear ContentVersion
        String title = quantities.size() == 1
            ? 'Propuesta Comodato - ' + getFirstMachineName(machineIds)
            : 'Propuesta Comodato - ' + quantities.size() + ' equipos';

        ContentVersion cv = new ContentVersion();
        cv.Title          = title;
        cv.PathOnClient   = 'Propuesta_Comodato_Multi.pdf';
        cv.VersionData    = pdfBlob;
        cv.IsMajorVersion = true;
        insert cv;

        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        // Vincular al Quote
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

    private static void crearPartidasMultiMaquina(Set<Id> machineIds, Map<Id, Integer> quantities, Id quoteId) {
        if (quoteId == null) return;

        List<Quote> quotes = [SELECT Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
        if (quotes.isEmpty() || quotes[0].Pricebook2Id == null) return;
        Id pricebookId = quotes[0].Pricebook2Id;

        // Servicios YA RESUELTOS: si la Quote tiene un ajuste excepcional activo, la cantidad
        // y el precio que llegan aca son los ajustados. Nunca se lee Comodato__c directo.
        List<ComodatoOverrideResolver.LineaResuelta> todosServicios =
            new List<ComodatoOverrideResolver.LineaResuelta>();
        for (ComodatoOverrideResolver.LineaResuelta l : ComodatoOverrideResolver.resolver(machineIds, quoteId)) {
            if (l.productoAsociadoId != null && l.tipoDeAsociacion == 'Insumo Mensual') {
                todosServicios.add(l);
            }
        }

        // Obtener PricebookEntries
        Set<Id> productoIds = new Set<Id>();
        for (ComodatoOverrideResolver.LineaResuelta s : todosServicios) {
            productoIds.add(s.productoAsociadoId);
        }
        // Agregar las máquinas mismas
        productoIds.addAll(machineIds);

        Map<Id, Id> prod2ToPbe = new Map<Id, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productoIds AND IsActive = true
        ]) {
            prod2ToPbe.put(pbe.Product2Id, pbe.Id);
        }

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();

        // Partidas de máquinas (precio 0, cantidad según selección)
        for (Id machineId : machineIds) {
            if (!prod2ToPbe.containsKey(machineId)) continue;
            Integer qty = quantities.get(machineId);
            QuoteLineItem qli = new QuoteLineItem();
            qli.QuoteId          = quoteId;
            qli.Product2Id       = machineId;
            qli.PricebookEntryId = prod2ToPbe.get(machineId);
            qli.Quantity         = qty;
            qli.UnitPrice        = 0;
            qli.Estado__c        = 'Sin gestión';
            qlis.add(qli);
        }

        // Partidas de servicios/insumos por máquina
        for (ComodatoOverrideResolver.LineaResuelta s : todosServicios) {
            if (!prod2ToPbe.containsKey(s.productoAsociadoId)) continue;
            Integer machineQty = quantities.get(s.maquinaId);
            Decimal baseQty = (s.cantidadMinimaMensual == null || s.cantidadMinimaMensual <= 0)
                ? 1 : s.cantidadMinimaMensual;
            Decimal precio = s.precioUnitarioNeto == null ? 0 : s.precioUnitarioNeto;

            QuoteLineItem qli = new QuoteLineItem();
            qli.QuoteId          = quoteId;
            qli.Product2Id       = s.productoAsociadoId;
            qli.PricebookEntryId = prod2ToPbe.get(s.productoAsociadoId);
            qli.Quantity         = baseQty * machineQty;
            qli.UnitPrice        = precio;
            qli.Estado__c        = 'Sin gestión';
            qlis.add(qli);
        }

        if (!qlis.isEmpty()) insert qlis;

        // Crear OpportunityLineItems (productos de la OPP)
        List<Quote> quoteForOpp = [SELECT OpportunityId FROM Quote WHERE Id = :quoteId LIMIT 1];
        if (quoteForOpp.isEmpty()) return;
        Id oppId = quoteForOpp[0].OpportunityId;

        List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
        for (Id machineId : machineIds) {
            if (!prod2ToPbe.containsKey(machineId)) continue;
            Integer qty = quantities.get(machineId);
            OpportunityLineItem oli = new OpportunityLineItem();
            oli.OpportunityId    = oppId;
            oli.Product2Id       = machineId;
            oli.PricebookEntryId = prod2ToPbe.get(machineId);
            oli.Quantity         = qty;
            oli.UnitPrice        = 0;
            olis.add(oli);
        }
        if (!olis.isEmpty()) insert olis;
    }

    private static List<MachineSelection> parsearSelecciones(String json) {
        if (String.isBlank(json)) return new List<MachineSelection>();
        return (List<MachineSelection>) System.JSON.deserialize(json, List<MachineSelection>.class);
    }

    private static String serializeQuantities(Set<Id> machineIds, Map<Id, Integer> quantities) {
        List<String> parts = new List<String>();
        for (Id mid : machineIds) {
            parts.add(String.valueOf(quantities.get(mid)));
        }
        return String.join(parts, ',');
    }

    private static String getFirstMachineName(Set<Id> machineIds) {
        List<Product2> prods = [SELECT Name FROM Product2 WHERE Id IN :machineIds LIMIT 1];
        return prods.isEmpty() ? 'Comodato' : prods[0].Name;
    }

    public class MachineSelection {
        public Id machineId;
        public Integer quantity;
    }

    public class Input {
        @InvocableVariable(label='Selecciones JSON [{machineId, quantity}]' required=true)
        public String machineSelectionsJson;

        @InvocableVariable(label='ID de la Quote' required=true)
        public Id quoteId;

        @InvocableVariable(label='Ajustes excepcionales (JSON)' required=false)
        public String ajustesJson;
    }

    public class Output {
        @InvocableVariable public Id contentDocumentId;
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;

        public Output(Id id, Boolean success, String errorMsg) {
            this.contentDocumentId = id;
            this.success = success;
            this.errorMessage = errorMsg;
        }
    }
}