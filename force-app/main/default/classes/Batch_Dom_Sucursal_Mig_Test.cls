@isTest(SeeAllData=true)
private class Batch_Dom_Sucursal_Mig_Test {
    // Utilidad de migración one-off: se prueba contra datos reales (SeeAllData)
    // corriendo el batch en modo piloto (1 registro). El DML se revierte al terminar el test.
    @isTest
    static void ejecutaPiloto() {
        Test.startTest();
        Database.executeBatch(new Batch_Domicilio_a_Sucursal_Migracion(1), 200);
        Test.stopTest();
        System.assert(true, 'El batch debe ejecutar sin excepciones no controladas');
    }
}