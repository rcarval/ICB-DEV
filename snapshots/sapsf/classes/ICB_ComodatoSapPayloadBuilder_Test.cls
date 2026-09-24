/**
 * Verifica el armado del payload de comodato para SAP.
 *
 * El caso que motiva estos tests: el envio fallaba con "Product2.Precio_de_Lista__c vacio para
 * la maquina ...". Ese campo esta vacio en 27 de los 31 equipos activos, mientras el valor real
 * vive en la lista de precios COMODATO. Ahora la lista es la fuente y el campo es respaldo.
 */
@IsTest
private class ICB_ComodatoSapPayloadBuilder_Test {

    private static final String LISTA = 'COMODATO';

    private static Pricebook2 comodato;
    private static Product2 maquina;
    private static Product2 insumo;

    /**
     * Monta el escenario completo que el builder exige: cuenta con codigos SAP, oportunidad,
     * cotizacion con la maquina y su insumo, configuracion Comodato__c y contrato firmado.
     *
     * @param precioEnLista precio de la maquina en la lista COMODATO; null para no crear entrada.
     * @param precioEnCampo valor de Product2.Precio_de_Lista__c; null para dejarlo vacio.
     */
    private static Contrato_Digital__c montar(Decimal precioEnLista, Decimal precioEnCampo) {
        Account cta = new Account(
            Name = 'CLIENTE SAP TEST',
            C_digo_de_cliente__c = '1000123',
            Cliente_Despacho__c = '1000123',
            // El flow FlowBeforeAPI_Insert calcula Sucursal__c a partir de SucursalAuxiliar__c y
            // sobrescribe lo que se mande. Sin el codigo auxiliar deja "Codigo de sucursal
            // desconocido", que no es valor valido de la picklist, y el insert falla.
            SucursalAuxiliar__c = 'S001',
            Sucursal__c = 'S001 - Suc Santiago'
        );
        insert cta;

        maquina = new Product2(Name = 'MAQUINA SAP TEST', Codigo__c = '40002159',
                               IsActive = true, Visible_For_Sales__c = true,
                               Tipo_Equipo__c = 'Máquina Café',
                               Precio_de_Lista__c = precioEnCampo);
        insumo = new Product2(Name = 'CAPSULA SAP TEST', Codigo__c = 'INS-SAP-1',
                              IsActive = true, Visible_For_Sales__c = true);
        insert new List<Product2>{ maquina, insumo };

        insert new Comodato__c(
            Maquina__c = maquina.Id, Producto_Asociado__c = insumo.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 5, Unidad_de_Medida__c = 'Unidades',
            Precio_Unitario_Neto__c = 8000
        );

        Id std = Test.getStandardPricebookId();
        List<PricebookEntry> enStd = new List<PricebookEntry>();
        for (Product2 p : new List<Product2>{ maquina, insumo }) {
            enStd.add(new PricebookEntry(Pricebook2Id = std, Product2Id = p.Id,
                                         UnitPrice = 1000, IsActive = true));
        }
        insert enStd;

        comodato = new Pricebook2(Name = LISTA, IsActive = true);
        insert comodato;
        if (precioEnLista != null) {
            insert new PricebookEntry(Pricebook2Id = comodato.Id, Product2Id = maquina.Id,
                                      UnitPrice = precioEnLista, IsActive = true,
                                      UseStandardPrice = false);
        }

        Opportunity opp = new Opportunity(
            Name = 'OPP SAP TEST', AccountId = cta.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), Pricebook2Id = std
        );
        insert opp;

