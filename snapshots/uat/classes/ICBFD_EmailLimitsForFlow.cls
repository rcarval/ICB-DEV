public with sharing class ICBFD_EmailLimitsForFlow {

    public class Request {
        @InvocableVariable public String dummy;
    }

    public class Response {
        @InvocableVariable public Integer maximo;
        @InvocableVariable public Integer restante;
        @InvocableVariable public String mensaje;
    }

    @InvocableMethod(label='ICBFD - Obtener capacidad email (Org Limits)')
    public static List<Response> run(List<Request> reqs) {

        Response r = new Response();

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:LimiteEmail/services/data/v65.0/limits');

        // 🔥 Autenticación con sesión actual
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            r.mensaje = 'Error consultando límites: ' + res.getStatusCode();
            return new List<Response>{ r };
        }

        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        for (String key : payload.keySet()) {
            if (key != null && key.toLowerCase().contains('singleemail')) {
                Map<String, Object> lim =
                    (Map<String, Object>) payload.get(key);

                r.maximo = (Integer) lim.get('Max');
                r.restante = (Integer) lim.get('Remaining');
                break;
            }
        }

        if (r.maximo == null) {
            r.mensaje = 'No se encontró límite de email.';
        } else {
            r.mensaje =
                'Disponibles hoy: ' + r.restante + ' de ' + r.maximo;
        }

        return new List<Response>{ r };
    }
}