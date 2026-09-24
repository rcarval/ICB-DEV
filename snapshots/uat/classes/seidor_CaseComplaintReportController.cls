public with sharing class seidor_CaseComplaintReportController {

    public Case caseRecord { get; set; }

    public seidor_CaseComplaintReportController() {

        Id caseId = ApexPages.currentPage().getParameters().get('id');

        if(caseId != null) {
            loadCase(caseId);
        }
    }

    private void loadCase(Id caseId) {

        caseRecord = [
            SELECT
                Id,
                CaseNumber,
                Motivo__c,
                Investigacion__c,
                Acciones_Correctivas__c,
                Acciones_Preventivas__c,
                Conclusiones__c,
                Product.Name,
                Marca__c,
                Account.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
    }
}