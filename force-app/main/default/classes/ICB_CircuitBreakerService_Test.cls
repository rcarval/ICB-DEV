@IsTest
public class ICB_CircuitBreakerService_Test {

    private static Circuit_Breaker__c crearConfig(String nombre, Boolean activo, Integer umbral, Integer ventanaSeg) {
        Circuit_Breaker__c cb = new Circuit_Breaker__c(
            Name = nombre,
            Nombre_Proceso__c = nombre,
            Activo__c = activo,
            Umbral_Intentos__c = umbral,
            Ventana_Segundos__c = ventanaSeg,
            Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado',
            Contador_Ventana__c = 0,
            Destinatarios_Correo__c = 'test@icbfs.cl'
        );
        insert cb;
        return cb;
    }

    @IsTest
    static void testUnLoteQueSuperaElUmbralSeBloqueaCompleto() {
        crearConfig('ProcesoTest1', true, 20, 60);

        List<String> nombres = new List<String>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 25; i++) {
            nombres.add('ProcesoTest1');
            ids.add(null);
        }

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(nombres, ids);
        Test.stopTest();

        for (Integer i = 0; i < 25; i++) {
            System.assertEquals(false, resultados.get(i).permitirContinuar,
                'Un lote de 25 intentos en una sola llamada (25 > umbral 20) debe bloquearse completo');
        }

