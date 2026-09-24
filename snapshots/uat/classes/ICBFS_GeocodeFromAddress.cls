public with sharing class ICBFS_GeocodeFromAddress {

    public class GeocodeRequest {
        @InvocableVariable(required=true)
        public Id domicilioId;
    }

    @InvocableMethod(label='Geocodificar domicilio (Async)')
    public static void geocode(List<GeocodeRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        Set<Id> ids = new Set<Id>();
        for (GeocodeRequest r : requests) {
            if (r != null && r.domicilioId != null) {
                ids.add(r.domicilioId);
            }
        }
        if (!ids.isEmpty()) {
            geocodeAsync(new List<Id>(ids));
        }
    }

    @future(callout=true)
    private static void geocodeAsync(List<Id> domicilioIds) {
        List<Domicilio_de_Cliente__c> doms = [
            SELECT Id, Direccion_Para_Geocode__c
            FROM Domicilio_de_Cliente__c
            WHERE Id IN :domicilioIds
        ];

        List<Domicilio_de_Cliente__c> toUpdate = new List<Domicilio_de_Cliente__c>();

        for (Domicilio_de_Cliente__c dom : doms) {
            if (String.isBlank(dom.Direccion_Para_Geocode__c)) continue;

            try {
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');

                String endpoint =
                    'https://maps.googleapis.com/maps/api/geocode/json?address=' +
                    EncodingUtil.urlEncode(dom.Direccion_Para_Geocode__c, 'UTF-8') +
                    '&key=' + getApiKey();

                req.setEndpoint(endpoint);

                HttpResponse res = new Http().send(req);
                if (res.getStatusCode() != 200) continue;

                Map<String, Object> root =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                if ((String)root.get('status') != 'OK') continue;

                List<Object> results = (List<Object>) root.get('results');
                if (results.isEmpty()) continue;

                Map<String, Object> geometry =
                    (Map<String, Object>) ((Map<String, Object>)results[0]).get('geometry');
                Map<String, Object> location =
                    (Map<String, Object>) geometry.get('location');

                toUpdate.add(new Domicilio_de_Cliente__c(
                    Id = dom.Id,
                    Latitud__c = String.valueOf(location.get('lat')),
                    Longitud__c = String.valueOf(location.get('lng'))
                ));

            } catch (Exception e) {
                // fail silent (opcional: guardar debug)
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static String getApiKey() {
        return 'TU_API_KEY_AQUI';
    }
}