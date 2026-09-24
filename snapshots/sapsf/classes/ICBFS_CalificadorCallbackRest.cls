@RestResource(urlMapping='/icbfs/calificador/callback/*')
global without sharing class ICBFS_CalificadorCallbackRest {
    @HttpPost
    global static void receive() {
        RestRequest incoming = RestContext.request;
        String rawBody = incoming.requestBody == null ? null : incoming.requestBody.toString();
        ICBFS_CalificadorConfig.Values config = ICBFS_CalificadorConfig.getValues();
        if (!secureEquals(config.callbackToken, header(incoming, 'X-ICBFS-Callback-Token'))) {
            respond(401, new Map<String, Object>{'ok'=>false, 'error'=>'no autorizado'});
            return;
        }
        String correlationId = header(incoming, 'X-ICBFS-Correlation-Id');
        if (String.isBlank(correlationId)) {
            respond(400, new Map<String, Object>{'ok'=>false, 'error'=>'falta correlation id'});
            return;
        }
        List<ICBFS_Calificacion_Request__c> matches = [
            SELECT Id, Account__c, Execution_Arn__c, Estado__c
            FROM ICBFS_Calificacion_Request__c
            WHERE Correlation_Id__c=:correlationId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (matches.isEmpty()) {
            respond(404, new Map<String, Object>{'ok'=>false, 'error'=>'solicitud no encontrada'});
            return;
        }
        ICBFS_Calificacion_Request__c request = matches[0];
        if (String.isBlank(request.Execution_Arn__c)) {
            respond(409, new Map<String, Object>{'ok'=>false, 'error'=>'solicitud aun sin execution arn'});
            return;
        }
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(rawBody);
            Boolean failed = 'fallido'.equalsIgnoreCase(stringValue(root.get('estado')));
            if (!failed && !containsAccount(root, String.valueOf(request.Account__c))) {
                respond(422, new Map<String, Object>{'ok'=>false, 'error'=>'payload sin lead correlacionado'});
                return;
            }
            Database.SaveResult result = EventBus.publish(new ICBFS_Calificacion_Lead__e(
                Account_Id__c=String.valueOf(request.Account__c),
                Execution_Arn__c=request.Execution_Arn__c,
                Payload__c=rawBody
            ));
            if (!result.isSuccess()) {
                respond(503, new Map<String, Object>{'ok'=>false, 'error'=>'no fue posible encolar el resultado'});
                return;
            }
            respond(202, new Map<String, Object>{'ok'=>true, 'estado'=>'recibido'});
        } catch (Exception error) {
            respond(400, new Map<String, Object>{'ok'=>false, 'error'=>'json invalido'});
        }
    }

    private static Boolean containsAccount(Map<String, Object> root, String accountId) {
        if (root == null || !(root.get('leads') instanceof List<Object>)) return false;
        for (Object item : (List<Object>) root.get('leads')) {
            if (item instanceof Map<String, Object>
                && accountId == stringValue(((Map<String, Object>) item).get('codigo'))) return true;
        }
        return false;
    }

    private static String header(RestRequest request, String expected) {
        String direct = request.headers.get(expected);
        if (direct != null) return direct;
        for (String key : request.headers.keySet()) if (key.equalsIgnoreCase(expected)) return request.headers.get(key);
        return null;
    }

    private static Boolean secureEquals(String expected, String actual) {
        if (String.isBlank(expected) || String.isBlank(actual)) return false;
        String left = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(expected)));
        String right = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(actual)));
        return left == right;
    }

    private static String stringValue(Object value) { return value == null ? null : String.valueOf(value); }
    private static void respond(Integer statusCode, Map<String, Object> body) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}