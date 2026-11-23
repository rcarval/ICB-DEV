@IsTest
private class ICB_LeadConversionFlowAction_Test {

    /**
     * La conversión real y el post-mapeo quedan cubiertos por ICB_LeadsSII_ResponseHandlerTest
     * y el uso en producción del Flow; aquí solo se valida el contrato del invocable
     * (entradas vacías / nulas y forma de la respuesta) sin depender de reglas de validación
     * específicas de Lead en la org.
     */
    @IsTest
    static void convertAndMap_handlesNullOrEmptyRequests() {
        Test.startTest();
        List<ICB_LeadConversionFlowAction.Response> nullOut =
            ICB_LeadConversionFlowAction.convertAndMap(null);
        List<ICB_LeadConversionFlowAction.Response> emptyOut =
            ICB_LeadConversionFlowAction.convertAndMap(new List<ICB_LeadConversionFlowAction.Request>());
        Test.stopTest();

        System.assertEquals(0, nullOut.size(), 'Null requests debe retornar lista vacía.');
        System.assertEquals(0, emptyOut.size(), 'Lista vacía de requests debe retornar lista vacía.');
    }

    /**
     * Ejecuta el invocable con un Lead real para cubrir el mapeo a Response y delegación al servicio.
     * El éxito de Database.convertLead depende de la org; se valida forma de respuesta y coherencia de IDs.
     */
    @IsTest
    static void convertAndMap_withLeadId_delegatesToService() {
        Lead ld = ICB_LeadsSII_TestFactory.createLeadBase();
        ICB_LeadConversionService.setSimulateSuccessfulConversionForTests(true);
        ICB_LeadConversionFlowAction.Request req = new ICB_LeadConversionFlowAction.Request();
        req.leadId = ld.Id;
        ICB_LeadConversionFlowAction.Request reqNullLead = new ICB_LeadConversionFlowAction.Request();

        Test.startTest();
        List<ICB_LeadConversionFlowAction.Response> responses = ICB_LeadConversionFlowAction.convertAndMap(
            new List<ICB_LeadConversionFlowAction.Request>{ reqNullLead, req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Solo el request con leadId válido produce salida ordenada.');
        System.assertEquals(ld.Id, responses[0].leadId);
        System.assertEquals(true, responses[0].success);
        System.assertNotEquals(null, responses[0].accountId);
    }
}