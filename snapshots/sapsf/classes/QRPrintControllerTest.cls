@IsTest
private class QRPrintControllerTest {

    @TestSetup
    static void setupData() {
        Campaign c = new Campaign(
            Name = 'Test QR Campaign',
            IsActive = true
        );
        insert c;

        Lead l = new Lead(
            FirstName = 'Test',
            LastName = 'User',
            Company = 'ICB',
            Email = 'test.qr@icb.cl'
        );
        insert l;

        CampaignMember cm = new CampaignMember(
            CampaignId = c.Id,
            LeadId = l.Id,
            QR_Token__c = 'TOK_TEST_001'
        );
        insert cm;

        QR_Scan__c scan = new QR_Scan__c(
            Token__c = 'TOK_SCAN_DISTINTO_001',
            Campa_a__c = c.Id,
            CampaignMemberId__c = cm.Id,
            Fecha_Hora__c = Datetime.now(),
            Impreso__c = false
        );
        insert scan;
    }

    @IsTest
    static void testGetUnprintedScans() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];

        Test.startTest();
        List<QRPrintController.ScanWrapper> wrappers = QRPrintController.getUnprintedScans(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrappers, 'Debe retornar lista');
        System.assert(wrappers.size() > 0, 'Debe tener al menos un escaneo');
        System.assertEquals('Test User', wrappers[0].memberName, 'Nombre del miembro debe coincidir');
        System.assertNotEquals(null, wrappers[0].memberRecordId, 'Debe traer el Id del miembro para linkear');
        System.assertEquals('00v', String.valueOf(wrappers[0].memberRecordId).substring(0,3), 'Debe linkear a CampaignMember (00v)');
    }

    @IsTest
    static void testMarkAsPrinted() {
        QR_Scan__c scan = [SELECT Id, Impreso__c FROM QR_Scan__c LIMIT 1];
        System.assertEquals(false, scan.Impreso__c, 'Debe empezar como no impreso');

        Test.startTest();
        QRPrintController.markAsPrinted(scan.Id);
        Test.stopTest();

        scan = [SELECT Impreso__c FROM QR_Scan__c WHERE Id = :scan.Id];
        System.assertEquals(true, scan.Impreso__c, 'Debe marcarse como impreso');
    }

    @IsTest
    static void testGetQRDataUsesCampaignMemberToken() {
        QR_Scan__c scan = [SELECT Id FROM QR_Scan__c LIMIT 1];

        Test.startTest();
        String qrData = QRPrintController.getQRData(scan.Id);
        Test.stopTest();

        System.assertNotEquals(null, qrData, 'Debe retornar data para QR');
        System.assert(qrData.contains('/?token='), 'Debe retornar URL de landing con token');
        System.assert(qrData.contains('TOK_TEST_001'), 'Debe usar el token del CampaignMember');
    }

    @IsTest
    static void testGetUnprintedScansGroupedByCampaignMember() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];
        CampaignMember cm = [SELECT Id FROM CampaignMember LIMIT 1];

        List<QR_Scan__c> extraScans = new List<QR_Scan__c>();
        for (Integer i = 0; i < 3; i++) {
            extraScans.add(new QR_Scan__c(
                Token__c = 'TOK_EXTRA_' + i,
                Campa_a__c = c.Id,
                CampaignMemberId__c = cm.Id,
                Fecha_Hora__c = Datetime.now().addMinutes(i + 1),
                Impreso__c = false
            ));
        }
        insert extraScans;

        Test.startTest();
        List<QRPrintController.ScanWrapper> wrappers = QRPrintController.getUnprintedScans(c.Id);
        Test.stopTest();

        System.assertEquals(1, wrappers.size(), 'Debe agrupar scans del mismo CampaignMember en una sola fila');
        System.assertEquals(4, wrappers[0].quantity, 'Debe mostrar la cantidad agrupada');
        System.assertEquals(4, wrappers[0].scanIds.size(), 'Debe devolver todos los scanIds del grupo');
    }

    @IsTest
    static void testMarkAsPrintedBatch() {
        Campaign c = [SELECT Id FROM Campaign LIMIT 1];
        CampaignMember cm = [SELECT Id FROM CampaignMember LIMIT 1];

        List<QR_Scan__c> extraScans = new List<QR_Scan__c>();
        for (Integer i = 0; i < 2; i++) {
            extraScans.add(new QR_Scan__c(
                Token__c = 'TOK_BATCH_' + i,
                Campa_a__c = c.Id,
                CampaignMemberId__c = cm.Id,
                Fecha_Hora__c = Datetime.now().addMinutes(i + 5),
                Impreso__c = false
            ));
        }
        insert extraScans;

        List<Id> ids = new List<Id>();
        for (QR_Scan__c s : [SELECT Id FROM QR_Scan__c WHERE Campa_a__c = :c.Id AND Impreso__c = false]) {
            ids.add(s.Id);
        }

        Test.startTest();
        QRPrintController.markAsPrintedBatch(ids);
        Test.stopTest();

        Integer remaining = [SELECT count() FROM QR_Scan__c WHERE Id IN :ids AND Impreso__c = false];
        System.assertEquals(0, remaining, 'Todos los scans del grupo deben quedar impresos');
    }

    @IsTest
    static void testErrors() {
        try {
            QRPrintController.getUnprintedScans(null);
            System.assert(false, 'Debe lanzar excepcion');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Debe lanzar excepcion con mensaje');
        }

        try {
            QRPrintController.markAsPrinted(null);
            System.assert(false, 'Debe lanzar excepcion');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Debe lanzar excepcion con mensaje');
        }

        try {
            QRPrintController.getQRData(null);
            System.assert(false, 'Debe lanzar excepcion');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Debe lanzar excepcion con mensaje');
        }

        try {
            QRPrintController.markAsPrintedBatch(new List<Id>());
            System.assert(false, 'Debe lanzar excepcion');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Debe lanzar excepcion con mensaje');
        }
    }
}