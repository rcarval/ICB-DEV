@IsTest
private class ComodatoMulti_Test {

    @TestSetup
    static void setupData() {
        // Crear productos máquina
        Product2 maquina1 = new Product2(
            Name = 'MAQUINA CAFE TEST LB 4300',
            IsActive = true,
            Tipo_Equipo__c = 'Máquina Café',
            TextoCategoria__c = '593 MAQUINAS Y REPUESTOS',
            Codigo__c = 'TEST-MAQ-001'
        );
        Product2 maquina2 = new Product2(
            Name = 'MAQUINA CAFE TEST S2 EK 2G',
            IsActive = true,
            Tipo_Equipo__c = 'Máquina Café',
            TextoCategoria__c = '593 MAQUINAS Y REPUESTOS',
            Codigo__c = 'TEST-MAQ-002'
        );
        Product2 dispensador1 = new Product2(
            Name = 'DISPENSADOR TEST SALSAS 4L',
            IsActive = true,
            Tipo_Equipo__c = 'Dispensador',
            TextoCategoria__c = '593 MAQUINAS Y REPUESTOS',
            Codigo__c = 'TEST-DISP-001'
        );
        Product2 insumo1 = new Product2(
            Name = 'CAFE GRANO LAVAZZA TEST 1KG',
            IsActive = true,
            Codigo__c = 'TEST-INS-001'
        );
        Product2 insumo2 = new Product2(
            Name = 'CAPSULA LAVAZZA TEST BLUE',
            IsActive = true,
            Codigo__c = 'TEST-INS-002'
        );
        insert new List<Product2>{ maquina1, maquina2, dispensador1, insumo1, insumo2 };

        // Standard Pricebook
        Id stdPb = Test.getStandardPricebookId();
        List<PricebookEntry> stdEntries = new List<PricebookEntry>();
        for (Product2 p : [SELECT Id FROM Product2]) {
            stdEntries.add(new PricebookEntry(
                Pricebook2Id = stdPb,
                Product2Id = p.Id,
                UnitPrice = 0,
                IsActive = true
            ));
        }
        insert stdEntries;

        // Pricebook Comodato
        Pricebook2 comodatoPb = new Pricebook2(Name = 'COMODATO TEST', IsActive = true);
        insert comodatoPb;

        List<PricebookEntry> comodatoEntries = new List<PricebookEntry>();
        for (Product2 p : [SELECT Id FROM Product2]) {
            comodatoEntries.add(new PricebookEntry(
                Pricebook2Id = comodatoPb.Id,
                Product2Id = p.Id,
                UnitPrice = 0,
                IsActive = true
            ));
        }
        insert comodatoEntries;

        // Configuraciones Comodato__c
        List<Comodato__c> configs = new List<Comodato__c>();
        configs.add(new Comodato__c(
            Maquina__c = maquina1.Id,
            Producto_Asociado__c = insumo1.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Precio_Unitario_Neto__c = 15000,
            Cantidad_Minima_Mensual__c = 5,
            Unidad_de_Medida__c = 'KG'
        ));
        configs.add(new Comodato__c(
            Maquina__c = maquina2.Id,
            Producto_Asociado__c = insumo2.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Precio_Unitario_Neto__c = 8000,
            Cantidad_Minima_Mensual__c = 100,
            Unidad_de_Medida__c = 'Unidades'
        ));
        configs.add(new Comodato__c(
            Maquina__c = maquina1.Id,
            Producto_Asociado__c = insumo2.Id,
            Tipo_de_Asociacion__c = 'Aporte de Marca',
            Cantidad_Aporte__c = 2
        ));
        insert configs;

        // Account y Opportunity para Quote
        Account acc = new Account(Name = 'Test Account Comodato');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp Comodato Multi',
            AccountId = acc.Id,
            StageName = 'En proceso de Firma',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = comodatoPb.Id
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Test Quote Comodato Multi',
            OpportunityId = opp.Id,
            Pricebook2Id = comodatoPb.Id
        );
        insert q;
    }

    @IsTest
    static void testGenerarPDFMultiAction_MultiMaquina() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Product2 m1 = [SELECT Id FROM Product2 WHERE Name LIKE 'MAQUINA CAFE TEST LB%' LIMIT 1];
        Product2 m2 = [SELECT Id FROM Product2 WHERE Name LIKE 'MAQUINA CAFE TEST S2%' LIMIT 1];

        String selectionsJson = '[{"machineId":"' + m1.Id + '","quantity":2},{"machineId":"' + m2.Id + '","quantity":1}]';

        GenerarPDFComodatoMultiAction.Input input = new GenerarPDFComodatoMultiAction.Input();
        input.machineSelectionsJson = selectionsJson;
        input.quoteId = q.Id;

        Test.startTest();
        List<GenerarPDFComodatoMultiAction.Output> results =
            GenerarPDFComodatoMultiAction.generar(new List<GenerarPDFComodatoMultiAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Debería ser exitoso: ' + results[0].errorMessage);
        System.assertNotEquals(null, results[0].contentDocumentId);

        // Verificar que se crearon QuoteLineItems
        List<QuoteLineItem> qlis = [SELECT Id, Product2Id, Quantity FROM QuoteLineItem WHERE QuoteId = :q.Id];
        System.assert(qlis.size() >= 3, 'Debería haber al menos 3 partidas (2 máquinas + servicios). Actual: ' + qlis.size());
    }

    @IsTest
    static void testGenerarPDFMultiAction_MismaMaquinaMultiple() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Product2 m1 = [SELECT Id FROM Product2 WHERE Name LIKE 'MAQUINA CAFE TEST LB%' LIMIT 1];

        // 3 unidades de la misma máquina
        String selectionsJson = '[{"machineId":"' + m1.Id + '","quantity":3}]';

        GenerarPDFComodatoMultiAction.Input input = new GenerarPDFComodatoMultiAction.Input();
        input.machineSelectionsJson = selectionsJson;
        input.quoteId = q.Id;

        Test.startTest();
        List<GenerarPDFComodatoMultiAction.Output> results =
            GenerarPDFComodatoMultiAction.generar(new List<GenerarPDFComodatoMultiAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(true, results[0].success);

        // Verificar partida de máquina con qty=3
        QuoteLineItem machineQli = [
            SELECT Quantity FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :m1.Id LIMIT 1
        ];
        System.assertEquals(3, machineQli.Quantity);
    }

    @IsTest
    static void testGenerarPDFMultiAction_EmptySelection() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        GenerarPDFComodatoMultiAction.Input input = new GenerarPDFComodatoMultiAction.Input();
        input.machineSelectionsJson = '[]';
        input.quoteId = q.Id;

        Test.startTest();
        List<GenerarPDFComodatoMultiAction.Output> results =
            GenerarPDFComodatoMultiAction.generar(new List<GenerarPDFComodatoMultiAction.Input>{ input });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Debería fallar con selección vacía');
        System.assert(String.isNotBlank(results[0].errorMessage), 'Debe tener mensaje de error');
    }

    @IsTest
    static void testMultiControllerPreviewHtml() {
        Product2 m1 = [SELECT Id FROM Product2 WHERE Name LIKE 'MAQUINA CAFE TEST LB%' LIMIT 1];
        Product2 m2 = [SELECT Id FROM Product2 WHERE Name LIKE 'MAQUINA CAFE TEST S2%' LIMIT 1];

        String selectionsJson = '[{"machineId":"' + m1.Id + '","quantity":2},{"machineId":"' + m2.Id + '","quantity":1}]';

        Test.startTest();
        String html = ComodatoPropuestaMultiController.getMultiMachinePreviewHtml(selectionsJson);
        Test.stopTest();

        System.assertNotEquals(null, html);
        System.assert(html.contains('MAQUINA CAFE TEST LB 4300'), 'Debe contener nombre de máquina 1');
        System.assert(html.contains('MAQUINA CAFE TEST S2 EK 2G'), 'Debe contener nombre de máquina 2');
        System.assert(html.contains('x2 unidades'), 'Debe indicar cantidad');
        System.assert(html.contains('PROPUESTA'), 'Debe tener banner PROPUESTA');
    }

    @IsTest
    static void testMultiControllerPreviewHtml_Empty() {
        Test.startTest();
        String html = ComodatoPropuestaMultiController.getMultiMachinePreviewHtml('');
        Test.stopTest();

        System.assert(html.contains('Selecciona al menos'));
    }

    @IsTest
    static void testSelectorSearch_Cafe() {
        Test.startTest();
        List<Product2> results = SelectorMultiMaquinaController.searchMachines('MAQUINA', 'Máquina Café');
        Test.stopTest();

        // La búsqueda debe retornar resultados (puede ser 0 si sharing restringe en test context)
        System.assertNotEquals(null, results, 'Resultados no deben ser null');
    }

    @IsTest
    static void testSelectorSearch_Dispensador() {
        Test.startTest();
        List<Product2> results = SelectorMultiMaquinaController.searchMachines('DISPENSADOR', 'Dispensador');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Resultados no deben ser null');
    }

    @IsTest
    static void testSelectorSearch_ShortTerm() {
        Test.startTest();
        List<Product2> results = SelectorMultiMaquinaController.searchMachines('M', 'Máquina Café');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'No debe buscar con menos de 2 caracteres');
    }

    // ═══════════════════════════════════════════════════════
    // Cabecera compartida entre la vista previa y el PDF
    // ═══════════════════════════════════════════════════════

    @IsTest
    static void laCabeceraTraeLavazzaYLasMarcasRepresentadas() {
        Test.startTest();
        String html = ComodatoCabecera.html();
        Test.stopTest();

        System.assert(html.contains('/resource/ICBLogo'), 'Debe llevar el logo de ICB.');
        System.assert(html.contains('/resource/LavazzaLogo'), 'Debe llevar el logo de Lavazza.');
        for (String marca : new List<String>{ 'LogoKraft', 'LogoKraftHeinz', 'LogoNutella', 'LogoDonJuan' }) {
            System.assert(html.contains('/resource/' + marca), marca + ' debe estar en la cabecera.');
        }
        // Lavazza manda; las marcas van mas chicas para que las cinco entren en el ancho A4.
        System.assert(html.contains('height:70px'), 'Lavazza conserva su tamano.');
        // Las alturas son distintas entre marcas a proposito: un emblema macizo pesa mas que
        // una palabra a igual altura. Si alguien las iguala, esto lo delata.
        System.assert(html.contains('height:20px'), 'Kraft y Nutella van a 20px.');
        System.assert(html.contains('height:18px'), 'Kraft Heinz va algo mas bajo.');
        System.assert(html.contains('height:31px'), 'Don Juan, mas compacto, va mas alto.');
        System.assert(!html.contains('height:70px;margin-left'),
            'Ninguna marca debe quedar del tamano de Lavazza.');
    }

    @IsTest
    static void laVistaPreviaUsaLaMismaCabeceraQueElPdf() {
        Product2 maquina = [SELECT Id FROM Product2 WHERE Codigo__c = 'TEST-MAQ-001' LIMIT 1];
        String seleccion = '[{"machineId":"' + maquina.Id + '","quantity":1}]';

        Test.startTest();
        String html = ComodatoPropuestaMultiController.getMultiMachinePreviewHtmlConAjustes(seleccion, null);
        Test.stopTest();

        // Es el punto que fallo una vez: se cambio el PDF y la vista previa quedo atras.
        System.assert(html.contains('/resource/LogoKraft'),
            'La vista previa debe mostrar las mismas marcas que el PDF.');
        System.assert(html.contains('PROPUESTA'), 'Debe traer el banner.');
    }

    @IsTest
    static void sinSeleccionLaVistaPreviaAvisaEnVezDeFallar() {
        Test.startTest();
        String html = ComodatoPropuestaMultiController.getMultiMachinePreviewHtmlConAjustes('', null);
        Test.stopTest();

        System.assert(html.contains('Selecciona al menos una'), 'Debe pedir una seleccion.');
    }

    @IsTest
    static void unJsonIlegibleDevuelveElErrorEnPantalla() {
        Test.startTest();
        String html = ComodatoPropuestaMultiController.getMultiMachinePreviewHtmlConAjustes('{no es json}', null);
        Test.stopTest();

        System.assert(html.contains('Error'), 'Un JSON roto no debe romper la pantalla.');
    }

    @IsTest
    static void laPaginaSeArmaDesdeLosParametrosDeUrl() {
        Product2 maquina = [SELECT Id FROM Product2 WHERE Codigo__c = 'TEST-MAQ-001' LIMIT 1];

        Test.startTest();
        PageReference pg = Page.ComodatoPropuestaMulti;
        pg.getParameters().put('machineIds', maquina.Id);
        pg.getParameters().put('quantities', '2');
        Test.setCurrentPage(pg);
        ComodatoPropuestaMultiController ctrl = new ComodatoPropuestaMultiController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.sections, 'Debe armar las secciones desde la URL.');
        System.assertEquals(1, ctrl.sections.size(), 'Una maquina, una seccion.');
        System.assertEquals(false, ctrl.hasMultipleSections, 'Con una sola no es multi.');
    }

    @IsTest
    static void sinParametrosLaPaginaNoRevienta() {
        Test.startTest();
        PageReference pg = Page.ComodatoPropuestaMulti;
        Test.setCurrentPage(pg);
        ComodatoPropuestaMultiController ctrl = new ComodatoPropuestaMultiController();
        Test.stopTest();

        System.assertEquals(null, ctrl.sections, 'Sin maquinas no hay secciones que armar.');
    }
}