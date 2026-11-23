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

    @IsTest
    static void sendsUsingUrlsConfiguredOnCampaign() {
        Campaign campaign = new Campaign(
            Name = 'UT OpenDay Configurable',
            IsActive = true,
            ID_Formulario_WEB__c = 'openday-futuro-sin-ruta-hardcodeada',
            OpenDay_Header_URL__c = 'https://example.com/header.png',
            OpenDay_Footer_URL__c = 'https://example.com/footer.png',
            OpenDay_Maps_URL__c = 'https://maps.example.com/openday'
        );
        insert campaign;

        Lead lead = new Lead(
            FirstName = 'Configurable',
            LastName = 'Member',
            Company = 'ICB',
            Email = 'configurable.member@icb.cl'
        );
        insert lead;

        Test.startTest();
        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            LeadId = lead.Id,
            QR_Token__c = 'TOK_CONFIG_001',
            QR_Enviado__c = false
        );
        insert cm;
        Test.stopTest();

        CampaignMember after = [
            SELECT QR_Enviado__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals(true, after.QR_Enviado__c,
            'A campaign configured with URLs must work without a hardcoded city route.');
    }

    @IsTest
    static void keepsTemucoLegacyRouteDuringMigration() {
        Campaign campaign = new Campaign(
            Name = 'UT OpenDay Temuco Legacy',
            IsActive = true,
            ID_Formulario_WEB__c = 'Temuco09092026'
        );
        insert campaign;

        Lead lead = new Lead(
            FirstName = 'Temuco',
            LastName = 'Legacy',
            Company = 'ICB',
            Email = 'temuco.legacy@icb.cl'
        );
        insert lead;

        Test.startTest();
        CampaignMember cm = new CampaignMember(
            CampaignId = campaign.Id,
            LeadId = lead.Id,
            QR_Token__c = 'TOK_TEMUCO_LEGACY_001',
            QR_Enviado__c = false
        );
        insert cm;
        Test.stopTest();

        CampaignMember after = [
            SELECT QR_Enviado__c
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        System.assertEquals(true, after.QR_Enviado__c,
            'Temuco must continue working while Campaign URL fields are being populated.');
    }
}