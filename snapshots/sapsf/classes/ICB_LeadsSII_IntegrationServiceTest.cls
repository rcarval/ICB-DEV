@isTest
private class ICB_LeadsSII_IntegrationServiceTest {
    @isTest
    static void testValidationResultAndEmptyBranches() {
        ICB_LeadsSII_IntegrationService.ValidationResult vr =
            new ICB_LeadsSII_IntegrationService.ValidationResult();
        System.assertEquals(true, vr.isComplete);
        System.assertEquals(0, vr.missingFields.size());

        System.assertEquals(
            0,
            ICB_LeadsSII_IntegrationService.queryLeadsForSII((Set<Id>) null).size()
        );
        System.assertEquals(
            0,
            ICB_LeadsSII_IntegrationService.queryLeadsForSII(new Set<Id>()).size()
        );
        System.assertEquals(
            0,
            ICB_LeadsSII_IntegrationService.queryLeadsForSII((Set<String>) null).size()
        );
        System.assertEquals(
            0,
            ICB_LeadsSII_IntegrationService.queryLeadsForSII(new Set<String>()).size()
        );
    }

    @isTest
    static void testQueryLeadsForSIIConIdYString() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();

        List<Lead> byId = ICB_LeadsSII_IntegrationService.queryLeadsForSII(
            new Set<Id>{ ld.Id }
        );
        List<Lead> byString = ICB_LeadsSII_IntegrationService.queryLeadsForSII(
            new Set<String>{ String.valueOf(ld.Id) }
        );

        System.assertEquals(1, byId.size());
        System.assertEquals(1, byString.size());
        System.assertEquals(ld.Id, byId[0].Id);
        System.assertEquals(ld.Id, byString[0].Id);
    }

    @isTest
    static void testExtractRut() {
        Lead ld = new Lead(RUT__c = '81.482.800-k ');
        String rut = ICB_LeadsSII_IntegrationService.extractRut(ld);
        System.assertEquals('81482800-K', rut);

        System.assertEquals(null, ICB_LeadsSII_IntegrationService.extractRut(null));
        System.assertEquals(null, ICB_LeadsSII_IntegrationService.extractRut(new Lead()));
        System.assertEquals(null, ICB_LeadsSII_IntegrationService.extractRut(new Lead(RUT__c = '   ')));
    }
}