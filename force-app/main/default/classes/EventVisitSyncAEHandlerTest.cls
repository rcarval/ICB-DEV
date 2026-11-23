@IsTest
private class EventVisitSyncAEHandlerTest {

    private static Opportunity createOpportunity(String rtDeveloperName) {
        Account acc = new Account(Name = 'ACC ' + rtDeveloperName + ' ' + System.now().getTime());
        insert acc;

        RecordType rt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND DeveloperName = :rtDeveloperName
            LIMIT 1
        ];

        Opportunity opp = new Opportunity(
            Name = 'OPP ' + rtDeveloperName + ' ' + System.now().getTime(),
            StageName = 'Cliente Contactado',
            CloseDate = Date.today().addDays(15),
            AccountId = acc.Id,
            RecordTypeId = rt.Id,
            Tiene_Visita_Agendada__c = false
        );
        insert opp;
        return opp;
    }

    private static Opportunity createNonAutoOpportunity() {
        Account acc = new Account(Name = 'ACC NON AUTO ' + System.now().getTime());
        insert acc;

        List<RecordType> nonAutoRecordTypes = [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND DeveloperName != 'Auto_Enrolamiento'
            LIMIT 1
        ];

        System.assert(!nonAutoRecordTypes.isEmpty(), 'Se requiere al menos un RecordType distinto de Auto_Enrolamiento para esta prueba.');

        Opportunity opp = new Opportunity(
            Name = 'OPP NON AUTO ' + System.now().getTime(),
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(15),
            AccountId = acc.Id,
            RecordTypeId = nonAutoRecordTypes[0].Id,
            Tiene_Visita_Agendada__c = false
        );
        insert opp;
        return opp;
    }

    private static Event createEvent(Id whatId, String estadoVisita) {
        Event ev = new Event(
            Subject = 'Visita test',
            StartDateTime = System.now().addHours(1),
            EndDateTime = System.now().addHours(2),
            WhatId = whatId,
            Estado_de_la_visita__c = estadoVisita
        );
        insert ev;
        return ev;
    }

    private static Event createEvent(Id whatId, String estadoVisita, String description, String subject) {
        Event ev = new Event(
            Subject = subject,
            Description = description,
            StartDateTime = System.now().addHours(1),
            EndDateTime = System.now().addHours(2),
            WhatId = whatId,
            Estado_de_la_visita__c = estadoVisita
        );
        insert ev;
        return ev;
    }

    private static String getAnyNonProgramadaStatus() {
        for (Schema.PicklistEntry pe : Event.Estado_de_la_visita__c.getDescribe().getPicklistValues()) {
            if (pe.isActive() && pe.getValue() != 'Programada') {
                return pe.getValue();
            }
        }
        System.assert(false, 'Se requiere al menos un valor activo distinto de Programada en Estado_de_la_visita__c');
        return null;
    }

    @IsTest
    static void shouldSetFlagTrueOnInsertForAutoEnrolamiento() {
        Opportunity opp = createOpportunity('Auto_Enrolamiento');

        Test.startTest();
        createEvent(opp.Id, 'Programada');
        Test.stopTest();

        Opportunity refreshed = [SELECT Tiene_Visita_Agendada__c, StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, refreshed.Tiene_Visita_Agendada__c);
        System.assertEquals('Visita Agendada', refreshed.StageName);
    }

    @IsTest
    static void shouldSetFlagFalseOnStatusChangeAndDelete() {
        Opportunity opp = createOpportunity('Auto_Enrolamiento');
        Event ev = createEvent(opp.Id, 'Programada');

        ev.Estado_de_la_visita__c = getAnyNonProgramadaStatus();

        update ev;

        Opportunity afterStatusChange = [SELECT Tiene_Visita_Agendada__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, afterStatusChange.Tiene_Visita_Agendada__c);

        ev.Estado_de_la_visita__c = 'Programada';
        update ev;

        update new Opportunity(Id = opp.Id, StageName = 'Visita Agendada');

        Test.startTest();
        delete ev;
        Test.stopTest();

        Opportunity afterDelete = [SELECT Tiene_Visita_Agendada__c, StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, afterDelete.Tiene_Visita_Agendada__c);
        System.assertEquals('Cliente Contactado', afterDelete.StageName);
    }

    @IsTest
    static void shouldSetFlagTrueOnUndelete() {
        Opportunity opp = createOpportunity('Auto_Enrolamiento');
        Event ev = createEvent(opp.Id, 'Programada');
        delete ev;

        Test.startTest();
        undelete ev;
        Test.stopTest();

        Opportunity refreshed = [SELECT Tiene_Visita_Agendada__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, refreshed.Tiene_Visita_Agendada__c);
    }

    @IsTest
    static void shouldNotAffectOtherOpportunityRecordTypes() {
        Opportunity opp = createNonAutoOpportunity();

        Test.startTest();
        createEvent(opp.Id, 'Programada');
        Test.stopTest();

        Opportunity refreshed = [SELECT Tiene_Visita_Agendada__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, refreshed.Tiene_Visita_Agendada__c);
    }

    @IsTest
    static void shouldAutoSetConcretadaAndDetallesFromEvent() {
        Opportunity opp = createOpportunity('Auto_Enrolamiento');

        Test.startTest();
        createEvent(opp.Id, 'Concretada', 'Detalle desde evento', 'Visita concretada');
        Test.stopTest();

        Opportunity refreshed = [
            SELECT Visita_Concretada__c, Detalles__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        System.assertEquals(true, refreshed.Visita_Concretada__c);
        System.assertEquals('Detalle desde evento', refreshed.Detalles__c);
    }
}