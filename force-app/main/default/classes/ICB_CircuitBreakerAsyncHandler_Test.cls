@IsTest
public class ICB_CircuitBreakerAsyncHandler_Test {

    @IsTest
    static void testProcesarIntentosPersisteElConteoReal() {
        insert new Circuit_Breaker__c(
            Name = 'ProcesoAsyncTest', Nombre_Proceso__c = 'ProcesoAsyncTest', Activo__c = true,
            Umbral_Intentos__c = 1, Ventana_Segundos__c = 60, Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado', Contador_Ventana__c = 0, Destinatarios_Correo__c = 'test@icbfs.cl'
        );

        List<Circuit_Breaker_Intento__e> eventos = new List<Circuit_Breaker_Intento__e>{
            new Circuit_Breaker_Intento__e(Nombre_Proceso__c = 'ProcesoAsyncTest', Registro_Id__c = null),
            new Circuit_Breaker_Intento__e(Nombre_Proceso__c = 'ProcesoAsyncTest', Registro_Id__c = null)
        };

        Test.startTest();
        ICB_CircuitBreakerAsyncHandler.procesarIntentos(eventos);
        Test.stopTest();

        Circuit_Breaker__c actualizado = [
            SELECT Estado__c, Contador_Ventana__c
            FROM Circuit_Breaker__c
            WHERE Nombre_Proceso__c = 'ProcesoAsyncTest'
        ];
        System.assertEquals('Abierto', actualizado.Estado__c,
            '2 intentos > umbral 1 procesados por el handler async deben abrir el breaker de forma persistente');
        System.assertEquals(2, actualizado.Contador_Ventana__c.intValue());
    }

    @IsTest
    static void testPublicacionDelPlatformEventLlegaAlTrigger() {
        insert new Circuit_Breaker__c(
            Name = 'ProcesoEventoTest', Nombre_Proceso__c = 'ProcesoEventoTest', Activo__c = true,
            Umbral_Intentos__c = 1, Ventana_Segundos__c = 60, Enfriamiento_Minutos__c = 15,
            Estado__c = 'Cerrado', Contador_Ventana__c = 0, Destinatarios_Correo__c = 'test@icbfs.cl'
        );

        Test.startTest();
        EventBus.publish(new List<Circuit_Breaker_Intento__e>{
            new Circuit_Breaker_Intento__e(Nombre_Proceso__c = 'ProcesoEventoTest', Registro_Id__c = null)
        });
        Test.getEventBus().deliver();
        Test.stopTest();

        Circuit_Breaker__c actualizado = [
            SELECT Contador_Ventana__c
            FROM Circuit_Breaker__c
            WHERE Nombre_Proceso__c = 'ProcesoEventoTest'
        ];
        System.assertEquals(1, actualizado.Contador_Ventana__c.intValue(),
            'El trigger suscriptor debe recibir el evento publicado y llamar al handler');
    }
}