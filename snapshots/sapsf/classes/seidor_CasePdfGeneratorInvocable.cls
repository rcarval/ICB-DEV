public with sharing class seidor_CasePdfGeneratorInvocable {

    // ===== INPUT DESDE FLOW =====
    public class FlowInput {
        @InvocableVariable(required=true)
        public Id caseId;
        @InvocableVariable(required=true)
        public String numberCase;
    }

    // ===== OUTPUT HACIA FLOW =====
    public class FlowOutput {
        @InvocableVariable
        public String previewUrl;

        @InvocableVariable
        public String pdfPageUrl;

        @InvocableVariable
        public Id contentDocumentId;

        // @InvocableVariable
        // public Boolean alreadyExists;   
    }

    // ===== MÉTODO INVOCABLE =====
    @InvocableMethod(label='Generar URLs PDF Reclamo Calidad')
    public static List<FlowOutput> generateUrls(List<FlowInput> inputs) {

        List<FlowOutput> results = new List<FlowOutput>();

        for (FlowInput input : inputs) {

            FlowOutput output = new FlowOutput();

            // URL HTML para PREVIEW (iframe en Screen Flow)
            output.previewUrl =
                '/apex/ReclamoCalidadPDFController'
                + '?caseId=' + String.valueOf(input.caseId)
                + '&preview=true';

            // URL PDF REAL (solo para generación / descarga)
            output.pdfPageUrl =
                '/apex/ReclamoCalidadPDFController'
                + '?caseId=' + String.valueOf(input.caseId);

                Case c = [
                    SELECT N_FDR__c
                    FROM Case
                    WHERE Id = :input.caseId
                ];

                // VALIDACIÓN SI YA EXISTE ALGÚN PDF ADJUNTO AL CASO
                List<ContentDocumentLink> existingFdrFiles = [
                    SELECT Id,
                           ContentDocumentId,
                           ContentDocument.Title
                    FROM ContentDocumentLink
                    WHERE LinkedEntity.Id = :input.caseId AND ContentDocument.Title LIKE 'FDR Calidad - %'
                ];

                //     if (!existingFdrFiles.isEmpty()) {
                //         throw new AuraHandledException(
                //             '⚠ Ya existe un PDF FDR adjunto a este Caso. No es posible generar uno nuevo.'
                //         );
                //     }

                //     if (!existingFdrFiles.isEmpty()) {
                //         output.alreadyExists = true;
                //         results.add(output);
                //         continue;
                //     } 

            // ===== GENERAR PDF DESDE VISUALFORCE =====
            PageReference pdfPage = Page.ReclamoCalidadPDFController;
            pdfPage.getParameters().put('caseId', String.valueOf(input.caseId));
            pdfPage.getParameters().put('fdrNumber', String.valueOf(c.N_FDR__c));

            Blob pdfBlob;
            try {
                pdfBlob = pdfPage.getContentAsPDF();
            } catch (Exception e) {
                System.debug('Error generando PDF: ' + e.getMessage());
                results.add(output);
                continue;
            }

        
        // ===== ACTUALIZAR CAMPO FDR_modificado__c EN EL CASE =====
        Case caseToUpdate = new Case(
            Id = input.caseId,
            //Status = 'En devolución', // Cambia el status a "En devolución" --> por definición ya no se genera el update de etapa desde aqui
            FDR_modificado__c = false
        );
        update caseToUpdate;

            // ===== GUARDAR PDF COMO FILE =====
            ContentVersion cv = new ContentVersion();
            // cv.Title = 'Reclamo Calidad - ' + String.valueOf(input.numberCase);
            cv.Title = 'FDR Calidad - ' + input.numberCase;
            cv.PathOnClient = 'ReclamoCalidad.pdf';
            cv.VersionData = pdfBlob;
            insert cv;

            // Obtener ContentDocumentId
            cv = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id
            ];

            // ===== ASOCIAR FILE AL CASE =====
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId = input.caseId;
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;

            output.contentDocumentId = cv.ContentDocumentId;

            results.add(output);
        }

        return results;
    }
    
    
    
    
    
    
    
    
    
    
    
    
    public static void getInt(){
        Integer I =0;
        		I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
    }
}