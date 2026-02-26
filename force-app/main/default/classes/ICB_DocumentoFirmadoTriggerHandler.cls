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
        Set<String> contratoIds = new Set<String>();
        for (DocumentoFirmado__e e : events) {
            if (String.isNotBlank(e.ContratoId__c)) {
                contratoIds.add(e.ContratoId__c);
            }
        }
        if (contratoIds.isEmpty()) {
            return;
        }
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
        }
    }

    private static void applyEventToRecord(DocumentoFirmado__e e, Contrato_Digital__c c) {
        if (String.isNotBlank(e.Estado__c)) {
            c.Estado__c = e.Estado__c;
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
        /*if (String.isNotBlank(e.RawPayload__c)) {
            c.Raw_Payload__c = truncateToLength(e.RawPayload__c, 32768);
        }*/
    }

    private static String truncateToLength(String s, Integer maxLen) {
        if (s == null || s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen);
    }
}
