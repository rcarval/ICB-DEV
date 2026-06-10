public with sharing class seidor_AssociarArchivosCaso {

    @InvocableMethod(label='Asociar Archivos a Caso')
    public static void asociar(List<Request> requests) {

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        Map<Id, Boolean> caseHasFiles = new Map<Id, Boolean>();
        Set<Id> caseIds = new Set<Id>();

        // Build ContentDocumentLinks and track cases with files
        for (Request r : requests) {
            if (r.caseId != null) {
                caseIds.add(r.caseId);
                if (r.documentIds != null && !r.documentIds.isEmpty()) {
                    caseHasFiles.put(r.caseId, true);
                    for (Id docId : r.documentIds) {
                        links.add(new ContentDocumentLink(
                            ContentDocumentId = docId,
                            LinkedEntityId    = r.caseId,
                            ShareType         = 'V',
                            Visibility        = 'AllUsers'
                        ));
                    }
                }
            }
        }

        if (!links.isEmpty()) {
            insert links;
        }

        // Update Case flag Archivo_Adjunto__c only when files were uploaded
        // if (!caseIds.isEmpty()) {
        //     List<Case> casesToUpdate = new List<Case>();
        //     for (Case c : [
        //         SELECT Id, Imagen_adjunta__c
        //         FROM Case
        //         WHERE Id IN :caseIds
        //     ]) {
        //         if (caseHasFiles.containsKey(c.Id)) {
        //              c.Imagen_adjunta__c = true;
                    
        //             casesToUpdate.add(c);
        //         }
        //     }

        //     if (!casesToUpdate.isEmpty()) {
        //         update casesToUpdate;
        //     }
        // }
    }

    public class Request {
        @InvocableVariable(required=true)
        public Id caseId;

        @InvocableVariable(required=true)
        public List<Id> documentIds;
    }
}