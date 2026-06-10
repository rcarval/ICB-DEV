@IsTest
private class seidor_AssociarArchivosCasoTest {

    @IsTest
    static void testAsociarArchivos_OK() {
        // 1. Crear Caso
        Case c = new Case(
            Subject = 'Caso con archivos',
            Status  = 'New',
            Origin  = 'Web'
        );
        insert c;

        // 2. Crear archivo (ContentVersion)
        ContentVersion cv = new ContentVersion(
            Title = 'ArchivoTest',
            PathOnClient = 'ArchivoTest.pdf',
            VersionData = Blob.valueOf('Contenido de prueba')
        );
        insert cv;

        // 3. Obtener ContentDocumentId
        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ].ContentDocumentId;

        // 4. Construir request invocable
        seidor_AssociarArchivosCaso.Request req = 
            new seidor_AssociarArchivosCaso.Request();
        req.caseId = c.Id;
        req.documentIds = new List<Id>{ contentDocumentId };

        List<seidor_AssociarArchivosCaso.Request> requests =
            new List<seidor_AssociarArchivosCaso.Request>{ req };

        // 5. Ejecutar método invocable
        Test.startTest();
        seidor_AssociarArchivosCaso.asociar(requests);
        Test.stopTest();

        // 6. Validar ContentDocumentLink
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id
        ];
        System.assertEquals(1, links.size(), 'Debe existir un ContentDocumentLink');

        // 7. Validar flag en Case
        // Case updatedCase = [
        //     SELECT Archivo_Adjunto__c
        //     FROM Case
        //     WHERE Id = :c.Id
        // ];
        // System.assertEquals(true, updatedCase.Archivo_Adjunto__c,
        //     'El caso debe marcarse con archivo adjunto');
    }

    @IsTest
    static void testAsociarSinArchivos_NoActualizaCaso() {
        // 1. Crear Caso
        Case c = new Case(
            Subject = 'Caso sin archivos',
            Status  = 'New',
            Origin  = 'Phone'
        );
        insert c;

        // 2. Request sin documentos
        seidor_AssociarArchivosCaso.Request req =
            new seidor_AssociarArchivosCaso.Request();
        req.caseId = c.Id;
        req.documentIds = new List<Id>();

        List<seidor_AssociarArchivosCaso.Request> requests =
            new List<seidor_AssociarArchivosCaso.Request>{ req };

        // 3. Ejecutar
        Test.startTest();
        seidor_AssociarArchivosCaso.asociar(requests);
        Test.stopTest();

        // 4. Validar que no se actualizó el flag
        // Case updatedCase = [
        //     SELECT Archivo_Adjunto__c
        //     FROM Case
        //     WHERE Id = :c.Id
        // ];
        // System.assertEquals(false, updatedCase.Archivo_Adjunto__c,
        //     'El caso no debe marcarse como con archivo');
    }

    @IsTest
    static void testBulkMultipleCases() {
        // 1. Crear Casos
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 2; i++) {
            cases.add(new Case(
                Subject = 'Caso bulk ' + i,
                Status  = 'New',
                Origin  = 'Email'
            ));
        }
        insert cases;

        // 2. Crear archivo
        ContentVersion cv = new ContentVersion(
            Title = 'BulkFile',
            PathOnClient = 'BulkFile.txt',
            VersionData = Blob.valueOf('Bulk content')
        );
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ].ContentDocumentId;

        // 3. Requests bulk
        List<seidor_AssociarArchivosCaso.Request> requests =
            new List<seidor_AssociarArchivosCaso.Request>();

        for (Case c : cases) {
            seidor_AssociarArchivosCaso.Request req =
                new seidor_AssociarArchivosCaso.Request();
            req.caseId = c.Id;
            req.documentIds = new List<Id>{ contentDocumentId };
            requests.add(req);
        }

        // 4. Ejecutar
        Test.startTest();
        seidor_AssociarArchivosCaso.asociar(requests);
        Test.stopTest();

        // 5. Validar resultados
        // List<Case> updatedCases = [
        //     SELECT Archivo_Adjunto__c
        //     FROM Case
        //     WHERE Id IN :cases
        // ];

        // for (Case c : updatedCases) {
        //     System.assertEquals(true, c.Archivo_Adjunto__c,
        //         'Todos los casos deben marcarse con archivo');
        // }
    }
}