        Circuit_Breaker__c actualizado = [
            SELECT Estado__c, Contador_Ventana__c
            FROM Circuit_Breaker__c
            WHERE Nombre_Proceso__c = 'ProcesoTest1'
        ];
        System.assertEquals('Abierto', actualizado.Estado__c);
        System.assertEquals(25, actualizado.Contador_Ventana__c.intValue());
    }

    @IsTest
    static void testDosLotesSucesivosElSegundoAbreElBreaker() {
        crearConfig('ProcesoTest2', true, 20, 60);

        Test.startTest();

        List<String> primerLote = new List<String>();
        List<Id> idsPrimerLote = new List<Id>();
        for (Integer i = 0; i < 15; i++) {
            primerLote.add('ProcesoTest2');
            idsPrimerLote.add(null);
        }
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultadoUno =
            ICB_CircuitBreakerService.evaluarLote(primerLote, idsPrimerLote);

        for (Integer i = 0; i < 15; i++) {
            System.assertEquals(true, resultadoUno.get(i).permitirContinuar, 'Primer lote (15) debe permitirse');
        }

        List<String> segundoLote = new List<String>();
        List<Id> idsSegundoLote = new List<Id>();
        for (Integer i = 0; i < 10; i++) {
            segundoLote.add('ProcesoTest2');
            idsSegundoLote.add(null);
        }
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultadoDos =
            ICB_CircuitBreakerService.evaluarLote(segundoLote, idsSegundoLote);

        Test.stopTest();

        for (Integer i = 0; i < 10; i++) {
            System.assertEquals(false, resultadoDos.get(i).permitirContinuar,
                'Segundo lote debe bloquearse: 15 + 10 = 25 > umbral 20');
        }

        Circuit_Breaker__c actualizado = [
            SELECT Estado__c FROM Circuit_Breaker__c WHERE Nombre_Proceso__c = 'ProcesoTest2'
        ];
        System.assertEquals('Abierto', actualizado.Estado__c);
    }

    @IsTest
    static void testKillSwitchInactivoSiemprePermite() {
        crearConfig('ProcesoTest3', false, 1, 60);

        List<String> nombres = new List<String>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 50; i++) {
            nombres.add('ProcesoTest3');
            ids.add(null);
        }

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(nombres, ids);
        Test.stopTest();

        for (Integer i = 0; i < 50; i++) {
            System.assertEquals(true, resultados.get(i).permitirContinuar,
                'Con Activo__c=false (kill switch) siempre debe permitir, sin importar el volumen');
        }

        Circuit_Breaker__c actualizado = [
            SELECT Contador_Ventana__c FROM Circuit_Breaker__c WHERE Nombre_Proceso__c = 'ProcesoTest3'
        ];
        System.assertEquals(0, actualizado.Contador_Ventana__c.intValue(),
            'El contador no debe modificarse mientras el breaker esta inactivo');
    }

    @IsTest
    static void testAutoCierraTrasEnfriamientoVencido() {
        Circuit_Breaker__c cb = new Circuit_Breaker__c(
            Name = 'ProcesoReset',
            Nombre_Proceso__c = 'ProcesoReset',
            Activo__c = true,
            Umbral_Intentos__c = 20,
            Ventana_Segundos__c = 1,
            Enfriamiento_Minutos__c = 15,
            Estado__c = 'Abierto',
            Contador_Ventana__c = 25,
            Fecha_Apertura__c = Datetime.now().addMinutes(-20),
            Correo_Enviado__c = true,
            Total_Intentos_Bloqueados__c = 10,
            Destinatarios_Correo__c = 'test@icbfs.cl'
        );
        insert cb;

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(new List<String>{ 'ProcesoReset' }, new List<Id>{ null });
        Test.stopTest();

        System.assertEquals(true, resultados.get(0).permitirContinuar,
            'Tras vencer el enfriamiento, un intento unico por debajo del umbral debe permitirse');

        Circuit_Breaker__c actualizado = [
            SELECT Estado__c, Correo_Enviado__c, Total_Intentos_Bloqueados__c
            FROM Circuit_Breaker__c
            WHERE Id = :cb.Id
        ];
        System.assertEquals('Cerrado', actualizado.Estado__c);
        System.assertEquals(false, actualizado.Correo_Enviado__c);
        System.assertEquals(0, actualizado.Total_Intentos_Bloqueados__c.intValue());
    }

    @IsTest
    static void testUnSoloCorreoPorApertura() {
        crearConfig('ProcesoCorreo', true, 5, 60);

        Test.startTest();
        Integer antes = Limits.getEmailInvocations();

        List<String> primerLote = new List<String>();
        List<Id> idsPrimerLote = new List<Id>();
        for (Integer i = 0; i < 6; i++) {
            primerLote.add('ProcesoCorreo');
            idsPrimerLote.add(null);
        }
        ICB_CircuitBreakerService.evaluarLote(primerLote, idsPrimerLote);
        Integer despuesPrimerLote = Limits.getEmailInvocations();

        ICB_CircuitBreakerService.evaluarLote(new List<String>{ 'ProcesoCorreo' }, new List<Id>{ null });
        Integer despuesSegundoLote = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(1, despuesPrimerLote - antes, 'Debe enviarse exactamente 1 correo al abrirse el breaker');
        System.assertEquals(0, despuesSegundoLote - despuesPrimerLote,
            'No debe enviarse un segundo correo mientras el breaker sigue abierto');
    }

    @IsTest
    static void testAutoprovisionaRegistroFaltante() {
        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(new List<String>{ 'ProcesoSinConfigPrevia' }, new List<Id>{ null });
        Test.stopTest();

        System.assertEquals(true, resultados.get(0).permitirContinuar,
            'Sin config previa, el proceso se autoprovisiona inactivo (fail-open)');

        List<Circuit_Breaker__c> creados = [
            SELECT Id, Activo__c FROM Circuit_Breaker__c WHERE Nombre_Proceso__c = 'ProcesoSinConfigPrevia'
        ];
        System.assertEquals(1, creados.size());
        System.assertEquals(false, creados[0].Activo__c);
    }

    @IsTest
    static void testProcesosMixtosEnUnMismoLoteSonIndependientes() {
        crearConfig('ProcesoMixtoA', true, 20, 60);
        crearConfig('ProcesoMixtoB', true, 0, 60);

        List<String> nombres = new List<String>{ 'ProcesoMixtoA', 'ProcesoMixtoB' };
        List<Id> ids = new List<Id>{ null, null };

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(nombres, ids);
        Test.stopTest();

        System.assertEquals(true, resultados.get(0).permitirContinuar, 'ProcesoMixtoA (1 intento, umbral 20) debe permitirse');
        System.assertEquals(false, resultados.get(1).permitirContinuar, 'ProcesoMixtoB (1 intento, umbral 0) debe bloquearse');
    }

    @IsTest
    static void testBypassActivoPermiteSinContarNiFrenar() {
        Circuit_Breaker__c cb = crearConfig('ProcesoBypass', true, 1, 60);
        cb.Bypass_Activo__c = true;
        cb.Bypass_Hasta__c = Datetime.now().addMinutes(30);
        update cb;

        List<String> nombres = new List<String>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 50; i++) {
            nombres.add('ProcesoBypass');
            ids.add(null);
        }

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(nombres, ids);
        Test.stopTest();

        for (Integer i = 0; i < 50; i++) {
            System.assertEquals(true, resultados.get(i).permitirContinuar,
                'Con Bypass_Activo=true debe permitir todo, sin importar el umbral');
        }

        Circuit_Breaker__c actualizado = [
            SELECT Contador_Ventana__c, Estado__c, Bypass_Activo__c FROM Circuit_Breaker__c WHERE Id = :cb.Id
        ];
        System.assertEquals(0, actualizado.Contador_Ventana__c.intValue(),
            'El bypass no debe incrementar el contador de la ventana');
        System.assertEquals('Cerrado', actualizado.Estado__c);
        System.assertEquals(true, actualizado.Bypass_Activo__c, 'El bypass sigue activo, aun no vence');
    }

    @IsTest
    static void testBypassVencidoSeAutodesactivaYVuelveAContar() {
        Circuit_Breaker__c cb = crearConfig('ProcesoBypassVencido', true, 20, 60);
        cb.Bypass_Activo__c = true;
        cb.Bypass_Hasta__c = Datetime.now().addMinutes(-5);
        update cb;

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(new List<String>{ 'ProcesoBypassVencido' }, new List<Id>{ null });
        Test.stopTest();

        System.assertEquals(true, resultados.get(0).permitirContinuar,
            'Un solo intento por debajo del umbral debe permitirse tras vencer el bypass');

        Circuit_Breaker__c actualizado = [
            SELECT Bypass_Activo__c, Bypass_Hasta__c, Contador_Ventana__c
            FROM Circuit_Breaker__c WHERE Id = :cb.Id
        ];
        System.assertEquals(false, actualizado.Bypass_Activo__c, 'El bypass vencido debe autodesactivarse');
        System.assertEquals(null, actualizado.Bypass_Hasta__c);
        System.assertEquals(1, actualizado.Contador_Ventana__c.intValue(),
            'Tras vencer el bypass, debe volver a contar normalmente');
    }

    @IsTest
    static void testNombreProcesoVacioSeBloquea() {
        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(new List<String>{ '' }, new List<Id>{ null });
        Test.stopTest();

        System.assertEquals(false, resultados.get(0).permitirContinuar);
    }

    @IsTest
    static void testLoteDe200RegistrosMismoProcesoSeBloqueaCompletoSinErrorDeLimites() {
        // Tamaño máximo real de una transacción de Record-Triggered Flow en Salesforce.
        crearConfig('ProcesoTest200', true, 20, 60);

        List<String> nombres = new List<String>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 200; i++) {
            nombres.add('ProcesoTest200');
            ids.add(null);
        }

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(nombres, ids);
        Test.stopTest();

        System.assertEquals(200, resultados.size(), 'Debe devolver un resultado por cada uno de los 200 items');
        for (Integer i = 0; i < 200; i++) {
            System.assertEquals(false, resultados.get(i).permitirContinuar,
                'Un lote de 200 (>> umbral 20) debe bloquearse completo, sin excepciones de limites');
        }

        Circuit_Breaker__c actualizado = [
            SELECT Estado__c, Contador_Ventana__c FROM Circuit_Breaker__c WHERE Nombre_Proceso__c = 'ProcesoTest200'
        ];
        System.assertEquals('Abierto', actualizado.Estado__c);
        System.assertEquals(200, actualizado.Contador_Ventana__c.intValue());
    }

    @IsTest
    static void testLoteDe200RegistrosBajoUmbralAltoSePermiteCompleto() {
        // Confirma que un umbral alto (ej. carga legitima grande) no se bloquea de mas.
        crearConfig('ProcesoTest200OK', true, 500, 60);

        List<String> nombres = new List<String>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 200; i++) {
            nombres.add('ProcesoTest200OK');
            ids.add(null);
        }

        Test.startTest();
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLote(nombres, ids);
        Test.stopTest();

        for (Integer i = 0; i < 200; i++) {
            System.assertEquals(true, resultados.get(i).permitirContinuar,
                'Un lote de 200 con umbral 500 debe permitirse completo');
        }
    }

    @IsTest
    static void testUsuarioSinCustomPermissionNoTieneBypass() {
        // El usuario que corre los tests no tiene Bypass_Control_Flujos_SAP asignado,
        // asi que ejercita la rama real de FeatureManagement.checkPermission.
        System.assertEquals(false, ICB_CircuitBreakerService.usuarioTieneBypass(),
            'Sin el custom permission no debe haber bypass');
    }

}