@isTest
public class seidor_CasePdfGeneratorInvocableTest {

    @testSetup
    static void setupData() {

        Case c = new Case(
            Subject = 'Caso Test',
            Status = 'New',
            Origin = 'Phone',
            N_Factura__c = '5029739',
            //Direccion_de_Retiro__c = '',
            Codigo_Cliente__c = 'FS34880',
            Cliente_Despacho__c = 'FS34880-2'
        );
        insert c;
    }

    @isTest
    static void test_generateUrls_successFlow() {

        Case c = [SELECT Id, FDR_modificado__c FROM Case LIMIT 1];

        seidor_CasePdfGeneratorInvocable.FlowInput input =
            new seidor_CasePdfGeneratorInvocable.FlowInput();

        input.caseId = c.Id;
        input.numberCase = 'CASE-001';

        Test.startTest();

        List<seidor_CasePdfGeneratorInvocable.FlowOutput> results =
            seidor_CasePdfGeneratorInvocable.generateUrls(
                new List<seidor_CasePdfGeneratorInvocable.FlowInput>{ input }
            );

        Test.stopTest();

        seidor_CasePdfGeneratorInvocable.FlowOutput res = results[0];

        System.assertNotEquals(null, res.previewUrl, 'previewUrl should not be null');
        System.assertNotEquals(null, res.pdfPageUrl, 'pdfPageUrl should not be null');
        System.assertNotEquals(null, res.downloadUrl, 'downloadUrl should not be null');
        System.assert(res.previewUrl.contains('preview=true'), 'previewUrl should contain preview=true');
    }

    @isTest
    static void test_updateCaseAndSavePdf() {
        Case c = [SELECT Id, N_FDR__c, Tipo_de_Requerimiento__c FROM Case LIMIT 1];
        Blob testBlob = Blob.valueOf('Test PDF Content');
        String numberCase = 'CASE-001';
        String tituloPdf = (c.Tipo_de_Requerimiento__c == 'Devoluciones') ? 'FDR Devoluciones - ' : 'FDR Calidad - ';

        seidor_CasePdfGeneratorInvocable.FlowOutput output =
            new seidor_CasePdfGeneratorInvocable.FlowOutput();

        Test.startTest();
        seidor_CasePdfGeneratorInvocable.updateCaseAndSavePdf(
            c.Id, tituloPdf, numberCase, testBlob, output
        );
        Test.stopTest();

        System.assertNotEquals(null, output.contentDocumentId, 'contentDocumentId should be set');

        ContentDocumentLink cdl = [
            SELECT Id, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :output.contentDocumentId
            AND LinkedEntityId = :c.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, cdl, 'Should have a ContentDocumentLink to the Case');
        System.assertEquals(c.Id, cdl.LinkedEntityId, 'File should be linked to the Case');

        ContentVersion cv = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :output.contentDocumentId
            LIMIT 1
        ];
        System.assertEquals(
            tituloPdf + numberCase, cv.Title, 'ContentVersion title should match'
        );

        Case updatedCase = [
            SELECT FDR_modificado__c
            FROM Case
            WHERE Id = :c.Id
        ];
        System.assertEquals(
            false, updatedCase.FDR_modificado__c,
            'FDR_modificado__c should be set to false'
        );
    }

    @isTest
    static void test_generateUrls_multipleInputs() {

        List<Case> cases = new List<Case>();

        for (Integer i = 0; i < 2; i++) {
            cases.add(new Case(
                Subject = 'Caso ' + i,
                Status = 'New',
                Origin = 'Phone'
            ));
        }
        insert cases;

        List<seidor_CasePdfGeneratorInvocable.FlowInput> inputs =
            new List<seidor_CasePdfGeneratorInvocable.FlowInput>();

        for (Case c : cases) {
            seidor_CasePdfGeneratorInvocable.FlowInput input =
                new seidor_CasePdfGeneratorInvocable.FlowInput();

            input.caseId = c.Id;
            input.numberCase = 'CASE-' + c.Id;

            inputs.add(input);
        }

        Test.startTest();

        List<seidor_CasePdfGeneratorInvocable.FlowOutput> results =
            seidor_CasePdfGeneratorInvocable.generateUrls(inputs);

        seidor_CasePdfGeneratorInvocable.getInt();
        Test.stopTest();
    }
}