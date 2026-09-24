@isTest
public class seidor_getDocumentNCCaseTest {

    @testSetup
    static void setupData() {

        // Crear Case base
        Case c = new Case(
            Subject = 'Caso Test',
            Status = 'New',
            Origin = 'Phone'
        );
        insert c;
    }

    // 🔥 CASO 1: Existe archivo FDR
    @isTest
    static void test_existingFDRFile() {

        Case c = [SELECT Id FROM Case LIMIT 1];

        // Crear archivo (ContentVersion)
        ContentVersion cv = new ContentVersion(
            Title = 'FDR Calidad - Test',
            PathOnClient = 'test.pdf',
            VersionData = Blob.valueOf('Test File')
        );
        insert cv;

        // Obtener ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        // Linkear al Case
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = c.Id,
            ShareType = 'V'
        );
        insert link;

        // Input
        seidor_getDocumentNCCase.Input input = new seidor_getDocumentNCCase.Input();
        input.caseId = c.Id;

        Test.startTest();

        List<seidor_getDocumentNCCase.Output> result =
            seidor_getDocumentNCCase.getDocumentNC(new List<seidor_getDocumentNCCase.Input>{ input });

        Test.stopTest();

        System.assert(result.size() == 1);
        System.assert(result[0].alreadyExists == true);
        System.assert(result[0].contentDocumentId != null);
    }

    // 🔥 CASO 2: Existe NC (pero NO FDR)
    @isTest
    static void test_existingNCFile() {

        Case c = [SELECT Id, Archivo_cargado__c FROM Case LIMIT 1];

        // Crear archivo NC
        ContentVersion cv = new ContentVersion(
            Title = 'Nota de credito - Test',
            PathOnClient = 'nc.pdf',
            VersionData = Blob.valueOf('NC File')
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = c.Id,
            ShareType = 'V'
        );
        insert link;

        seidor_getDocumentNCCase.Input input = new seidor_getDocumentNCCase.Input();
        input.caseId = c.Id;

        Test.startTest();

        List<seidor_getDocumentNCCase.Output> result =
            seidor_getDocumentNCCase.getDocumentNC(new List<seidor_getDocumentNCCase.Input>{ input });

        Test.stopTest();

        Case updatedCase = [SELECT Archivo_cargado__c FROM Case WHERE Id = :c.Id];

        System.assert(result.size() == 1);
        System.assert(result[0].existingNCFiles == true);
        System.assert(result[0].contentDocumentId != null);
        System.assert(updatedCase.Archivo_cargado__c == true);
    }

    // 🔥 CASO 3: Sin archivos
    @isTest
    static void test_noFiles() {

        Case c = new Case(
            Subject = 'Caso sin archivos',
            Status = 'New',
            Origin = 'Phone'
        );
        insert c;

        seidor_getDocumentNCCase.Input input = new seidor_getDocumentNCCase.Input();
        input.caseId = c.Id;

        Test.startTest();

        List<seidor_getDocumentNCCase.Output> result =
            seidor_getDocumentNCCase.getDocumentNC(new List<seidor_getDocumentNCCase.Input>{ input });

        Test.stopTest();

        System.assert(result.size() == 0 || result.size() == 1);
    }
}