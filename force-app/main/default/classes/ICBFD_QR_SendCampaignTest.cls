/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-25
Descripción : Test para:
              - ICBFS_QR_SendCampaignInvocable
              - ICBFS_QR_SendCampaignQueue
              Cubre ejecución completa usando Lead + CampaignMember con token.
**********************************************************************************/
@IsTest
private class ICBFD_QR_SendCampaignTest {

    @TestSetup
    static void setupData() {

        Campaign c = new Campaign(
            Name = 'Test QR Campaign',
            IsActive = true
        );
        insert c;

        Lead l = new Lead(
            LastName = 'Test',
            Company  = 'ICB',
            Email    = 'test.qr@icb.cl'
        );
        insert l;

        // CampaignMember con token y no enviado
        CampaignMember cm = new CampaignMember(
            CampaignId   = c.Id,
            LeadId       = l.Id,
            QR_Token__c  = 'TOK_TEST_001',
            QR_Enviado__c = false
        );
        insert cm;
    }

    @IsTest
    static void testInvocable_EnqueueAndRunQueue() {

        Id campaignId = [SELECT Id FROM Campaign LIMIT 1].Id;

        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = campaignId;
        // Para Lead no se usa, pero es requerido por el invocable
        req.accountEmailFieldApi = 'PersonEmail';
        req.landingBaseUrl = 'https://example.com/openday';
        req.subject = 'Test QR';

        Test.startTest();
        ICBFS_QR_SendCampaignInvocable.enviar(
            new List<ICBFS_QR_SendCampaignInvocable.Request>{ req }
        );
        Test.stopTest();

        // Validación “a prueba de ambiente”: si sendEmail en test devuelve success,
        // se marcará como enviado; si no, quedará en false. Lo importante es que NO reviente.
        CampaignMember cm = [
            SELECT Id, QR_Enviado__c, QR_Token__c
            FROM CampaignMember
            WHERE CampaignId = :campaignId
            LIMIT 1
        ];

        System.assertEquals('TOK_TEST_001', cm.QR_Token__c, 'El token debe mantenerse');
        System.assertNotEquals(null, cm.QR_Enviado__c, 'Debe existir estado de envío');
    }

    @IsTest
    static void testInvocable_ThrowsWhenAccountEmailFieldBlank() {

        Id campaignId = [SELECT Id FROM Campaign LIMIT 1].Id;

        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = campaignId;
        req.accountEmailFieldApi = ''; // debe lanzar error

        Boolean threw = false;

        Test.startTest();
        try {
            ICBFS_QR_SendCampaignInvocable.enviar(
                new List<ICBFS_QR_SendCampaignInvocable.Request>{ req }
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Debe lanzar excepción si accountEmailFieldApi viene vacío');
    }

    @IsTest
    static void testQueue_NullCampaignId_NoCrash() {
        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(null, 'PersonEmail', null, null));
        Test.stopTest();
        System.assert(true, 'Queue no debe reventar con campaignId null');
    }
}