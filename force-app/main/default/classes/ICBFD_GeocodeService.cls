/**
 * ICB Food Service
 * Desarrollado por: José Illanes
 * Fecha: 2026-02-05
 * Descripción: Geocodifica una dirección (texto) usando OpenStreetMap Nominatim y retorna lat/lon para Flow.
 */
public with sharing class ICBFD_GeocodeService {

    public class Request {
        @InvocableVariable(required=true)
        public String direccion;
    }

    public class Response {
        @InvocableVariable
        public Decimal latitud;

        @InvocableVariable
        public Decimal longitud;

        @InvocableVariable
        public String rawJson;

        @InvocableVariable
        public String error;
    }

    @InvocableMethod(label='ICBFD Geocodificar Dirección (Gratis)' description='Convierte dirección a lat/long usando OpenStreetMap Nominatim')
    public static List<Response> geocode(List<Request> requests) {
        List<Response> results = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();

            try {
                if (String.isBlank(req.direccion)) {
                    res.error = 'Dirección vacía';
                    results.add(res);
                    continue;
                }

                String encoded = EncodingUtil.urlEncode(req.direccion, 'UTF-8');

                // Nominatim (OpenStreetMap) - formato JSON
                String endpoint = 'https://nominatim.openstreetmap.org/search?q=' + encoded
                                + '&format=json&limit=1&addressdetails=0';

                HttpRequest httpReq = new HttpRequest();
                httpReq.setMethod('GET');
                httpReq.setEndpoint(endpoint);

                // IMPORTANTE: Nominatim exige User-Agent identificable
                httpReq.setHeader('User-Agent', 'ICBFD-Salesforce-Geocoder/1.0 (contacto@icbfs.cl)');

                // Si tu org bloquea callouts, agrega Remote Site Settings a nominatim.openstreetmap.org
                Http http = new Http();
                HttpResponse httpRes = http.send(httpReq);

                res.rawJson = httpRes.getBody();

                if (httpRes.getStatusCode() < 200 || httpRes.getStatusCode() >= 300) {
                    res.error = 'HTTP ' + httpRes.getStatusCode() + ' - ' + httpRes.getStatus();
                    results.add(res);
                    continue;
                }

                List<Object> arr = (List<Object>) JSON.deserializeUntyped(httpRes.getBody());
                if (arr == null || arr.isEmpty()) {
                    res.error = 'Sin resultados para la dirección';
                    results.add(res);
                    continue;
                }

                Map<String, Object> first = (Map<String, Object>) arr[0];
                // Nominatim devuelve lat/lon como String
                res.latitud  = Decimal.valueOf(String.valueOf(first.get('lat')));
                res.longitud = Decimal.valueOf(String.valueOf(first.get('lon')));

            } catch (Exception e) {
                res.error = e.getMessage();
            }

            results.add(res);
        }

        return results;
    }
}