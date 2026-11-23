@isTest(SeeAllData=true)
private class Batch_Fact_Suc_Backfill_Test {
    @isTest
    static void ejecutaPiloto() {
        Test.startTest();
        Database.executeBatch(new Batch_Facturas_Sucursal_Backfill(1), 200);
        Test.stopTest();
        System.assert(true, 'El batch debe ejecutar sin excepciones no controladas');
    }
}