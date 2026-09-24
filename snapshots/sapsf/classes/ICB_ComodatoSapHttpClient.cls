/**
 * Cliente HTTP para el envío del contrato de comodato a SAP OData (ZBI_COMODATO_SF).
 * Implementa el patrón GET (CSRF Fetch) + POST documentado en la prueba técnica de
 * docs/MEMORIA_INTEGRACION_SAP_COMODATO_FIRMADO.md (sección 3).
 *
 * Comportamiento de sesión CSRF confirmado en sapsf (2026-07-24): SAP exige que la cookie de
 * sesión (sap-usercontext + SAP_SESSIONID_...) recibida en el GET se reenvíe en el POST — Named
 * Credential NO encadena cookies entre llamados independientes, hay que hacerlo a mano. Sin esto
 * SAP responde 403 "CSRF token validation failed" aunque el token esté bien.
 *
 * PENDIENTE ANTES DE USAR EN PROD:
 *   - Named Credential 'SAP_Comodato' no existe todavía en PROD (sí en sapsf).
 */
public with sharing class ICB_ComodatoSapHttpClient {

    public class SapCalloutException extends Exception {}

    @TestVisible
    private static final String NAMED_CREDENTIAL = 'callout:SAP_Comodato';
    @TestVisible
    private static final String SERVICE_ROOT_PATH = '/sap/opu/odata/sap/ZBI_COMODATO_SF_SRV_01/';
    @TestVisible
    private static final String ENTITY_PATH = SERVICE_ROOT_PATH + 'AfComodatoCabSet';

    public class SapResponse {
        public Integer statusCode;
        public String body;
        public SapResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }

    public static SapResponse post(String jsonBody) {
        CsrfToken csrf = fetchCsrfToken();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + ENTITY_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('x-csrf-token', csrf.token);
        if (String.isNotBlank(csrf.cookie)) {
            req.setHeader('Cookie', csrf.cookie);
        }
        req.setBody(jsonBody);
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        return new SapResponse(res.getStatusCode(), res.getBody());
    }

    private class CsrfToken {
        String token;
        String cookie;
    }

    @TestVisible
    private static CsrfToken fetchCsrfToken() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + SERVICE_ROOT_PATH);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setHeader('x-csrf-token', 'Fetch');
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new SapCalloutException('No se pudo obtener CSRF token de SAP. HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }

        String token = res.getHeader('x-csrf-token');
        if (String.isBlank(token)) {
            throw new SapCalloutException('SAP no devolvió header x-csrf-token en el GET.');
        }

        // SAP SÍ devuelve la cookie de sesión (sap-usercontext + SAP_SESSIONID_...), pero con el
        // nombre de header en minúsculas ('set-cookie'). HttpResponse.getHeader() en Apex es
        // sensible a mayúsculas/minúsculas exactas, por eso se busca la clave manualmente entre
        // getHeaderKeys() en vez de asumir 'Set-Cookie'. Confirmado 2026-07-24: sin este fix el
        // POST fallaba con 403 "CSRF token validation failed" porque nunca se reenviaba la cookie.
        CsrfToken result = new CsrfToken();
        result.token = token;
        result.cookie = extractCookiePairs(findHeaderIgnoreCase(res, 'set-cookie'));
        return result;
    }

    private static String findHeaderIgnoreCase(HttpResponse res, String headerName) {
        for (String key : res.getHeaderKeys()) {
            if (key.equalsIgnoreCase(headerName)) {
                return res.getHeader(key);
            }
        }
        return null;
    }

    // Apex concatena múltiples headers Set-Cookie del mismo nombre en un solo string separado por
    // ';', mezclando pares cookie=valor con atributos (path=, domain=, expires=, etc.) que NO son
    // válidos dentro de un header Cookie de request. Se filtran los atributos y se dejan solo los
    // pares reales (ej. sap-usercontext=... y SAP_SESSIONID_QAS_300=...).
    @TestVisible
    private static String extractCookiePairs(String rawSetCookie) {
        if (String.isBlank(rawSetCookie)) {
            return null;
        }
        Set<String> attributeNames = new Set<String>{
            'path', 'domain', 'expires', 'max-age', 'secure', 'httponly', 'samesite'
        };
        List<String> pairs = new List<String>();
        for (String segment : rawSetCookie.split(';')) {
            String trimmed = segment.trim();
            if (String.isBlank(trimmed)) continue;
            Integer eq = trimmed.indexOf('=');
            String attrName = (eq > -1 ? trimmed.substring(0, eq) : trimmed).toLowerCase();
            if (attributeNames.contains(attrName)) continue;
            pairs.add(trimmed);
        }
        return pairs.isEmpty() ? null : String.join(pairs, '; ');
    }
}