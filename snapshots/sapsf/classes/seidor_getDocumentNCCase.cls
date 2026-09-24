public with sharing class seidor_getDocumentNCCase {
    public class Input {
        @InvocableVariable(required=true)
        public Id caseId;

        @InvocableVariable
        public List<Id> existingNCFiles;
    }

    public class Output {
        @InvocableVariable
        public Integer generatedNumber;

        @InvocableVariable
        public Id contentDocumentId;

        @InvocableVariable
        public Boolean alreadyExists;
        @InvocableVariable
        public Boolean existingNCFiles;
    }

        @InvocableMethod(label='Obtiene el documento NC del caso'
                     description='Esta clase realiza la logica para obtener el documento NC del caso')
    public static List<Output> getDocumentNC(List<Input> inputs) {

        List<Output> results = new List<Output>();

        for (Input input : inputs) {

            Output out = new Output();

            //1. Bloquear el Case
            Case c = [
                SELECT Id, N_FDR__c, Archivo_cargado__c
                FROM Case
                WHERE Id = :input.caseId
                LIMIT 1
                FOR UPDATE
            ];


                // VALIDACIÓN SI YA EXISTE UN PDF FDR CALIDAD ADJUNTO AL CASO
                List<ContentDocumentLink> existingFdrFiles = [
                    SELECT Id,
                        ContentDocumentId,
                        ContentDocument.Title
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :input.caseId
                    AND ContentDocument.Title LIKE 'FDR Calidad - %'
                ];

                if (!existingFdrFiles.isEmpty()) {

                    ContentDocumentLink fileLink = existingFdrFiles[0];

                    out.alreadyExists = true;
                    out.contentDocumentId = fileLink.ContentDocumentId;

                    results.add(out);
                    continue;
                }

                // VALIDACIÓN SI YA EXISTE UNA NOTA DE CRÉDITO ADJUNTA AL CASO
                List<ContentDocumentLink> existingNCFiles = [
                    SELECT Id,
                        ContentDocumentId,
                        ContentDocument.Title
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :input.caseId
                    /*AND (
                        ContentDocument.Title LIKE 'Nota de credito - %'
                        OR ContentDocument.Title LIKE 'NC - %'
                        OR ContentDocument.Title LIKE 'Nota Credito - %'
                        OR ContentDocument.Title LIKE 'Nota - %'
                    )*/
                ];

                if (!existingNCFiles.isEmpty()) {

                    ContentDocumentLink fileLink = existingNCFiles[0];

                    out.existingNCFiles = true;
                    out.contentDocumentId = fileLink.ContentDocumentId;
                    c.Archivo_cargado__c = true;
                    update c;

                    results.add(out);
                    continue;
                }
        }

   

        return results;
    }
}