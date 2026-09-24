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

        // Activos por owner: Set de Ids de cuenta (clientes con factura en últimos 3 meses)
        Map<Id, Set<Id>> activeAccountIdsByOwner = new Map<Id, Set<Id>>();
        for (Facturas__c f : [
            SELECT Cliente__c, Cliente__r.OwnerId
            FROM Facturas__c
            WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
            AND Cliente__r.OwnerId IN :activeOwnerIds
        ]) {
            Id ownerId = f.Cliente__r.OwnerId;
            if (ownerId == null) continue;
            if (!activeAccountIdsByOwner.containsKey(ownerId)) {
                activeAccountIdsByOwner.put(ownerId, new Set<Id>());
            }
            activeAccountIdsByOwner.get(ownerId).add(f.Cliente__c);
        }

        // Recuperados por owner: Set de Ids (facturaron este mes y NO el mes pasado) — mismas queries que recoveredMap pero obteniendo IDs
        Set<Id> facturaronEsteMesIds = new Set<Id>();
        for (Facturas__c f : [SELECT Cliente__c FROM Facturas__c WHERE Fecha_de_Documento__c = THIS_MONTH]) {
            facturaronEsteMesIds.add(f.Cliente__c);
        }
        Set<Id> facturaronMesPasadoIds = new Set<Id>();
        for (Facturas__c f : [SELECT Cliente__c FROM Facturas__c WHERE Fecha_de_Documento__c = LAST_MONTH]) {
            facturaronMesPasadoIds.add(f.Cliente__c);
        }
        Map<Id, Set<Id>> recoveredAccountIdsByOwner = new Map<Id, Set<Id>>();
        for (Account a : [
            SELECT Id, OwnerId
            FROM Account
            WHERE OwnerId IN :activeOwnerIds
            AND Id IN :facturaronEsteMesIds
            AND Id NOT IN :facturaronMesPasadoIds
        ]) {
            if (!recoveredAccountIdsByOwner.containsKey(a.OwnerId)) {
                recoveredAccountIdsByOwner.put(a.OwnerId, new Set<Id>());
            }
            recoveredAccountIdsByOwner.get(a.OwnerId).add(a.Id);
        }

        // Recovered solo entre activos: para cada owner, cuántos recuperados están en activeMap (intersección)
        Map<Id, Integer> recoveredMap = new Map<Id, Integer>();
        for (Id oId : activeOwnerIds) {
            Set<Id> activeIds = activeAccountIdsByOwner.get(oId);
            Set<Id> recoveredIds = recoveredAccountIdsByOwner.get(oId);
            Integer count = 0;
            if (activeIds != null && recoveredIds != null) {
                for (Id accId : recoveredIds) {
                    if (activeIds.contains(accId)) count++;
                }
            }
            recoveredMap.put(oId, count);
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
                  WHERE Fecha_de_Documento__c < THIS_MONTH
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
        
        // Si es día 1 del mes, calcular fechas del mes anterior
        Date lastDayOfPreviousMonth = null;
        Integer previousYear = null;
        Integer previousMonth = null;
        String previousMonthKey = null;
        
        if (today.day() == 1) {
            lastDayOfPreviousMonth = today.addDays(-1);
            previousYear = lastDayOfPreviousMonth.year();
            previousMonth = lastDayOfPreviousMonth.month();
            previousMonthKey = String.valueOf(previousYear) + '-' + 
                              (previousMonth < 10 ? '0' + String.valueOf(previousMonth) : String.valueOf(previousMonth));
        }
        
        for (Id oId : activeOwnerIds) {
            Integer activeCount    = activeMap.containsKey(oId)    ? activeMap.get(oId)    : 0;
            Integer churnedCount   = churnedMap.containsKey(oId)   ? churnedMap.get(oId)   : 0;
            Integer retainedCount  = retainedMap.containsKey(oId)  ? retainedMap.get(oId)  : 0;
            Integer recoveredCount = recoveredMap.containsKey(oId) ? recoveredMap.get(oId) : 0;
            Integer newAccountCount = newAccountMap.containsKey(oId) ? newAccountMap.get(oId) : 0;

            if (activeCount == 0 && churnedCount == 0 && retainedCount == 0 && recoveredCount == 0 && newAccountCount == 0) continue;

            Decimal denom       = Decimal.valueOf(activeCount);
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

            if (today.day() == 1) {
                String monthlyUniqueKey = String.valueOf(oId) + '|' + previousMonthKey;
                
                toUpsertMonthly.add(new MonthlyROAKPI__c(
                    UniqueKey__c = monthlyUniqueKey,
                    OwnerId__c = oId,
                    Month__c = lastDayOfPreviousMonth,
                    Year__c = previousYear,
                    MonthNumber__c = previousMonth,
                    CarteraActiva__c = activeCount,
                    Nuevos__c = newAccountCount,
                    Retenidos__c = retainedCount,
                    Fugados__c = churnedCount,
                    Recuperados__c = recoveredCount
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