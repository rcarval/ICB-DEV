/**
 * ICB Food Service
 * Desarrollado por: JosÃ© Illanes
 * Fecha: 2026-02-05
 * DescripciÃ³n: Bulk-safe. Resuelve Domicilio_Cliente__c y Sucursal__c por Cliente__c + key (Direccion__c).
 * Nota: En update, si alguno sigue null, intenta asignar aunque Cliente/Key no hayan cambiado.
 */
public with sharing class ICBFD_FacturasDomicilioClienteService {

    public static void asignarDomicilio(List<Facturas__c> nuevos, Map<Id, Facturas__c> oldMap) {
        if (nuevos == null || nuevos.isEmpty()) return;

        Set<Id> accountIds = new Set<Id>();
        Set<String> keys = new Set<String>();
        Set<String> customerCodes = new Set<String>();
        List<Facturas__c> objetivo = new List<Facturas__c>();

        for (Facturas__c f : nuevos) {
            String key = (String) f.Direccion__c;
            String customerCode = normalizar((String) f.C_digo_de_Cliente__c);
            Boolean necesitaCliente = (f.Cliente__c == null && !String.isBlank(customerCode));
            Boolean necesitaDomicilio = (f.Domicilio_Cliente__c == null && !String.isBlank(key));
            Boolean necesitaSucursal = (f.Sucursal__c == null);

            if (!necesitaCliente && !necesitaDomicilio && !necesitaSucursal) continue;

            if (oldMap != null && oldMap.containsKey(f.Id)) {
                Facturas__c oldF = oldMap.get(f.Id);
                String oldKey = (String) oldF.Direccion__c;
                Boolean sameCliente = (oldF.Cliente__c == f.Cliente__c);
                Boolean sameKey = (normalizar(oldKey) == normalizar(key));
                Boolean sameCustomerCode = (normalizar((String) oldF.C_digo_de_Cliente__c) == customerCode);
                Boolean oldTeniaCliente = (oldF.Cliente__c != null);
                Boolean oldTeniaDomicilio = (oldF.Domicilio_Cliente__c != null);
                Boolean oldTeniaSucursal = (oldF.Sucursal__c != null);

                if (sameCliente && sameKey && sameCustomerCode && oldTeniaCliente && oldTeniaDomicilio && oldTeniaSucursal) {
                    continue;
                }
            }

            if (!String.isBlank(customerCode)) {
                customerCodes.add(customerCode);
            }
            if (f.Cliente__c != null) {
                accountIds.add(f.Cliente__c);
            }
            if (!String.isBlank(key)) {
                keys.add(normalizar(key));
            }
            objetivo.add(f);
        }

        if (objetivo.isEmpty()) return;

        Map<String, Account> cuentaPorCodigo = new Map<String, Account>();
        if (!customerCodes.isEmpty()) {
            for (Account cuenta : [
                SELECT Id, ParentId, RecordType.DeveloperName, Cliente_Despacho__c, C_digo_de_cliente__c
                FROM Account
                WHERE C_digo_de_cliente__c IN :customerCodes
                ORDER BY LastModifiedDate DESC
            ]) {
                String code = normalizar(cuenta.C_digo_de_cliente__c);
                if (String.isBlank(code) || cuentaPorCodigo.containsKey(code)) continue;
                if (cuenta.RecordType != null && cuenta.RecordType.DeveloperName == 'Sucursal') continue;
                cuentaPorCodigo.put(code, cuenta);
            }
        }

        for (Facturas__c f : objetivo) {
            if (f.Cliente__c == null) {
                String customerCode = normalizar((String) f.C_digo_de_Cliente__c);
                if (!String.isBlank(customerCode) && cuentaPorCodigo.containsKey(customerCode)) {
                    f.Cliente__c = cuentaPorCodigo.get(customerCode).Id;
                }
            }
            if (f.Cliente__c != null) {
                accountIds.add(f.Cliente__c);
            }
        }

        if (accountIds.isEmpty()) return;

        Map<Id, Account> cuentas = new Map<Id, Account>([
            SELECT Id, ParentId, RecordType.DeveloperName, Cliente_Despacho__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        Map<String, Id> mapKeyToDomicilio = new Map<String, Id>();
        if (!keys.isEmpty()) {
            for (Domicilio_de_Cliente__c d : [
                SELECT Id, Cliente__c, Cliente_Despacho__c
                FROM Domicilio_de_Cliente__c
                WHERE Cliente__c IN :accountIds
                  AND Cliente_Despacho__c IN :keys
            ]) {
                if (d.Cliente__c == null || String.isBlank(d.Cliente_Despacho__c)) continue;
                mapKeyToDomicilio.put(buildKey(d.Cliente__c, d.Cliente_Despacho__c), d.Id);
            }
        }

        Map<String, List<Id>> sucursalesPorClave = new Map<String, List<Id>>();
        if (!keys.isEmpty()) {
            for (Account sucursal : [
                SELECT Id, ParentId, Cliente_Despacho__c
                FROM Account
                WHERE ParentId IN :accountIds
                  AND RecordType.DeveloperName = 'Sucursal'
                  AND Cliente_Despacho__c IN :keys
            ]) {
                if (sucursal.ParentId == null || String.isBlank(sucursal.Cliente_Despacho__c)) continue;
                String clave = buildKey(sucursal.ParentId, sucursal.Cliente_Despacho__c);
                if (!sucursalesPorClave.containsKey(clave)) {
                    sucursalesPorClave.put(clave, new List<Id>());
                }
                sucursalesPorClave.get(clave).add(sucursal.Id);
            }
        }

        for (Facturas__c f : objetivo) {
            String key = String.isBlank((String) f.Direccion__c) ? null : String.valueOf(f.Direccion__c).trim();
            String claveFactura = key == null ? null : buildKey(f.Cliente__c, key);

            if (f.Domicilio_Cliente__c == null && claveFactura != null && mapKeyToDomicilio.containsKey(claveFactura)) {
                f.Domicilio_Cliente__c = mapKeyToDomicilio.get(claveFactura);
                f.Ya_procesada__c = true;
            }

            if (f.Sucursal__c == null) {
                Id sucursalId = resolverSucursal(cuentas.get(f.Cliente__c), key, claveFactura, sucursalesPorClave);
                if (sucursalId != null) {
                    f.Sucursal__c = sucursalId;
                }
            }
        }
    }

    private static Id resolverSucursal(
        Account cuentaCliente,
        String key,
        String claveBusqueda,
        Map<String, List<Id>> sucursalesPorClave
    ) {
        if (cuentaCliente == null) return null;

        if (cuentaCliente.RecordType != null && cuentaCliente.RecordType.DeveloperName == 'Sucursal') {
            return cuentaCliente.Id;
        }

        if (!String.isBlank(key) && claveBusqueda != null && sucursalesPorClave.containsKey(claveBusqueda)) {
            List<Id> candidatas = sucursalesPorClave.get(claveBusqueda);
            if (candidatas != null && candidatas.size() == 1) {
                return candidatas[0];
            }
        }

        if (!String.isBlank(key) && !String.isBlank(cuentaCliente.Cliente_Despacho__c)
            && cuentaCliente.Cliente_Despacho__c.trim() == key) {
            return cuentaCliente.Id;
        }

        return null;
    }

    private static String buildKey(Id accountId, String key) {
        return String.valueOf(accountId) + '|' + String.valueOf(key).trim();
    }

    private static String normalizar(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}