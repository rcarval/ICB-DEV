/**
 * Verifica el blindaje de los productos de las listas de precios protegidas frente a la
 * sincronizacion automatica IsActive <- Visible_For_Sales__c del trigger SyncVisibleAndActive.
 *
 * El caso que motiva estos tests: activar un producto de COMODATO y que un update posterior
 * (por integracion, carga masiva o edicion de otro campo) lo revirtiera a inactivo.
 */
@IsTest
private class ICB_ProductoProtegido_Test {

    private static final String LISTA_PROTEGIDA = 'COMODATO';

    /** Producto con codigo obligatorio, y sin depender de valores de otra org. */
    private static Product2 nuevoProducto(String nombre, String codigo, Boolean visible) {
        return new Product2(
            Name = nombre,
            Codigo__c = codigo,
            IsActive = true,
            Visible_For_Sales__c = visible
        );
    }

    /** Entrada de precio en la lista indicada. Requiere entrada en la estandar primero. */
    private static void agregarAListaDePrecios(Id productoId, Id pricebookId) {
        Id std = Test.getStandardPricebookId();
        insert new PricebookEntry(Pricebook2Id = std, Product2Id = productoId,
                                  UnitPrice = 1000, IsActive = true);
        if (pricebookId != std) {
            insert new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productoId,
                                      UnitPrice = 1000, IsActive = true, UseStandardPrice = false);
        }
    }

    private static Id listaProtegida() {
        List<Pricebook2> pbs = [SELECT Id FROM Pricebook2 WHERE Name = :LISTA_PROTEGIDA LIMIT 1];
        if (!pbs.isEmpty()) {
            return pbs[0].Id;
        }
        Pricebook2 pb = new Pricebook2(Name = LISTA_PROTEGIDA, IsActive = true);
        insert pb;
        return pb.Id;
    }

    @IsTest
    static void productoEnListaProtegida_conservaIsActiveAunqueVisibleSeaFalse() {
        Id pbProtegida = listaProtegida();

        Product2 p = nuevoProducto('Producto Protegido Test', 'PROT-001', false);
        insert p;                       // en insert no hay lista todavia: el trigger lo desactiva
        agregarAListaDePrecios(p.Id, pbProtegida);

        // El equipo lo activa a mano, con Visible_For_Sales__c en false.
        p.IsActive = true;
        Test.startTest();
        update p;
        Test.stopTest();

        Product2 despues = [SELECT IsActive, Visible_For_Sales__c FROM Product2 WHERE Id = :p.Id];
        System.assertEquals(true, despues.IsActive,
            'Un producto de una lista protegida no debe ser desactivado por el trigger.');
        System.assertEquals(false, despues.Visible_For_Sales__c,
            'Visible_For_Sales__c no debe alterarse.');
    }

    @IsTest
    static void productoEnListaProtegida_sobreviveAUpdateDeOtroCampo() {
        Id pbProtegida = listaProtegida();

        Product2 p = nuevoProducto('Producto Protegido Test 2', 'PROT-002', false);
        insert p;
        agregarAListaDePrecios(p.Id, pbProtegida);

        p.IsActive = true;
        update p;

        // Esto es lo que ocurria a diario: un update por otro motivo revertia IsActive.
        Test.startTest();
        p.Description = 'Actualizado por integracion';
        update p;
        Test.stopTest();

        Product2 despues = [SELECT IsActive FROM Product2 WHERE Id = :p.Id];
        System.assertEquals(true, despues.IsActive,
            'Un update por otro motivo no debe revertir IsActive en un producto protegido.');
    }

    @IsTest
    static void productoFueraDeListaProtegida_sigueSincronizando() {
        Product2 p = nuevoProducto('Producto Normal Test', 'NORM-001', false);
        insert p;   // sin lista protegida: el comportamiento original se mantiene

        Test.startTest();
        p.IsActive = true;
        update p;
        Test.stopTest();

        Product2 despues = [SELECT IsActive FROM Product2 WHERE Id = :p.Id];
        System.assertEquals(false, despues.IsActive,
            'Fuera de las listas protegidas el trigger debe seguir sincronizando IsActive.');
    }

    @IsTest
    static void visibleTrue_activaAunqueEsteProtegido() {
        Id pbProtegida = listaProtegida();

        Product2 p = nuevoProducto('Producto Protegido Test 3', 'PROT-003', false);
        insert p;
        agregarAListaDePrecios(p.Id, pbProtegida);

        // Si el negocio marca Visible_For_Sales__c, el equipo puede alinearlo sin estorbo:
        // el blindaje no impide activar, solo impide que un automatismo desactive.
        Test.startTest();
        p.Visible_For_Sales__c = true;
        p.IsActive = true;
        update p;
        Test.stopTest();

        Product2 despues = [SELECT IsActive, Visible_For_Sales__c FROM Product2 WHERE Id = :p.Id];
        System.assertEquals(true, despues.IsActive);
        System.assertEquals(true, despues.Visible_For_Sales__c);
    }

    @IsTest
    static void enMasa_soloSeProtegenLosDeLaLista() {
        Id pbProtegida = listaProtegida();

        List<Product2> prods = new List<Product2>();
        for (Integer i = 0; i < 20; i++) {
            prods.add(nuevoProducto('Masivo ' + i, 'MAS-' + i, false));
        }
        insert prods;

        // Los pares quedan protegidos; los impares no.
        Id std = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Integer i = 0; i < prods.size(); i += 2) {
            pbes.add(new PricebookEntry(Pricebook2Id = std, Product2Id = prods[i].Id,
                                        UnitPrice = 1000, IsActive = true));
        }
        insert pbes;
        List<PricebookEntry> enProtegida = new List<PricebookEntry>();
        for (Integer i = 0; i < prods.size(); i += 2) {
            enProtegida.add(new PricebookEntry(Pricebook2Id = pbProtegida, Product2Id = prods[i].Id,
                                               UnitPrice = 1000, IsActive = true, UseStandardPrice = false));
        }
        insert enProtegida;

        for (Product2 p : prods) {
            p.IsActive = true;
        }

        Test.startTest();
        update prods;   // una sola transaccion, 20 registros: el calculo debe ser bulk-safe
        Test.stopTest();

        Map<Id, Product2> despues = new Map<Id, Product2>(
            [SELECT Id, IsActive FROM Product2 WHERE Id IN :prods]);
        for (Integer i = 0; i < prods.size(); i++) {
            Boolean esperado = (Math.mod(i, 2) == 0);   // protegidos conservan true
            System.assertEquals(esperado, despues.get(prods[i].Id).IsActive,
                'Producto ' + i + (esperado ? ' protegido debia seguir activo.'
                                            : ' no protegido debia desactivarse.'));
        }
    }

    @IsTest
    static void idsEnListasProtegidas_conEntradaVacia_noConsultaNiFalla() {
        Test.startTest();
        Set<Id> vacio = ICB_ProductoProtegido.idsEnListasProtegidas(new Set<Id>());
        Set<Id> nulo = ICB_ProductoProtegido.idsEnListasProtegidas(null);
        Test.stopTest();

        System.assertEquals(0, vacio.size());
        System.assertEquals(0, nulo.size());
    }
}