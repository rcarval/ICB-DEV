@IsTest
private class TaskProactivaAEHandlerTest {

    private static Id getOppRtId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    private static Opportunity createOpp(Id rtId, String stageName) {
        Account acc = new Account(Name = 'ACC TASK PROACTIVA ' + System.now().getTime());
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'OPP TASK PROACTIVA ' + System.now().getTime(),
            AccountId = acc.Id,
            RecordTypeId = rtId,
            StageName = stageName,
            CloseDate = Date.today().addDays(10),
            Amount = 1500,
            Visita_Concretada__c = true,
            Detalles__c = 'Resumen reunión',
            Valor_oportunidad__c = 1500
        );
        insert opp;
        return opp;
    }

    private static String getAnyClosedTaskStatus() {
        List<TaskStatus> rows = [SELECT ApiName FROM TaskStatus WHERE IsClosed = true LIMIT 1];
        System.assert(!rows.isEmpty(), 'Se requiere al menos un TaskStatus cerrado.');
        return rows[0].ApiName;
    }

    @IsTest
    static void shouldMoveToPropuestaWhenTaskCompleted() {
        Id autoRtId = getOppRtId('Auto_Enrolamiento');
        Opportunity opp = createOpp(autoRtId, 'Visita Concertada');

        Task t = new Task(
            WhatId = opp.Id,
            Subject = 'Enviar propuesta al cliente',
            ActivityDate = Date.today().addDays(1)
        );
        insert t;

        Test.startTest();
        t.Status = getAnyClosedTaskStatus();
        update t;
        Test.stopTest();

        Opportunity refreshed = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Propuesta Enviada', refreshed.StageName);
    }

    @IsTest
    static void shouldNotMoveForOtherSubject() {
        Id autoRtId = getOppRtId('Auto_Enrolamiento');
        Opportunity opp = createOpp(autoRtId, 'Visita Concertada');

        Task t = new Task(
            WhatId = opp.Id,
            Subject = 'Otra tarea',
            ActivityDate = Date.today().addDays(1)
        );
        insert t;

        Test.startTest();
        t.Status = getAnyClosedTaskStatus();
        update t;
        Test.stopTest();

        Opportunity refreshed = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Visita Concertada', refreshed.StageName);
    }
}