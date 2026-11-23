public with sharing class ICBFS_CalificadorService {
    private static final String NAMED_CREDENTIAL = 'ICBFS_Calificador';
    private static final String ASYNC_PATH = '/v1/calificar/async';
    private static final Integer TIMEOUT_MS = 120000;

    public class AsyncResponse {
        public Boolean ok;
        public String estado;
        public String executionArn;
        public String mensaje;
    }

    public class CalificadorException extends Exception {}

    public static AsyncResponse send(Account account, String webhookUrl, String correlationId, String callbackToken) {
        if (account == null || account.Id == null) throw new CalificadorException('Account obligatorio');
        if (String.isBlank(webhookUrl) || !webhookUrl.toLowerCase().startsWith('https://')) {
            throw new CalificadorException('Webhook HTTPS no configurado');
        }
        if (String.isBlank(correlationId)) throw new CalificadorException('Correlation Id obligatorio');
        if (String.isBlank(callbackToken)) throw new CalificadorException('Token de callback no configurado');
        Map<String, Object> lead = new Map<String, Object>();
        putIfPresent(lead, 'rut', account.RUT__c);
        putIfPresent(lead, 'codigo', String.valueOf(account.Id));
        putIfPresent(lead, 'codigo_sap', account.C_digo_de_cliente__c);
        putIfPresent(lead, 'nombre_fantasia', firstNotBlank(account.Nombre_de_Fantasia__c, account.Name));
        putIfPresent(lead, 'pagina_web', account.Website);
        putIfPresent(lead, 'mail_contacto', account.Email__c);
        putIfPresent(lead, 'especialidad_crm', account.Especialidad__c);
        putIfPresent(lead, 'comuna', resolveComuna(account));
        putIfPresent(lead, 'direccion', buildAddress(account));
        Map<String, Object> webhookHeaders = new Map<String, Object>{
            'X-ICBFS-Correlation-Id' => correlationId,
            'X-ICBFS-Callback-Token' => callbackToken
        };
        Map<String, Object> payload = new Map<String, Object>{
            'lead' => lead,
            'webhook' => webhookUrl,
            'webhook_headers' => webhookHeaders
        };
        String requestBody = JSON.serialize(payload);
        Long started = System.currentTimeMillis();
        HttpResponse response;
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:' + NAMED_CREDENTIAL + ASYNC_PATH);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(TIMEOUT_MS);
            request.setBody(requestBody);
            response = new Http().send(request);
            Integer statusCode = response.getStatusCode();
            if (statusCode != 202) {
                throw new CalificadorException('Respuesta inesperada: ' + statusCode + ' ' + safeSnippet(response.getBody(), 500));
            }
            AsyncResponse result = (AsyncResponse) JSON.deserialize(response.getBody(), AsyncResponse.class);
            if (result == null || result.ok != true || String.isBlank(result.executionArn)) {
                throw new CalificadorException('Respuesta 202 sin executionArn válido');
            }
            ICB_LogIntegracionService.insertarLogOutbound(
                'ICBFS_CalificadorService.send', 'callout:' + NAMED_CREDENTIAL + ASYNC_PATH, 'POST',
                'Content-Type: application/json', requestBody, statusCode, null, response.getBody(), true, null,
                System.currentTimeMillis() - started, correlationId
            );
            return result;
        } catch (Exception error) {
            ICB_LogIntegracionService.insertarLogOutbound(
                'ICBFS_CalificadorService.send', 'callout:' + NAMED_CREDENTIAL + ASYNC_PATH, 'POST',
                'Content-Type: application/json', requestBody, response == null ? null : response.getStatusCode(), null,
                response == null ? null : response.getBody(), false, error.getMessage(),
                System.currentTimeMillis() - started, correlationId
            );
            throw error;
        }
    }

    private static void putIfPresent(Map<String, Object> target, String key, Object value) {
        if (value != null && String.isNotBlank(String.valueOf(value))) target.put(key, value);
    }

    private static String firstNotBlank(String preferido, String alternativa) {
        return String.isNotBlank(preferido) ? preferido : alternativa;
    }

    private static String resolveComuna(Account account) {
        if (account.Comuna__r != null && String.isNotBlank(account.Comuna__r.Name)) return account.Comuna__r.Name;
        if (account.Comuna_Facturaci_n__r != null && String.isNotBlank(account.Comuna_Facturaci_n__r.Name)) {
            return account.Comuna_Facturaci_n__r.Name;
        }
        return null;
    }

    private static String buildAddress(Account account) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(account.BillingStreet)) parts.add(account.BillingStreet);
        if (String.isNotBlank(account.BillingCity)) parts.add(account.BillingCity);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String safeSnippet(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength) + '...';
    }
}