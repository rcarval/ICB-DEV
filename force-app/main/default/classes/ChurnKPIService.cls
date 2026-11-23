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

        // Recuperables: clientes que facturaron en los últimos 12 meses pero NO en los últimos 3 meses
        Set<Id> recoverableAccounts = new Set<Id>();

        for (Account a : [
            SELECT Id
            FROM Account
            WHERE Id IN (
                SELECT Cliente__c
                FROM Facturas__c
                WHERE Fecha_de_Documento__c >= LAST_N_MONTHS:12
                  AND Fecha_de_Documento__c < LAST_N_MONTHS:3
            )
            AND Id NOT IN (
                SELECT Cliente__c
                FROM Facturas__c
                WHERE Fecha_de_Documento__c >= LAST_N_MONTHS:3
                  AND Fecha_de_Documento__c < THIS_MONTH
            )
        ]) {
            recoverableAccounts.add(a.Id);
        }        

        // Recovered: clientes que NO facturaron en el mes anterior pero SÍ en el mes actual
        Map<Id, Integer> recoveredMap = new Map<Id, Integer>();
        if (!recoverableAccounts.isEmpty()) {
            for (AggregateResult ar : [
                SELECT OwnerId ownerId, COUNT(Id) total
                FROM Account
                WHERE OwnerId IN :activeOwnerIds
                  AND Id IN :recoverableAccounts
                  AND Id IN (
                      SELECT Cliente__c
                      FROM Facturas__c
                      WHERE Fecha_de_Documento__c = THIS_MONTH
                  )
                GROUP BY OwnerId
            ]) {
                Id oid = (Id) ar.get('ownerId');
                Integer total = ((Decimal) ar.get('total')).intValue();
                recoveredMap.put(oid, total);
            }
        }
        

        // New Accounts: clientes que facturaron por primera vez en el mes actual
        Map<Id, Integer> newAccountMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OwnerId ownerId, COUNT(Id) total
            FROM Account
            WHERE OwnerId IN :activeOwnerIds
              AND Id IN (
                  SELECT Cliente__c
                  FROM Facturas__c
                  WHERE Fecha_de_Documento__c = THIS_MONTH
              )
              AND Id NOT IN (
                  SELECT Cliente__c
                  FROM Facturas__c
                  WHERE Fecha_de_Documento__c >= LAST_N_MONTHS:12
                  AND Fecha_de_Documento__c < THIS_MONTH
              )
            GROUP BY OwnerId
        ]) {
            Id oid = (Id) ar.get('ownerId');
            Integer total = ((Decimal) ar.get('total')).intValue();
            newAccountMap.put(oid, total);
        }

        // Construcción y upsert de KPI
        List<SalesKPI__c> toUpsert = new List<SalesKPI__c>();
        List<MonthlyROAKPI__c> toUpsertMonthly = new List<MonthlyROAKPI__c>();
        
        Date lastDayOfMonth = today.toStartOfMonth().addMonths(1).addDays(-1);
        
        Boolean isLastDayOfMonth = today == lastDayOfMonth;
        
        
        for (Id oId : activeOwnerIds) {
            Integer activeCount    = activeMap.containsKey(oId)    ? activeMap.get(oId)    : 0;
            Integer churnedCount   = churnedMap.containsKey(oId)   ? churnedMap.get(oId)   : 0;
            Integer retainedCount  = retainedMap.containsKey(oId)  ? retainedMap.get(oId)  : 0;
            Integer recoveredCount = recoveredMap.containsKey(oId) ? recoveredMap.get(oId) : 0;
            Integer newAccountCount = newAccountMap.containsKey(oId) ? newAccountMap.get(oId) : 0;

            if (activeCount == 0 && churnedCount == 0 && retainedCount == 0 && recoveredCount == 0 && newAccountCount == 0) continue;

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
                RetainedPct__c   = retainedPct,
                RecoveredCount__c = recoveredCount,
                NewAccountCount__c = newAccountCount
            ));

            if (isLastDayOfMonth) {
    
                String monthKey = String.valueOf(today.year()) + '-' + 
                    (today.month() < 10 ? '0' + String.valueOf(today.month()) : String.valueOf(today.month()));
            
                String monthlyUniqueKey = String.valueOf(oId) + '|' + monthKey;
            
                toUpsertMonthly.add(new MonthlyROAKPI__c(
                    UniqueKey__c     = monthlyUniqueKey,
                    OwnerId__c       = oId,
                    Month__c         = today,          // Fecha exacta del último día
                    Year__c          = today.year(),
                    MonthNumber__c   = today.month(),
                    CarteraActiva__c = activeCount,
                    Nuevos__c        = newAccountCount,
                    Retenidos__c     = retainedCount,
                    Fugados__c       = churnedCount,
                    Recuperados__c   = recoveredCount
                ));
            }
            

        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert SalesKPI__c.Fields.UniqueKey__c;
        }

        if (!toUpsertMonthly.isEmpty()) {
            upsert toUpsertMonthly MonthlyROAKPI__c.Fields.UniqueKey__c;
        }

    }
}