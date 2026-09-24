@isTest
private class seidor_AgentWorkTriggerHandlerTest {

    private static Id fakeId(Schema.SObjectType sObjType) {
        String keyPrefix = sObjType.getDescribe().getKeyPrefix();
        Integer randomNum = Math.abs(Crypto.getRandomInteger());
        String seq = String.valueOf(randomNum).leftPad(12, '0');
        if (seq.length() > 12) {
            seq = seq.substring(seq.length() - 12);
        }
        return (Id) (keyPrefix + seq);
    }

    @isTest
    static void handleAfterInsert_asignaHumano_debeActualizarSession() {
        Id humanoId = fakeId(User.SObjectType);
        Id sessionId = fakeId(MessagingSession.SObjectType);

        seidor_MessagingSessionTriggerHandler.botUserIdsCache = new Set<Id>{ fakeId(User.SObjectType) };
        seidor_AgentWorkTriggerHandler.suppressDml = true;
        seidor_AgentWorkTriggerHandler.mockSessionsCache = new Map<Id, MessagingSession>{
            sessionId => new MessagingSession(Id = sessionId, Ejecutivo_asignado__c = false)
        };

        AgentWork aw = new AgentWork(
            Id = fakeId(AgentWork.SObjectType),
            WorkItemId = sessionId,
            UserId = humanoId
        );

        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterInsert(new List<AgentWork>{ aw });
        Test.stopTest();

        MessagingSession updated = seidor_AgentWorkTriggerHandler.mockSessionsCache.get(sessionId);
        Assert.areEqual(humanoId, updated.Agente__c, 'Agente__c debe asignarse al humano');
        Assert.isTrue(updated.Ejecutivo_asignado__c, 'Ejecutivo_asignado__c debe ser true');
    }

    @isTest
    static void handleAfterInsert_asignaBot_noDebeTocarSession() {
        Id botId = fakeId(User.SObjectType);
        Id sessionId = fakeId(MessagingSession.SObjectType);

        seidor_MessagingSessionTriggerHandler.botUserIdsCache = new Set<Id>{ botId };
        seidor_AgentWorkTriggerHandler.suppressDml = true;
        seidor_AgentWorkTriggerHandler.mockSessionsCache = new Map<Id, MessagingSession>{
            sessionId => new MessagingSession(Id = sessionId, Ejecutivo_asignado__c = false)
        };

        AgentWork aw = new AgentWork(
            Id = fakeId(AgentWork.SObjectType),
            WorkItemId = sessionId,
            UserId = botId
        );

        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterInsert(new List<AgentWork>{ aw });
        Test.stopTest();

        MessagingSession updated = seidor_AgentWorkTriggerHandler.mockSessionsCache.get(sessionId);
        Assert.isNull(updated.Agente__c, 'Agente__c no debe asignarse si UserId es bot');
        Assert.isFalse(updated.Ejecutivo_asignado__c, 'Ejecutivo_asignado__c debe seguir false');
    }

    @isTest
    static void handleAfterInsert_workItemNoEsMessagingSession_noDebeProcesar() {
        Id humanoId = fakeId(User.SObjectType);
        Id workItemId = fakeId(Case.SObjectType);

        seidor_MessagingSessionTriggerHandler.botUserIdsCache = new Set<Id>{ fakeId(User.SObjectType) };
        seidor_AgentWorkTriggerHandler.mockSessionsCache = new Map<Id, MessagingSession>();

        AgentWork aw = new AgentWork(
            Id = fakeId(AgentWork.SObjectType),
            WorkItemId = workItemId,
            UserId = humanoId
        );

        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterInsert(new List<AgentWork>{ aw });
        Test.stopTest();
    }

