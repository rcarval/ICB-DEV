/**
 * @Description Cobertura para ICBFS_QR_SendCampaignInvocable y ICBFS_QR_SendCampaignQueue.
 */
@IsTest
private class ICBFS_QR_SendCampaignQueueTest {

    @IsTest
    static void invocable_enqueues_and_sends() {
        Campaign c = new Campaign(Name = 'Test Campaign', IsActive = true);
        insert c;

        Lead l = new Lead(
            LastName = 'Test Lead',
            Company  = 'ACME',
            Email    = 'lead@test.com'
        );
        insert l;

        CampaignMember cm = new CampaignMember(
            CampaignId  = c.Id,
            LeadId      = l.Id,
            Status      = 'Sent',
            QR_Token__c = 'tok-123'
        );
        insert cm;

        ICBFS_QR_SendCampaignInvocable.Request req = new ICBFS_QR_SendCampaignInvocable.Request();
        req.campaignId = c.Id;
        req.accountEmailFieldApi = 'Email__c'; // no se usa para Lead
        req.landingBaseUrl = 'https://example.com';
        req.subject = 'Test Subject';

        Test.startTest();
        ICBFS_QR_SendCampaignInvocable.enviar(new List<ICBFS_QR_SendCampaignInvocable.Request>{ req });
        Test.stopTest(); // ejecuta el queueable

        Integer jobs = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ICBFS_QR_SendCampaignQueue'];
        System.assert(jobs > 0, 'Se debió ejecutar el Queueable de envío de QR');
    }
}