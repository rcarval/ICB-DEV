public with sharing class ICBFS_GeocodeJob implements Queueable, Database.AllowsCallouts {

    private Id domicilioId;

    public ICBFS_GeocodeJob(Id domicilioId) {
        this.domicilioId = domicilioId;
    }

    public void execute(QueueableContext context) {
        if (domicilioId == null) return;

        Domicilio_de_Cliente__c dom = [
            SELECT Id,
                   Region__c,
                   Domicilio_Adicional__Street__s,
                   Domicilio_Adicional__City__s,
                   Domicilio_Adicional__StateCode__s,
                   Domicilio_Adicional__PostalCode__s,
                   Domicilio_Adicional__CountryCode__s
            FROM Domicilio_de_Cliente__c
            WHERE Id = :domicilioId
            LIMIT 1
        ];

        List<String> parts = new List<String>();
        if (!String.isBlank(dom.Domicilio_Adicional__Street__s)) parts.add(dom.Domicilio_Adicional__Street__s.trim());
        if (!String.isBlank(dom.Domicilio_Adicional__City__s)) parts.add(dom.Domicilio_Adicional__City__s.trim());
        if (!String.isBlank(dom.Domicilio_Adicional__StateCode__s)) parts.add(dom.Domicilio_Adicional__StateCode__s.trim());
        if (!String.isBlank(dom.Domicilio_Adicional__PostalCode__s)) parts.add(dom.Domicilio_Adicional__PostalCode__s.trim());
        if (!String.isBlank(dom.Domicilio_Adicional__CountryCode__s)) parts.add(dom.Domicilio_Adicional__CountryCode__s.trim());
        if (dom.Region__c != null && !String.isBlank(String.valueOf(dom.Region__c))) {
            parts.add(String.valueOf(dom.Region__c).trim());
        }

        String addressText = String.join(parts, ', ');
        if (String.isBlank(addressText)) return;

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setTimeout(10000);

        String endpoint =
            'https://maps.googleapis.com/maps/api/geocode/json?address=' +
            EncodingUtil.urlEncode(addressText, 'UTF-8') +
            '&key=TU_API_KEY_AQUI';

        req.setEndpoint(endpoint);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) return;

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if ((String)root.get('status') != 'OK') return;

        List<Object> results = (List<Object>) root.get('results');
        if (results == null || results.isEmpty()) return;

        Map<String, Object> first = (Map<String, Object>) results[0];
        Map<String, Object> geometry = (Map<String, Object>) first.get('geometry');
        Map<String, Object> loc = (Map<String, Object>) geometry.get('location');

        Double lat = Double.valueOf(String.valueOf(loc.get('lat')));
        Double lng = Double.valueOf(String.valueOf(loc.get('lng')));

        update new Domicilio_de_Cliente__c(
            Id = domicilioId,
            Latitud__c = String.valueOf(lat),
            Longitud__c = String.valueOf(lng)
        );
    }
}