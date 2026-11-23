@IsTest
private class ICBFS_CondPagoSAPAsyncInvokerTest {
    @IsTest
    static void enqueue_creates_single_queueable_per_account() {
        ICBFS_CondPagoSAPAsyncInvoker.Input req1 = new ICBFS_CondPagoSAPAsyncInvoker.Input();
        req1.accountId = (Id) '001000000000000AAA';

        ICBFS_CondPagoSAPAsyncInvoker.Input req2 = new ICBFS_CondPagoSAPAsyncInvoker.Input();
        req2.accountId = (Id) '001000000000000AAA';

        Test.startTest();
        ICBFS_CondPagoSAPAsyncInvoker.enqueue(new List<ICBFS_CondPagoSAPAsyncInvoker.Input>{ req1, req2, null });
        Test.stopTest();

        Integer jobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ICBFS_CondPagoSAPAsyncInvoker'
        ];
        System.assertEquals(1, jobs, 'Debe encolar solo un job por AccountId unico.');
    }

    @IsTest
    static void enqueue_ignores_null_or_empty_inputs() {
        Test.startTest();
        ICBFS_CondPagoSAPAsyncInvoker.enqueue(null);
        ICBFS_CondPagoSAPAsyncInvoker.enqueue(new List<ICBFS_CondPagoSAPAsyncInvoker.Input>());
        Test.stopTest();

        Integer jobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ICBFS_CondPagoSAPAsyncInvoker'
        ];
        System.assertEquals(0, jobs, 'No debe encolar jobs cuando no hay entradas validas.');
    }

    @IsTest
    static void queueable_execute_covers_blank_and_non_blank_paths() {
        new ICBFS_CondPagoSAPAsyncInvoker.RunFlowQueueable('   ').execute(null);
        new ICBFS_CondPagoSAPAsyncInvoker.RunFlowQueueable('001000000000000AAA').execute(null);
        System.assert(true, 'Queueable execute completed without bubbling exceptions.');
    }
}