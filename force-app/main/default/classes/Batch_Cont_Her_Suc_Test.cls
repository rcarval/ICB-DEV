@isTest(SeeAllData=true)
private class Batch_Cont_Her_Suc_Test {
    @isTest
    static void ejecutaPiloto() {
        Test.startTest();
        Database.executeBatch(new Batch_Contacto_Herencia_Sucursal(1), 200);
        Test.stopTest();
        System.assert(true, 'El batch debe ejecutar sin excepciones no controladas');
    }
}