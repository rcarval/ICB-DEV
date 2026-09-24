@IsTest
private class ICB_PdfRecoveryMemoryController_Test {
    @IsTest
    static void generaPdfEnMemoriaSinCrearArchivo() {
        Account account = new Account(Name = 'PDF memoria');
        insert account;
        Opportunity opportunity = new Opportunity(
            Name = 'PDF memoria',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opportunity;

        Test.startTest();
        ICB_PdfRecoveryMemoryController.PdfResult result =
            ICB_PdfRecoveryMemoryController.generarPdf(opportunity.Id);
        Test.stopTest();

        System.assert(String.isNotBlank(result.pdfBase64));
        System.assert(result.pdfFileName.endsWith('.pdf'));
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion]);
    }

    @IsTest
    static void rechazaSolicitudSinOportunidad() {
        try {
            ICB_PdfRecoveryMemoryController.generarPdf(null);
            System.assert(false, 'Debió rechazar la solicitud sin oportunidad.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }
}