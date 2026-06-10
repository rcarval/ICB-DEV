@isTest
private class ICB_LeadsSII_IntegrationActionTest {
    @isTest
    static void testEnqueueLeadsSIIIntegration_Ok() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();

        ICB_LeadsSII_IntegrationAction.InvocableInput input = new ICB_LeadsSII_IntegrationAction.InvocableInput();
        input.leadId = String.valueOf(ld.Id);

        Test.startTest();
        List<ICB_LeadsSII_IntegrationAction.InvocableOutput> outputs =
            ICB_LeadsSII_IntegrationAction.enqueueLeadsSIIIntegration(
                new List<ICB_LeadsSII_IntegrationAction.InvocableInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].queued);
        System.assertNotEquals(null, outputs[0].asyncJobId);
    }

    @isTest
    static void testEnqueueLeadsSIIIntegration_SinIdsValidos() {
        ICB_LeadsSII_IntegrationAction.InvocableInput input = new ICB_LeadsSII_IntegrationAction.InvocableInput();
        input.leadId = ' ';

        List<ICB_LeadsSII_IntegrationAction.InvocableOutput> outputs =
            ICB_LeadsSII_IntegrationAction.enqueueLeadsSIIIntegration(
                new List<ICB_LeadsSII_IntegrationAction.InvocableInput>{ input }
            );

        System.assertEquals(1, outputs.size());
        System.assertEquals(false, outputs[0].queued);
        System.assert(outputs[0].message.contains('No se recibieron Ids'));
    }
}