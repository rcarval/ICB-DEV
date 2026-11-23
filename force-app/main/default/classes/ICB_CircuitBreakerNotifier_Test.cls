@IsTest
public class ICB_CircuitBreakerNotifier_Test {

    @IsTest
    static void testEnviaCorreoConDestinatariosConfigurados() {
        Circuit_Breaker__c cb = new Circuit_Breaker__c(
            Name = 'NotifTest',
            Nombre_Proceso__c = 'NotifTest',
            Activo__c = true,
            Umbral_Intentos__c = 20,
            Ventana_Segundos__c = 1,
            Enfriamiento_Minutos__c = 15,
            Estado__c = 'Abierto',
            Contador_Ventana__c = 25,
            Fecha_Apertura__c = Datetime.now(),
            Destinatarios_Correo__c = 'uno@test.com; dos@test.com'
        );
        insert cb;

        Test.startTest();
        Integer antes = Limits.getEmailInvocations();
        ICB_CircuitBreakerNotifier.enviarAlertaApertura(cb);
        Integer despues = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, despues - antes, 'Debe invocar Messaging.sendEmail exactamente una vez');
    }

    @IsTest
    static void testSinDestinatariosNoLanzaExcepcionNiEnviaCorreo() {
        Circuit_Breaker__c cb = new Circuit_Breaker__c(
            Name = 'NotifSinDest',
            Nombre_Proceso__c = 'NotifSinDest',
            Activo__c = true,
            Umbral_Intentos__c = 20,
            Ventana_Segundos__c = 1,
            Enfriamiento_Minutos__c = 15,
            Estado__c = 'Abierto',
            Contador_Ventana__c = 25,
            Fecha_Apertura__c = Datetime.now(),
            Destinatarios_Correo__c = null
        );
        insert cb;

        Test.startTest();
        Integer antes = Limits.getEmailInvocations();
        try {
            ICB_CircuitBreakerNotifier.enviarAlertaApertura(cb);
        } catch (Exception e) {
            System.assert(false, 'No debe lanzar excepcion sin destinatarios configurados: ' + e.getMessage());
        }
        Integer despues = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(0, despues - antes, 'Sin destinatarios no debe invocar Messaging.sendEmail');
    }

    @IsTest
    static void testBreakerNuloNoLanzaExcepcion() {
        Test.startTest();
        try {
            ICB_CircuitBreakerNotifier.enviarAlertaApertura(null);
        } catch (Exception e) {
            System.assert(false, 'No debe lanzar excepcion con breaker nulo: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testParsearDestinatarios() {
        List<String> resultado = ICB_CircuitBreakerNotifier.parsearDestinatarios('uno@test.com; dos@test.com,  ,tres@test.com ');
        System.assertEquals(3, resultado.size());
        System.assertEquals('uno@test.com', resultado[0]);
        System.assertEquals('dos@test.com', resultado[1]);
        System.assertEquals('tres@test.com', resultado[2]);
    }

    @IsTest
    static void testParsearDestinatariosVacio() {
        List<String> resultado = ICB_CircuitBreakerNotifier.parsearDestinatarios(null);
        System.assertEquals(0, resultado.size());
    }
}