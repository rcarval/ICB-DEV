/** Regenera el contrato solo para descarga local; no crea ContentVersion ni archivos. */
public with sharing class ICB_PdfRecoveryMemoryController {
    @AuraEnabled(cacheable=false)
    public static PdfResult generarPdf(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('No se pudo regenerar el PDF: falta la oportunidad.');
        }

        List<Opportunity> opportunities = [SELECT Id FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        if (opportunities.isEmpty()) {
            throw new AuraHandledException('No se encontró la oportunidad para regenerar el PDF.');
        }

        Blob pdfBody;
        try {
            PageReference pdfPage = Page.ContratoComodatoFinal;
            pdfPage.getParameters().put('opportunityId', String.valueOf(opportunityId));
            pdfBody = Test.isRunningTest() ? Blob.valueOf('%PDF-1.4 Test') : pdfPage.getContentAsPDF();
        } catch (Exception e) {
            throw new AuraHandledException('No se pudo regenerar el PDF: ' + e.getMessage());
        }

        if (pdfBody == null || pdfBody.size() == 0) {
            throw new AuraHandledException('No se pudo regenerar el PDF: el documento quedó vacío.');
        }

        PdfResult result = new PdfResult();
        result.pdfBase64 = EncodingUtil.base64Encode(pdfBody);
        result.pdfFileName = 'Contrato_Comodato.pdf';
        return result;
    }

    public class PdfResult {
        @AuraEnabled public String pdfBase64;
        @AuraEnabled public String pdfFileName;
    }
}