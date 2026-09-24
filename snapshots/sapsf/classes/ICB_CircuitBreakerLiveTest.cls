/**********************************************************************************
 * ICB_CircuitBreakerLiveTest
 * Utilidad de validacion EN VIVO (no es un @IsTest) sobre los 5 procesos reales
 * ya instrumentados: prende Activo__c=true y dispara una rafaga por encima del
 * umbral configurado para cada uno, dejandolos ABIERTOS a proposito (no resetea).
 * No toca SAP ni Account real: solo ejercita ICB_CircuitBreakerCheck directamente.
 * Invocar desde Apex anonimo: ICB_CircuitBreakerLiveTest.activarYCortarTodos();
 **********************************************************************************/
public with sharing class ICB_CircuitBreakerLiveTest {

    private static final List<String> PROCESOS = new List<String>{
        'Update_Cliente_Full_Cliente_SAP',
        'Crear_Asociacion',
        'Subflow_Domicilio_adicional_cliente_v3',
        'Update_Domicilio_adicional_cliente_v1_1',
        'Auto_crear_cliente_full_v1'
    };

    public static void activarYCortarTodos() {
        List<Circuit_Breaker__c> filas = [
            SELECT Id, Nombre_Proceso__c, Umbral_Intentos__c, Activo__c
            FROM Circuit_Breaker__c
            WHERE Nombre_Proceso__c IN :PROCESOS
        ];

        if (filas.size() != PROCESOS.size()) {
            System.debug(LoggingLevel.WARN, 'Se esperaban ' + PROCESOS.size() + ' registros, se encontraron ' + filas.size());
        }

        List<Circuit_Breaker__c> paraActivar = new List<Circuit_Breaker__c>();
        for (Circuit_Breaker__c fila : filas) {
            fila.Activo__c = true;
            paraActivar.add(fila);
        }
        update paraActivar;
        System.debug(LoggingLevel.INFO, 'PASO 1: Activo__c=true en ' + paraActivar.size() + ' procesos.');

        List<String> nombresRafaga = new List<String>();
        List<Id> idsRafaga = new List<Id>();
        for (Circuit_Breaker__c fila : filas) {
            Integer umbral = fila.Umbral_Intentos__c != null ? fila.Umbral_Intentos__c.intValue() : 20;
            Integer cantidad = umbral + 5;
            for (Integer i = 0; i < cantidad; i++) {
                nombresRafaga.add(fila.Nombre_Proceso__c);
                idsRafaga.add(null);
            }
        }

        System.debug(LoggingLevel.INFO, 'PASO 2: enviando rafaga de ' + nombresRafaga.size() + ' intentos combinados (todos los procesos en un solo lote).');

        List<ICB_CircuitBreakerCheck.Request> requests = new List<ICB_CircuitBreakerCheck.Request>();
        for (Integer i = 0; i < nombresRafaga.size(); i++) {
            ICB_CircuitBreakerCheck.Request r = new ICB_CircuitBreakerCheck.Request();
            r.nombreProceso = nombresRafaga[i];
            r.registroId = idsRafaga[i];
            requests.add(r);
        }
        ICB_CircuitBreakerCheck.verificar(requests);

        System.debug(LoggingLevel.INFO, 'PASO 3: rafaga enviada. Verificando estado final de cada proceso...');

        List<Circuit_Breaker__c> estadoFinal = [
            SELECT Nombre_Proceso__c, Estado__c, Contador_Ventana__c, Total_Intentos_Bloqueados__c, Correo_Enviado__c, Fecha_Apertura__c
            FROM Circuit_Breaker__c
            WHERE Nombre_Proceso__c IN :PROCESOS
        ];
        for (Circuit_Breaker__c fila : estadoFinal) {
            System.debug(LoggingLevel.INFO, fila.Nombre_Proceso__c
                + ' -> Estado=' + fila.Estado__c
                + ' Contador=' + fila.Contador_Ventana__c
                + ' Bloqueados=' + fila.Total_Intentos_Bloqueados__c
                + ' CorreoEnviado=' + fila.Correo_Enviado__c
                + ' FechaApertura=' + fila.Fecha_Apertura__c);
        }

        System.debug(LoggingLevel.INFO, 'LISTO. No se reseteo nada a proposito: quedan abiertos para verlos en vivo en el panel.');
    }
}