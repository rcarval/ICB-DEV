/**
 * ICB Food Service/**
 * ICB Food Service
 * Desarrollado por: José Illanes
 * Fecha: 2026-02-04
 * Descripción: Tests para asignación de Domicilio_Cliente__c en Facturas__c (bulk-safe)
 */
@IsTest
private class ICBFD_FDClienteServiceTest {

    @IsTest
    static void test_asigna_domicilio_por_key() {
        Account a = new Account(Name = 'Cuenta Test');
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
            SELECT Id, Domicilio_Cliente__c
            FROM Facturas__c
            WHERE Id = :f.Id
        ];

        System.assertEquals(dom.Id, fDB.Domicilio_Cliente__c, 'Debe asignar el domicilio correcto');
    }

    @IsTest
    static void test_bulk_200_registros() {
        Account a = new Account(Name = 'Cuenta Bulk');
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

        System.assertEquals(200, ok, 'Debe asignar domicilio a todas en bulk');
    }
}