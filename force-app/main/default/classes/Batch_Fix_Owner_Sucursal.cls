/**
 * Batch_Fix_Owner_Sucursal
 * Corrige el OwnerId de las Sucursales migradas: OwnerId = OwnerId del DOMICILIO de origen.
 * Mapea por (ParentId | Cliente_Despacho__c) = (Domicilio.Cliente__c | Cliente_Despacho__c).
 * Claves duplicadas: usa el domicilio mas reciente (ORDER BY LastModifiedDate DESC).
 * Solo actualiza las que difieren.
 *
 *   Database.executeBatch(new Batch_Fix_Owner_Sucursal(), 200);
 */
public class Batch_Fix_Owner_Sucursal implements Database.Batchable<SObject>, Database.Stateful {

    public Integer updated = 0;
    public Integer errorCount = 0;
    public Integer maxRecords;

    public Batch_Fix_Owner_Sucursal() { this.maxRecords = null; }
    public Batch_Fix_Owner_Sucursal(Integer maxRecords) { this.maxRecords = maxRecords; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q =
            'SELECT Id, OwnerId, ParentId, Cliente_Despacho__c ' +
            'FROM Account ' +
            'WHERE RecordType.DeveloperName = \'Sucursal\' AND ParentId != null';
        if (maxRecords != null) q += ' LIMIT ' + maxRecords;
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> parentIds = new Set<Id>();
        Set<String> desps = new Set<String>();
        for (Account a : (List<Account>) scope) { parentIds.add(a.ParentId); desps.add(a.Cliente_Despacho__c); }

        Map<String, Id> keyToDomOwner = new Map<String, Id>();
        for (Domicilio_de_Cliente__c d : [SELECT Cliente__c, Cliente_Despacho__c, OwnerId
                                          FROM Domicilio_de_Cliente__c
                                          WHERE Cliente__c IN :parentIds AND Cliente_Despacho__c IN :desps
                                          ORDER BY LastModifiedDate DESC]) {
            String k = d.Cliente__c + '|' + d.Cliente_Despacho__c;
            if (!keyToDomOwner.containsKey(k)) keyToDomOwner.put(k, d.OwnerId);
        }

        List<Account> upd = new List<Account>();
        for (Account a : (List<Account>) scope) {
            Id domOwner = keyToDomOwner.get(a.ParentId + '|' + a.Cliente_Despacho__c);
            if (domOwner != null && domOwner != a.OwnerId) {
                upd.add(new Account(Id = a.Id, OwnerId = domOwner));
            }
        }

        if (!upd.isEmpty()) {
            for (Database.SaveResult sr : Database.update(upd, false)) {
                if (sr.isSuccess()) { updated++; } else { errorCount++; System.debug('ERR ' + sr.getErrors()[0].getMessage()); }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('===== FIX OWNER (DOMICILIO) ===== Actualizadas: ' + updated + ' | Errores: ' + errorCount);
    }
}