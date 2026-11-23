/**
 * Batch_Contacto_Herencia_Sucursal
 *
 * Fuente 1: Domicilio.Contacto__c -> hereda a la Sucursal:
 *   - Crea AccountContactRelation (Contact <-> Sucursal, IsActive=true)
 *   - Puebla Contact.Contacto_Cuenta_Sucursal__c con la Sucursal
 * NO cambia Contact.AccountId. Llave (Cliente=ParentId | Cliente_Despacho__c).
 *
 * PILOTO:  Database.executeBatch(new Batch_Contacto_Herencia_Sucursal(5), 200);
 * FULL:    Database.executeBatch(new Batch_Contacto_Herencia_Sucursal(), 200);
 */
public class Batch_Contacto_Herencia_Sucursal implements Database.Batchable<SObject>, Database.Stateful {

    public Integer acrCreated = 0;
    public Integer contactsUpdated = 0;
    public Integer noMatch = 0;
    public Integer errorCount = 0;
    public List<String> errors = new List<String>();
    public Map<String, Id> keyToSucursal = new Map<String, Id>();
    public Boolean mapLoaded = false;
    public Integer maxRecords;

    public Batch_Contacto_Herencia_Sucursal() { this.maxRecords = null; }
    public Batch_Contacto_Herencia_Sucursal(Integer maxRecords) { this.maxRecords = maxRecords; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q =
            'SELECT Id, Contacto__c, Cliente__c, Cliente_Despacho__c ' +
            'FROM Domicilio_de_Cliente__c ' +
            'WHERE Contacto__c != null AND Cliente__c != null AND Cliente_Despacho__c != null';
        if (maxRecords != null) q += ' LIMIT ' + maxRecords;
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            if (!mapLoaded) {
                Id rt = Schema.SObjectType.Account
                    .getRecordTypeInfosByDeveloperName().get('Sucursal').getRecordTypeId();
                for (Account a : [SELECT Id, ParentId, Cliente_Despacho__c
                                  FROM Account
                                  WHERE RecordTypeId = :rt
                                  AND ParentId != null AND Cliente_Despacho__c != null]) {
                    keyToSucursal.put(a.ParentId + '|' + a.Cliente_Despacho__c, a.Id);
                }
                mapLoaded = true;
            }

            Map<Id, Id> contactToSucursal = new Map<Id, Id>();
            for (Domicilio_de_Cliente__c d : (List<Domicilio_de_Cliente__c>) scope) {
                Id sucId = keyToSucursal.get(d.Cliente__c + '|' + d.Cliente_Despacho__c);
                if (sucId == null) { noMatch++; continue; }
                contactToSucursal.put(d.Contacto__c, sucId);
            }
            if (contactToSucursal.isEmpty()) return;

            Set<String> existingAcr = new Set<String>();
            for (AccountContactRelation r : [SELECT AccountId, ContactId
                                             FROM AccountContactRelation
                                             WHERE ContactId IN :contactToSucursal.keySet()
                                             AND AccountId IN :contactToSucursal.values()]) {
                existingAcr.add(r.AccountId + '|' + r.ContactId);
            }

            List<AccountContactRelation> acrs = new List<AccountContactRelation>();
            List<Contact> cts = new List<Contact>();
            for (Id cId : contactToSucursal.keySet()) {
                Id sucId = contactToSucursal.get(cId);
                if (!existingAcr.contains(sucId + '|' + cId)) {
                    acrs.add(new AccountContactRelation(AccountId = sucId, ContactId = cId, IsActive = true));
                }
                cts.add(new Contact(Id = cId, Contacto_Cuenta_Sucursal__c = sucId));
            }

            if (!acrs.isEmpty()) {
                for (Database.SaveResult sr : Database.insert(acrs, false)) {
                    if (sr.isSuccess()) acrCreated++;
                    else { errorCount++; if (errors.size() < 50) errors.add('ACR: ' + sr.getErrors()[0].getMessage()); }
                }
            }
            if (!cts.isEmpty()) {
                for (Database.SaveResult sr : Database.update(cts, false)) {
                    if (sr.isSuccess()) contactsUpdated++;
                    else { errorCount++; if (errors.size() < 50) errors.add('CT: ' + sr.getErrors()[0].getMessage()); }
                }
            }
        } catch (Exception e) {
            errorCount++;
            errors.add('EXECUTE: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('===== PASO 3 =====');
        System.debug('ACR creadas: ' + acrCreated);
        System.debug('Contacts actualizados: ' + contactsUpdated);
        System.debug('Sin Sucursal: ' + noMatch + ' | Errores: ' + errorCount);
        for (String e : errors) System.debug('ERR ' + e);
    }
}