public without sharing class ChurnKPIService {

    @InvocableMethod(label='Actualizar Churn KPI')
    public static void upsertKPI(List<Id> userIds) {
        Set<Id> ownerIds = new Set<Id>();
        if (userIds != null) ownerIds.addAll(userIds);

        // Auto-descubre owners si no se especifican
        if (ownerIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Cliente__r.OwnerId ownerId
                FROM Facturas__c
                WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
                GROUP BY Cliente__r.OwnerId
            ]) {
                Id oid = (Id) ar.get('ownerId');
                if (oid != null) ownerIds.add(oid);
            }
            for (AggregateResult ar : [
                SELECT OwnerId ownerId
                FROM Account
                WHERE Id IN (
                    SELECT Cliente__c
                    FROM Facturas__c
                    WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
                )
                AND Id NOT IN (
                    SELECT Cliente__c
                    FROM Facturas__c
                    WHERE Fecha_de_Documento__c = THIS_MONTH
                )
                GROUP BY OwnerId
            ]) {
                Id oid = (Id) ar.get('ownerId');
                if (oid != null) ownerIds.add(oid);
            }
        }

        // 🔒 Filtrar solo OwnerIds activos
        Set<Id> activeOwnerIds = new Set<Id>();
        for (User u : [
            SELECT Id FROM User WHERE Id IN :ownerIds AND IsActive = true
        ]) {
            activeOwnerIds.add(u.Id);
        }
        if (activeOwnerIds.isEmpty()) return;

        Date today = Date.today();
        String todayKey = String.valueOf(today);

        // Activos: clientes únicos con facturas en últimos 3 meses por Owner
        Map<Id, Integer> activeMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Cliente__r.OwnerId ownerId, COUNT_DISTINCT(Cliente__c) total
            FROM Facturas__c
            WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
              AND Cliente__r.OwnerId IN :activeOwnerIds
            GROUP BY Cliente__r.OwnerId
        ]) {
            Id oid = (Id) ar.get('ownerId');
            Integer total = ((Decimal) ar.get('total')).intValue();
            activeMap.put(oid, total);
        }

        // Churned
        Map<Id, Integer> churnedMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OwnerId ownerId, COUNT(Id) total
            FROM Account
            WHERE OwnerId IN :activeOwnerIds
              AND Id IN (
                  SELECT Cliente__c
                  FROM Facturas__c
                  WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
              )
              AND Id NOT IN (
                  SELECT Cliente__c
                  FROM Facturas__c
                  WHERE Fecha_de_Documento__c = THIS_MONTH
              )
            GROUP BY OwnerId
        ]) {
            Id oid = (Id) ar.get('ownerId');
            Integer total = ((Decimal) ar.get('total')).intValue();
            churnedMap.put(oid, total);
        }

        // Retained
        Map<Id, Integer> retainedMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OwnerId ownerId, COUNT(Id) total
            FROM Account
            WHERE OwnerId IN :activeOwnerIds
              AND Id IN (
                  SELECT Cliente__c
                  FROM Facturas__c
                  WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
              )
              AND Id IN (
                  SELECT Cliente__c
                  FROM Facturas__c
                  WHERE Fecha_de_Documento__c = THIS_MONTH
              )
            GROUP BY OwnerId
        ]) {
            Id oid = (Id) ar.get('ownerId');
            Integer total = ((Decimal) ar.get('total')).intValue();
            retainedMap.put(oid, total);
        }

        // Construcción y upsert de KPI
        List<SalesKPI__c> toUpsert = new List<SalesKPI__c>();
        for (Id oId : activeOwnerIds) {
            Integer activeCount    = activeMap.containsKey(oId)    ? activeMap.get(oId)    : 0;
            Integer churnedCount   = churnedMap.containsKey(oId)   ? churnedMap.get(oId)   : 0;
            Integer retainedCount  = retainedMap.containsKey(oId)  ? retainedMap.get(oId)  : 0;

            if (activeCount == 0 && churnedCount == 0 && retainedCount == 0) continue;

            Decimal denom       = Decimal.valueOf(activeCount + churnedCount);
            Decimal churnPct    = denom == 0 ? 0 : Decimal.valueOf(churnedCount) / denom;
            Decimal retainedPct = denom == 0 ? 0 : Decimal.valueOf(retainedCount) / denom;

            String uniqueKey = String.valueOf(oId) + '|' + todayKey;

            toUpsert.add(new SalesKPI__c(
                UniqueKey__c     = uniqueKey,
                OwnerId          = oId,
                AsOfDate__c      = today,
                ActiveCount__c   = activeCount,
                ChurnedCount__c  = churnedCount,
                ChurnPct__c      = churnPct,
                RetainedCount__c = retainedCount,
                RetainedPct__c   = retainedPct
            ));
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert SalesKPI__c.Fields.UniqueKey__c;
        }
    }
}