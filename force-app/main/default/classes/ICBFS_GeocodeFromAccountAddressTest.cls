@IsTest
private class ICBFS_GeocodeFromAccountAddressTest {

    @IsTest
    static void testShippingSuccess() {
        Account acc = new Account(
            Name = 'Cuenta Shipping',
            ShippingStreet = 'Av. Libertador 123',
            ShippingCity = 'Santiago',
            ShippingState = 'Metropolitana',
            ShippingCountry = 'Chile'
        );
        insert acc;

        Test.setMock(HttpCalloutMock.class, new MockGeocodeSuccess());

        ICBFS_GeocodeFromAccountAddress.GeocodeRequest req = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        req.accountId = acc.Id;
        req.targetType = 'SHIPPING';

        Test.startTest();
        List<ICBFS_GeocodeFromAccountAddress.GeocodeResponse> outRes =
            ICBFS_GeocodeFromAccountAddress.geocode(new List<ICBFS_GeocodeFromAccountAddress.GeocodeRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, outRes.size());
        System.assertEquals(-33.45, outRes[0].latitude);
        System.assertEquals(-70.66, outRes[0].longitude);
        System.assertEquals(null, outRes[0].errorMessage);
    }

    @IsTest
    static void testBillingWithoutAddressReturnsError() {
        Account acc = new Account(Name = 'Cuenta Billing');
        insert acc;

        ICBFS_GeocodeFromAccountAddress.GeocodeRequest req = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        req.accountId = acc.Id;
        req.targetType = 'BILLING';

        List<ICBFS_GeocodeFromAccountAddress.GeocodeResponse> outRes =
            ICBFS_GeocodeFromAccountAddress.geocode(new List<ICBFS_GeocodeFromAccountAddress.GeocodeRequest>{ req });

        System.assertEquals(1, outRes.size());
        System.assertEquals(
            'No hay direccion suficiente para geocodificar (calle, ciudad y pais)',
            outRes[0].errorMessage
        );
    }

    @IsTest
    static void testCompleteShippingCoordinatesSkipCallout() {
        Account acc = new Account(
            Name = 'Cuenta Coordenadas Existentes',
            ShippingStreet = 'Av. Libertador 123',
            ShippingCity = 'Santiago',
            ShippingCountry = 'Chile',
            ShippingLatitude = -33.44,
            ShippingLongitude = -70.65
        );
        insert acc;

        ICBFS_GeocodeFromAccountAddress.GeocodeRequest req = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        req.accountId = acc.Id;
        req.targetType = 'SHIPPING';

        List<ICBFS_GeocodeFromAccountAddress.GeocodeResponse> outRes =
            ICBFS_GeocodeFromAccountAddress.geocode(
                new List<ICBFS_GeocodeFromAccountAddress.GeocodeRequest>{ req }
            );

        System.assertEquals(0, Limits.getCallouts());
        System.assertEquals(null, outRes[0].latitude);
        System.assertEquals(null, outRes[0].longitude);
        System.assertEquals('Coordenadas ya informadas; geocodificacion omitida', outRes[0].errorMessage);
    }

    @IsTest
    static void testSucursalSkipsBilling() {
        Id sucursalRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Sucursal')
            .getRecordTypeId();
        Account acc = new Account(
            Name = 'Sucursal Sin Billing GEO',
            RecordTypeId = sucursalRtId,
            BillingStreet = 'Av. Apoquindo 3000',
            BillingCity = 'Las Condes',
            BillingCountry = 'Chile'
        );
        insert acc;

        ICBFS_GeocodeFromAccountAddress.GeocodeRequest req = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        req.accountId = acc.Id;
        req.targetType = 'BILLING';

        List<ICBFS_GeocodeFromAccountAddress.GeocodeResponse> outRes =
            ICBFS_GeocodeFromAccountAddress.geocode(
                new List<ICBFS_GeocodeFromAccountAddress.GeocodeRequest>{ req }
            );

        System.assertEquals(0, Limits.getCallouts());
        System.assertEquals('Billing no aplica para Account Sucursal', outRes[0].errorMessage);
    }

    @IsTest
    static void testNullAndInvalidRequests() {
        ICBFS_GeocodeFromAccountAddress.GeocodeRequest nullIdReq = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        ICBFS_GeocodeFromAccountAddress.GeocodeRequest invalidReq = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        invalidReq.accountId = '001000000000000AAA';

        List<ICBFS_GeocodeFromAccountAddress.GeocodeResponse> outRes =
            ICBFS_GeocodeFromAccountAddress.geocode(
                new List<ICBFS_GeocodeFromAccountAddress.GeocodeRequest>{ nullIdReq, invalidReq }
            );

        System.assertEquals(2, outRes.size());
        System.assertEquals('AccountId es requerido', outRes[0].errorMessage);
        System.assertEquals('No se encuentra el Account con ese Id', outRes[1].errorMessage);
    }

    @IsTest
    static void testReusableComposedAddressGeocoding() {
        Test.setMock(HttpCalloutMock.class, new MockGeocodeSuccess());

        Test.startTest();
        ICBFS_GeocodeFromAccountAddress.GeocodeResponse result =
            ICBFS_GeocodeFromAccountAddress.geocodeComposedAddress('El Greco 510, Maipu, CL');
        Test.stopTest();

        System.assertEquals(-33.45, result.latitude);
        System.assertEquals(-70.66, result.longitude);
        System.assertEquals(null, result.errorMessage);
    }

    @IsTest
    static void testReusableAddressHandlesBlankAndProviderFailures() {
        ICBFS_GeocodeFromAccountAddress.GeocodeResponse blankResult =
            ICBFS_GeocodeFromAccountAddress.geocodeComposedAddress('');
        System.assertEquals('No hay direccion suficiente para geocodificar', blankResult.errorMessage);

        Test.setMock(HttpCalloutMock.class, new MockGeocodeResponse(429, '{"status":"OVER_QUERY_LIMIT"}'));
        ICBFS_GeocodeFromAccountAddress.GeocodeResponse rateLimited =
            ICBFS_GeocodeFromAccountAddress.geocodeComposedAddress('El Greco 510, Maipu, CL');
        System.assertEquals(
            'Google Geocoding sin cuota disponible o rate limit (HTTP 429)',
            rateLimited.errorMessage
        );
    }

    @IsTest
    static void testReusableAddressHandlesZeroResults() {
        Test.setMock(HttpCalloutMock.class, new MockGeocodeResponse(200, '{"status":"ZERO_RESULTS","results":[]}'));
        ICBFS_GeocodeFromAccountAddress.GeocodeResponse result =
            ICBFS_GeocodeFromAccountAddress.geocodeComposedAddress('Direccion inexistente, CL');
        System.assertEquals('No se encontro resultado para geocodificacion', result.errorMessage);
    }

    private class MockGeocodeSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().contains('maps.googleapis.com/maps/api/geocode/json'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"results":[{"geometry":{"location":{"lat":-33.45,"lng":-70.66}}}],"status":"OK"}');
            return res;
        }
    }

    private class MockGeocodeResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        MockGeocodeResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }
}