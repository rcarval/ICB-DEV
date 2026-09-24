@IsTest
private class ICB_LeadConversionService_Test {

    @IsTest
    static void convertAndMapLeads_null_returnsEmpty() {
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> r = ICB_LeadConversionService.convertAndMapLeads(null);
        Test.stopTest();
        System.assertEquals(0, r.size());
    }

    @IsTest
    static void convertAndMapLeads_empty_returnsEmpty() {
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> r = ICB_LeadConversionService.convertAndMapLeads(new Set<Id>());
        Test.stopTest();
        System.assertEquals(0, r.size());
    }

    @IsTest
    static void convertAndMapLeads_noLeadRows_leadNoEncontrado() {
        Id notALeadId = UserInfo.getOrganizationId();
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ notALeadId });
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('Lead no encontrado', results[0].message);
    }

    @IsTest
    static void convertAndMapLeads_simulated_success_and_mapping() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        ICB_LeadConversionService.setSimulateSuccessfulConversionForTests(true);
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ ld.Id });
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].accountId);
    }

    @IsTest
    static void convertAndMapLeads_simulated_bulkTwoLeads() {
        Lead a = ICB_LeadsSII_TestFactory.createLeadBase();
        Lead b = new Lead(
            FirstName = 'Bulk',
            LastName = 'Dos',
            Company = 'EMPRESA BULK DOS SPA',
            Status = 'Validación SII',
            RUT__c = '12345678-5',
            Cliente_Contactado__c = 'SI'
        );
        insert b;
        ICB_LeadConversionService.setSimulateSuccessfulConversionForTests(true);
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ a.Id, b.Id });
        Test.stopTest();
        System.assertEquals(2, results.size());
        for (ICB_LeadConversionService.ConversionResult cr : results) {
            System.assertEquals(true, cr.success);
        }
    }

    @IsTest
    static void convertAndMapLeads_realConvertPath_smoke() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ ld.Id });
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(ld.Id, results[0].leadId);
        System.assertNotEquals(null, results[0].success);
    }
}