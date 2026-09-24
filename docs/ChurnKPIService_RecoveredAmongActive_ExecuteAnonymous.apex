// Ejecutar en Developer Console → Debug → Open Execute Anonymous Window.
// Solo para el owner 005Pr000005nDlWIAU; todas las queries filtran por sus cuentas para no superar 50k filas.

Id ownerId = '005Pr000005nDlWIAU';

// Cuentas de este owner (para filtrar todas las consultas y no pasarnos de filas)
List<Account> cuentasOwner = [SELECT Id FROM Account WHERE OwnerId = :ownerId LIMIT 50000];
Set<Id> accountIdsOfOwner = new Set<Id>();
for (Account a : cuentasOwner) accountIdsOfOwner.add(a.Id);
if (accountIdsOfOwner.isEmpty()) {
    System.debug('El owner no tiene cuentas.');
    return;
}

// Activos: clientes de este owner con factura en últimos 3 meses
Set<Id> activeAccountIds = new Set<Id>();
for (Facturas__c f : [
    SELECT Cliente__c
    FROM Facturas__c
    WHERE Fecha_de_Documento__c = LAST_N_MONTHS:3
    AND Cliente__c IN :accountIdsOfOwner
]) {
    activeAccountIds.add(f.Cliente__c);
}

// Facturaron este mes (solo cuentas de este owner)
Set<Id> facturaronEsteMesIds = new Set<Id>();
for (Facturas__c f : [
    SELECT Cliente__c
    FROM Facturas__c
    WHERE Fecha_de_Documento__c = THIS_MONTH
    AND Cliente__c IN :accountIdsOfOwner
]) {
    facturaronEsteMesIds.add(f.Cliente__c);
}

// Facturaron el mes pasado (solo cuentas de este owner)
Set<Id> facturaronMesPasadoIds = new Set<Id>();
for (Facturas__c f : [
    SELECT Cliente__c
    FROM Facturas__c
    WHERE Fecha_de_Documento__c = LAST_MONTH
    AND Cliente__c IN :accountIdsOfOwner
]) {
    facturaronMesPasadoIds.add(f.Cliente__c);
}

// Recuperados = este mes sí, mes pasado no
Set<Id> recoveredIds = new Set<Id>();
for (Id accId : facturaronEsteMesIds) {
    if (!facturaronMesPasadoIds.contains(accId)) recoveredIds.add(accId);
}

// Recuperados que además están en activos
Integer recoveredAmongActive = 0;
for (Id accId : recoveredIds) {
    if (activeAccountIds.contains(accId)) recoveredAmongActive++;
}

// Detalle: nombres de los clientes recuperados (entre activos)
List<Account> recuperados = [
    SELECT Id, Name
    FROM Account
    WHERE Id IN :recoveredIds
    AND Id IN :activeAccountIds
    ORDER BY Name
];

User u = [SELECT Name FROM User WHERE Id = :ownerId LIMIT 1];
System.debug('Owner: ' + u.Name + ' (' + ownerId + ')');
System.debug('Activos (últimos 3 meses): ' + activeAccountIds.size());
System.debug('Recuperados (entre activos): ' + recoveredAmongActive);
System.debug('--- Clientes recuperados ---');
for (Account a : recuperados) {
    System.debug('  ' + a.Name + ' (' + a.Id + ')');
}
