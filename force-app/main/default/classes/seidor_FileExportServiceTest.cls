@isTest
private class seidor_FileExportServiceTest {

    // =========================================================================
    // Validaciones de entrada (sin SeeAllData)
    // =========================================================================

    @isTest
    static void createExcelFile_contenidoBlank_debeArrojarExcepcion() {
        String html = '';
        String filename = 'reporte.xls';

        AuraHandledException capturada;
        try {
            Test.startTest();
            seidor_FileExportService.createExcelFile(html, filename);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }

        System.assertNotEquals(null, capturada,
            'Debe arrojar AuraHandledException cuando el contenido está vacío');
    }

    @isTest
    static void createExcelFile_contenidoNull_debeArrojarExcepcion() {
        String html = null;
        String filename = 'reporte.xls';

        AuraHandledException capturada;
        try {
            Test.startTest();
            seidor_FileExportService.createExcelFile(html, filename);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }

        System.assertNotEquals(null, capturada,
            'Debe arrojar AuraHandledException cuando el contenido es null');
    }

    @isTest
    static void createExcelFile_contenidoExcedeTamanoMaximo_debeArrojarExcepcion() {
        // Generar string que excede MAX_CONTENT_LENGTH (5.000.000)
        String largeHtml = 'x'.repeat(5000001);
        String filename = 'reporte.xls';

        AuraHandledException capturada;
        try {
            Test.startTest();
            seidor_FileExportService.createExcelFile(largeHtml, filename);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }

        System.assertNotEquals(null, capturada,
            'Debe arrojar AuraHandledException cuando el contenido excede 5MB');
    }

    // =========================================================================
    // Charset logic
    // =========================================================================

    @isTest
    static void createExcelFile_sinCharset_agregaMetaTag() {
        String html = '<html><body><table><tr><td>Prueba</td></tr></table></body></html>';
        String filename = 'reporte_sin_charset';

        Test.startTest();
        String resultId = seidor_FileExportService.createExcelFile(html, filename);
        Test.stopTest();

        System.assertNotEquals(null, resultId, 'Debe retornar un Id');

        ContentVersion cv = [
            SELECT Id, Title, PathOnClient, VersionData, IsMajorVersion
            FROM ContentVersion
            WHERE Id = :resultId
        ];

        String content = cv.VersionData.toString();
        System.assert(content.startsWith('<meta http-equiv="Content-Type"'),
            'El charset debe agregarse al inicio del contenido');
        System.assert(content.contains('charset=UTF-8'),
            'El contenido debe contener charset=UTF-8');
        System.assertEquals(filename, cv.Title, 'Title debe coincidir');
        System.assertEquals(filename + '.xls', cv.PathOnClient, 'PathOnClient debe ser filename.xls');
        System.assertEquals(false, cv.IsMajorVersion, 'Debe ser versión menor');
    }

    @isTest
    static void createExcelFile_conCharset_noAgregaDuplicado() {
        String html = '<html><head><meta charset="UTF-8"></head><body>Test</body></html>';
        String filename = 'reporte_con_charset';

        Test.startTest();
        String resultId = seidor_FileExportService.createExcelFile(html, filename);
        Test.stopTest();

        System.assertNotEquals(null, resultId);

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :resultId
        ];

        String content = cv.VersionData.toString();
        // El contenido original ya tiene 'charset=', no debe duplicarse
        // El original tiene 1 ocurrencia, no debe tener más
        Integer count = countOccurrences(content, 'charset');
        System.assertEquals(1, count, 'charset no debe duplicarse cuando ya está presente');
    }

    @isTest
    static void createExcelFile_charsetEnMedio_noAgregaDuplicado() {
        // Caso borde: charset= aparece en medio del contenido (no necesariamente como meta tag)
        String html = '<html><body>El charset=UTF-8 es necesario</body></html>';
        String filename = 'charset_en_texto';

        Test.startTest();
        String resultId = seidor_FileExportService.createExcelFile(html, filename);
        Test.stopTest();

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :resultId
        ];

        String content = cv.VersionData.toString();
        // No debe agregar otro meta tag, pero el contenido original debe preservarse
        Integer count = countOccurrences(content, 'charset');
        System.assertEquals(1, count, 'No debe agregar meta tag duplicado cuando charset ya aparece');
        System.assertEquals(html, content, 'El contenido debe preservarse exactamente igual');
    }

    // =========================================================================
    // Happy path — verifica que se crea el ContentVersion correctamente
    // =========================================================================

    @isTest
    static void createExcelFile_happyPath_creaContentVersion() {
        String html = '<table><tr><td>Datos de prueba</td></tr></table>';
        String filename = 'reporte_financiero';

        Integer cvCountBefore = [SELECT COUNT() FROM ContentVersion];

        Test.startTest();
        String resultId = seidor_FileExportService.createExcelFile(html, filename);
        Test.stopTest();

        Integer cvCountAfter = [SELECT COUNT() FROM ContentVersion];

        System.assertEquals(cvCountBefore + 1, cvCountAfter,
            'Debe crearse exactamente 1 ContentVersion');

        ContentVersion cv = [
            SELECT Id, Title, PathOnClient, VersionData, IsMajorVersion,
                   ContentDocumentId, FileType, FileExtension
            FROM ContentVersion
            WHERE Id = :resultId
        ];

        System.assertEquals(filename, cv.Title);
        System.assertEquals(filename + '.xls', cv.PathOnClient);
        System.assertEquals(false, cv.IsMajorVersion);
        System.assertEquals('xls', cv.FileExtension, 'FileExtension debe ser xls');

        String storedContent = cv.VersionData.toString();
        System.assert(storedContent.contains('Datos de prueba'),
            'El contenido HTML debe persistir en VersionData');
        System.assert(storedContent.contains('charset=UTF-8'),
            'Debe tener charset para compatibilidad con Excel');
    }

    // =========================================================================
    // DML exception — PathOnClient > 255 caracteres dispara DmlException
    // =========================================================================

    @isTest
    static void createExcelFile_dmlException_pathOnClientDemasiadoLargo() {
        // PathOnClient/Title tienen límite de caracteres. filename de 10000 excede cualquier límite.
        String longFilename = 'x'.repeat(10000);
        String html = '<table><tr><td>Test</td></tr></table>';

        AuraHandledException capturada;
        try {
            Test.startTest();
            seidor_FileExportService.createExcelFile(html, longFilename);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }

        System.assertNotEquals(null, capturada,
            'filename extremadamente largo debe generar DML exception capturada como AuraHandledException');
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static Integer countOccurrences(String haystack, String needle) {
        Integer count = 0;
        Integer idx = 0;
        while ((idx = haystack.indexOf(needle, idx)) != -1) {
            count++;
            idx += needle.length();
        }
        return count;
    }
}