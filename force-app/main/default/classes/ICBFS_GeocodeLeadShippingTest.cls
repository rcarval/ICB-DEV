@IsTest
private class ICBFS_GeocodeLeadShippingTest {
    private static Lead createLead(Boolean withAddress) {
        Lead ld = new Lead(
            LastName = 'GEO TEST',
            Company = 'GEO TEST SPA',
            Status = 'Validación SII'
        );
        if (withAddress) {
            ld.Direccion_de_Despacho__Street__s = 'El Greco 510';
            ld.Direccion_de_Despacho__City__s = 'Maipu';
            ld.Direccion_de_Despacho__CountryCode__s = 'CL';
        }
        insert ld;
        return ld;
    }

    @IsTest
    static void geocodesIncompleteLeadAndPersistsPair() {
        Lead ld = createLead(true);
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        ICBFS_GeocodeLeadShipping.Request req = new ICBFS_GeocodeLeadShipping.Request();
        req.leadId = ld.Id;

        Test.startTest();
        List<ICBFS_GeocodeLeadShipping.Result> results =
            ICBFS_GeocodeLeadShipping.geocode(new List<ICBFS_GeocodeLeadShipping.Request>{ req });
        Test.stopTest();

        Lead updated = [
            SELECT Direccion_de_Despacho__Latitude__s, Direccion_de_Despacho__Longitude__s
            FROM Lead WHERE Id = :ld.Id
        ];
        System.assertEquals(true, results[0].success);
        System.assertEquals(false, results[0].skipped);
        System.assertEquals(-33.45, updated.Direccion_de_Despacho__Latitude__s);
        System.assertEquals(-70.66, updated.Direccion_de_Despacho__Longitude__s);
    }

    @IsTest
    static void skipsLeadWithCompletePairWithoutCallout() {
        Lead ld = createLead(true);
        ld.Direccion_de_Despacho__Latitude__s = -33.44;
        ld.Direccion_de_Despacho__Longitude__s = -70.65;
        update ld;
        ICBFS_GeocodeLeadShipping.Request req = new ICBFS_GeocodeLeadShipping.Request();
        req.leadId = ld.Id;

        List<ICBFS_GeocodeLeadShipping.Result> results =
            ICBFS_GeocodeLeadShipping.geocode(new List<ICBFS_GeocodeLeadShipping.Request>{ req });

        System.assertEquals(0, Limits.getCallouts());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[0].skipped);
    }

    @IsTest
    static void skipsInsufficientAddressAndHandlesInvalidRequest() {
        Lead ld = createLead(false);
        ICBFS_GeocodeLeadShipping.Request req = new ICBFS_GeocodeLeadShipping.Request();
        req.leadId = ld.Id;

        List<ICBFS_GeocodeLeadShipping.Result> results = ICBFS_GeocodeLeadShipping.geocode(
            new List<ICBFS_GeocodeLeadShipping.Request>{ req, null }
        );

        System.assertEquals(true, results[0].skipped);
        System.assert(results[0].errorMessage.contains('direccion suficiente'));
        System.assertEquals('LeadId es requerido', results[1].errorMessage);
        System.assertEquals(0, Limits.getCallouts());
    }

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"OK","results":[{"geometry":{"location":{"lat":-33.45,"lng":-70.66}}}]}');
            return res;
        }
    }
}