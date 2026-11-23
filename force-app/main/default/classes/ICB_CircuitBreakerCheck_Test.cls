@IsTest
public class ICB_CircuitBreakerCheck_Test {

    @IsTest
    static void testBulkConProcesosMixtosYNombreVacio() {
        insert new Circuit_Breaker__c(
            Name = 'P1', Nombre_Proceso__c = 'P1', Activo__c = true,
            Umbral_Intentos__c = 20, Ventana_Segundos__c = 1, Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado', Contador_Ventana__c = 0, Destinatarios_Correo__c = 'a@test.com'
        );
        insert new Circuit_Breaker__c(
            Name = 'P2', Nombre_Proceso__c = 'P2', Activo__c = false,
            Umbral_Intentos__c = 20, Ventana_Segundos__c = 1, Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado', Contador_Ventana__c = 0
        );

        List<ICB_CircuitBreakerCheck.Request> requests = new List<ICB_CircuitBreakerCheck.Request>();

        ICB_CircuitBreakerCheck.Request r1 = new ICB_CircuitBreakerCheck.Request();
        r1.nombreProceso = 'P1';
        requests.add(r1);

        ICB_CircuitBreakerCheck.Request r2 = new ICB_CircuitBreakerCheck.Request();
        r2.nombreProceso = 'P2';
        requests.add(r2);

        ICB_CircuitBreakerCheck.Request r3 = new ICB_CircuitBreakerCheck.Request();
        r3.nombreProceso = null;
        requests.add(r3);

        Test.startTest();
        List<ICB_CircuitBreakerCheck.Response> respuestas = ICB_CircuitBreakerCheck.verificar(requests);
        Test.stopTest();

        System.assertEquals(3, respuestas.size(), 'Debe devolver una Response por cada Request, en el mismo orden');
        System.assertEquals(true, respuestas[0].permitirContinuar, 'P1 activo bajo umbral debe permitir');
        System.assertEquals(true, respuestas[1].permitirContinuar, 'P2 inactivo (kill switch) debe permitir sin contar');
        System.assertEquals(false, respuestas[2].permitirContinuar, 'Nombre de proceso vacio debe bloquear por seguridad');
    }

    @IsTest
    static void testRegistraLogAlBloquearSinLanzarExcepcion() {
        insert new Circuit_Breaker__c(
            Name = 'P3', Nombre_Proceso__c = 'P3', Activo__c = true,
            Umbral_Intentos__c = 1, Ventana_Segundos__c = 60, Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado', Contador_Ventana__c = 5, Inicio_Ventana__c = Datetime.now(),
            Destinatarios_Correo__c = 'a@test.com'
        );

        ICB_CircuitBreakerCheck.Request r1 = new ICB_CircuitBreakerCheck.Request();
        r1.nombreProceso = 'P3';
        r1.registroId = null;

        Test.startTest();
        List<ICB_CircuitBreakerCheck.Response> respuestas =
            ICB_CircuitBreakerCheck.verificar(new List<ICB_CircuitBreakerCheck.Request>{ r1 });
        Test.stopTest();

        System.assertEquals(1, respuestas.size());
        System.assertEquals(false, respuestas[0].permitirContinuar, 'Debe bloquear al superar el umbral (5+1 > 1)');
        System.assertEquals('Abierto', respuestas[0].estadoBreaker);
    }

    @IsTest
    static void testConAccountIdRealComoRegistroId() {
        Account acc = new Account(Name = 'Cuenta Test Circuit Breaker');
        insert acc;

        insert new Circuit_Breaker__c(
            Name = 'P4', Nombre_Proceso__c = 'P4', Activo__c = true,
            Umbral_Intentos__c = 20, Ventana_Segundos__c = 1, Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado', Contador_Ventana__c = 0, Destinatarios_Correo__c = 'a@test.com'
        );

        ICB_CircuitBreakerCheck.Request r1 = new ICB_CircuitBreakerCheck.Request();
        r1.nombreProceso = 'P4';
        r1.registroId = acc.Id;

        Test.startTest();
        List<ICB_CircuitBreakerCheck.Response> respuestas =
            ICB_CircuitBreakerCheck.verificar(new List<ICB_CircuitBreakerCheck.Request>{ r1 });
        Test.stopTest();

        System.assertEquals(true, respuestas[0].permitirContinuar);
    }

    @IsTest
    static void testBypassDeIntegracionPermiteTodo() {
        ICB_CircuitBreakerCheck.Request req = new ICB_CircuitBreakerCheck.Request();
        req.nombreProceso = 'Update_Cliente_Full_Cliente_SAP';

        ICB_CircuitBreakerService.bypassUsuarioForzado = true;
        List<ICB_CircuitBreakerCheck.Response> respuestas;
        try {
            Test.startTest();
            respuestas = ICB_CircuitBreakerCheck.verificar(
                new List<ICB_CircuitBreakerCheck.Request>{ req });
            Test.stopTest();
        } finally {
            ICB_CircuitBreakerService.bypassUsuarioForzado = null;
        }

        System.assertEquals(1, respuestas.size());
        System.assertEquals(true, respuestas[0].permitirContinuar,
            'Con bypass de usuario el invocable debe dejar continuar siempre');
    }

}