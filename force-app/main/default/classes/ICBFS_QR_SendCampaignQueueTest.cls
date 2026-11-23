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
            FirstName = 'Test',
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

    @IsTest
    static void account_email_uses_complete_fallback_chain() {
        Id branchId = '001000000000001AAA';
        CampaignMember cm = new CampaignMember(AccountId = branchId);
        Account parentAccount = new Account();
        Account branch = new Account();
        Map<Id, Account> accounts = new Map<Id, Account>{ branchId => branch };

        branch.put('Email__c', 'direct@example.com');
        branch.put('Datos_de_Contacto_Principal__c', 'branch@example.com');
        parentAccount.put('Email__c', 'parent@example.com');
        parentAccount.put('Datos_de_Contacto_Principal__c', 'parent-data@example.com');
        branch.putSObject('Parent', parentAccount);

        System.assertEquals('direct@example.com',
            ICBFS_QR_SendCampaignQueue.resolveEmail(cm, accounts, 'Email__c'));

        branch.put('Email__c', null);
        System.assertEquals('branch@example.com',
            ICBFS_QR_SendCampaignQueue.resolveEmail(cm, accounts, 'Email__c'));

        branch.put('Datos_de_Contacto_Principal__c', null);
        System.assertEquals('parent@example.com',
            ICBFS_QR_SendCampaignQueue.resolveEmail(cm, accounts, 'Email__c'));

        parentAccount.put('Email__c', null);
        System.assertEquals('parent-data@example.com',
            ICBFS_QR_SendCampaignQueue.resolveEmail(cm, accounts, 'Email__c'));
    }

    @IsTest
    static void invalid_email_is_skipped_and_next_valid_fallback_is_used() {
        System.assertEquals('valid@example.com',
            ICBFS_QR_SendCampaignQueue.firstValidEmail(
                new List<Object>{ null, '', 'OUTLOOKCOM', ' valid@example.com ' }
            ));
        System.assertEquals(null,
            ICBFS_QR_SendCampaignQueue.firstValidEmail(
                new List<Object>{ 'missing-at.example.com', 'missing-dot@example' }
            ));
    }
}