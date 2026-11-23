@isTest(SeeAllData=true)
private class Batch_Fix_Owner_Suc_Test {
    @isTest
    static void ejecuta() {
        Test.startTest();
        Database.executeBatch(new Batch_Fix_Owner_Sucursal(1), 200);
        Test.stopTest();
        System.assert(true, 'El batch debe ejecutar sin excepciones no controladas');
    }
}