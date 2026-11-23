@IsTest
private class ICBFS_CampaignMemberCanalHandlerTest {

    @IsTest
    static void setsManualForAccountOnlyMemberWithoutCanal() {
        Campaign campaign = new Campaign(Name = 'UT Manual Account', IsActive = true);
        insert campaign;

        Account account = new Account(Name = 'Cuenta Manual');
        insert account;

        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            AccountId = account.Id,
            Status = 'Sent'
        );
        insert cm;

        CampaignMember inserted = [
            SELECT Canal__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals('Manual', inserted.Canal__c);
    }

    @IsTest
    static void setsManualForContactMemberWithoutCanal() {
        Campaign campaign = new Campaign(Name = 'UT Manual Contact', IsActive = true);
        insert campaign;

        Account account = new Account(Name = 'Cuenta Contacto');
        insert account;

        Contact contact = new Contact(
            LastName = 'Contacto Manual',
            Email = 'contacto.manual@test.com',
            AccountId = account.Id
        );
        insert contact;

        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            ContactId = contact.Id,
            Status = 'Sent'
        );
        insert cm;

        CampaignMember inserted = [
            SELECT Canal__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals('Manual', inserted.Canal__c);
    }

    @IsTest
    static void keepsExistingCanalForLeadMember() {
        Campaign campaign = new Campaign(Name = 'UT Lead Canal', IsActive = true);
        insert campaign;

        Lead lead = new Lead(
            FirstName = 'Lead',
            LastName = 'Canal',
            Company = 'ICB',
            Email = 'lead.canal@test.com'
        );
        insert lead;

        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            LeadId = lead.Id,
            Canal__c = 'Meta',
            Status = 'Sent'
        );
        insert cm;

        CampaignMember inserted = [
            SELECT Canal__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals('Meta', inserted.Canal__c);
    }
}