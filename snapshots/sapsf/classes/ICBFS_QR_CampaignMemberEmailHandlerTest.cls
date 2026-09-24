@IsTest
private class ICBFS_QR_CampaignMemberEmailHandlerTest {

    @IsTest
    static void sendsWhenCampaignMemberIsAddedManually() {
        Campaign campaign = new Campaign(
            Name = 'UT OpenDay Manual',
            IsActive = true,
            ID_Formulario_WEB__c = 'concepcion24062026'
        );
        insert campaign;

        Lead lead = new Lead(
            FirstName = 'Manual',
            LastName = 'Member',
            Company = 'ICB',
            Email = 'manual.member@icb.cl'
        );
        insert lead;

        Test.startTest();
        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            LeadId = lead.Id,
            QR_Token__c = 'TOK_MANUAL_001',
            QR_Enviado__c = false
        );
        insert cm;
        Test.stopTest();

        CampaignMember after = [
            SELECT QR_Enviado__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals(true, after.QR_Enviado__c, 'Manual member with token must be sent.');
    }

    @IsTest
    static void skipsUnsupportedCampaignFormKey() {
        Campaign campaign = new Campaign(
            Name = 'UT Unsupported Manual',
            IsActive = true,
            ID_Formulario_WEB__c = 'otra-campana'
        );
        insert campaign;

        Lead lead = new Lead(
            FirstName = 'No',
            LastName = 'Route',
            Company = 'ICB',
            Email = 'no.route@icb.cl'
        );
        insert lead;

        Test.startTest();
        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            LeadId = lead.Id,
            QR_Token__c = 'TOK_NO_ROUTE_001',
            QR_Enviado__c = false
        );
        insert cm;
        Test.stopTest();

        CampaignMember after = [
            SELECT QR_Enviado__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals(false, after.QR_Enviado__c, 'Unsupported campaigns must not auto-send.');
    }
}