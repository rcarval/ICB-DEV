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
        System.assertEquals('No hay direccion suficiente para geocodificar', outRes[0].errorMessage);
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

    private class MockGeocodeSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().contains('maps.googleapis.com/maps/api/geocode/json'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"results":[{"geometry":{"location":{"lat":-33.45,"lng":-70.66}}}],"status":"OK"}');
            return res;
        }
    }
}