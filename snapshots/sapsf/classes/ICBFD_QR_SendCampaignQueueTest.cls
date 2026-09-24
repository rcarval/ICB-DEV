/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-25
Descripción : Test class para ICBFS_QR_SendCampaignQueue.
              - Caso OK: Lead con email + token => marca QR_Enviado__c = true
              - Caso NO-ENVÍO estable: Lead sin email (aunque token exista) => NO marca QR_Enviado__c
              - Caso defaults: subject/landingBaseUrl vacíos (cubre ramas para pasar 75%)
**********************************************************************************/
@IsTest
private class ICBFD_QR_SendCampaignQueueTest {

    @IsTest
    static void testQueueable_Token_SendsAndMarksSent() {

        Campaign camp = new Campaign(Name = 'UT - OpenDay QR', IsActive = true);
        insert camp;

        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'ICBFS Test',
            Email = 'salesforce.acux+ut@gmail.com'
        );
        insert l;

        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            LeadId = l.Id,
            Status = getAnyCampaignMemberStatus(),
            QR_Token__c = 'TOKEN_UT_001',
            QR_Enviado__c = false
        );
        insert cm;

        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            camp.Id,
            'Email__c', // no se usa en estos tests (no hay Accounts)
            'https://energy-saas-7178.my.site.com/openday',
            'UT Subject'
        ));
        Test.stopTest();

        CampaignMember after = [
            SELECT Id, QR_Enviado__c, QR_Token__c
            FROM CampaignMember
            WHERE Id = :cm.Id
            LIMIT 1
        ];

        System.assertEquals(true, after.QR_Enviado__c, 'Con token y email, debería marcarse como enviado.');
        System.assertNotEquals(null, after.QR_Token__c, 'Token debería existir.');
    }

    @IsTest
    static void testQueueable_NoEmail_DoesNotMarkSent() {

        Campaign camp = new Campaign(Name = 'UT - OpenDay QR No Email', IsActive = true);
        insert camp;

        // Lead SIN email (condición estable que el Queue respeta)
        Lead l = new Lead(
            LastName = 'Test Lead No Email',
            Company = 'ICBFS Test'
        );
        insert l;

        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            LeadId = l.Id,
            Status = getAnyCampaignMemberStatus(),
            QR_Enviado__c = false
        );
        insert cm;

        // Blindaje por si hay automatización que marca enviado
        CampaignMember before = [
            SELECT Id, QR_Enviado__c, Lead.Email, QR_Token__c
            FROM CampaignMember
            WHERE Id = :cm.Id
            LIMIT 1
        ];
        if (before.QR_Enviado__c == true) {
            update new CampaignMember(Id = before.Id, QR_Enviado__c = false);
        }

        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            camp.Id,
            'Email__c',
            'https://energy-saas-7178.my.site.com/openday',
            'UT Subject'
        ));
        Test.stopTest();

        CampaignMember after = [
            SELECT Id, QR_Enviado__c, Lead.Email, QR_Token__c
            FROM CampaignMember
            WHERE Id = :cm.Id
            LIMIT 1
        ];

        System.assertEquals(null, after.Lead.Email, 'Precondición: el Lead debe no tener email.');
        System.assertEquals(false, after.QR_Enviado__c, 'Sin email, el Queue NO debería marcar como enviado.');
    }

    @IsTest
    static void testQueueable_Defaults_Subject_And_Landing() {

        Campaign camp = new Campaign(Name = 'UT - Defaults', IsActive = true);
        insert camp;

        Lead l = new Lead(
            LastName = 'Test Lead Defaults',
            Company = 'ICBFS Test',
            Email = 'salesforce.acux+defaults@gmail.com'
        );
        insert l;

        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            LeadId = l.Id,
            Status = getAnyCampaignMemberStatus(),
            QR_Token__c = 'TOKEN_DEFAULTS_001',
            QR_Enviado__c = false
        );
        insert cm;

        // subject y landingBaseUrl vacíos para cubrir ramas default en el Queue
        Test.startTest();
        System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
            camp.Id,
            'Email__c',
            null,
            null
        ));
        Test.stopTest();

        CampaignMember after = [
            SELECT Id, QR_Enviado__c
            FROM CampaignMember
            WHERE Id = :cm.Id
            LIMIT 1
        ];

        System.assertEquals(true, after.QR_Enviado__c, 'Con token + email, incluso con defaults, debe marcar enviado.');
    }

    private static String getAnyCampaignMemberStatus() {
        List<Schema.PicklistEntry> vals = CampaignMember.Status.getDescribe().getPicklistValues();
        System.assert(!vals.isEmpty(), 'CampaignMember.Status no tiene valores de picklist.');
        for (Schema.PicklistEntry pe : vals) {
            if (pe.isActive()) return pe.getValue();
        }
        return vals[0].getValue();
    }
}