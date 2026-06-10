@isTest
private class ICB_CalloutAPI_SII_Test {
    @isTest
    static void testConsultarSituacionTributariaTercero_BlankRut() {
        try {
            ICB_CalloutAPI_SII.consultarSituacionTributariaTerceroRaw(null);
            System.assert(false, 'Debio lanzar excepcion por RUT nulo.');
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('RUT es obligatorio'));
        }
    }

    @isTest
    static void testConsultarSituacionTributariaTercero_Ok() {
        String body = '{"rut":81482800,"dv":"K","razon_social":"EMPRESA TEST","actividades":[{"codigo":"475201"}],"observaciones":{"inconcurrente":false}}';
        Test.setMock(
            HttpCalloutMock.class,
            new ICB_LeadsSII_TestFactory.SiiHttpMock(200, 'OK', body)
        );

        Test.startTest();
        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto =
            ICB_CalloutAPI_SII.consultarSituacionTributariaTercero('81482800-K');
        Test.stopTest();

        System.assertNotEquals(null, dto);
        System.assertEquals('EMPRESA TEST', dto.razon_social);
        System.assertEquals('475201', dto.actividades[0].codigo);
    }
}