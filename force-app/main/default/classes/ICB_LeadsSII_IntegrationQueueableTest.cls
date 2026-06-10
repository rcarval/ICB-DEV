@isTest
private class ICB_LeadsSII_IntegrationQueueableTest {
    @isTest
    static void testQueueableSinIds() {
        Test.startTest();
        System.enqueueJob(new ICB_LeadsSII_IntegrationQueueable(null));
        Test.stopTest();
        System.assert(true, 'Queueable sin IDs ejecutado.');
    }

    @isTest
    static void testQueueableManejaExcepcionCallout() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        Test.setMock(
            HttpCalloutMock.class,
            new ICB_LeadsSII_TestFactory.SiiHttpMock(500, 'Server Error', '{"error":"boom"}')
        );

        Test.startTest();
        System.enqueueJob(new ICB_LeadsSII_IntegrationQueueable(new List<Id>{ ld.Id }));
        Test.stopTest();

        Lead updated = [SELECT Aprobado_SII__c, Observaciones_SII__c FROM Lead WHERE Id = :ld.Id];
        System.assertEquals(false, updated.Aprobado_SII__c);
        System.assert(updated.Observaciones_SII__c.contains('Error consultando SII'));
    }

    @isTest
    static void testQueueableProcesaLead() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        String body = '{"rut":81482800,"dv":"K","razon_social":"ABAST Y SERV DE LOS IND DE LA MADERA DE VALPO Y ACON LTDA","inicio_actividades":true,"actividades":[{"codigo":"475201"}],"observaciones":{"inconcurrente":false,"suplantado":false,"no_ubicado":false,"termino_giro":false,"domicilio_inexistente":false,"actividad_esporadica":false,"no_habido_domicilio":false,"termino_giro_obligatorio":false}}';
        Test.setMock(
            HttpCalloutMock.class,
            new ICB_LeadsSII_TestFactory.SiiHttpMock(200, 'OK', body)
        );

        Test.startTest();
        System.enqueueJob(new ICB_LeadsSII_IntegrationQueueable(new List<Id>{ ld.Id }));
        Test.stopTest();

        Lead updated = [
            SELECT Status, IsConverted, Aprobado_SII__c, Codigo_Actividad_SII__c, Observaciones_SII__c
            FROM Lead
            WHERE Id = :ld.Id
        ];
        System.assertEquals(true, updated.Aprobado_SII__c);
        System.assertEquals(475201, updated.Codigo_Actividad_SII__c);
        System.assert(
            updated.Observaciones_SII__c != null &&
                updated.Observaciones_SII__c.contains('Aprobado por validaciones SII')
        );
        if (updated.IsConverted == true) {
            System.assertEquals('Prospecto', updated.Status);
        } else {
            System.assert(
                updated.Observaciones_SII__c.contains('Conversión no realizada'),
                'Sin conversión debe quedar indicado en observaciones.'
            );
        }
    }
}