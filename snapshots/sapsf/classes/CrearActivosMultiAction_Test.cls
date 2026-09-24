/**
 * Verifica la accion que crea los activos al firmar el contrato de comodato.
 *
 * El caso que motiva estos tests: el flujo Automatizacion_Comodato_Firmado asignaba la
 * coleccion assetIds a Opportunity.Activo_Asignado__c, que es un campo Buscar de un solo
 * valor. Con una cotizacion de 6 maquinas el guardado fallaba con
 * INVALID_TYPE_ON_FIELD_IN_RECORD y el contrato no se podia dejar firmado.
 */
@IsTest
private class CrearActivosMultiAction_Test {

    /** Oportunidad con productos de maquina y las cantidades pedidas. */
    private static Id montarOportunidad(List<Integer> cantidades, String tipoEquipo) {
        Account cta = new Account(Name = 'CLIENTE TEST COMODATO');
        insert cta;

        List<Product2> prods = new List<Product2>();
        for (Integer i = 0; i < cantidades.size(); i++) {
            prods.add(new Product2(
                Name = 'MAQUINA TEST ' + i, Codigo__c = 'MT-' + i,
                IsActive = true, Visible_For_Sales__c = true, Tipo_Equipo__c = tipoEquipo
            ));
        }
        insert prods;

        Id std = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 p : prods) {
            pbes.add(new PricebookEntry(Pricebook2Id = std, Product2Id = p.Id,
                                        UnitPrice = 1000, IsActive = true));
        }
        insert pbes;

        Opportunity opp = new Opportunity(
            Name = 'OPP TEST COMODATO', AccountId = cta.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30),
            Pricebook2Id = std
        );
        insert opp;

        List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
        for (Integer i = 0; i < prods.size(); i++) {
            olis.add(new OpportunityLineItem(
                OpportunityId = opp.Id, PricebookEntryId = pbes[i].Id,
                Quantity = cantidades[i], UnitPrice = 1000
            ));
        }
        insert olis;
        return opp.Id;
    }

    private static CrearActivosMultiAction.Output ejecutar(Id oppId) {
        Account cta = [SELECT Id FROM Account WHERE Name = 'CLIENTE TEST COMODATO' LIMIT 1];
        CrearActivosMultiAction.Input inp = new CrearActivosMultiAction.Input();
        inp.opportunityId = oppId;
        inp.accountId = cta.Id;
        return CrearActivosMultiAction.crearActivos(
            new List<CrearActivosMultiAction.Input>{ inp })[0];
    }

    @IsTest
    static void conVariasMaquinasDevuelveUnPrimerActivoUnico() {
        Id oppId = montarOportunidad(new List<Integer>{ 2, 3, 1 }, 'Máquina Café');

        Test.startTest();
        CrearActivosMultiAction.Output out = ejecutar(oppId);
        Test.stopTest();

        System.assertEquals(true, out.success, 'Debe completar: ' + out.errorMessage);
        // Un activo por equipo, no por unidad: 3 equipos aunque sumen 6 unidades.
        System.assertEquals(3, out.assetIds.size(), 'Tres equipos, tres activos.');
        System.assertEquals(3, out.cantidadActivos);
        // Las unidades no se pierden: viajan en Quantity, no en la cantidad de activos.
        Decimal unidades = 0;
        for (Asset a : [SELECT Quantity FROM Asset WHERE Id IN :out.assetIds]) {
            System.assertNotEquals(null, a.Quantity, 'Cada activo debe llevar su cantidad.');
            unidades += a.Quantity;
        }
        System.assertEquals(6, unidades, 'Las 6 unidades quedan repartidas en los 3 activos.');
        // Sin esto el flujo intentaba meter 6 Ids en un campo Buscar y el guardado fallaba.
        System.assertNotEquals(null, out.primerAssetId, 'Debe exponer un solo Id.');
        System.assertEquals(out.assetIds[0], out.primerAssetId,
            'El primer activo es el mismo que ya se usa para Contract.Activo__c.');
    }

    @IsTest
    static void elPrimerActivoSirveParaUnCampoDeBusqueda() {
        Id oppId = montarOportunidad(new List<Integer>{ 4 }, 'Máquina Café');   // 1 equipo, 4 unidades

        Test.startTest();
        CrearActivosMultiAction.Output out = ejecutar(oppId);
        // Es exactamente lo que hace Final_Update_Opp en el flujo.
        update new Opportunity(Id = oppId, Activo_Asignado__c = out.primerAssetId);
        Test.stopTest();

        System.assertEquals(out.primerAssetId,
            [SELECT Activo_Asignado__c FROM Opportunity WHERE Id = :oppId].Activo_Asignado__c,
            'El campo Buscar debe aceptar el valor sin error de tipo.');
    }

    @IsTest
    static void tambienFuncionaConDispensadores() {
        Id oppId = montarOportunidad(new List<Integer>{ 1, 1 }, 'Dispensador');

        Test.startTest();
        CrearActivosMultiAction.Output out = ejecutar(oppId);
        Test.stopTest();

        System.assertEquals(2, out.assetIds.size(), 'Los dispensadores tambien generan activos.');
        System.assertNotEquals(null, out.contractId, 'Y su contrato.');
    }

    @IsTest
    static void sinPartidasNoCreaNadaNiRevienta() {
        Account cta = new Account(Name = 'CLIENTE TEST COMODATO');
        insert cta;
        Opportunity opp = new Opportunity(
            Name = 'OPP VACIA', AccountId = cta.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Test.startTest();
        CrearActivosMultiAction.Output out = ejecutar(opp.Id);
        Test.stopTest();

        System.assertEquals(true, out.success, 'No debe fallar: ' + out.errorMessage);
        System.assertEquals(0, out.assetIds.size());
        System.assertEquals(0, out.cantidadActivos);
        System.assertEquals(null, out.primerAssetId,
            'Sin activos el campo Buscar queda vacio, no en un valor inventado.');
    }
}