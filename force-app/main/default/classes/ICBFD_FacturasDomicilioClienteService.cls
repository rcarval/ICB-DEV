/**
 * ICB Food Service
 * Desarrollado por: José Illanes
 * Fecha: 2026-02-05
 * Descripción: Bulk-safe. Resuelve Domicilio_Cliente__c por Cliente__c + key (Direccion__c).
 * Nota: En update, si Domicilio_Cliente__c sigue null, intenta asignar aunque Cliente/Key no hayan cambiado.
 */
public with sharing class ICBFD_FacturasDomicilioClienteService {

    public static void asignarDomicilio(List<Facturas__c> nuevos, Map<Id, Facturas__c> oldMap) {
        if (nuevos == null || nuevos.isEmpty()) return;

        Set<Id> accountIds = new Set<Id>();
        Set<String> keys = new Set<String>();
        List<Facturas__c> objetivo = new List<Facturas__c>();

        for (Facturas__c f : nuevos) {
            if (f.Cliente__c == null) continue;
            if (f.Domicilio_Cliente__c != null) continue;

            String key = (String) f.Direccion__c;
            if (String.isBlank(key)) continue;

            // ✅ En update: SOLO saltar si Cliente+Key no cambiaron Y antes ya existía domicilio
            if (oldMap != null && oldMap.containsKey(f.Id)) {
                Facturas__c oldF = oldMap.get(f.Id);

                String oldKey = (String) oldF.Direccion__c;
                Boolean sameCliente = (oldF.Cliente__c == f.Cliente__c);
                Boolean sameKey = (String.valueOf(oldKey).trim() == String.valueOf(key).trim());
                Boolean oldTeniaDomicilio = (oldF.Domicilio_Cliente__c != null);

                if (sameCliente && sameKey && oldTeniaDomicilio) {
                    continue;
                }
            }

            accountIds.add(f.Cliente__c);
            keys.add(key.trim());
            objetivo.add(f);
        }

        if (objetivo.isEmpty()) return;

        List<Domicilio_de_Cliente__c> domicilios = [
            SELECT Id, Cliente__c, Cliente_Despacho__c
            FROM Domicilio_de_Cliente__c
            WHERE Cliente__c IN :accountIds
              AND Cliente_Despacho__c IN :keys
        ];

        Map<String, Id> mapKeyToDomicilio = new Map<String, Id>();
        for (Domicilio_de_Cliente__c d : domicilios) {
            if (d.Cliente__c == null || String.isBlank(d.Cliente_Despacho__c)) continue;
            mapKeyToDomicilio.put(buildKey(d.Cliente__c, d.Cliente_Despacho__c), d.Id);
        }

        for (Facturas__c f : objetivo) {
            String key = String.valueOf(f.Direccion__c).trim();
            String k = buildKey(f.Cliente__c, key);

            if (mapKeyToDomicilio.containsKey(k)) {
                f.Domicilio_Cliente__c = mapKeyToDomicilio.get(k);
                f.Ya_procesada__c = true; // ✅ SOLO si asignó domicilio
            }
        }
    }

    private static String buildKey(Id accountId, String key) {
        return String.valueOf(accountId) + '|' + String.valueOf(key).trim();
    }
}