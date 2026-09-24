/**
 * Verifica el reparador de la lista COMODATO.
 *
 * Caso real: un proceso externo apago las entradas de precio a las 04:00 y el selector del
 * flujo, que consulta PricebookEntry y no Product2, quedo con 1 maquina de 22.
 */
@IsTest
private class ICB_ReactivarEquiposComodatoJob_Test {

    private static Pricebook2 listaProtegida;

    /** Crea el producto y su entrada en la lista indicada, con el IsActive pedido. */
    private static PricebookEntry montar(String nombre, String tipoEquipo,
                                         Boolean productoActivo, Boolean entradaActiva,
                                         Pricebook2 lista) {
        Product2 p = new Product2(
            Name = nombre, Codigo__c = nombre.left(12),
            IsActive = productoActivo, Visible_For_Sales__c = productoActivo,
            Tipo_Equipo__c = tipoEquipo
        );
        insert p;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(),
                                  Product2Id = p.Id, UnitPrice = 1000, IsActive = true);
        PricebookEntry e = new PricebookEntry(
            Pricebook2Id = lista.Id, Product2Id = p.Id,
            UnitPrice = 1000, IsActive = entradaActiva, UseStandardPrice = false
        );
        insert e;
        return e;
    }

    private static Pricebook2 crearLista(String nombre) {
        Pricebook2 pb = new Pricebook2(Name = nombre, IsActive = true);
        insert pb;
        return pb;
    }

    @IsTest
    static void reviveElEquipoApagadoPorElProcesoExterno() {
        Pricebook2 comodato = crearLista('COMODATO');
        PricebookEntry e = montar('MAQUINA APAGADA', 'Máquina Café', true, false, comodato);

        Test.startTest();
        Integer n = ICB_ReactivarEquiposComodatoJob.reactivar();
        Test.stopTest();

        System.assertEquals(1, n, 'Debe reparar la entrada apagada.');
        System.assertEquals(true, [SELECT IsActive FROM PricebookEntry WHERE Id = :e.Id].IsActive,
            'Sin esto el equipo no aparece en el selector del flujo.');
    }

    @IsTest
    static void noRevivaUnEquipoCuyoProductoEstaApagado() {
        Pricebook2 comodato = crearLista('COMODATO');
        PricebookEntry e = montar('MAQUINA DUPLICADA', 'Máquina Café', false, false, comodato);

        Test.startTest();
        ICB_ReactivarEquiposComodatoJob.reactivar();
        Test.stopTest();

        // Producto apagado = duplicado. Revivirlo volveria a ensuciar la lista depurada.
        System.assertEquals(false, [SELECT IsActive FROM PricebookEntry WHERE Id = :e.Id].IsActive,
            'Si el producto esta apagado, la entrada se queda afuera.');
    }

    @IsTest
    static void noTocaLosInsumos() {
        Pricebook2 comodato = crearLista('COMODATO');
        PricebookEntry e = montar('KETCHUP INSUMO', null, true, false, comodato);

        Test.startTest();
        Integer n = ICB_ReactivarEquiposComodatoJob.reactivar();
        Test.stopTest();

        System.assertEquals(0, n, 'Sin Tipo_Equipo__c no es un equipo.');
        System.assertEquals(false, [SELECT IsActive FROM PricebookEntry WHERE Id = :e.Id].IsActive,
            'Los insumos que el equipo depuro a mano deben quedarse apagados.');
    }

    @IsTest
    static void noTocaOtrasListasDePrecio() {
        Pricebook2 otra = crearLista('LISTA CUALQUIERA');
        PricebookEntry e = montar('MAQUINA OTRA LISTA', 'Máquina Café', true, false, otra);

        Test.startTest();
        Integer n = ICB_ReactivarEquiposComodatoJob.reactivar();
        Test.stopTest();

        System.assertEquals(0, n, 'El reparador es solo para las listas administradas a mano.');
        System.assertEquals(false, [SELECT IsActive FROM PricebookEntry WHERE Id = :e.Id].IsActive);
    }

    @IsTest
    static void reparaVariosDeUnaVez() {
        Pricebook2 comodato = crearLista('COMODATO');
        for (Integer i = 0; i < 25; i++) {
            montar('MAQ LOTE ' + i, 'Máquina Café', true, false, comodato);
        }

        Test.startTest();
        Integer n = ICB_ReactivarEquiposComodatoJob.reactivar();
        Test.stopTest();

        System.assertEquals(25, n, 'Debe repararlas todas en un solo update.');
        System.assertEquals(25, [
            SELECT COUNT() FROM PricebookEntry
            WHERE Pricebook2Id = :comodato.Id AND IsActive = true
        ]);
    }

    @IsTest
    static void seEjecutaComoJobProgramado() {
        Pricebook2 comodato = crearLista('COMODATO');
        PricebookEntry e = montar('MAQUINA AGENDADA', 'Máquina Café', true, false, comodato);

        Test.startTest();
        String jobId = System.schedule('Test reactivar COMODATO', '0 0 5 * * ?',
                                       new ICB_ReactivarEquiposComodatoJob());
        Test.stopTest();   // al cerrar, el job corre

        System.assertNotEquals(null, jobId, 'Debe poder programarse.');
        System.assertEquals(true, [SELECT IsActive FROM PricebookEntry WHERE Id = :e.Id].IsActive,
            'Al correr el job programado la entrada queda activa.');
    }
}