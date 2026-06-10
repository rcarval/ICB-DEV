public with sharing class ICBFS_GeocodeUpdateAccount {

    public class GeocodeAccountUpdateRequest {
        @InvocableVariable(label='Id de Account' required=true)
        public Id accountId;

        @InvocableVariable(label='Latitud')
        public Double latitude;

        @InvocableVariable(label='Longitud')
        public Double longitude;

        @InvocableVariable(label='Tipo de direccion (SHIPPING/BILLING)')
        public String targetType;
    }

    public class GeocodeAccountUpdateResult {
        @InvocableVariable(label='Id de Account')
        public Id accountId;

        @InvocableVariable(label='Actualizado')
        public Boolean success;

        @InvocableVariable(label='Mensaje de error')
        public String errorMessage;
    }

    @InvocableMethod(label='ICBFS Actualizar Geocode Account' description='Actualiza coordenadas estandar de Account para direccion de despacho o facturacion')
    public static List<GeocodeAccountUpdateResult> applyGeocodingToAccounts(List<GeocodeAccountUpdateRequest> requests) {
        List<GeocodeAccountUpdateResult> results = new List<GeocodeAccountUpdateResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
        Boolean hasShippingLat = accountFields.containsKey('ShippingLatitude');
        Boolean hasShippingLon = accountFields.containsKey('ShippingLongitude');
        Boolean hasBillingLat = accountFields.containsKey('BillingLatitude');
        Boolean hasBillingLon = accountFields.containsKey('BillingLongitude');

        List<Account> toUpdate = new List<Account>();
        List<Integer> toUpdateReqIndexes = new List<Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            GeocodeAccountUpdateRequest req = requests[i];
            GeocodeAccountUpdateResult res = new GeocodeAccountUpdateResult();
            res.success = false;
            res.accountId = req != null ? req.accountId : null;

            if (req == null) {
                res.errorMessage = 'Request nulo';
                results.add(res);
                continue;
            }
            if (req.accountId == null) {
                res.errorMessage = 'AccountId es requerido';
                results.add(res);
                continue;
            }
            if (req.latitude == null || req.longitude == null) {
                res.errorMessage = 'Latitud y longitud son requeridas';
                results.add(res);
                continue;
            }

            String target = normalizeTargetType(req.targetType);
            if (target == 'BILLING' && (!hasBillingLat || !hasBillingLon)) {
                res.errorMessage = 'Campos estandar BillingLatitude/BillingLongitude no disponibles en la org';
                results.add(res);
                continue;
            }
            if (target == 'SHIPPING' && (!hasShippingLat || !hasShippingLon)) {
                res.errorMessage = 'Campos estandar ShippingLatitude/ShippingLongitude no disponibles en la org';
                results.add(res);
                continue;
            }

            Account a = new Account(Id = req.accountId);
            if (target == 'BILLING') {
                a.put('BillingLatitude', req.latitude);
                a.put('BillingLongitude', req.longitude);
            } else {
                a.put('ShippingLatitude', req.latitude);
                a.put('ShippingLongitude', req.longitude);
            }

            toUpdate.add(a);
            toUpdateReqIndexes.add(i);
            results.add(res);
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(toUpdate, false);
            for (Integer j = 0; j < saveResults.size(); j++) {
                Integer reqIndex = toUpdateReqIndexes[j];
                GeocodeAccountUpdateResult res = results[reqIndex];
                Database.SaveResult sr = saveResults[j];
                if (sr.isSuccess()) {
                    res.success = true;
                    res.errorMessage = null;
                } else {
                    res.success = false;
                    res.errorMessage = sr.getErrors() != null && !sr.getErrors().isEmpty()
                        ? sr.getErrors()[0].getMessage()
                        : 'Error desconocido al actualizar Account';
                }
            }
        }

        return results;
    }

    private static String normalizeTargetType(String targetType) {
        String raw = String.isBlank(targetType) ? 'SHIPPING' : targetType.trim().toUpperCase();
        return raw == 'BILLING' ? 'BILLING' : 'SHIPPING';
    }
}