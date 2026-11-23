public with sharing class ICBFS_CalificacionEventHandler {
    public static void afterInsert(List<ICBFS_Calificacion_Lead__e> events) {
        if (events == null || events.isEmpty()) return;
        Set<String> executionArns = new Set<String>();
        for (ICBFS_Calificacion_Lead__e event : events) if (String.isNotBlank(event.Execution_Arn__c)) executionArns.add(event.Execution_Arn__c);
        Map<String, ICBFS_Calificacion_Request__c> requestByArn = new Map<String, ICBFS_Calificacion_Request__c>();
        if (!executionArns.isEmpty()) {
            for (ICBFS_Calificacion_Request__c request : [
                SELECT Id, Account__c, Execution_Arn__c, Estado__c
                FROM ICBFS_Calificacion_Request__c WHERE Execution_Arn__c IN :executionArns
            ]) requestByArn.put(request.Execution_Arn__c, request);
        }
        Map<Id, ICBFS_Calificacion_Request__c> requestUpdates = new Map<Id, ICBFS_Calificacion_Request__c>();
        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        for (ICBFS_Calificacion_Lead__e event : events) {
            try {
                ICBFS_Calificacion_Request__c request = requestByArn.get(event.Execution_Arn__c);
                if (request == null) {
                    logInbound(event, false, 'ExecutionArn sin solicitud asociada');
                    continue;
                }
                if (request.Estado__c == 'Completado' || request.Estado__c == 'Error') {
                    logInbound(event, true, 'Callback duplicado ignorado');
                    continue;
                }
                Id eventAccountId = parseAccountId(event.Account_Id__c);
                if (eventAccountId == null || eventAccountId != request.Account__c) {
                    logInbound(event, false, 'AccountId no coincide con la solicitud');
                    continue;
                }
                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
                if ('fallido'.equalsIgnoreCase(stringValue(root.get('estado')))) {
                    String failure = truncate(stringValue(root.get('error')), 32768);
                    if (String.isBlank(failure)) failure = 'Calificador AWS informo estado fallido';
                    accountUpdates.put(request.Account__c, new Account(
                        Id=request.Account__c, ICBFS_Calificador_Estado__c='Error',
                        ICBFS_Calificador_Fecha_Respuesta__c=System.now(), ICBFS_Calificador_Ultimo_Error__c=failure
                    ));
                    requestUpdates.put(request.Id, new ICBFS_Calificacion_Request__c(
                        Id=request.Id, Estado__c='Error', Fecha_Respuesta__c=System.now(),
                        Payload_Respuesta__c=truncate(event.Payload__c, 131072), Ultimo_Error__c=failure
                    ));
                    logInbound(event, true, 'Fallo de AWS correlacionado');
                    continue;
                }
                Map<String, Object> lead = findLead(root, String.valueOf(request.Account__c));
                if (lead == null) throw new CalificacionEventException('Payload sin lead correlacionado');
                Account account = new Account(
                    Id=request.Account__c,
                    ICBFS_Calificador_Estado__c='Completado',
                    ICBFS_Calificador_Fecha_Respuesta__c=System.now(),
                    ICBFS_Calificador_Ultimo_Error__c=null,
                    ICBFS_Calificacion__c=stringValue(lead.get('calificacion')),
                    ICBFS_Calificador_Score__c=decimalValue(lead.get('score')),
                    ICBFS_Calificador_Segmento__c=stringValue(lead.get('segmento')),
                    ICBFS_Calificador_Confiabilidad__c=stringValue(lead.get('confiabilidad')),
                    ICBFS_Calificador_D1__c=dimensionScore(lead, 'd1'), ICBFS_Calificador_D2__c=dimensionScore(lead, 'd2'),
                    ICBFS_Calificador_D3__c=dimensionScore(lead, 'd3'), ICBFS_Calificador_D4__c=dimensionScore(lead, 'd4'),
                    ICBFS_Calificador_Alertas__c=serializeValue(lead.get('alertas'), 32768),
                    ICBFS_Calificador_Notas__c=truncate(stringValue(lead.get('notas')), 32768)
                );
                accountUpdates.put(account.Id, account);
                requestUpdates.put(request.Id, new ICBFS_Calificacion_Request__c(
                    Id=request.Id, Estado__c='Completado', Fecha_Respuesta__c=System.now(),
                    Payload_Respuesta__c=truncate(event.Payload__c, 131072), Ultimo_Error__c=null
                ));
                logInbound(event, true, 'Resultado correlacionado');
            } catch (Exception error) {
                logInbound(event, false, error.getMessage());
            }
        }
        if (!requestUpdates.isEmpty()) {
            List<ICBFS_Calificacion_Request__c> filas = requestUpdates.values();
            reportarFallos('ICBFS_Calificacion_Request__c', filas, Database.update(filas, false));
        }
        if (!accountUpdates.isEmpty()) {
            List<Account> filas = accountUpdates.values();
            reportarFallos('Account', filas, Database.update(filas, false));
        }
    }

    private static void reportarFallos(String objeto, List<SObject> filas, List<Database.SaveResult> resultados) {
        List<String> fallos = new List<String>();
        for (Integer i = 0; i < resultados.size(); i++) {
            if (resultados[i].isSuccess()) continue;
            List<String> motivos = new List<String>();
            for (Database.Error e : resultados[i].getErrors()) motivos.add(e.getStatusCode() + ': ' + e.getMessage());
            fallos.add(filas[i].Id + ' -> ' + String.join(motivos, ' | '));
        }
        if (fallos.isEmpty()) return;
        String detalle = 'No se pudo actualizar ' + fallos.size() + ' fila(s) de ' + objeto + ': ' + String.join(fallos, ' ;; ');
        ICB_LogIntegracionService.insertarLogInbound(
            'ICBFS_CalificacionEventHandler.afterInsert', null, false,
            truncate(detalle, 32768), truncate('Escritura fallida en ' + objeto, 500)
        );
    }

    private static Map<String, Object> findLead(Map<String, Object> root, String accountId) {
        if (root == null || !(root.get('leads') instanceof List<Object>)) return null;
        for (Object item : (List<Object>) root.get('leads')) {
            if (!(item instanceof Map<String, Object>)) continue;
            Map<String, Object> lead = (Map<String, Object>) item;
            if (accountId == stringValue(lead.get('codigo'))) return lead;
        }
        return null;
    }

    private static Decimal dimensionScore(Map<String, Object> lead, String key) {
        Object dimension = lead.get(key);
        if (!(dimension instanceof Map<String, Object>)) return null;
        return decimalValue(((Map<String, Object>) dimension).get('puntaje'));
    }

    private static Id parseAccountId(String value) {
        try { return String.isBlank(value) ? null : (Id) value; } catch (Exception ignored) { return null; }
    }
    private static String stringValue(Object value) { return value == null ? null : String.valueOf(value); }
    private static Decimal decimalValue(Object value) {
        try { return value == null ? null : Decimal.valueOf(String.valueOf(value)); } catch (Exception ignored) { return null; }
    }
    private static String serializeValue(Object value, Integer maxLength) { return value == null ? null : truncate(JSON.serialize(value), maxLength); }
    private static String truncate(String value, Integer maxLength) { return value == null || value.length() <= maxLength ? value : value.substring(0, maxLength); }
    private static void logInbound(ICBFS_Calificacion_Lead__e event, Boolean success, String context) {
        ICB_LogIntegracionService.insertarLogInbound(
            'ICBFS_CalificacionEventHandler.afterInsert', truncate(event.Payload__c, 131072), success,
            success ? null : truncate(context, 32768), truncate(context, 500)
        );
    }
    public class CalificacionEventException extends Exception {}
}