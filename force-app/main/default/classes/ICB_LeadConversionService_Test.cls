@IsTest
private class ICB_LeadConversionService_Test {

    private static Lead createLeadBase() {
        Lead ld = new Lead(
            FirstName = 'CASA PARAISO',
            LastName = 'RESTAURANTE',
            Company = 'ABAST Y SERV DE LOS IND DE LA MADERA DE VALPO Y ACON LTDA',
            Status = 'Validación SII',
            RUT__c = '81482800-K',
            Cliente_Contactado__c = 'SI'
        );
        insert ld;
        return ld;
    }

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
        Lead ld = createLeadBase();
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
    static void convertAndMapLeads_copiesCompleteShippingCoordinates() {
        Lead ld = createLeadBase();
        ld.Direccion_de_Despacho__Latitude__s = -33.4501;
        ld.Direccion_de_Despacho__Longitude__s = -70.6602;
        update ld;

        ICB_LeadConversionService.setSimulateSuccessfulConversionForTests(true);
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ ld.Id });
        Test.stopTest();

        Account convertedAccount = [
            SELECT ShippingLatitude, ShippingLongitude
            FROM Account
            WHERE Id = :results[0].accountId
        ];
        System.assertEquals(-33.4501, convertedAccount.ShippingLatitude);
        System.assertEquals(-70.6602, convertedAccount.ShippingLongitude);
    }

    @IsTest
    static void convertAndMapLeads_doesNotCopyNullShippingCoordinates() {
        Lead ld = createLeadBase();
        ld.Direccion_de_Despacho__Latitude__s = null;
        ld.Direccion_de_Despacho__Longitude__s = null;

        ICB_LeadConversionService.setSimulateSuccessfulConversionForTests(true);
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ ld.Id });
        Test.stopTest();

        Account convertedAccount = [
            SELECT ShippingLatitude, ShippingLongitude
            FROM Account
            WHERE Id = :results[0].accountId
        ];
        System.assertEquals(null, convertedAccount.ShippingLatitude);
        System.assertEquals(null, convertedAccount.ShippingLongitude);
    }

    @IsTest
    static void convertAndMapLeads_simulated_bulkTwoLeads() {
        Lead a = createLeadBase();
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
        Lead ld = createLeadBase();
        Test.startTest();
        List<ICB_LeadConversionService.ConversionResult> results =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ ld.Id });
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(ld.Id, results[0].leadId);
        System.assertNotEquals(null, results[0].success);
    }
}