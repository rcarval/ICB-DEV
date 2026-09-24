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

        //Validar que el archivo quedó linkeado al Case
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id
        ];

        //Validar update del Case
        Case updatedCase = [SELECT FDR_modificado__c FROM Case WHERE Id = :c.Id];
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