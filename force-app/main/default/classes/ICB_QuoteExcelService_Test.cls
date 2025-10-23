/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Exportación de Quote a Excel
Descripción: Clase de test para ICB_QuoteExcelService
Test: ICB_QuoteExcelService_Test

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripción
------ ---------- ---------------------------------------------------------------
1.0 23-10-2025            RCG                Creación de la clase.
**********************************************************************************/
@isTest
public class ICB_QuoteExcelService_Test {
    
    @TestSetup
    static void setupTestData() {
        // Crear Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Crear Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;
        
        // Crear Product2
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            ProductCode = 'TEST001',
            IsActive = true
        );
        insert testProduct;
        
        // Crear Pricebook2
        Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        
        // Crear PricebookEntry
        PricebookEntry testPricebookEntry = new PricebookEntry(
            Pricebook2Id = standardPricebook.Id,
            Product2Id = testProduct.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert testPricebookEntry;
        
        // Crear Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            AccountId = testAccount.Id,
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30)
        );
        insert testQuote;
        
        // Crear QuoteLineItem
        QuoteLineItem testLineItem = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = testPricebookEntry.Id,
            Quantity = 2,
            UnitPrice = 100.00,
            ListPrice = 100.00,
            Discount = 10.00,
            Description = 'Test Description',
            ServiceDate = Date.today().addDays(7)
        );
        insert testLineItem;
        
        // Actualizar Quote para calcular totales
        testQuote.Status = 'Approved';
        testQuote.GrandTotal = 180.00; // 2 * 100 * 0.9
        update testQuote;
    }
    
    @isTest
    static void testGenerateExcelFileFromFlow() {
        // Obtener Quote de test
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        
        Test.startTest();
        
        // Llamar método invocable
        List<String> fileIds = ICB_QuoteExcelService.generateExcelFileFromFlow(new List<Id>{testQuote.Id});
        
        Test.stopTest();
        
        // Verificaciones
        System.assertEquals(1, fileIds.size(), 'Debe retornar un ID de archivo');
        System.assertNotEquals('ERROR:', fileIds[0].substring(0, 6), 'No debe haber errores');
        
        // Verificar que se creó el archivo
        List<ContentVersion> files = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId = :fileIds[0]];
        System.assertEquals(1, files.size(), 'Debe haberse creado un archivo');
        System.assert(files[0].Title.contains('Cotización_'), 'El título debe contener "Cotización_"');
    }
    
    @isTest
    static void testGenerateExcelFile() {
        // Obtener Quote de test
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        
        Test.startTest();
        
        // Llamar método principal
        String fileId = ICB_QuoteExcelService.generateExcelFile(testQuote.Id);
        
        Test.stopTest();
        
        // Verificaciones
        System.assertNotEquals(null, fileId, 'Debe retornar un ID de archivo');
        System.assertNotEquals('ERROR:', fileId.substring(0, 6), 'No debe haber errores');
        
        // Verificar que se creó el archivo
        List<ContentVersion> files = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId = :fileId];
        System.assertEquals(1, files.size(), 'Debe haberse creado un archivo');
    }
    
    @isTest
    static void testGenerateExcelFileWithNoLineItems() {
        // Crear Quote sin LineItems
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        
        Quote emptyQuote = new Quote(
            Name = 'Empty Quote',
            AccountId = testAccount.Id,
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft'
        );
        insert emptyQuote;
        
        Test.startTest();
        
        try {
            ICB_QuoteExcelService.generateExcelFile(emptyQuote.Id);
            System.assert(false, 'Debe lanzar excepción para Quote sin productos');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('no tiene productos'), 'Debe indicar que no tiene productos');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testGenerateExcelFileWithInvalidQuote() {
        Test.startTest();
        
        try {
            ICB_QuoteExcelService.generateExcelFile('001000000000000'); // ID inválido
            System.assert(false, 'Debe lanzar excepción para Quote inválida');
        } catch (Exception e) {
            System.assert(true, 'Debe lanzar excepción para Quote inválida');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testGenerateExcelContentFormat() {
        // Obtener datos de test
        Quote testQuote = [SELECT Id, Name, QuoteNumber, Account.Name, Opportunity.Name, GrandTotal, ExpirationDate FROM Quote LIMIT 1];
        List<QuoteLineItem> lineItems = [SELECT Id, Product2.Name, Product2.ProductCode, Quantity, UnitPrice, ListPrice, Discount, TotalPrice, Description, ServiceDate FROM QuoteLineItem];
        
        Test.startTest();
        
        // Llamar método privado a través de reflexión (simulado)
        String excelContent = ICB_QuoteExcelService.generateExcelFile(testQuote.Id);
        
        Test.stopTest();
        
        // Verificar que se creó el archivo
        List<ContentVersion> files = [SELECT Id, Title, VersionData FROM ContentVersion WHERE ContentDocumentId = :excelContent];
        System.assertEquals(1, files.size(), 'Debe haberse creado un archivo');
        
        // Verificar contenido del archivo
        String fileContent = files[0].VersionData.toString();
        System.assert(fileContent.contains('<html'), 'Debe contener HTML');
        System.assert(fileContent.contains('xmlns:o="urn:schemas-microsoft-com:office:office"'), 'Debe tener namespace de Office');
        System.assert(fileContent.contains('xmlns:x="urn:schemas-microsoft-com:office:excel"'), 'Debe tener namespace de Excel');
        System.assert(fileContent.contains(testQuote.Name), 'Debe contener el nombre de la Quote');
        System.assert(fileContent.contains(testQuote.QuoteNumber), 'Debe contener el número de Quote');
    }
}
