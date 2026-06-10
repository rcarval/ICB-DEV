@isTest
private class ICB_LeadsSII_ResponseHandlerTest {
    @isTest
    static void testApplySIIResult_Aprobado() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto = ICB_LeadsSII_TestFactory.buildApprovedResponse();

        Test.startTest();
        ICB_LeadsSII_ResponseHandler.applySIIResult(ld, dto, ld.RUT__c);
        Test.stopTest();

        Lead updated = [
            SELECT Status, IsConverted, ConvertedAccountId, Aprobado_SII__c, Observaciones_SII__c, Codigo_Actividad_SII__c
            FROM Lead
            WHERE Id = :ld.Id
        ];
        System.assertEquals(true, updated.Aprobado_SII__c, 'SII debe marcar aprobación.');
        System.assertEquals(475201, updated.Codigo_Actividad_SII__c);
        System.assert(
            updated.Observaciones_SII__c != null &&
                updated.Observaciones_SII__c.contains('Aprobado por validaciones SII'),
            'Debe persistir el mensaje base de aprobación SII.'
        );
        // Database.convertLead puede fallar por reglas de validación de la org; el handler documenta el caso.
        if (updated.IsConverted == true) {
            System.assertNotEquals(null, updated.ConvertedAccountId);
            System.assertEquals('Prospecto', updated.Status);
        } else {
            System.assert(
                updated.Observaciones_SII__c.contains('Conversión no realizada'),
                'Sin conversión debe quedar indicado en observaciones.'
            );
        }
    }

    @isTest
    static void testApplySIIResult_Rechazado() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto = ICB_LeadsSII_TestFactory.buildRejectedResponse();

        Test.startTest();
        ICB_LeadsSII_ResponseHandler.applySIIResult(ld, dto, ld.RUT__c);
        Test.stopTest();

        Lead updated = [
            SELECT Aprobado_SII__c, Observaciones_SII__c, Codigo_Actividad_SII__c
            FROM Lead
            WHERE Id = :ld.Id
        ];
        System.assertEquals(false, updated.Aprobado_SII__c);
        System.assert(updated.Observaciones_SII__c.contains('coincidencia insuficiente'));
        System.assert(updated.Observaciones_SII__c.contains('Inconcurrente'));
        System.assertEquals(620200, updated.Codigo_Actividad_SII__c);
    }

    @isTest
    static void testApplySIIResult_SinInicioActividades() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        ld.Company = 'CALMA & CAFE SPA';
        update ld;

        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto = ICB_LeadsSII_TestFactory.buildSinInicioActividadesResponse();

        Test.startTest();
        ICB_LeadsSII_ResponseHandler.applySIIResult(ld, dto, ld.RUT__c);
        Test.stopTest();

        Lead updated = [
            SELECT Aprobado_SII__c, Observaciones_SII__c, IsConverted
            FROM Lead
            WHERE Id = :ld.Id
        ];
        System.assertEquals(false, updated.Aprobado_SII__c);
        System.assert(updated.Observaciones_SII__c.contains('no tiene inicio de actividades'));
        System.assert(updated.Observaciones_SII__c.contains('CALMA & CAFE SPA'));
        System.assertEquals(false, updated.IsConverted);
    }

    @isTest
    static void testApplyException() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();

        Test.startTest();
        ICB_LeadsSII_ResponseHandler.applyException(
            ld.Id,
            new ICB_CalloutAPI_SII.ICB_CalloutSIIException('Error de prueba'),
            ld.RUT__c
        );
        Test.stopTest();

        Lead updated = [SELECT Aprobado_SII__c, Observaciones_SII__c FROM Lead WHERE Id = :ld.Id];
        System.assertEquals(false, updated.Aprobado_SII__c);
        System.assert(updated.Observaciones_SII__c.contains('Error consultando SII'));
    }
}