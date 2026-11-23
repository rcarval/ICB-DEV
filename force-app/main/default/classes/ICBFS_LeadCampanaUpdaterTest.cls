@IsTest
private class ICBFS_LeadCampanaUpdaterTest {

    @IsTest
    static void asignarCampana_noFallaSiCampaignIdNoExiste() {
        Lead leadRecord = new Lead(
            FirstName = 'Test',
            LastName = 'LeadCampanaUpdater',
            Company = 'ACME',
            Email = 'leadcampanaupdater@test.com'
        );
        insert leadRecord;

        Campaign campaignRecord = new Campaign(
            Name = 'UT LeadCampanaUpdater',
            IsActive = true
        );
        insert campaignRecord;

        ICBFS_LeadCampanaUpdater.Input inputRecord = new ICBFS_LeadCampanaUpdater.Input();
        inputRecord.leadId = leadRecord.Id;
        inputRecord.campaignId = campaignRecord.Id;

        Test.startTest();
        ICBFS_LeadCampanaUpdater.asignarCampana(new List<ICBFS_LeadCampanaUpdater.Input>{ inputRecord });
        Test.stopTest();

        Lead afterLead = [SELECT Id FROM Lead WHERE Id = :leadRecord.Id];
        System.assertEquals(leadRecord.Id, afterLead.Id, 'El lead debe seguir disponible tras ejecutar la accion.');
    }
}