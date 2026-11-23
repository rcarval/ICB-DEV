/**
 * Batch_Facturas_Sucursal_Backfill
 *
 * Backfill de Facturas__c.Sucursal__c usando la llave (Cliente=ParentId | Cliente_Despacho__c)
 * del Domicilio al que la factura ya apunta.
 *
 * Prerrequisito: Paso 2 completado (Sucursales creadas).
 *
 * PILOTO:  Database.executeBatch(new Batch_Facturas_Sucursal_Backfill(5), 200);
 * FULL:    Database.executeBatch(new Batch_Facturas_Sucursal_Backfill(), 200);
 */
public class Batch_Facturas_Sucursal_Backfill implements Database.Batchable<SObject>, Database.Stateful {

    public Integer processedCount = 0;
    public Integer noMatchCount = 0;
    public Integer errorCount = 0;
    public List<String> sampleNoMatch = new List<String>();
    public List<String> errors = new List<String>();
    public Map<String, Id> keyToSucursal = new Map<String, Id>();
    public Boolean mapLoaded = false;
    public Integer maxRecords;

    public Batch_Facturas_Sucursal_Backfill() { this.maxRecords = null; }
    public Batch_Facturas_Sucursal_Backfill(Integer maxRecords) { this.maxRecords = maxRecords; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q =
            'SELECT Id, Domicilio_Cliente__r.Cliente__c, Domicilio_Cliente__r.Cliente_Despacho__c ' +
            'FROM Facturas__c ' +
            'WHERE Domicilio_Cliente__c != null AND Sucursal__c = null';
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

            List<Facturas__c> toUpdate = new List<Facturas__c>();
            for (Facturas__c f : (List<Facturas__c>) scope) {
                Id cli = (f.Domicilio_Cliente__r != null) ? f.Domicilio_Cliente__r.Cliente__c : null;
                String desp = (f.Domicilio_Cliente__r != null) ? f.Domicilio_Cliente__r.Cliente_Despacho__c : null;
                if (cli == null || desp == null) {
                    noMatchCount++;
                    if (sampleNoMatch.size() < 50) sampleNoMatch.add(f.Id + ': domicilio sin cliente/despacho');
                    continue;
                }
                Id sucId = keyToSucursal.get(cli + '|' + desp);
                if (sucId == null) {
                    noMatchCount++;
                    if (sampleNoMatch.size() < 50) sampleNoMatch.add(f.Id + ': sin Sucursal para ' + cli + '|' + desp);
                    continue;
                }
                toUpdate.add(new Facturas__c(Id = f.Id, Sucursal__c = sucId));
            }

            if (!toUpdate.isEmpty()) {
                for (Database.SaveResult sr : Database.update(toUpdate, false)) {
                    if (sr.isSuccess()) processedCount++;
                    else { errorCount++; if (errors.size() < 50) errors.add(sr.getErrors()[0].getMessage()); }
                }
            }
        } catch (Exception e) {
            errorCount++;
            errors.add('EXECUTE: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('===== PASO 4 =====');
        System.debug('Facturas actualizadas: ' + processedCount);
        System.debug('Sin match (van a PASO 5): ' + noMatchCount);
        System.debug('Errores: ' + errorCount);
        for (String s : sampleNoMatch) System.debug('NOMATCH ' + s);
        for (String e : errors) System.debug('ERR ' + e);
    }
}