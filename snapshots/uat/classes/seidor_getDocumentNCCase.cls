public without sharing class seidor_getDocumentNCCase {
    public class Input {
        @InvocableVariable(required=true)
        public Id caseId;
        @InvocableVariable
        public List<Id> uploadedFileIds;
        @InvocableVariable
        public String processType; // 'FDR' o 'NC' para indicar qué lógica ejecutar
    }
    public class Output {
        @InvocableVariable
        public Integer generatedNumber;
        @InvocableVariable
        public Id contentDocumentId;
        @InvocableVariable
        public Id contentVersionId;
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
            String pType = String.isBlank(input.processType) ? 'BOTH' : input.processType.toUpperCase();

            if (pType == 'FDR' || pType == 'BOTH') {
                List<ContentDocumentLink> existingFdrFiles = [
                    SELECT Id, ContentDocumentId, ContentDocument.Title
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :input.caseId
                    AND (ContentDocument.Title LIKE 'FDR Calidad - %' OR ContentDocument.Title LIKE 'FDR Devoluciones - %')
                ];
                if (!existingFdrFiles.isEmpty()) {
                    ContentDocumentLink fileLink = existingFdrFiles[0];
                    out.alreadyExists = true;
                    out.contentDocumentId = fileLink.ContentDocumentId;
                    results.add(out);
                    continue;
                }
            }

            if (pType == 'NC' || pType == 'BOTH') {
                Case c = [
                    SELECT Id, N_FDR__c, Archivo_cargado__c
                    FROM Case
                    WHERE Id = :input.caseId
                    LIMIT 1
                    FOR UPDATE
                ];

                List<ContentDocumentLink> ncFileLinks = new List<ContentDocumentLink>();
                if (input.uploadedFileIds != null && !input.uploadedFileIds.isEmpty()) {
                    ncFileLinks = [
                        SELECT Id, ContentDocumentId, ContentDocument.Title
                        FROM ContentDocumentLink
                        WHERE LinkedEntityId = :input.caseId
                        AND ContentDocumentId IN :input.uploadedFileIds
                        LIMIT 1
                    ];
                } else {
                    ncFileLinks = [
                        SELECT Id, ContentDocumentId, ContentDocument.Title
                        FROM ContentDocumentLink
                        WHERE LinkedEntityId = :input.caseId
                        ORDER BY ContentDocument.CreatedDate DESC
                        LIMIT 1
                    ];
                }

                if (!ncFileLinks.isEmpty()) {
                    ContentDocumentLink fileLink = ncFileLinks[0];
                    out.existingNCFiles = true;
                    out.contentDocumentId = fileLink.ContentDocumentId;
                    List<ContentVersion> cvList = [
                        SELECT Id, NC_cargada__c
                        FROM ContentVersion
                        WHERE ContentDocumentId = :fileLink.ContentDocumentId
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                    if (!cvList.isEmpty()) {
                        ContentVersion cv = cvList[0];
                        cv.NC_cargada__c = true;
                        update cv;
                        out.contentVersionId = cv.Id;
                    }
                    c.Archivo_cargado__c = true;
                    update c;
                }
            }
            results.add(out);
        }
        return results;
    }
}