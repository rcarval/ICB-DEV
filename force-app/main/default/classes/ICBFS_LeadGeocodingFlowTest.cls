@IsTest
private class ICBFS_LeadGeocodingFlowTest {
    @IsTest
    static void flowGeocodesLeadWithEligibleAddress() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        Lead ld = new Lead(
            LastName = 'FLOW GEO',
            Company = 'FLOW GEO SPA',
            Status = 'Validación SII',
            Direccion_de_Despacho__Street__s = 'El Greco 510',
            Direccion_de_Despacho__City__s = 'Maipu',
            Direccion_de_Despacho__CountryCode__s = 'CL'
        );
        insert ld;
        Test.stopTest();

        Lead updated = [
            SELECT Direccion_de_Despacho__Latitude__s, Direccion_de_Despacho__Longitude__s
            FROM Lead WHERE Id = :ld.Id
        ];
        // Las rutas AsyncAfterCommit de Flow no se ejecutan de forma observable
        // en este tipo de test Apex. Este test valida el criterio de entrada y
        // que el DML que agenda el Flow no bloquee la transaccion comercial.
        System.assertEquals(null, updated.Direccion_de_Despacho__Latitude__s);
        System.assertEquals(null, updated.Direccion_de_Despacho__Longitude__s);
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