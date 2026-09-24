public with sharing class ICBFS_GeocodeFromAccountAddress {
    private static final String GOOGLE_BASE_URL = 'https://maps.googleapis.com';
    private static final String GOOGLE_API_KEY = 'AIzaSyCGne7KhusClfRnasLBqqL8Dw_NkDWI8Ps';

    public class GeocodeRequest {
        @InvocableVariable(label='Id de Account' required=true)
        public Id accountId;

        @InvocableVariable(label='Tipo de direccion (SHIPPING/BILLING)')
        public String targetType;
    }

    public class GeocodeResponse {
        @InvocableVariable(label='Latitud')
        public Double latitude;

        @InvocableVariable(label='Longitud')
        public Double longitude;

        @InvocableVariable(label='Mensaje de error')
        public String errorMessage;
    }

    @InvocableMethod(label='ICBFS Geocodificar direccion de Account' callout=true)
    public static List<GeocodeResponse> geocode(List<GeocodeRequest> requests) {
        List<GeocodeResponse> results = new List<GeocodeResponse>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> accountIds = new Set<Id>();
        for (GeocodeRequest req : requests) {
            if (req != null && req.accountId != null) {
                accountIds.add(req.accountId);
            }
        }

        Map<Id, Account> accountMap = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accountMap = new Map<Id, Account>([
                SELECT Id, ShippingStreet, ShippingCity, ShippingState, ShippingCountry,
                       BillingStreet, BillingCity, BillingState, BillingCountry
                FROM Account
                WHERE Id IN :accountIds
            ]);
        }

        for (GeocodeRequest req : requests) {
            GeocodeResponse res = new GeocodeResponse();
            if (req == null || req.accountId == null) {
                res.errorMessage = 'AccountId es requerido';
                results.add(res);
                continue;
            }

            Account acc = accountMap.get(req.accountId);
            if (acc == null) {
                res.errorMessage = 'No se encuentra el Account con ese Id';
                results.add(res);
                continue;
            }

            String target = normalizeTargetType(req.targetType);
            String address = target == 'BILLING'
                ? composeAddress(acc.BillingStreet, acc.BillingCity, acc.BillingState, acc.BillingCountry)
                : composeAddress(acc.ShippingStreet, acc.ShippingCity, acc.ShippingState, acc.ShippingCountry);

            if (String.isBlank(address)) {
                res.errorMessage = 'No hay direccion suficiente para geocodificar';
                results.add(res);
                continue;
            }

            try {
                HttpRequest httpReq = new HttpRequest();
                String endpointUrl = GOOGLE_BASE_URL
                    + '/maps/api/geocode/json?address=' + EncodingUtil.urlEncode(address, 'UTF-8')
                    + '&key=' + EncodingUtil.urlEncode(GOOGLE_API_KEY, 'UTF-8');
                httpReq.setEndpoint(endpointUrl);
                httpReq.setMethod('GET');
                httpReq.setHeader('Accept', 'application/json');

                HttpResponse httpResp = new Http().send(httpReq);
                if (httpResp.getStatusCode() != 200) {
                    Integer code = httpResp.getStatusCode();
                    if (code == 401 || code == 403) {
                        res.errorMessage = 'Google Geocoding rechazo autenticacion/permisos (HTTP ' + code + ')';
                    } else if (code == 429) {
                        res.errorMessage = 'Google Geocoding sin cuota disponible o rate limit (HTTP 429)';
                    } else {
                        res.errorMessage = 'HTTP ' + code + ': ' + httpResp.getBody();
                    }
                    results.add(res);
                    continue;
                }

                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(httpResp.getBody());
                String status = root != null && root.containsKey('status')
                    ? String.valueOf(root.get('status'))
                    : null;
                String providerError = root != null && root.containsKey('error_message')
                    ? String.valueOf(root.get('error_message'))
                    : null;

                List<Object> resultsList = root != null && root.containsKey('results')
                    ? (List<Object>) root.get('results')
                    : null;
                if (resultsList == null || resultsList.isEmpty()) {
                    res.errorMessage = !String.isBlank(providerError)
                        ? 'Geocodificacion rechazada: ' + providerError + ' (status=' + status + ')'
                        : 'No se encontro resultado para geocodificacion';
                    results.add(res);
                    continue;
                }

                Map<String, Object> first = (Map<String, Object>) resultsList[0];
                Map<String, Object> geometry = first != null ? (Map<String, Object>) first.get('geometry') : null;
                Map<String, Object> location = geometry != null ? (Map<String, Object>) geometry.get('location') : null;
                if (location == null || !location.containsKey('lat') || !location.containsKey('lng')) {
                    res.errorMessage = 'Respuesta de geocodificacion sin latitud/longitud';
                    results.add(res);
                    continue;
                }

                res.latitude = (Double) location.get('lat');
                res.longitude = (Double) location.get('lng');
                results.add(res);
            } catch (Exception ex) {
                res.errorMessage = 'Error en callout o parsing: ' + ex.getMessage();
                results.add(res);
            }
        }

        return results;
    }

    private static String normalizeTargetType(String targetType) {
        String raw = String.isBlank(targetType) ? 'SHIPPING' : targetType.trim().toUpperCase();
        return raw == 'BILLING' ? 'BILLING' : 'SHIPPING';
    }

    private static String composeAddress(String street, String city, String state, String country) {
        List<String> parts = new List<String>();
        if (!String.isBlank(street)) {
            parts.add(street.trim());
        }
        if (!String.isBlank(city)) {
            parts.add(city.trim());
        }
        if (!String.isBlank(state)) {
            parts.add(state.trim());
        }
        if (!String.isBlank(country)) {
            parts.add(country.trim());
        }
        return String.join(parts, ', ');
    }
}