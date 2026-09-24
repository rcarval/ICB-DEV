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
            FirstName = 'Test',
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
        req.sendMode = ICBFS_QR_SendCampaignQueue.SEND_MODE_MASSIVE;

        Test.startTest();
        ICBFS_QR_SendCampaignInvocable.enviar(new List<ICBFS_QR_SendCampaignInvocable.Request>{ req });
        Test.stopTest();

        System.assert(true, 'Invocable and queue executed without error');
    }

    @IsTest
    static void testQueueable_WithMissingToken_DoesNotError() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];

        Lead l2 = new Lead(
            FirstName = 'Test',
            LastName = 'WithoutToken',
            Company = 'ICB',
            Email = 'withouttoken@icb.cl'
        );
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

        System.assert(true, 'Queueable executed without error for member without token');
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

        System.assertEquals(true, thrown, 'Must throw when accountEmailFieldApi is blank');
    }

    @IsTest
    static void testQueueable_WithToken_DoesNotError() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];

        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            c.Id,
            'PersonEmail',
            'https://example.com/openday',
            'Test Subject'
        ));
        Test.stopTest();

        System.assert(true, 'Queueable executed without error for member with token');
    }

    @IsTest
    static void testQueueable_ReminderMode_DoesNotSkipAlreadySent() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];
        CampaignMember cm = [SELECT Id FROM CampaignMember LIMIT 1];
        update new CampaignMember(Id = cm.Id, QR_Enviado__c = true);

        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            c.Id,
            'PersonEmail',
            'https://example.com/openday',
            'ICB Food Service OPENDAY',
            null,
            null,
            ICBFS_QR_SendCampaignQueue.SEND_MODE_REMINDER
        ));
        Test.stopTest();

        System.assert(true, 'Reminder mode executed without error for already sent member');
    }

    @IsTest
    static void testInvocable_ThrowsWhenCampaignIdBlank() {
        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = null;
        req.accountEmailFieldApi = 'PersonEmail';

        Boolean thrown = false;

        Test.startTest();
        try {
            ICBFS_QR_SendCampaignInvocable.enviar(new List<ICBFS_QR_SendCampaignInvocable.Request>{ req });
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Must throw when campaignId is null');
    }
}