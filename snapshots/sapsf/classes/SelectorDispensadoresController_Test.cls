/**
 * Verifica que el selector de dispensadores devuelva los equipos con sus lineas de comodato
 * ya resueltas y separadas por tipo, que es lo que permite mostrar el vinculo
 * dispensador -> insumo y buscar por insumo en pantalla.
 */
@IsTest
private class SelectorDispensadoresController_Test {

    private static Product2 crearProducto(String nombre, String codigo, String tipoEquipo) {
        return new Product2(
            Name = nombre,
            Codigo__c = codigo,
            IsActive = true,
            Visible_For_Sales__c = true,   // el trigger sincroniza IsActive con este campo
            Tipo_Equipo__c = tipoEquipo
        );
    }

    private static Id crearListaDePrecios(List<Product2> productos) {
        Id std = Test.getStandardPricebookId();
        Pricebook2 pb = new Pricebook2(Name = 'Lista Test Dispensadores', IsActive = true);
        insert pb;

        List<PricebookEntry> enStd = new List<PricebookEntry>();
        for (Product2 p : productos) {
            enStd.add(new PricebookEntry(Pricebook2Id = std, Product2Id = p.Id,
                                         UnitPrice = 1000, IsActive = true));
        }
        insert enStd;

        List<PricebookEntry> enPb = new List<PricebookEntry>();
        for (Product2 p : productos) {
            enPb.add(new PricebookEntry(Pricebook2Id = pb.Id, Product2Id = p.Id,
                                        UnitPrice = 1000, IsActive = true, UseStandardPrice = false));
        }
        insert enPb;
        return pb.Id;
    }

    @IsTest
    static void devuelveDispensadorConSusLineasSeparadasPorTipo() {
        Product2 disp = crearProducto('DISPENSADOR DE SALSAS TEST', 'DSP-001', 'Dispensador');
        Product2 ketchup = crearProducto('KETCHUP TEST 1 kg', 'INS-KET', null);
        Product2 servilleta = crearProducto('SERVILLETAS TEST', 'APO-SER', null);
        Product2 instalacion = crearProducto('INSTALACION TEST', 'SRV-INS', null);
        insert new List<Product2>{ disp, ketchup, servilleta, instalacion };

        insert new List<Comodato__c>{
            new Comodato__c(Maquina__c = disp.Id, Producto_Asociado__c = ketchup.Id,
                            Tipo_de_Asociacion__c = 'Insumo Mensual',
                            Cantidad_Minima_Mensual__c = 20, Unidad_de_Medida__c = 'Kilos',
                            Precio_Unitario_Neto__c = 8500),
            new Comodato__c(Maquina__c = disp.Id, Producto_Asociado__c = servilleta.Id,
                            Tipo_de_Asociacion__c = 'Aporte de Marca', Cantidad_Aporte__c = 6),
            new Comodato__c(Maquina__c = disp.Id, Producto_Asociado__c = instalacion.Id,
                            Tipo_de_Asociacion__c = 'Servicio')
        };

        Id pbId = crearListaDePrecios(new List<Product2>{ disp });

        Test.startTest();
        List<SelectorDispensadoresController.DispensadorDto> r =
            SelectorDispensadoresController.obtenerDispensadores(pbId);
        Test.stopTest();

        System.assertEquals(1, r.size(), 'Debe devolver el dispensador de la lista de precios.');
        SelectorDispensadoresController.DispensadorDto d = r[0];
        System.assertEquals('DISPENSADOR DE SALSAS TEST', d.nombre);
        System.assertEquals(1, d.insumos.size(), 'El insumo mensual va en su propia lista.');
        System.assertEquals(1, d.aportes.size(), 'El aporte de marca va en su propia lista.');
        System.assertEquals(1, d.servicios.size(), 'El servicio va en su propia lista.');
        System.assertEquals(true, d.configurado, 'Con un insumo mensual el equipo es proponible.');

        System.assertEquals(20, d.insumos[0].cantidad, 'La cantidad del insumo sale de la mensual.');
        System.assertEquals(6, d.aportes[0].cantidad,
            'En un aporte de marca la cantidad debe salir de Cantidad_Aporte__c, no de la mensual.');
    }

