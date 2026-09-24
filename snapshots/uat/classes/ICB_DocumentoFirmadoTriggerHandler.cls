/**********************************************************************************
 * ICB_DocumentoFirmadoTriggerHandler
 * Actualiza Contrato_Digital__c cuando llega un evento DocumentoFirmado__e (TuFirma).
 * SEIDOR - RCG
 **********************************************************************************/
public with sharing class ICB_DocumentoFirmadoTriggerHandler {

    public static void onAfterInsert(List<DocumentoFirmado__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        String origen = 'ICB_DocumentoFirmadoTriggerHandler.onAfterInsert';
        String payload = JSON.serialize(events);
        Set<String> contratoIds = new Set<String>();
        for (DocumentoFirmado__e e : events) {
            if (String.isNotBlank(e.ContratoId__c)) {
                contratoIds.add(e.ContratoId__c);
            }
        }
        if (contratoIds.isEmpty()) {
            ICB_LogIntegracionService.insertarLogInbound(origen, payload, false, 'Ningún evento con ContratoId__c', 'eventos sin ContratoId__c válido');
            return;
        }
        try {
            List<Contrato_Digital__c> contratos = [
                SELECT Id, Contrato_ID__c
                FROM Contrato_Digital__c
                WHERE Contrato_ID__c IN :contratoIds
            ];
            Map<String, Contrato_Digital__c> byContratoId = new Map<String, Contrato_Digital__c>();
            for (Contrato_Digital__c c : contratos) {
                byContratoId.put(c.Contrato_ID__c, c);
            }
            List<Contrato_Digital__c> toUpdate = new List<Contrato_Digital__c>();
            for (DocumentoFirmado__e e : events) {
                if (String.isBlank(e.ContratoId__c)) {
                    continue;
                }
                Contrato_Digital__c c = byContratoId.get(e.ContratoId__c);
                if (c == null) {
                    continue;
                }
                applyEventToRecord(e, c);
                toUpdate.add(c);
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
                processSignedContracts(toUpdate);
            }
            ICB_LogIntegracionService.insertarLogInbound(origen, payload, true, null, 'Contratos actualizados: ' + toUpdate.size());
        } catch (Exception e) {
            ICB_LogIntegracionService.insertarLogInbound(origen, payload, false, e.getMessage(), 'ContratoIds: ' + String.join(new List<String>(contratoIds), ', '));
            throw e;
        }
    }

    private static void applyEventToRecord(DocumentoFirmado__e e, Contrato_Digital__c c) {
        if (String.isNotBlank(e.Estado__c)) {
            c.Estado__c = mapEstadoFromEvent(e.Estado__c);
        } else if (e.FechaFirma__c != null || String.isNotBlank(e.PdfFirmadoUrl__c)) {
            c.Estado__c = 'Firmado';
        }
        if (String.isNotBlank(e.ExternalTransactionId__c)) {
            c.Documento_ID_TuFirma_del__c = e.ExternalTransactionId__c;
        }
        if (e.FechaFirma__c != null) {
            c.Fecha_Firma__c = e.FechaFirma__c;
        }
        if (String.isNotBlank(e.PdfFirmadoUrl__c)) {
            c.PDF_Firmado_URL__c = e.PdfFirmadoUrl__c;
        }

    }

    private static String mapEstadoFromEvent(String eventEstado) {
        if (String.isBlank(eventEstado)) {
            return null;
        }
        String normal = eventEstado.trim().toLowerCase();
        if (normal == 'signed' || normal == 'completed' || normal == 'firmado') {
            return 'Firmado';
        }
        if (normal == 'rejected' || normal == 'rechazado') {
            return 'Rechazado';
        }
        if (normal == 'expired' || normal == 'expirado') {
            return 'Expirado';
        }
        if (normal == 'error' || normal == 'failed' || normal == 'failure') {
            return 'Rechazado';
        }
        if (normal == 'sent' || normal == 'enviado') {
            return 'Enviado';
        }
        if (normal == 'pending' || normal == 'pendiente') {
            return 'Pendiente';
        }
        return eventEstado.trim();
    }

    private static String truncateToLength(String s, Integer maxLen) {
        if (s == null || s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen);
    }

    private static void processSignedContracts(List<Contrato_Digital__c> updatedContracts) {
        Set<Id> signedContractIds = new Set<Id>();
        for (Contrato_Digital__c c : updatedContracts) {
            if (c.Estado__c == 'Firmado') {
                signedContractIds.add(c.Id);
            }
        }
        if (signedContractIds.isEmpty()) {
            return;
        }

        List<Opportunity> opps = [
            SELECT Id, Name, AccountId, Contrato_Digital_Firmado__c, StageName, CloseDate
            FROM Opportunity
            WHERE Contrato_Digital_Firmado__c IN :signedContractIds
        ];
        if (opps.isEmpty()) {
            return;
        }

        Map<Id, Quote> quoteByOpp = new Map<Id, Quote>();
        for (Quote q : [
            SELECT Id, OpportunityId
            FROM Quote
            WHERE OpportunityId IN :new Map<Id, Opportunity>(opps).keySet()
              AND IsSyncing = true
        ]) {
            quoteByOpp.put(q.OpportunityId, q);
        }

        if (quoteByOpp.isEmpty()) {
            for (Quote q : [
                SELECT Id, OpportunityId
                FROM Quote
                WHERE OpportunityId IN :new Map<Id, Opportunity>(opps).keySet()
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!quoteByOpp.containsKey(q.OpportunityId)) {
                    quoteByOpp.put(q.OpportunityId, q);
                }
            }
        }

        Set<Id> quoteIds = new Set<Id>();
        for (Quote q : quoteByOpp.values()) {
            quoteIds.add(q.Id);
        }

        Map<Id, List<QuoteLineItem>> qlisByQuote = new Map<Id, List<QuoteLineItem>>();
        if (!quoteIds.isEmpty()) {
            for (QuoteLineItem qli : [
                SELECT QuoteId, Product2Id, Quantity, UnitPrice
                FROM QuoteLineItem
                WHERE QuoteId IN :quoteIds
            ]) {
                if (!qlisByQuote.containsKey(qli.QuoteId)) {
                    qlisByQuote.put(qli.QuoteId, new List<QuoteLineItem>());
                }
                qlisByQuote.get(qli.QuoteId).add(qli);
            }
        }

        List<Asset> assetsToInsert = new List<Asset>();
        List<Opportunity> oppToUpdate = new List<Opportunity>();
        Map<Id, Integer> assetCountByOpp = new Map<Id, Integer>();

        for (Opportunity opp : opps) {
            Quote q = quoteByOpp.get(opp.Id);
            if (q == null || !qlisByQuote.containsKey(q.Id)) {
                continue;
            }
            Integer countForOpp = 0;
            for (QuoteLineItem qli : qlisByQuote.get(q.Id)) {
                if (qli.Product2Id == null) continue;
                assetsToInsert.add(new Asset(
                    Name = 'Asset ' + String.valueOf(opp.Name),
                    AccountId = opp.AccountId,
                    Product2Id = qli.Product2Id,
                    Quantity = qli.Quantity,
                    Status = 'Activo',
                    InstallDate = Date.today()
                ));
                countForOpp++;
            }
            assetCountByOpp.put(opp.Id, countForOpp);
            opp.StageName = 'Documento firmado';
            oppToUpdate.add(opp);
        }

        if (!assetsToInsert.isEmpty()) {
            insert assetsToInsert;
        }

        List<Contract> contractsToInsert = new List<Contract>();
        if (!oppToUpdate.isEmpty()) {
            for (Opportunity opp : oppToUpdate) {
                if (assetCountByOpp.get(opp.Id) == null || assetCountByOpp.get(opp.Id) == 0) {
                    continue;
                }
                contractsToInsert.add(new Contract(
                    Name = 'Contrato ' + opp.Name,
                    AccountId = opp.AccountId,
                    Status = 'Draft',
                    StartDate = Date.today(),
                    ContractTerm = 12
                ));
            }
            update oppToUpdate;
        }

        if (!contractsToInsert.isEmpty()) {
            insert contractsToInsert;
        }
    }
}