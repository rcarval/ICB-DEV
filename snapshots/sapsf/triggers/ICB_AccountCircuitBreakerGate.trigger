/**
 * @Name        : ICB_AccountCircuitBreakerGate
 * @Description : Antes de guardar, verifica el Circuit Breaker SAP para los procesos
 *                que se disparan por este cambio de Account. Si el proceso esta
 *                abierto/bloqueado, rechaza el registro completo (addError) para
 *                que la carga masiva NO quede guardada, no solo que se salte SAP.
 */
trigger ICB_AccountCircuitBreakerGate on Account (before insert, before update) {
    ICB_CircuitBreakerAccountGate.evaluarAntesDeGuardar(
        Trigger.new,
        Trigger.isUpdate ? Trigger.oldMap : null
    );
}