    @IsTest
    static void elTextoDeBusquedaIncluyeLosInsumos() {
        Product2 disp = crearProducto('DISPENSADOR TEST BUSQUEDA', 'DSP-002', 'Dispensador');
        Product2 mayo = crearProducto('MAYONESA TEST 1 kg', 'INS-MAY', null);
        insert new List<Product2>{ disp, mayo };
        insert new Comodato__c(Maquina__c = disp.Id, Producto_Asociado__c = mayo.Id,
                               Tipo_de_Asociacion__c = 'Insumo Mensual',
                               Cantidad_Minima_Mensual__c = 10, Unidad_de_Medida__c = 'Kilos');
        Id pbId = crearListaDePrecios(new List<Product2>{ disp });

        Test.startTest();
        List<SelectorDispensadoresController.DispensadorDto> r =
            SelectorDispensadoresController.obtenerDispensadores(pbId);
        Test.stopTest();

        System.assertEquals(1, r.size());
        System.assert(r[0].textoBusqueda.contains('mayonesa'),
            'Buscar por insumo es el caso de uso central: el texto debe incluirlos.');
        System.assert(r[0].textoBusqueda.contains('dispensador test busqueda'),
            'Tambien debe permitir buscar por el nombre del equipo.');
    }

    @IsTest
    static void dispensadorSinConfiguracionSeDevuelveMarcado() {
        Product2 disp = crearProducto('DISPENSADOR SIN CONFIG TEST', 'DSP-003', 'Dispensador');
        insert disp;
        Id pbId = crearListaDePrecios(new List<Product2>{ disp });

        Test.startTest();
        List<SelectorDispensadoresController.DispensadorDto> r =
            SelectorDispensadoresController.obtenerDispensadores(pbId);
        Test.stopTest();

        System.assertEquals(1, r.size(), 'No debe ocultarse: la pantalla lo muestra como no disponible.');
        System.assertEquals(false, r[0].configurado);
        System.assertEquals(0, r[0].insumos.size());
    }

    @IsTest
    static void noDevuelveMaquinasDeCafe() {
        Product2 cafe = crearProducto('MAQUINA CAFE TEST', 'MAQ-CAF', 'Máquina Café');
        Product2 disp = crearProducto('DISPENSADOR TEST MIXTO', 'DSP-004', 'Dispensador');
        insert new List<Product2>{ cafe, disp };
        Id pbId = crearListaDePrecios(new List<Product2>{ cafe, disp });

        Test.startTest();
        List<SelectorDispensadoresController.DispensadorDto> r =
            SelectorDispensadoresController.obtenerDispensadores(pbId);
        Test.stopTest();

        System.assertEquals(1, r.size(), 'El selector de dispensadores no debe traer maquinas de cafe.');
        System.assertEquals('DISPENSADOR TEST MIXTO', r[0].nombre);
    }

    @IsTest
    static void sinListaDePreciosDevuelveTodosLosDispensadoresActivos() {
        Product2 disp = crearProducto('DISPENSADOR SIN LISTA TEST', 'DSP-005', 'Dispensador');
        insert disp;

        Test.startTest();
        List<SelectorDispensadoresController.DispensadorDto> r =
            SelectorDispensadoresController.obtenerDispensadores(null);
        Test.stopTest();

        Boolean encontrado = false;
        for (SelectorDispensadoresController.DispensadorDto d : r) {
            if (d.nombre == 'DISPENSADOR SIN LISTA TEST') encontrado = true;
        }
        System.assert(encontrado, 'Sin lista de precios no debe dejar la pantalla en blanco.');
    }

    @IsTest
    static void variosDispensadoresEnUnaSolaConsulta() {
        List<Product2> disps = new List<Product2>();
        for (Integer i = 0; i < 10; i++) {
            disps.add(crearProducto('DISPENSADOR MASIVO ' + i, 'DSP-M' + i, 'Dispensador'));
        }
        Product2 insumo = crearProducto('INSUMO MASIVO TEST', 'INS-MAS', null);
        List<Product2> todos = new List<Product2>(disps);
        todos.add(insumo);
        insert todos;

        List<Comodato__c> cfgs = new List<Comodato__c>();
        for (Product2 d : disps) {
            cfgs.add(new Comodato__c(Maquina__c = d.Id, Producto_Asociado__c = insumo.Id,
                                     Tipo_de_Asociacion__c = 'Insumo Mensual',
                                     Cantidad_Minima_Mensual__c = 5, Unidad_de_Medida__c = 'Kilos'));
        }
        insert cfgs;
        Id pbId = crearListaDePrecios(disps);

        Test.startTest();
        List<SelectorDispensadoresController.DispensadorDto> r =
            SelectorDispensadoresController.obtenerDispensadores(pbId);
        Test.stopTest();

        System.assertEquals(10, r.size());
        for (SelectorDispensadoresController.DispensadorDto d : r) {
            System.assertEquals(1, d.insumos.size(), d.nombre + ' debia traer su insumo resuelto.');
        }
        System.assert(Limits.getQueries() < 10,
            'Las lineas deben resolverse en una sola consulta, no por dispensador.');
    }
}