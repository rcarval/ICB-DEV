/**
 * @description Tests para seidor_SetAgenteFromOwnerAction. Como el método no
 * hace DML ni SOQL (before-save, muta en memoria), no necesitamos insertar
 * MessagingSession real — evita la limitación ya documentada en
 * MessagingSessionTipificacionCtrl_Test (MessagingSession no es insertable
 * en test context sin un Messaging Channel configurado).
 */
@isTest
private class seidor_SetAgenteFromOwnerActionTest {

    private static Id fakeId(Schema.SObjectType sObjType) {
        String keyPrefix = sObjType.getDescribe().getKeyPrefix();
        Integer randomNum = Math.abs(Crypto.getRandomInteger());
        String seq = String.valueOf(randomNum).leftPad(12, '0');
        if (seq.length() > 12) {
            seq = seq.substring(seq.length() - 12);
        }
        return (Id) (keyPrefix + seq); // 3 (prefix) + 12 = 15 chars, formato válido
    }

    @isTest
    static void setAgenteFromOwner_ownerRealYAgenteVacio_debeSetear() {
        Id agenteRealId = fakeId(User.SObjectType);
        MessagingSession ms = new MessagingSession(
            Id = fakeId(MessagingSession.SObjectType),
            OwnerId = agenteRealId
        );

        Test.startTest();
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(new List<MessagingSession>{ ms });
        Test.stopTest();

        Assert.areEqual(agenteRealId, ms.Agente__c,
            'Agente__c debe quedar igual al nuevo OwnerId cuando es un usuario real');
    }

    @isTest
    static void setAgenteFromOwner_ownerRealYAgenteYaTeniaOtroAgente_debeActualizar() {
        // Cubre el caso de transferencia entre dos agentes humanos reales:
        // Agente__c debe reflejar siempre el ÚLTIMO dueño real, no congelarse
        // en el primero.
        Id agentePrevioId = fakeId(User.SObjectType);
        Id agenteNuevoId  = fakeId(User.SObjectType);

        MessagingSession ms = new MessagingSession(
            Id = fakeId(MessagingSession.SObjectType),
            OwnerId   = agenteNuevoId,
            Agente__c = agentePrevioId
        );

        Test.startTest();
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(new List<MessagingSession>{ ms });
        Test.stopTest();

        Assert.areEqual(agenteNuevoId, ms.Agente__c,
            'Agente__c debe actualizarse al nuevo dueño real, aunque ya tuviera un valor previo');
    }

    @isTest
    static void setAgenteFromOwner_ownerEsBot_noDebeTocarAgente() {
        Id agenteRealId = fakeId(User.SObjectType);
        MessagingSession ms = new MessagingSession(
            Id = fakeId(MessagingSession.SObjectType),
            OwnerId   = seidor_SetAgenteFromOwnerAction.BOT_OWNER_ID,
            Agente__c = agenteRealId // ya tenía un agente real capturado antes
        );

        Test.startTest();
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(new List<MessagingSession>{ ms });
        Test.stopTest();

        Assert.areEqual(agenteRealId, ms.Agente__c,
            'Agente__c NUNCA debe quedar con el Id del bot de cola, ni sobrescribirse cuando el bot recupera la sesión');
    }

    @isTest
    static void setAgenteFromOwner_ownerNull_noDebeFallar() {
        MessagingSession ms = new MessagingSession(
            Id = fakeId(MessagingSession.SObjectType),
            OwnerId = null
        );

        Test.startTest();
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(new List<MessagingSession>{ ms });
        Test.stopTest();

        Assert.isNull(ms.Agente__c, 'Sin OwnerId no debe setear Agente__c');
    }

    @isTest
    static void setAgenteFromOwner_listaVacia_noDebeFallar() {
        Test.startTest();
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(new List<MessagingSession>());
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(null);
        Test.stopTest();
        // Si no lanzó excepción, pasa. Cobertura de bulk-safety / null-safety.
    }

    @isTest
    static void setAgenteFromOwner_bulk200Registros_debeProcesarTodos() {
        // Antes-save flows pueden invocarse con lotes grandes (ej. carga masiva
        // de datos que dispara reasignación de OwnerId) — validar bulk-safety.
        List<MessagingSession> sessions = new List<MessagingSession>();
        Map<Id, Id> expectedAgenteById = new Map<Id, Id>();

        for (Integer i = 0; i < 200; i++) {
            Id sessionId = fakeId(MessagingSession.SObjectType);
            Id ownerId = Math.mod(i, 10) == 0
                ? seidor_SetAgenteFromOwnerAction.BOT_OWNER_ID
                : fakeId(User.SObjectType);

            sessions.add(new MessagingSession(Id = sessionId, OwnerId = ownerId));
            expectedAgenteById.put(sessionId, ownerId == seidor_SetAgenteFromOwnerAction.BOT_OWNER_ID ? null : ownerId);
        }

        Test.startTest();
        seidor_SetAgenteFromOwnerAction.setAgenteFromOwner(sessions);
        Test.stopTest();

        for (MessagingSession ms : sessions) {
            Assert.areEqual(expectedAgenteById.get(ms.Id), ms.Agente__c,
                'Registro ' + ms.Id + ' no cumplió la regla esperada en procesamiento bulk');
        }
    }
}