        Quote q = new Quote(Name = 'QUOTE SAP TEST', OpportunityId = opp.Id, Pricebook2Id = std);
        insert q;
        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[0].Id,
                              Quantity = 1, UnitPrice = 0),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[1].Id,
                              Quantity = 24, UnitPrice = 8000)
        };

        Contrato_Digital__c cd = new Contrato_Digital__c(
            Presupuesto__c = q.Id,
            Oportunidad__c = opp.Id,
            Contrato_ID__c = 'FD-00000619',
            Fecha_Firma__c = System.now(),
            PDF_Firmado_URL__c = 's3://icbfs-documents/signed/FD-00000619/test.pdf'
        );
        insert cd;
        return cd;
    }

    @IsTest
    static void elValorSaleDeLaListaComodato() {
        Contrato_Digital__c cd = montar(210000, null);   // como en el org: campo vacio

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        List<Object> detalle = (List<Object>) payload.get('AfComodatoDetSet');
        System.assertNotEquals(null, detalle, 'Debe traer el detalle (AfComodatoDetSet).');
        Map<String, Object> lineaMaquina = null;
        for (Object o : detalle) {
            Map<String, Object> m = (Map<String, Object>) o;
            if (m.get('TipoSku') == 'Maquinas') lineaMaquina = m;
        }
        System.assertNotEquals(null, lineaMaquina, 'Debe existir la linea de la maquina.');
        System.assertEquals('210000', lineaMaquina.get('Valor'),
            'El valor debe salir del precio de la lista COMODATO.');
    }

    @IsTest
    static void siLaListaNoTienePrecioUsaElCampoComoRespaldo() {
        Contrato_Digital__c cd = montar(null, 178000);

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        for (Object o : (List<Object>) payload.get('AfComodatoDetSet')) {
            Map<String, Object> m = (Map<String, Object>) o;
            if (m.get('TipoSku') == 'Maquinas') {
                System.assertEquals('178000', m.get('Valor'),
                    'Sin entrada en la lista debe caer a Product2.Precio_de_Lista__c.');
            }
        }
    }

    @IsTest
    static void sinValorEnNingunaParteAvisaConElNombreDelEquipo() {
        Contrato_Digital__c cd = montar(null, null);

        Test.startTest();
        String error = '';
        try {
            ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        } catch (ICB_ComodatoSapPayloadBuilder.ValidationException e) {
            error = e.getMessage();
        }
        Test.stopTest();

        System.assert(error.contains('MAQUINA SAP TEST'),
            'El mensaje debe nombrar el equipo para poder cargarle el precio. Fue: ' + error);
        System.assert(error.contains('COMODATO'), 'Y decir donde falta el dato.');
    }

    @IsTest
    static void unPrecioEnCeroNoCuentaComoValor() {
        // Es el estado real de 51 de las 52 maquinas de la lista: entrada activa, precio 0.
        Contrato_Digital__c cd = montar(0, null);

        Test.startTest();
        Boolean fallo = false;
        try {
            ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        } catch (ICB_ComodatoSapPayloadBuilder.ValidationException e) {
            fallo = true;
        }
        Test.stopTest();

        System.assertEquals(true, fallo, 'Mandar 0 a SAP seria peor que avisar que falta el dato.');
    }

    @IsTest
    static void elInsumoViajaConSuCantidadMinima() {
        Contrato_Digital__c cd = montar(210000, null);

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        Boolean hayInsumo = false;
        for (Object o : (List<Object>) payload.get('AfComodatoDetSet')) {
            Map<String, Object> m = (Map<String, Object>) o;
            if (m.get('Matnr') == 'INS-SAP-1') {
                hayInsumo = true;
                // Va con decimales porque el builder serializa el Decimal tal cual.
                System.assertEquals('5.00', m.get('Cantidad'),
                    'La cantidad del insumo es el compromiso mensual, no la de la cotizacion.');
            }
        }
        System.assertEquals(true, hayInsumo, 'El insumo debe ir en el payload.');
    }

    @IsTest
    static void sinContratoFirmadoNoSeArmaElPayload() {
        Contrato_Digital__c cd = montar(210000, null);
        cd.Fecha_Firma__c = null;
        update cd;

        Test.startTest();
        Boolean fallo = false;
        try {
            ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        } catch (ICB_ComodatoSapPayloadBuilder.ValidationException e) {
            fallo = true;
        }
        Test.stopTest();

        System.assertEquals(true, fallo, 'No se puede informar a SAP antes de la firma.');
    }

    // ═══════════════════════════════════════════════════════
    // Consolidacion: SAP identifica cada linea por TipoSku + Matnr, sin la maquina
    // ═══════════════════════════════════════════════════════

    /**
     * Dos maquinas del mismo modelo que comparten insumo y aporte. Es el caso que hacia que
     * SAP se quedara solo con la ultima linea recibida.
     *
     * @param uomSegundaMaquina unidad del insumo en la segunda maquina; distinta fuerza el aviso.
     */
    private static Contrato_Digital__c montarDosMaquinas(String uomSegundaMaquina) {
        Account cta = new Account(
            Name = 'CLIENTE SAP TEST', C_digo_de_cliente__c = '1000123',
            Cliente_Despacho__c = '1000123',
            SucursalAuxiliar__c = 'S001', Sucursal__c = 'S001 - Suc Santiago'
        );
        insert cta;

        Product2 m1 = new Product2(Name = 'MAQUINA A', Codigo__c = 'MAQ-A', IsActive = true,
                                   Visible_For_Sales__c = true, Tipo_Equipo__c = 'Máquina Café');
        Product2 m2 = new Product2(Name = 'MAQUINA B', Codigo__c = 'MAQ-B', IsActive = true,
                                   Visible_For_Sales__c = true, Tipo_Equipo__c = 'Máquina Café');
        Product2 ins = new Product2(Name = 'CAPSULA COMPARTIDA', Codigo__c = 'INS-COMP',
                                    IsActive = true, Visible_For_Sales__c = true);
        Product2 apo = new Product2(Name = 'TAZAS COMPARTIDAS', Codigo__c = 'APO-COMP',
                                    IsActive = true, Visible_For_Sales__c = true);
        insert new List<Product2>{ m1, m2, ins, apo };

        insert new List<Comodato__c>{
            new Comodato__c(Maquina__c = m1.Id, Producto_Asociado__c = ins.Id,
                            Tipo_de_Asociacion__c = 'Insumo Mensual',
                            Cantidad_Minima_Mensual__c = 12, Unidad_de_Medida__c = 'Unidades',
                            Precio_Unitario_Neto__c = 8000),
            new Comodato__c(Maquina__c = m2.Id, Producto_Asociado__c = ins.Id,
                            Tipo_de_Asociacion__c = 'Insumo Mensual',
                            Cantidad_Minima_Mensual__c = 20,
                            Unidad_de_Medida__c = uomSegundaMaquina,
                            Precio_Unitario_Neto__c = 8000),
            new Comodato__c(Maquina__c = m1.Id, Producto_Asociado__c = apo.Id,
                            Tipo_de_Asociacion__c = 'Aporte de Marca',
                            Cantidad_Aporte__c = 12, Unidad_de_Medida__c = 'Unidades'),
            new Comodato__c(Maquina__c = m2.Id, Producto_Asociado__c = apo.Id,
                            Tipo_de_Asociacion__c = 'Aporte de Marca',
                            Cantidad_Aporte__c = 18, Unidad_de_Medida__c = 'Unidades')
        };

        Id std = Test.getStandardPricebookId();
        List<PricebookEntry> enStd = new List<PricebookEntry>();
        for (Product2 p : new List<Product2>{ m1, m2, ins, apo }) {
            enStd.add(new PricebookEntry(Pricebook2Id = std, Product2Id = p.Id,
                                         UnitPrice = 1000, IsActive = true));
        }
        insert enStd;

        Pricebook2 pb = new Pricebook2(Name = LISTA, IsActive = true);
        insert pb;
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = pb.Id, Product2Id = m1.Id, UnitPrice = 100000,
                               IsActive = true, UseStandardPrice = false),
            new PricebookEntry(Pricebook2Id = pb.Id, Product2Id = m2.Id, UnitPrice = 200000,
                               IsActive = true, UseStandardPrice = false)
        };

        Opportunity opp = new Opportunity(Name = 'OPP DOS MAQ', AccountId = cta.Id,
                                          StageName = 'Prospecting',
                                          CloseDate = Date.today().addDays(30),
                                          Pricebook2Id = std);
        insert opp;
        Quote q = new Quote(Name = 'QUOTE DOS MAQ', OpportunityId = opp.Id, Pricebook2Id = std);
        insert q;
        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[0].Id,
                              Quantity = 3, UnitPrice = 0),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[1].Id,
                              Quantity = 2, UnitPrice = 0),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[2].Id,
                              Quantity = 32, UnitPrice = 8000),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = enStd[3].Id,
                              Quantity = 30, UnitPrice = 1000)
        };

        Contrato_Digital__c cd = new Contrato_Digital__c(
            Presupuesto__c = q.Id, Oportunidad__c = opp.Id,
            Contrato_ID__c = 'FD-00000620', Fecha_Firma__c = System.now(),
            PDF_Firmado_URL__c = 's3://icbfs-documents/signed/FD-00000620/test.pdf'
        );
        insert cd;
        return cd;
    }

    /** Devuelve la unica linea del material pedido, o null si no hay exactamente una. */
    private static Map<String, Object> lineaUnica(Map<String, Object> payload, String matnr) {
        Map<String, Object> encontrada = null;
        Integer veces = 0;
        for (Object o : (List<Object>) payload.get('AfComodatoDetSet')) {
            Map<String, Object> m = (Map<String, Object>) o;
            if (m.get('Matnr') == matnr) { veces++; encontrada = m; }
        }
        System.assertEquals(1, veces,
            'El material ' + matnr + ' debe viajar en una sola linea; SAP no distingue la maquina.');
        return encontrada;
    }

    @IsTest
    static void cadaMaterialViajaEnUnaSolaLinea() {
        Contrato_Digital__c cd = montarDosMaquinas('Unidades');

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        // Sin consolidar iban dos lineas por material y SAP descartaba una.
        lineaUnica(payload, 'INS-COMP');
        lineaUnica(payload, 'APO-COMP');
        lineaUnica(payload, 'MAQ-A');
        lineaUnica(payload, 'MAQ-B');
    }

    @IsTest
    static void lasMaquinasSeSuman() {
        Contrato_Digital__c cd = montarDosMaquinas('Unidades');

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        // Son dos modelos distintos: cada uno conserva su propia cantidad.
        System.assertEquals(3, Decimal.valueOf(String.valueOf(
            lineaUnica(payload, 'MAQ-A').get('Cantidad'))).setScale(0),
            'La maquina A va con sus 3 unidades.');
        System.assertEquals(2, Decimal.valueOf(String.valueOf(
            lineaUnica(payload, 'MAQ-B').get('Cantidad'))).setScale(0),
            'Y la B con sus 2.');
    }

    @IsTest
    static void elInsumoNoSeSumaSeConservaElMayor() {
        Contrato_Digital__c cd = montarDosMaquinas('Unidades');

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        Map<String, Object> linea = lineaUnica(payload, 'INS-COMP');
        // 12 en una maquina y 20 en la otra: no se acumulan, y quedarse en 12 dejaria al
        // contrato por debajo del compromiso de la segunda.
        System.assertEquals(20, Decimal.valueOf(String.valueOf(linea.get('Cantidad'))).setScale(0),
            'El insumo no se suma: queda el compromiso mayor.');
        System.assertEquals(20, Decimal.valueOf(String.valueOf(linea.get('ConsumoMinimo'))).setScale(0),
            'Y el consumo minimo acompana.');
    }

    @IsTest
    static void elAporteNoSeSumaSeConservaElMayor() {
        Contrato_Digital__c cd = montarDosMaquinas('Unidades');

        Test.startTest();
        Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        Test.stopTest();

        System.assertEquals(18, Decimal.valueOf(String.valueOf(
            lineaUnica(payload, 'APO-COMP').get('Cantidad'))).setScale(0),
            'Los aportes son un set por contrato: 12 y 18 no dan 30.');
    }

    @IsTest
    static void dosUnidadesDistintasParaElMismoMaterialSeAvisan() {
        // En PROD hay casos reales: CAFE ENTERO TIERRA SEL figura en Unidades para una maquina
        // y en Kilos para otra. Sumar o comparar eso seria mezclar magnitudes.
        Contrato_Digital__c cd = montarDosMaquinas('Kilos');

        Test.startTest();
        String error = '';
        try {
            ICB_ComodatoSapPayloadBuilder.build(cd.Id);
        } catch (ICB_ComodatoSapPayloadBuilder.ValidationException e) {
            error = e.getMessage();
        }
        Test.stopTest();

        System.assert(error.contains('INS-COMP'),
            'Debe nombrar el material inconsistente. Fue: ' + error);
        System.assert(error.contains('Unidad_de_Medida__c'), 'Y decir donde corregirlo.');
    }
}