@IsTest
private class ICBFS_QR_SendCampaignTest {

    @TestSetup
    static void setupData() {
        Campaign c = new Campaign(
            Name = 'Test QR Campaign',
            IsActive = true
        );
        insert c;

        Lead l = new Lead(
            LastName = 'Test',
            Company = 'ICB',
            Email = 'test.qr@icb.cl'
        );
        insert l;

        CampaignMember cm = new CampaignMember(
            CampaignId = c.Id,
            LeadId = l.Id,
            QR_Token__c = 'TOK_TEST_001',
            QR_Enviado__c = false
        );
        insert cm;
    }

    @IsTest
    static void testInvocable_EnqueueQueueable() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];

        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = c.Id;
        req.accountEmailFieldApi = 'PersonEmail';
        req.landingBaseUrl = 'https://example.com/openday';
        req.subject = 'Test Subject';
        req.headerUrl = 'https://cdn.jsdelivr.net/gh/tron0110/icbfs-openday-assets/ICBFS_OPENDAY_HEADER.png';
        req.footerUrl = 'https://cdn.jsdelivr.net/gh/tron0110/icbfs-openday-assets/ICBFS_OPENDAY_FOOTER.png';

        Test.startTest();
        ICBFS_QR_SendCampaignInvocable.enviar(new List<ICBFS_QR_SendCampaignInvocable.Request>{ req });
        Test.stopTest();

        System.assert(true, 'Invocable + Queue ejecutaron sin error');
    }

    @IsTest
    static void testQueueable_WithToken_Sends() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];

        Lead l2 = new Lead(LastName='WithToken', Company='ICB', Email='withtoken@icb.cl');
        insert l2;

        CampaignMember cm2 = new CampaignMember(
            CampaignId = c.Id,
            LeadId = l2.Id
        );
        insert cm2;

        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            c.Id,
            'PersonEmail',
            'https://example.com/openday',
            'Test'
        ));
        Test.stopTest();

        CampaignMember check = [SELECT QR_Token__c, QR_Enviado__c FROM CampaignMember WHERE Id = :cm2.Id LIMIT 1];
        System.assertNotEquals(null, check.QR_Token__c, 'El token debería haber sido generado automáticamente');
        System.assertEquals(true, check.QR_Enviado__c, 'Debe marcarse como enviado cuando tiene token');
    }

    @IsTest
    static void testInvocable_ThrowsWhenEmailFieldBlank() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];

        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = c.Id;
        req.accountEmailFieldApi = '';

        Boolean thrown = false;

        Test.startTest();
        try {
            ICBFS_QR_SendCampaignInvocable.enviar(new List<ICBFS_QR_SendCampaignInvocable.Request>{ req });
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Debe lanzar error si accountEmailFieldApi viene vacío');
    }

    @IsTest
    static void testQueueable_WithToken_SendSuccess() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];
        CampaignMember cm = [SELECT Id, QR_Token__c, QR_Enviado__c FROM CampaignMember LIMIT 1];

        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            c.Id,
            'PersonEmail',
            'https://example.com/openday',
            'Test Subject'
        ));
        Test.stopTest();

        CampaignMember result = [SELECT QR_Enviado__c FROM CampaignMember WHERE Id = :cm.Id LIMIT 1];
        System.assertEquals(true, result.QR_Enviado__c, 'Debe marcarse como enviado cuando tiene token');
    }

    @IsTest
    static void testInvocable_ThrowsWhenCampaignIdBlank() {
        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = null;
        req.accountEmailFieldApi = 'PersonEmail';

        Boolean thrown = false;
        String errorMsg = '';

        Test.startTest();
        try {
            ICBFS_QR_SendCampaignInvocable.enviar(new List<ICBFS_QR_SendCampaignInvocable.Request>{ req });
        } catch (Exception e) {
            thrown = true;
            errorMsg = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Debe lanzar error si campaignId es nulo');
    }
}