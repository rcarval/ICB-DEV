/**********************************************************************************
 * ICB_CircuitBreakerAsyncHandler
 * Procesa Circuit_Breaker_Intento__e (publicado PublishImmediately desde el gate
 * before-save). Corre en su propia transaccion, por lo tanto el conteo real,
 * la apertura del breaker y la notificacion SI sobreviven aunque el registro
 * que origino el intento haya sido rechazado (addError) y su transaccion
 * revertida.
 **********************************************************************************/
public without sharing class ICB_CircuitBreakerAsyncHandler {

    public static void procesarIntentos(List<Circuit_Breaker_Intento__e> eventos) {
        List<String> nombresProceso = new List<String>();
        List<Id> registroIds = new List<Id>();

        for (Circuit_Breaker_Intento__e evento : eventos) {
            nombresProceso.add(evento.Nombre_Proceso__c);
            registroIds.add(
                String.isNotBlank(evento.Registro_Id__c) ? (Id) evento.Registro_Id__c : null
            );
        }

        ICB_CircuitBreakerService.evaluarLote(nombresProceso, registroIds);
    }
}