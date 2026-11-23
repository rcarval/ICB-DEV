@IsTest
private class icbfs_AccountRutTriggerTest {
    @IsTest
    static void acceptsValidRutAndUnrelatedUpdateWithoutQueueable() {
        Test.startTest();
        Account acc = new Account(Name = 'RUT VALIDO', RUT__c = '12345678-5');
        insert acc;
        acc.Name = 'RUT VALIDO EDITADO';
        update acc;
        Integer queuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queuedJobs, 'El trigger RUT no debe encolar trabajos GEO');
        System.assertEquals(
            'RUT VALIDO EDITADO',
            [SELECT Name FROM Account WHERE Id = :acc.Id].Name
        );
    }

    @IsTest
    static void rejectsInvalidRut() {
        try {
            insert new Account(Name = 'RUT INVALIDO', RUT__c = '12345678-1');
            System.assert(false, 'El RUT invalido debio ser rechazado');
        } catch (DmlException ex) {
            System.assert(ex.getDmlMessage(0).contains('RUT invalido'));
        }
    }

    @IsTest
    static void rejectsInvalidFormatOnUpdate() {
        Account acc = new Account(Name = 'RUT FORMATO', RUT__c = '12345678-5');
        insert acc;
        acc.RUT__c = '123456785';

        try {
            update acc;
            System.assert(false, 'El formato invalido debio ser rechazado');
        } catch (DmlException ex) {
            System.assert(ex.getDmlMessage(0).contains('Formato de RUT incorrecto'));
        }
    }
}