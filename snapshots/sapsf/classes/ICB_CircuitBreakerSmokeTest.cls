/**********************************************************************************
 * ICB_CircuitBreakerSmokeTest
 * Utilidad de validacion manual (no es un @IsTest): ejercita el circuit breaker
 * de punta a punta usando un proceso descartable ('SMOKE_TEST_CircuitBreaker'),
 * sin tocar SAP ni Account real. Se invoca desde Apex anonimo:
 *   ICB_CircuitBreakerSmokeTest.ejecutar();
 * Imprime cada paso via System.debug y borra el registro de prueba al final.
 * Como efecto real: SI envia un correo verdadero (via ICB_CircuitBreakerNotifier)
 * al destinatario configurado abajo, para confirmar que la notificacion llega.
 **********************************************************************************/
public with sharing class ICB_CircuitBreakerSmokeTest {

    private static final String PROCESO = 'SMOKE_TEST_CircuitBreaker';
    private static final String DESTINATARIO = 'jillanes@icbfs.cl';
    private static final String REMITENTE_OWA = 'info@icbfs.cl';

    public static void ejecutar() {
        limpiarPrevio();

        Circuit_Breaker__c cb = new Circuit_Breaker__c(
            Name = PROCESO,
            Nombre_Proceso__c = PROCESO,
            Activo__c = true,
            Umbral_Intentos__c = 5,
            Ventana_Segundos__c = 60,
            Enfriamiento_Minutos__c = 1,
            Estado__c = 'Cerrado',
            Contador_Ventana__c = 0,
            Total_Intentos_Bloqueados__c = 0,
            Correo_Enviado__c = false,
            Destinatarios_Correo__c = DESTINATARIO,
            Remitente_OrgWideEmail__c = REMITENTE_OWA
        );
        insert cb;
        System.debug(LoggingLevel.INFO, 'PASO 0: registro de prueba creado. Activo=true, Umbral=5, Ventana=60s, Enfriamiento=1min');

        List<ICB_CircuitBreakerCheck.Request> rafaga = new List<ICB_CircuitBreakerCheck.Request>();
        for (Integer i = 0; i < 6; i++) {
            ICB_CircuitBreakerCheck.Request r = new ICB_CircuitBreakerCheck.Request();
            r.nombreProceso = PROCESO;
            rafaga.add(r);
        }
        List<ICB_CircuitBreakerCheck.Response> respRafaga = ICB_CircuitBreakerCheck.verificar(rafaga);
        System.debug(LoggingLevel.INFO, 'PASO 1 (rafaga de 6, umbral 5): permitirContinuar=' + respRafaga[0].permitirContinuar
            + ' estado=' + respRafaga[0].estadoBreaker + ' motivo=' + respRafaga[0].motivo
            + ' -- esperado: false / Abierto');

        ICB_CircuitBreakerCheck.Request r2 = new ICB_CircuitBreakerCheck.Request();
        r2.nombreProceso = PROCESO;
        List<ICB_CircuitBreakerCheck.Response> resp2 = ICB_CircuitBreakerCheck.verificar(new List<ICB_CircuitBreakerCheck.Request>{ r2 });
        System.debug(LoggingLevel.INFO, 'PASO 2 (1 intento mas mientras sigue abierto): permitirContinuar=' + resp2[0].permitirContinuar
            + ' estado=' + resp2[0].estadoBreaker + ' -- esperado: false / Abierto (y NINGUN correo nuevo)');

        Circuit_Breaker__c estadoActual = [
            SELECT Estado__c, Contador_Ventana__c, Total_Intentos_Bloqueados__c, Correo_Enviado__c, Fecha_Apertura__c
            FROM Circuit_Breaker__c WHERE Id = :cb.Id
        ];
        System.debug(LoggingLevel.INFO, 'PASO 3 (estado guardado): Estado=' + estadoActual.Estado__c
            + ' ContadorVentana=' + estadoActual.Contador_Ventana__c
            + ' TotalBloqueados=' + estadoActual.Total_Intentos_Bloqueados__c
            + ' CorreoEnviado=' + estadoActual.Correo_Enviado__c
            + ' FechaApertura=' + estadoActual.Fecha_Apertura__c);

        // Simula el boton "Reactivar ahora" del panel (mismo efecto que hace el Screen Flow).
        estadoActual.Estado__c = 'Cerrado';
        estadoActual.Fecha_Apertura__c = null;
        estadoActual.Correo_Enviado__c = false;
        estadoActual.Contador_Ventana__c = 0;
        estadoActual.Total_Intentos_Bloqueados__c = 0;
        update estadoActual;

        ICB_CircuitBreakerCheck.Request r4 = new ICB_CircuitBreakerCheck.Request();
        r4.nombreProceso = PROCESO;
        List<ICB_CircuitBreakerCheck.Response> resp4 = ICB_CircuitBreakerCheck.verificar(new List<ICB_CircuitBreakerCheck.Request>{ r4 });
        System.debug(LoggingLevel.INFO, 'PASO 4 (despues de "Reactivar ahora", 1 intento nuevo): permitirContinuar=' + resp4[0].permitirContinuar
            + ' estado=' + resp4[0].estadoBreaker + ' -- esperado: true / Cerrado');

        limpiarPrevio();
        System.debug(LoggingLevel.INFO, 'PASO 5: registro de prueba eliminado. Smoke test terminado. Revisa el correo de ' + DESTINATARIO + '.');
    }

    private static void limpiarPrevio() {
        delete [SELECT Id FROM Circuit_Breaker__c WHERE Nombre_Proceso__c = :PROCESO];
    }
}