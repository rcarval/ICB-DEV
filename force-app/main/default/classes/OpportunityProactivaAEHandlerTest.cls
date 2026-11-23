@IsTest
private class OpportunityProactivaAEHandlerTest {

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
        Account acc = new Account(Name = 'ACC OPP PROACTIVA ' + System.now().getTime());
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'OPP PROACTIVA ' + System.now().getTime(),
            AccountId = acc.Id,
            RecordTypeId = rtId,
            StageName = stageName,
            CloseDate = Date.today().addDays(10),
            Amount = 1000
        );
        insert opp;
        return opp;
    }

    @IsTest
    static void shouldNotCreateTaskWhenMovesToVisitaConcertada() {
        Id autoRtId = getOppRtId('Auto_Enrolamiento');
        Opportunity opp = createOpp(autoRtId, 'Visita Agendada');

        Test.startTest();
        opp.Visita_Concretada__c = true;
        opp.Detalles__c = 'Resumen para validar etapa';
        opp.Valor_oportunidad__c = 1000;
        opp.StageName = 'Visita Concertada';
        update opp;
        Test.stopTest();

        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :opp.Id
              AND Subject = 'Enviar propuesta al cliente'
        ];
        System.assertEquals(0, taskCount, 'No debe crear la tarea de propuesta.');
    }

    @IsTest
    static void shouldAllowPropuestaEnviadaWithoutCompletedTask() {
        Id autoRtId = getOppRtId('Auto_Enrolamiento');
        Opportunity opp = createOpp(autoRtId, 'Visita Concertada');

        Test.startTest();
        opp.StageName = 'Propuesta Enviada';
        update opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Propuesta Enviada', refreshed.StageName);
    }

    @IsTest
    static void shouldAllowCierreGanadaWithoutCompletedTask() {
        Id autoRtId = getOppRtId('Auto_Enrolamiento');
        Opportunity opp = createOpp(autoRtId, 'Propuesta Enviada');

        Test.startTest();
        opp.StageName = 'Cierre Ganada';
        update opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Cierre Ganada', refreshed.StageName);
    }
}