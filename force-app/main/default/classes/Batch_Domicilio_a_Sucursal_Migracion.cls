/**
 * Batch_Domicilio_a_Sucursal_Migracion
 *
 * Crea Account (RecordType=Sucursal) desde Domicilio_de_Cliente__c.
 * Llave de unicidad/idempotencia: (Cliente=ParentId | Cliente_Despacho__c).
 *   - Anti-duplicado: si ya existe una Sucursal con esa llave, se salta.
 *   - Re-ejecutable: una segunda corrida no duplica.
 *
 * lat/long: Domicilio.Latitud__c/Longitud__c son TEXTO -> ShippingLatitude/Longitude (Decimal).
 * Contacto (texto) -> Datos_de_Contacto_Principal__c (concatenado).
 *
 * PILOTO:  Database.executeBatch(new Batch_Domicilio_a_Sucursal_Migracion(5), 5);
 * FULL:    Database.executeBatch(new Batch_Domicilio_a_Sucursal_Migracion(), 200);
 */
public class Batch_Domicilio_a_Sucursal_Migracion implements Database.Batchable<SObject>, Database.Stateful {

    public Integer processedCount = 0;
    public Integer skippedExisting = 0;
    public Integer errorCount = 0;
    public List<String> errors = new List<String>();

    public Set<String> existingKeys = new Set<String>();
    public Boolean keysLoaded = false;

    // Limite opcional para piloto (null = sin limite)
    public Integer maxRecords;

    public Batch_Domicilio_a_Sucursal_Migracion() { this.maxRecords = null; }
    public Batch_Domicilio_a_Sucursal_Migracion(Integer maxRecords) { this.maxRecords = maxRecords; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q =
            'SELECT Id, Cliente__c, Cliente__r.Name, Cliente_Despacho__c, ' +
            '       Domicilio_Adicional__c, Latitud__c, Longitud__c, ' +
            '       Comuna_Despacho__c, Region__c, ' +
            '       Centro_de_Distribucion__c, Rango_Horario__c, ' +
            '       Codigo_ejecutivo__c, Gerencia__c, Canal__c, ' +
            '       Nombre_de_Contacto__c, Tel_fono_de_Contacto__c, Email_de_contacto__c ' +
            'FROM Domicilio_de_Cliente__c ' +
            'WHERE Cliente__c != null AND Cliente_Despacho__c != null ' +
            'ORDER BY Cliente__c, Cliente_Despacho__c, LastModifiedDate DESC';
        if (maxRecords != null) q += ' LIMIT ' + maxRecords;
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            Id sucursalRtId = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName().get('Sucursal').getRecordTypeId();

            if (!keysLoaded) {
                for (Account a : [SELECT ParentId, Cliente_Despacho__c
                                  FROM Account
                                  WHERE RecordTypeId = :sucursalRtId
                                  AND ParentId != null AND Cliente_Despacho__c != null]) {
                    existingKeys.add(a.ParentId + '|' + a.Cliente_Despacho__c);
                }
                keysLoaded = true;
            }

            List<Account> toInsert = new List<Account>();
            List<Id> insertKeyOwner = new List<Id>();
            List<String> insertKeys = new List<String>();

            for (Domicilio_de_Cliente__c d : (List<Domicilio_de_Cliente__c>) scope) {
                String key = d.Cliente__c + '|' + d.Cliente_Despacho__c;
                if (existingKeys.contains(key)) { skippedExisting++; continue; }
                existingKeys.add(key);

                Account s = new Account();
                s.RecordTypeId = sucursalRtId;
                s.ParentId = d.Cliente__c;
                s.Cliente_Despacho__c = d.Cliente_Despacho__c;
                s.Name = (d.Cliente__r != null ? d.Cliente__r.Name : 'Cliente') + ' - ' + d.Cliente_Despacho__c;

                if (d.Domicilio_Adicional__c != null) {
                    s.ShippingStreet     = d.Domicilio_Adicional__c.getStreet();
                    s.ShippingCity       = d.Domicilio_Adicional__c.getCity();
                    s.ShippingState      = d.Domicilio_Adicional__c.getState();
                    s.ShippingPostalCode = d.Domicilio_Adicional__c.getPostalCode();
                    s.ShippingCountry    = d.Domicilio_Adicional__c.getCountry();
                }
                Decimal lat = safeDecimal(d.Latitud__c);
                Decimal lng = safeDecimal(d.Longitud__c);
                if (lat != null) s.ShippingLatitude  = lat;
                if (lng != null) s.ShippingLongitude = lng;

                s.Comuna_Despacho__c          = d.Comuna_Despacho__c;
                s.Region_Despacho__c          = d.Region__c;
                s.Centro_de_Abastecimiento__c = d.Centro_de_Distribucion__c;
                s.Rango_Horario__c            = d.Rango_Horario__c;
                s.Codigo_ejecutivo__c         = d.Codigo_ejecutivo__c;
                s.Gerencia__c                 = d.Gerencia__c;
                // Canal__c es formula (no escribible) -> se deriva solo

                // Campo de 35 chars: guardar nombre (o email si no hay nombre), truncado.
                String dc;
                if (String.isNotBlank(d.Nombre_de_Contacto__c)) dc = d.Nombre_de_Contacto__c;
                else if (String.isNotBlank(d.Email_de_contacto__c)) dc = d.Email_de_contacto__c;
                if (String.isNotBlank(dc)) s.Datos_de_Contacto_Principal__c = dc.length() > 35 ? dc.left(35) : dc;

                toInsert.add(s);
                insertKeyOwner.add(d.Id);
                insertKeys.add(key);
            }

            if (!toInsert.isEmpty()) {
                Database.SaveResult[] rs = Database.insert(toInsert, false);
                for (Integer i = 0; i < rs.size(); i++) {
                    if (rs[i].isSuccess()) {
                        processedCount++;
                    } else {
                        errorCount++;
                        existingKeys.remove(insertKeys[i]);
                        errors.add('Dom ' + insertKeyOwner[i] + ': ' + rs[i].getErrors()[0].getMessage());
                    }
                }
            }
        } catch (Exception e) {
            errorCount++;
            errors.add('EXECUTE: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('===== PASO 2 =====');
        System.debug('Sucursales creadas: ' + processedCount);
        System.debug('Saltadas (ya existian): ' + skippedExisting);
        System.debug('Errores: ' + errorCount);
        for (Integer i = 0; i < Math.min(errors.size(), 20); i++) System.debug(errors[i]);
    }

    private static Decimal safeDecimal(String v) {
        if (String.isBlank(v)) return null;
        try { return Decimal.valueOf(v.trim().replace(',', '.')); }
        catch (Exception e) { return null; }
    }
}