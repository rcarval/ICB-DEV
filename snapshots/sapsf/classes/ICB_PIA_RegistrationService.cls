/**********************************************************************************
 * ICB_PIA_RegistrationService
 * Registro de usuario B2B en PIA post-confirmación código SAP.
 * SEIDOR - Ticket 00026565
 **********************************************************************************/
public with sharing class ICB_PIA_RegistrationService {

    public static final String NAMED_CREDENTIAL = 'API_de_PIA';
    public static final String ESTADO_PENDIENTE = 'Pendiente';
    public static final String ESTADO_EN_PROCESO = 'En_Proceso';
    public static final String ESTADO_CREADO = 'Creado_en_PIA';
    public static final String ESTADO_ERROR = 'Error_Reintentar';
    public static final String ESTADO_DUPLICADO = 'Duplicado';
    public static final String STATUS_EMAIL_VERIFIED = 'email_verified';
    public static final String PAYLOAD_TYPE_B2B = 'b2b';

    private static final Integer TIMEOUT_MS = 120000;
    private static final String LOG_PREFIX = '[ICB_PIA]';
    private static final Integer LOG_BODY_MAX = 2000;

    private static Map<String, ICB_PIA_Comuna_Mapping__mdt> comunaMappingByNameRegion;

    public class RegistrationResult {
        public Id accountId;
        public Boolean success;
        public String estadoSolicitud;
        public String mensaje;
    }

    public class ICB_PIARegistrationException extends Exception {}

    public static List<RegistrationResult> registerAccounts(List<Id> accountIds, Boolean forceRetry) {
        logInfo('INICIO registerAccounts | cuentas=' + (accountIds != null ? accountIds.size() : 0) + ' | forceRetry=' + forceRetry);
        List<RegistrationResult> results = new List<RegistrationResult>();
        if (accountIds == null || accountIds.isEmpty()) {
            logWarn('FIN registerAccounts | sin ids de cuenta');
            return results;
        }

        Map<Id, Map<String, Object>> extrasByAccountId = new Map<Id, Map<String, Object>>();
        Set<Id> uniqueIds = new Set<Id>();
        for (Id accountId : accountIds) {
            if (accountId != null) {
                uniqueIds.add(accountId);
            }
        }

        Map<Id, Account> accountsById = queryAccounts(uniqueIds);
        List<Account> accountsToUpdate = new List<Account>();

        for (Id accountId : accountIds) {
            RegistrationResult result = new RegistrationResult();
            result.accountId = accountId;
            result.success = false;

            if (accountId == null) {
                result.estadoSolicitud = ESTADO_ERROR;
                result.mensaje = 'Id de Cuenta inválido.';
                results.add(result);
                continue;
            }

            Account acc = accountsById.get(accountId);
            if (acc == null) {
                result.estadoSolicitud = ESTADO_ERROR;
                result.mensaje = 'No se encontró la Cuenta.';
                results.add(result);
                continue;
            }

            try {
                Map<String, Object> extras = new Map<String, Object>();
                processAccountRegistration(acc, forceRetry == true, result, extras);
                extrasByAccountId.put(accountId, extras);
                accountsToUpdate.add(buildAccountUpdate(accountId, result, extras));
            } catch (Exception ex) {
                logError('ERROR cuenta ' + accountId + ' | ' + ex.getMessage());
                result.estadoSolicitud = ESTADO_ERROR;
                result.mensaje = ex.getMessage();
                accountsToUpdate.add(buildErrorAccountUpdate(accountId, ex.getMessage()));
            }

            logInfo('RESULTADO cuenta ' + accountId + ' | success=' + result.success + ' | estado=' + result.estadoSolicitud + ' | mensaje=' + result.mensaje);
            results.add(result);
        }

        if (!accountsToUpdate.isEmpty()) {
            logInfo('Actualizando ' + accountsToUpdate.size() + ' cuenta(s) con resultado PIA');
            update accountsToUpdate;
        }

        ICB_LogIntegracionService.publicarLogsOutboundPendientes();
        logInfo('FIN registerAccounts');
        return results;
    }

    public static RegistrationResult registerAccount(Id accountId, Boolean forceRetry) {
        List<RegistrationResult> results = registerAccounts(new List<Id>{ accountId }, forceRetry);
        return results.isEmpty() ? null : results[0];
    }

    @TestVisible
    private static void processAccountRegistration(
        Account acc,
        Boolean forceRetry,
        RegistrationResult result,
        Map<String, Object> extras
    ) {
        if (acc == null) {
            throw new ICB_PIARegistrationException('Cuenta inválida.');
        }

        logInfo('Procesando cuenta ' + acc.Id + ' | SAP=' + acc.C_digo_de_cliente__c + ' | PIA_ID=' + acc.PIA_ID_Externo__c + ' | estado=' + acc.PIA_Estado_Solicitud__c + ' | forceRetry=' + forceRetry);

        if (String.isNotBlank(acc.PIA_ID_Externo__c)) {
            result.success = true;
            result.estadoSolicitud = acc.PIA_Estado_Solicitud__c;
            result.mensaje = 'La Cuenta ya tiene ID PIA registrado. Se omite el callout.';
            logInfo('OMITIDO callout | cuenta ' + acc.Id + ' ya tiene PIA_ID_Externo__c=' + acc.PIA_ID_Externo__c);
            return;
        }

        validateTriggerPreconditions(acc, forceRetry);

        if (String.isBlank(acc.C_digo_de_cliente__c)) {
            throw new ICB_PIARegistrationException('La Cuenta no tiene código SAP. No se invoca PIA.');
        }

        String validationMessage = validateRequiredData(acc);
        if (validationMessage != null) {
            logWarn('VALIDACION fallida | cuenta ' + acc.Id + ' | ' + validationMessage);
            throw new ICB_PIARegistrationException(validationMessage);
        }

        result.estadoSolicitud = ESTADO_EN_PROCESO;
        String requestBody = buildRequestBody(acc);
        logInfo('Callout PIA | cuenta ' + acc.Id + ' | payload=' + truncate(requestBody, LOG_BODY_MAX));
        HttpResponse response = executeCallout(acc.Id, requestBody);
        applyResponseToResult(response, result, extras);
        logInfo('Respuesta PIA procesada | cuenta ' + acc.Id + ' | success=' + result.success + ' | estado=' + result.estadoSolicitud);
    }

    @TestVisible
    private static void validateTriggerPreconditions(Account acc, Boolean forceRetry) {
        if (acc.PIA_Estado_Solicitud__c == ESTADO_CREADO ||
            acc.PIA_Estado_Solicitud__c == ESTADO_DUPLICADO) {
            throw new ICB_PIARegistrationException('La Cuenta ya fue procesada en PIA.');
        }
    }

    @TestVisible
    private static Map<Id, Account> queryAccounts(Set<Id> accountIds) {
        if (!Schema.sObjectType.Account.isAccessible()) {
            throw new ICB_PIARegistrationException('Sin permisos de lectura sobre Account.');
        }

        return new Map<Id, Account>([
            SELECT Id, Name, Email__c, Phone, RUT__c, BillingStreet, BillingCity,
                   ICBFS_Numero__c, Region__c, Region_Despacho__c, Comuna_Despacho__c,
                   ShippingStreet, ShippingCity, ShippingPostalCode, ShippingLatitude, ShippingLongitude,
                   BillingLatitude, BillingLongitude, ICBFS_Latitud_Longitud__c,
                   Latitud_y_Longitud_Facturacion__c, Nombre_de_contacto__c,
                   C_digo_de_cliente__c, PIA_ID_Externo__c, PIA_Estado_Solicitud__c,
                   Comuna_Facturaci_n__r.Name, Comuna_Facturaci_n__r.Region__c,
                   Comuna_Despacho__r.Name, Comuna_Despacho__r.Region__c,
                   (SELECT Id, FirstName, LastName, Email, MobilePhone, Phone
                    FROM Contacts
                    ORDER BY CreatedDate ASC
                    LIMIT 1)
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    @TestVisible
    private static String validateRequiredData(Account acc) {
        if (String.isBlank(resolveEmail(acc))) {
            return 'Email obligatorio para registro PIA.';
        }
        if (String.isBlank(acc.RUT__c)) {
            return 'RUT obligatorio para registro PIA.';
        }
        if (String.isBlank(acc.BillingStreet)) {
            return 'BillingStreet obligatorio para registro PIA.';
        }
        if (String.isBlank(resolveContactName(acc))) {
            return 'Nombre de contacto obligatorio para registro PIA.';
        }
        if (String.isBlank(resolveCellphone(acc))) {
            return 'Teléfono móvil obligatorio para registro PIA.';
        }
        return null;
    }

    @TestVisible
    private static String buildRequestBody(Account acc) {
        GeoMapping billingGeo = resolveGeoMapping(acc, false);
        GeoMapping businessGeo = resolveGeoMapping(acc, true);
        Map<String, Object> addressPayload = buildAddressPayload(acc, billingGeo);
        Map<String, Object> businessPayload = buildBusinessPayload(acc, businessGeo);

        Map<String, Object> payload = new Map<String, Object>{
            'socialReason' => acc.Name,
            'email' => resolveEmail(acc),
            'contactName' => resolveContactName(acc),
            'cellphone' => resolveCellphone(acc),
            'type' => PAYLOAD_TYPE_B2B,
            'businessTimeWindowIds' => resolveBusinessTimeWindowIds(),
            'address' => addressPayload,
            'business' => businessPayload
        };

        return JSON.serialize(payload);
    }

    @TestVisible
    private static HttpResponse executeCallout(Id accountId, String requestBody) {
        ICB_PIA_Settings__mdt settings = resolveSettings();
        String endpointPath = settings != null && String.isNotBlank(settings.Endpoint_Path__c)
            ? settings.Endpoint_Path__c
            : 'user-registration-salesforce';
        String endpoint = 'callout:' + NAMED_CREDENTIAL + '/' + endpointPath.replaceAll('^/+', '');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(requestBody);

        Long startMs = System.currentTimeMillis();
        HttpResponse res;
        String origen = 'ICB_PIA_RegistrationService.executeCallout';

        logInfo('HTTP POST | endpoint=' + endpoint + ' | cuenta=' + accountId);

        try {
            res = new Http().send(req);
            Integer statusCode = res != null ? res.getStatusCode() : null;
            Boolean ok = statusCode != null && statusCode >= 200 && statusCode < 300;
            logInfo('HTTP respuesta | cuenta=' + accountId + ' | status=' + statusCode + ' | ok=' + ok + ' | body=' + truncate(res != null ? res.getBody() : null, LOG_BODY_MAX));
            ICB_LogIntegracionService.insertarLogOutbound(
                origen,
                endpoint,
                'POST',
                null,
                requestBody,
                statusCode,
                null,
                res != null ? res.getBody() : null,
                ok,
                ok ? null : 'HTTP ' + statusCode,
                System.currentTimeMillis() - startMs,
                String.valueOf(accountId)
            );
            return res;
        } catch (Exception ex) {
            logError('HTTP excepcion | cuenta=' + accountId + ' | ' + ex.getMessage());
            ICB_LogIntegracionService.insertarLogOutbound(
                origen,
                endpoint,
                'POST',
                null,
                requestBody,
                res != null ? res.getStatusCode() : null,
                null,
                res != null ? res.getBody() : null,
                false,
                ex.getMessage(),
                System.currentTimeMillis() - startMs,
                String.valueOf(accountId)
            );
            throw ex;
        }
    }

    @TestVisible
    private static void applyResponseToResult(
        HttpResponse response,
        RegistrationResult result,
        Map<String, Object> extras
    ) {
        Integer statusCode = response != null ? response.getStatusCode() : null;
        String body = response != null ? response.getBody() : null;

        if (statusCode == 409 || isDuplicateResponse(statusCode, body)) {
            logInfo('PIA DUPLICADO | status=' + statusCode);
            populateSuccessFieldsFromBody(body, extras);
            result.estadoSolicitud = ESTADO_DUPLICADO;
            if (String.isNotBlank((String) extras.get('piaIdExterno'))) {
                result.success = true;
                result.mensaje = 'El negocio ya existe en PIA. Se registró el ID retornado.';
            } else {
                result.success = false;
                result.mensaje = 'El negocio ya existe en PIA, pero la respuesta no contiene ID. Requiere conciliación manual.';
            }
            return;
        }

        if (statusCode == null || statusCode < 200 || statusCode >= 300) {
            logError('PIA ERROR HTTP | status=' + statusCode + ' | body=' + truncate(body, LOG_BODY_MAX));
            result.success = false;
            result.estadoSolicitud = ESTADO_ERROR;
            result.mensaje = 'Error HTTP ' + statusCode + ': ' + truncate(body, 1000);
            return;
        }

        Map<String, Object> parsed = parseJsonMap(body);
        String statusValue = parsed != null ? String.valueOf(parsed.get('status')) : null;

        if (STATUS_EMAIL_VERIFIED.equalsIgnoreCase(statusValue)) {
            logInfo('PIA EXITO | status API=' + statusValue);
            populateSuccessFieldsFromBody(body, extras);
            result.success = true;
            result.estadoSolicitud = ESTADO_CREADO;
            result.mensaje = 'Usuario creado en PIA correctamente.';
            return;
        }

        if (isDuplicateResponse(statusCode, body)) {
            populateSuccessFieldsFromBody(body, extras);
            result.estadoSolicitud = ESTADO_DUPLICADO;
            if (String.isNotBlank((String) extras.get('piaIdExterno'))) {
                result.success = true;
                result.mensaje = 'El negocio ya existe en PIA. Se registró el ID retornado.';
            } else {
                result.success = false;
                result.mensaje = 'El negocio ya existe en PIA, pero la respuesta no contiene ID. Requiere conciliación manual.';
            }
            return;
        }

        logWarn('PIA respuesta no esperada | status API=' + statusValue);
        result.success = false;
        result.estadoSolicitud = ESTADO_ERROR;
        result.mensaje = 'Respuesta PIA no esperada. status=' + statusValue;
    }

    @TestVisible
    private static Boolean isDuplicateResponse(Integer statusCode, String body) {
        if (String.isBlank(body)) {
            return false;
        }
        String normalized = body.toLowerCase();
        return normalized.contains('duplicate') ||
            normalized.contains('already exists') ||
            normalized.contains('ya existe') ||
            normalized.contains('email already');
    }

    @TestVisible
    private static void populateSuccessFieldsFromBody(String body, Map<String, Object> extras) {
        Map<String, Object> parsed = parseJsonMap(body);
        if (parsed == null) {
            return;
        }

        extras.put('piaIdExterno', stringValue(parsed.get('id')));
        extras.put('piaEstadoRegistro', stringValue(parsed.get('status')));
        extras.put('piaFechaRegistro', parseDateTime(parsed.get('createdAt')));

        Map<String, Object> requestFieldValues = asMap(parsed.get('requestFieldValues'));
        Map<String, Object> business = asMap(requestFieldValues != null ? requestFieldValues.get('business') : null);
        if (business != null) {
            extras.put('piaBusinessId', stringValue(business.get('id')));
            Map<String, Object> city = asMap(business.get('city'));
            if (city != null) {
                extras.put('centroDistribucion', stringValue(city.get('distributionCenter')));
                extras.put('oficinaVentas', stringValue(city.get('salesOffice')));
            }
        }
    }

    private static Account buildAccountUpdate(Id accountId, RegistrationResult result, Map<String, Object> extras) {
        Account updateAcc = new Account(Id = accountId);
        updateAcc.PIA_Estado_Solicitud__c = result.estadoSolicitud;

        if (result.success) {
            assignParsedFields(updateAcc, extras);
            updateAcc.PIA_Error_Log__c = null;
        } else {
            updateAcc.PIA_Error_Log__c = truncate(result.mensaje, 32768);
        }

        return updateAcc;
    }

    private static Account buildErrorAccountUpdate(Id accountId, String message) {
        Account updateAcc = new Account(Id = accountId);
        updateAcc.PIA_Estado_Solicitud__c = ESTADO_ERROR;
        updateAcc.PIA_Error_Log__c = truncate(message, 32768);
        return updateAcc;
    }

    private static void assignParsedFields(Account updateAcc, Map<String, Object> extras) {
        if (extras == null) {
            return;
        }
        if (extras.containsKey('piaIdExterno') && extras.get('piaIdExterno') != null) {
            updateAcc.PIA_ID_Externo__c = String.valueOf(extras.get('piaIdExterno'));
        }
        if (extras.containsKey('piaEstadoRegistro') && extras.get('piaEstadoRegistro') != null) {
            updateAcc.PIA_Estado_Registro__c = String.valueOf(extras.get('piaEstadoRegistro'));
        }
        if (extras.containsKey('piaFechaRegistro') && extras.get('piaFechaRegistro') != null) {
            updateAcc.PIA_Fecha_Registro__c = (Datetime) extras.get('piaFechaRegistro');
        }
        if (extras.containsKey('piaBusinessId') && extras.get('piaBusinessId') != null) {
            updateAcc.PIA_Business_ID__c = String.valueOf(extras.get('piaBusinessId'));
        }
        if (extras.containsKey('centroDistribucion') && extras.get('centroDistribucion') != null) {
            updateAcc.Centro_Distribucion__c = String.valueOf(extras.get('centroDistribucion'));
        }
        if (extras.containsKey('oficinaVentas') && extras.get('oficinaVentas') != null) {
            updateAcc.Oficina_Ventas__c = String.valueOf(extras.get('oficinaVentas'));
        }
    }

    private class GeoMapping {
        public String communeId;
        public String regionId;
        public Integer cityId;
    }

    @TestVisible
    private static Map<String, Object> buildAddressPayload(Account acc, GeoMapping geo) {
        return buildLocationPayload(acc, geo, false);
    }

    @TestVisible
    private static Map<String, Object> buildBusinessPayload(Account acc, GeoMapping geo) {
        Map<String, Object> businessPayload = buildLocationPayload(acc, geo, true);
        businessPayload.put('rut', normalizeRut(acc.RUT__c));
        return businessPayload;
    }

    private static Map<String, Object> buildLocationPayload(Account acc, GeoMapping geo, Boolean business) {
        String street = business ? resolveShippingStreetName(acc) : resolveStreetName(acc);
        String streetNumber = business ? resolveShippingStreetNumber(acc) : resolveStreetNumber(acc);
        Decimal[] coords = business ? resolveShippingCoordinates(acc) : resolveBillingCoordinates(acc);
        return new Map<String, Object>{
            'address' => resolveFullAddress(street, streetNumber),
            'street' => street,
            'number' => streetNumber,
            'communeId' => geo.communeId,
            'regionId' => geo.regionId,
            'cityId' => geo.cityId,
            'coordinates' => new Map<String, Object>{
                'latitude' => coords[0],
                'longitude' => coords[1]
            }
        };
    }

    @TestVisible
    private static GeoMapping resolveGeoMapping(Account acc, Boolean business) {
        GeoMapping geo = new GeoMapping();
        ICB_PIA_Settings__mdt settings = resolveSettings();
        String comunaName = business
            ? resolveShippingComunaName(acc)
            : (acc.Comuna_Facturaci_n__r != null ? acc.Comuna_Facturaci_n__r.Name : null);
        String regionId = extractRegionId(acc, business);
        ICB_PIA_Comuna_Mapping__mdt mapping = findComunaMapping(comunaName, regionId);

        if (mapping != null) {
            geo.communeId = mapping.PIA_Commune_Id__c;
            geo.regionId = formatRegionIdForPia(mapping.PIA_Region_Id__c);
            geo.cityId = Integer.valueOf(String.valueOf(mapping.PIA_City_Id__c.intValue()));
            logInfo('Geo mapeo metadata | comuna=' + comunaName + ' | communeId=' + geo.communeId + ' | regionId=' + geo.regionId + ' | cityId=' + geo.cityId);
        } else {
            String normalizedRegionId = regionId;
            geo.regionId = formatRegionIdForPia(normalizedRegionId);
            geo.communeId = buildFallbackCommuneId(comunaName, geo.regionId);
            geo.cityId = settings != null && settings.Default_City_Id__c != null
                ? Integer.valueOf(String.valueOf(settings.Default_City_Id__c.intValue()))
                : 5453;
            logWarn('Geo fallback | comuna=' + comunaName + ' | communeId=' + geo.communeId + ' | regionId=' + geo.regionId + ' | cityId=' + geo.cityId);
        }

        return geo;
    }

    @TestVisible
    private static ICB_PIA_Comuna_Mapping__mdt findComunaMapping(String comunaName, String regionId) {
        if (String.isBlank(comunaName)) {
            return null;
        }
        if (comunaMappingByNameRegion == null) {
            comunaMappingByNameRegion = new Map<String, ICB_PIA_Comuna_Mapping__mdt>();
            for (ICB_PIA_Comuna_Mapping__mdt row : [
                SELECT Comuna_Name__c, PIA_Commune_Id__c, PIA_City_Id__c, PIA_Region_Id__c
                FROM ICB_PIA_Comuna_Mapping__mdt
            ]) {
                String key = buildComunaMappingKey(row.Comuna_Name__c, row.PIA_Region_Id__c);
                if (!comunaMappingByNameRegion.containsKey(key)) {
                    comunaMappingByNameRegion.put(key, row);
                } else {
                    ICB_PIA_Comuna_Mapping__mdt existing = comunaMappingByNameRegion.get(key);
                    if (row.PIA_Commune_Id__c < existing.PIA_Commune_Id__c) {
                        comunaMappingByNameRegion.put(key, row);
                    }
                }
            }
        }
        String normalizedName = normalizeKey(comunaName);
        return comunaMappingByNameRegion.get(buildComunaMappingKey(normalizedName, regionId));
    }

    private static String buildComunaMappingKey(String comunaName, String regionId) {
        String normalizedName = normalizeKey(comunaName);
        if (String.isBlank(regionId)) {
            return normalizedName;
        }
        return normalizedName + '|' + regionId.trim();
    }

    @TestVisible
    private static String extractRegionId(Account acc, Boolean business) {
        String regionSource = business ? resolveShippingRegionField(acc) : acc.Region__c;
        if (String.isBlank(regionSource)) {
            regionSource = business
                ? resolveShippingRegionName(acc)
                : (acc.Comuna_Facturaci_n__r != null ? acc.Comuna_Facturaci_n__r.Region__c : null);
        }
        if (String.isBlank(regionSource)) {
            return '13';
        }
        String digits = regionSource.replaceAll('[^0-9]', '');
        if (String.isNotBlank(digits)) {
            String regionToken = digits.left(2);
            return String.valueOf(Integer.valueOf(regionToken));
        }
        return regionSource.left(2);
    }

    private static String resolveShippingComunaName(Account acc) {
        try {
            return acc.Comuna_Despacho__r != null ? acc.Comuna_Despacho__r.Name : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String resolveShippingRegionName(Account acc) {
        try {
            return acc.Comuna_Despacho__r != null ? acc.Comuna_Despacho__r.Region__c : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String resolveShippingRegionField(Account acc) {
        try {
            return acc.Region_Despacho__c;
        } catch (Exception ignored) {
            return null;
        }
    }

    @TestVisible
    private static String extractRegionId(Account acc) {
        return extractRegionId(acc, false);
    }

    @TestVisible
    private static String formatRegionIdForPia(String regionId) {
        if (String.isBlank(regionId)) {
            return regionId;
        }
        String trimmedRegionId = regionId.trim();
        return trimmedRegionId.length() == 1 ? '0' + trimmedRegionId : trimmedRegionId;
    }

    @TestVisible
    private static String buildFallbackCommuneId(String comunaName, String regionId) {
        if (String.isBlank(comunaName)) {
            return 'CMN' + regionId + '000';
        }
        return 'CMN' + regionId + String.valueOf(Math.abs(comunaName.hashCode())).left(3);
    }

    @TestVisible
    private static String resolveStreetNumber(Account acc) {
        if (String.isNotBlank(acc.ICBFS_Numero__c)) {
            return acc.ICBFS_Numero__c.trim();
        }
        if (String.isBlank(acc.BillingStreet)) {
            return 'S/N';
        }
        List<String> tokens = acc.BillingStreet.trim().split('\\s+');
        if (!tokens.isEmpty()) {
            String lastToken = tokens[tokens.size() - 1];
            if (lastToken.replaceAll('[^0-9]', '').length() > 0) {
                return lastToken.replaceAll('[^0-9A-Za-z/]', '');
            }
        }
        return 'S/N';
    }

    @TestVisible
    private static String resolveStreetName(Account acc) {
        if (String.isBlank(acc.BillingStreet)) {
            return '';
        }
        if (String.isNotBlank(acc.ICBFS_Numero__c)) {
            return acc.BillingStreet.trim();
        }
        List<String> tokens = acc.BillingStreet.trim().split('\\s+');
        if (tokens.isEmpty()) {
            return '';
        }
        String lastToken = tokens[tokens.size() - 1];
        if (lastToken.replaceAll('[^0-9]', '').length() > 0 && tokens.size() > 1) {
            List<String> streetTokens = tokens.clone();
            streetTokens.remove(streetTokens.size() - 1);
            return String.join(streetTokens, ' ');
        }
        return acc.BillingStreet.trim();
    }

    @TestVisible
    private static String resolveFullAddress(String street, String streetNumber) {
        if (String.isBlank(street)) {
            return String.isNotBlank(streetNumber) && streetNumber != 'S/N' ? streetNumber : '';
        }
        if (String.isBlank(streetNumber) || streetNumber == 'S/N') {
            return street;
        }
        return street + ' ' + streetNumber;
    }

    @TestVisible
    private static Decimal[] resolveCoordinates(Account acc) {
        if (acc.ShippingLatitude != null && acc.ShippingLongitude != null) {
            return new Decimal[]{ acc.ShippingLatitude, acc.ShippingLongitude };
        }
        if (acc.BillingLatitude != null && acc.BillingLongitude != null) {
            return new Decimal[]{ acc.BillingLatitude, acc.BillingLongitude };
        }
        Decimal[] parsed = parseLatLongString(
            String.isNotBlank(acc.ICBFS_Latitud_Longitud__c)
                ? acc.ICBFS_Latitud_Longitud__c
                : acc.Latitud_y_Longitud_Facturacion__c
        );
        if (parsed != null) {
            return parsed;
        }
        return new Decimal[]{ -33.4489, -70.6693 };
    }

    private static String resolveShippingStreetNumber(Account acc) {
        String raw;
        try { raw = acc.ShippingStreet; } catch (Exception ignored) { raw = null; }
        if (String.isBlank(raw)) return 'S/N';
        List<String> tokens = raw.trim().split('\\s+');
        String lastToken = tokens[tokens.size() - 1];
        return lastToken.replaceAll('[^0-9A-Za-z/]', '').length() > 0
            ? lastToken.replaceAll('[^0-9A-Za-z/]', '') : 'S/N';
    }

    private static String resolveShippingStreetName(Account acc) {
        String raw;
        try { raw = acc.ShippingStreet; } catch (Exception ignored) { raw = null; }
        if (String.isBlank(raw)) return '';
        List<String> tokens = raw.trim().split('\\s+');
        String lastToken = tokens[tokens.size() - 1];
        if (lastToken.replaceAll('[^0-9]', '').length() > 0 && tokens.size() > 1) {
            tokens.remove(tokens.size() - 1);
            return String.join(tokens, ' ');
        }
        return raw.trim();
    }

    private static Decimal[] resolveShippingCoordinates(Account acc) {
        try {
            if (acc.ShippingLatitude != null && acc.ShippingLongitude != null) {
                return new Decimal[]{ acc.ShippingLatitude, acc.ShippingLongitude };
            }
        } catch (Exception ignored) { }
        return resolveCoordinates(acc);
    }

    private static Decimal[] resolveBillingCoordinates(Account acc) {
        if (acc.BillingLatitude != null && acc.BillingLongitude != null) {
            return new Decimal[]{ acc.BillingLatitude, acc.BillingLongitude };
        }
        return resolveCoordinates(acc);
    }

    @TestVisible
    private static Decimal[] parseLatLongString(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        List<String> parts = raw.replace(';', ',').split(',');
        if (parts.size() < 2) {
            return null;
        }
        try {
            return new Decimal[]{ Decimal.valueOf(parts[0].trim()), Decimal.valueOf(parts[1].trim()) };
        } catch (Exception ex) {
            return null;
        }
    }

    @TestVisible
    private static String resolveEmail(Account acc) {
        if (String.isNotBlank(acc.Email__c)) {
            return acc.Email__c.trim();
        }
        if (acc.Contacts != null && !acc.Contacts.isEmpty() && String.isNotBlank(acc.Contacts[0].Email)) {
            return acc.Contacts[0].Email.trim();
        }
        return null;
    }

    @TestVisible
    private static String resolveContactName(Account acc) {
        if (acc.Contacts != null && !acc.Contacts.isEmpty()) {
            Contact con = acc.Contacts[0];
            String fullName = ((con.FirstName != null ? con.FirstName + ' ' : '') + (con.LastName != null ? con.LastName : '')).trim();
            if (String.isNotBlank(fullName)) {
                return fullName;
            }
        }
        return acc.Nombre_de_contacto__c;
    }

    @TestVisible
    private static String resolveCellphone(Account acc) {
        String rawPhone = null;
        String source = null;
        if (acc.Contacts != null && !acc.Contacts.isEmpty()) {
            if (String.isNotBlank(acc.Contacts[0].MobilePhone)) {
                rawPhone = acc.Contacts[0].MobilePhone;
                source = 'Contact.MobilePhone';
            } else if (String.isNotBlank(acc.Contacts[0].Phone)) {
                rawPhone = acc.Contacts[0].Phone;
                source = 'Contact.Phone';
            }
        }
        if (String.isBlank(rawPhone) && String.isNotBlank(acc.Phone)) {
            rawPhone = acc.Phone;
            source = 'Account.Phone';
        }
        String normalized = normalizeCellphone(rawPhone);
        logInfo('Telefono | cuenta ' + acc.Id + ' | fuente=' + source + ' | raw=' + rawPhone + ' | normalizado=' + normalized);
        return normalized;
    }

    @TestVisible
    private static String normalizeCellphone(String rawPhone) {
        if (String.isBlank(rawPhone)) {
            return null;
        }
        String digits = rawPhone.replaceAll('[^0-9]', '');
        if (digits.startsWith('56') && digits.length() >= 11) {
            return '+' + digits.left(11);
        }
        if (digits.length() == 9 && digits.startsWith('9')) {
            return '+56' + digits;
        }
        if (digits.length() == 8) {
            return '+569' + digits;
        }
        return rawPhone.startsWith('+') ? rawPhone : '+' + digits;
    }

    @TestVisible
    private static String normalizeRut(String rut) {
        if (String.isBlank(rut)) {
            return rut;
        }
        return rut.replace('.', '').replace(' ', '').toUpperCase();
    }

    @TestVisible
    private static List<String> resolveBusinessTimeWindowIds() {
        ICB_PIA_Settings__mdt settings = resolveSettings();
        String raw = settings != null ? settings.Business_Time_Window_Ids__c : null;
        if (String.isBlank(raw)) {
            return new List<String>{ 'D8' };
        }
        List<String> values = new List<String>();
        for (String item : raw.split(',')) {
            if (String.isNotBlank(item)) {
                values.add(item.trim());
            }
        }
        return values.isEmpty() ? new List<String>{ 'D8' } : values;
    }

    @TestVisible
    private static ICB_PIA_Settings__mdt resolveSettings() {
        List<ICB_PIA_Settings__mdt> rows = [
            SELECT Business_Time_Window_Ids__c, Endpoint_Path__c, Default_City_Id__c
            FROM ICB_PIA_Settings__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @TestVisible
    private static Map<String, Object> parseJsonMap(String body) {
        if (String.isBlank(body)) {
            return null;
        }
        Object parsed = JSON.deserializeUntyped(body);
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
    }

    @TestVisible
    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    @TestVisible
    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    @TestVisible
    private static Datetime parseDateTime(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Datetime.valueOf(String.valueOf(value).replace('T', ' ').replace('Z', ''));
        } catch (Exception ex) {
            return Datetime.now();
        }
    }

    @TestVisible
    private static String normalizeKey(String value) {
        return String.isBlank(value) ? null : value.trim().toUpperCase();
    }

    @TestVisible
    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null) {
            return value;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    private static void logInfo(String mensaje) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' ' + mensaje);
    }

    private static void logWarn(String mensaje) {
        System.debug(LoggingLevel.WARN, LOG_PREFIX + ' ' + mensaje);
    }

    private static void logError(String mensaje) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + mensaje);
    }
}