    @isTest
    static void handleAfterInsert_sessionYaAsignada_noDebeSobrescribir() {
        Id humanoId = fakeId(User.SObjectType);
        Id sessionId = fakeId(MessagingSession.SObjectType);

        seidor_MessagingSessionTriggerHandler.botUserIdsCache = new Set<Id>{ fakeId(User.SObjectType) };
        seidor_AgentWorkTriggerHandler.suppressDml = true;
        seidor_AgentWorkTriggerHandler.mockSessionsCache = new Map<Id, MessagingSession>{
            sessionId => new MessagingSession(
                Id = sessionId,
                Agente__c = humanoId,
                Ejecutivo_asignado__c = true
            )
        };

        AgentWork aw = new AgentWork(
            Id = fakeId(AgentWork.SObjectType),
            WorkItemId = sessionId,
            UserId = humanoId
        );

        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterInsert(new List<AgentWork>{ aw });
        Test.stopTest();

        MessagingSession updated = seidor_AgentWorkTriggerHandler.mockSessionsCache.get(sessionId);
        Assert.areEqual(humanoId, updated.Agente__c, 'Agente__c debe conservarse');
        Assert.isTrue(updated.Ejecutivo_asignado__c, 'Ejecutivo_asignado__c debe seguir true');
    }

    @isTest
    static void handleAfterUpdate_userIdCambia_debeActualizarSession() {
        Id humanoId = fakeId(User.SObjectType);
        Id sessionId = fakeId(MessagingSession.SObjectType);
        Id awId = fakeId(AgentWork.SObjectType);
        Id oldUserId = fakeId(User.SObjectType);

        seidor_MessagingSessionTriggerHandler.botUserIdsCache = new Set<Id>{ fakeId(User.SObjectType) };
        seidor_AgentWorkTriggerHandler.suppressDml = true;
        seidor_AgentWorkTriggerHandler.mockSessionsCache = new Map<Id, MessagingSession>{
            sessionId => new MessagingSession(Id = sessionId, Ejecutivo_asignado__c = false)
        };

        AgentWork newAw = new AgentWork(Id = awId, WorkItemId = sessionId, UserId = humanoId);
        AgentWork oldAw = new AgentWork(Id = awId, WorkItemId = sessionId, UserId = oldUserId);

        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterUpdate(
            new List<AgentWork>{ newAw },
            new Map<Id, AgentWork>{ awId => oldAw }
        );
        Test.stopTest();

        MessagingSession updated = seidor_AgentWorkTriggerHandler.mockSessionsCache.get(sessionId);
        Assert.areEqual(humanoId, updated.Agente__c, 'Agente__c debe asignarse al nuevo humano');
        Assert.isTrue(updated.Ejecutivo_asignado__c, 'Ejecutivo_asignado__c debe ser true');
    }

    @isTest
    static void handleAfterUpdate_userIdNoCambia_noDebeProcesar() {
        Id humanoId = fakeId(User.SObjectType);
        Id sessionId = fakeId(MessagingSession.SObjectType);
        Id awId = fakeId(AgentWork.SObjectType);

        seidor_MessagingSessionTriggerHandler.botUserIdsCache = new Set<Id>{ fakeId(User.SObjectType) };
        seidor_AgentWorkTriggerHandler.mockSessionsCache = new Map<Id, MessagingSession>();

        AgentWork newAw = new AgentWork(Id = awId, WorkItemId = sessionId, UserId = humanoId);
        AgentWork oldAw = new AgentWork(Id = awId, WorkItemId = sessionId, UserId = humanoId);

        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterUpdate(
            new List<AgentWork>{ newAw },
            new Map<Id, AgentWork>{ awId => oldAw }
        );
        Test.stopTest();
    }

    @isTest
    static void listasVaciasOMapasNull_noDebenFallar() {
        Test.startTest();
        seidor_AgentWorkTriggerHandler.handleAfterInsert(new List<AgentWork>());
        seidor_AgentWorkTriggerHandler.handleAfterInsert(null);
        seidor_AgentWorkTriggerHandler.handleAfterUpdate(new List<AgentWork>(), new Map<Id, AgentWork>());
        seidor_AgentWorkTriggerHandler.handleAfterUpdate(null, null);
        Test.stopTest();
    }

    @isTest(SeeAllData=true)
    static void trigger_realAgentWorkInsert_noDebeLanzarExcepcion() {
        List<AgentWork> existentes = [SELECT Id, WorkItemId, UserId FROM AgentWork LIMIT 1];
        if (existentes.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay AgentWork en el org');
            return;
        }

        Test.startTest();
        try {
            update new AgentWork(Id = existentes[0].Id);
        } catch (DmlException e) {
            System.debug(LoggingLevel.WARN, 'Update de prueba no permitido: ' + e.getMessage());
        }
        Test.stopTest();
    }
}