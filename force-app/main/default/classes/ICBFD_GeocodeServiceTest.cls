/**
 * ICB Food Service
 * Desarrollado por: José Illanes
 * Fecha: 2026-02-05
 * Descripción: Test class para ICBFD_GeocodeService usando HttpCalloutMock (OpenStreetMap Nominatim).
 */
@IsTest
private class ICBFD_GeocodeServiceTest {

    private class NominatimMockOk implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Validaciones básicas
            System.assertEquals('GET', req.getMethod(), 'El método debe ser GET');
            System.assert(req.getEndpoint().contains('nominatim.openstreetmap.org/search'),
                'El endpoint debe apuntar a Nominatim');

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            // Nominatim devuelve un array de resultados con lat/lon como strings
            res.setBody('[{"lat":"-33.4990000","lon":"-70.7500000"}]');
            return res;
        }
    }

    private class NominatimMockEmpty implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('[]'); // sin resultados
            return res;
        }
    }

    @IsTest
    static void geocode_ok_devuelve_lat_lon() {
        Test.setMock(HttpCalloutMock.class, new NominatimMockOk());

        ICBFD_GeocodeService.Request r = new ICBFD_GeocodeService.Request();
        r.direccion = 'El Greco 510, MAIPU, Chile';

        Test.startTest();
        List<ICBFD_GeocodeService.Response> out = ICBFD_GeocodeService.geocode(new List<ICBFD_GeocodeService.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, out.size(), 'Debe devolver 1 respuesta');
        System.assertEquals(Decimal.valueOf('-33.4990000'), out[0].latitud, 'Latitud incorrecta');
        System.assertEquals(Decimal.valueOf('-70.7500000'), out[0].longitud, 'Longitud incorrecta');
        System.assertEquals(null, out[0].error, 'No debería venir error');
        System.assertNotEquals(null, out[0].rawJson, 'Debe guardar rawJson');
    }

    @IsTest
    static void geocode_sin_resultados_devuelve_error() {
        Test.setMock(HttpCalloutMock.class, new NominatimMockEmpty());

        ICBFD_GeocodeService.Request r = new ICBFD_GeocodeService.Request();
        r.direccion = 'Direccion Inexistente 123, Narnia';

        Test.startTest();
        List<ICBFD_GeocodeService.Response> out = ICBFD_GeocodeService.geocode(new List<ICBFD_GeocodeService.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, out.size(), 'Debe devolver 1 respuesta');
        System.assertEquals(null, out[0].latitud, 'Latitud debe venir null');
        System.assertEquals(null, out[0].longitud, 'Longitud debe venir null');
        System.assertEquals('Sin resultados para la dirección', out[0].error, 'Mensaje de error esperado');
    }

    @IsTest
    static void geocode_direccion_vacia_devuelve_error() {
        // No requiere mock porque no debería llamar al endpoint si la dirección viene vacía
        ICBFD_GeocodeService.Request r = new ICBFD_GeocodeService.Request();
        r.direccion = '';

        Test.startTest();
        List<ICBFD_GeocodeService.Response> out = ICBFD_GeocodeService.geocode(new List<ICBFD_GeocodeService.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, out.size(), 'Debe devolver 1 respuesta');
        System.assertEquals('Dirección vacía', out[0].error, 'Debe indicar dirección vacía');
    }
}