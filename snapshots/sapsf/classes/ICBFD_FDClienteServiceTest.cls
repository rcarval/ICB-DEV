/**
 * ICB Food Service
 * Desarrollado por: JosÃ© Illanes
 * Fecha: 2026-02-04
 * DescripciÃ³n: Tests para asignaciÃ³n de Domicilio_Cliente__c y Sucursal__c en Facturas__c
 */
@IsTest
private class ICBFD_FDClienteServiceTest {

    @IsTest
    static void test_asigna_domicilio_y_cuenta_base_por_key() {
        Account a = new Account(
            Name = 'Cuenta Test',
            Cliente_Despacho__c = 'FS34880-2'
        );
        insert a;

        Domicilio_de_Cliente__c dom = new Domicilio_de_Cliente__c(
            Cliente__c = a.Id,
            Cliente_Despacho__c = 'FS34880-2'
        );
        insert dom;

        Facturas__c f = new Facturas__c(
            Cliente__c = a.Id,
            Direccion__c = 'FS34880-2'
        );
        insert f;

        Facturas__c fDB = [
            SELECT Id, Domicilio_Cliente__c, Sucursal__c
            FROM Facturas__c
            WHERE Id = :f.Id
        ];

        System.assertEquals(dom.Id, fDB.Domicilio_Cliente__c, 'Debe asignar el domicilio correcto');
        System.assertEquals(a.Id, fDB.Sucursal__c, 'Debe asignar la misma cuenta cuando el despacho pertenece a la cuenta base');
    }

    @IsTest
    static void test_bulk_200_registros() {
        Account a = new Account(
            Name = 'Cuenta Bulk',
            Cliente_Despacho__c = 'K1'
        );
        insert a;

        Domicilio_de_Cliente__c dom = new Domicilio_de_Cliente__c(
            Cliente__c = a.Id,
            Cliente_Despacho__c = 'K1'
        );
        insert dom;

        List<Facturas__c> facturas = new List<Facturas__c>();
        for (Integer i = 0; i < 200; i++) {
            facturas.add(new Facturas__c(
                Cliente__c = a.Id,
                Direccion__c = 'K1'
            ));
        }

        Test.startTest();
        insert facturas;
        Test.stopTest();

        Integer ok = [
            SELECT count()
            FROM Facturas__c
            WHERE Cliente__c = :a.Id
              AND Domicilio_Cliente__c = :dom.Id
        ];

        Integer okSucursal = [
            SELECT count()
            FROM Facturas__c
            WHERE Cliente__c = :a.Id
              AND Sucursal__c = :a.Id
        ];

        System.assertEquals(200, ok, 'Debe asignar domicilio a todas en bulk');
        System.assertEquals(200, okSucursal, 'Debe asignar la cuenta base como sucursal a todas en bulk');
    }

    @IsTest
    static void test_prefiere_sucursal_hija_por_despacho() {
        Id negocioRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Negocio').getRecordTypeId();
        Id sucursalRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Sucursal').getRecordTypeId();

        Account matriz = new Account(
            Name = 'Cuenta Matriz',
            RecordTypeId = negocioRtId,
            Cliente_Despacho__c = 'FS50000-1',
            Sucursal__c = 'S001 - Suc Santiago'
        );
        insert matriz;

        Account sucursal = new Account(
            Name = 'Sucursal Operativa',
            RecordTypeId = sucursalRtId,
            ParentId = matriz.Id,
            Cliente_Despacho__c = 'FS50000-1',
            Sucursal__c = 'S001 - Suc Santiago'
        );
        insert sucursal;

        Domicilio_de_Cliente__c dom = new Domicilio_de_Cliente__c(
            Cliente__c = matriz.Id,
            Cliente_Despacho__c = 'FS50000-1'
        );
        insert dom;

        Facturas__c factura = new Facturas__c(
            Cliente__c = matriz.Id,
            Direccion__c = 'FS50000-1'
        );
        insert factura;

        Facturas__c facturaDb = [
            SELECT Sucursal__c, Domicilio_Cliente__c
            FROM Facturas__c
            WHERE Id = :factura.Id
        ];

        System.assertEquals(dom.Id, facturaDb.Domicilio_Cliente__c, 'Debe mantener la resoluciÃ³n de domicilio');
        System.assertEquals(sucursal.Id, facturaDb.Sucursal__c, 'Debe preferir la sucursal hija cuando existe match exacto');
    }
}